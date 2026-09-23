local ADDON, ns = ...

-- Single addon table. Nothing else goes into _G except SavedVariables (see DB.lua)
-- and the slash command registration at the bottom of this file.
ns.name = ADDON
ns.BUILD = "2026-09-23.40" -- bump on every change that is tested in game
ns.modules = {} -- name -> module table
ns.moduleOrder = {} -- registration order, also enable order
ns.L = setmetatable({}, {
    __index = function(_, key)
        return key
    end,
}) -- enUS fallback

---------------------------------------------------------------------------
-- Raw widget methods.
-- Edit Mode replaces SetPoint/ClearAllPoints/SetScale/Show/Hide on every frame
-- it manages with Lua wrappers that bookkeep snapping and anchor changes.
-- Calling those wrappers from addon code would run Blizzard Lua in a tainted
-- context and write tainted values into Blizzard tables. We therefore capture
-- the untouched widget methods from a private frame's metatable and call them
-- directly on Blizzard frames. See docs/adr/0003-raw-widget-methods.md.
---------------------------------------------------------------------------
do
    local probe = CreateFrame("Frame")
    local mt = getmetatable(probe).__index
    ns.Raw = {
        SetPoint = mt.SetPoint,
        ClearAllPoints = mt.ClearAllPoints,
        SetSize = mt.SetSize,
        SetWidth = mt.SetWidth,
        SetHeight = mt.SetHeight,
        SetScale = mt.SetScale,
        SetParent = mt.SetParent,
        SetAlpha = mt.SetAlpha,
        Show = mt.Show,
        Hide = mt.Hide,
        SetFrameStrata = mt.SetFrameStrata,
        SetFrameLevel = mt.SetFrameLevel,
        SetHitRectInsets = mt.SetHitRectInsets,
        EnableMouse = mt.EnableMouse,
        IsShown = mt.IsShown,
    }
end

---------------------------------------------------------------------------
-- Logging
---------------------------------------------------------------------------
local PREFIX = "|cff33ff99FCUI|r: "
function ns.Print(msg, ...)
    if select("#", ...) > 0 then
        msg = msg:format(...)
    end
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(msg))
end

ns.log = {} -- ring of recent diagnostics, shown by /fcui diag
local MAX_LOG = 50
function ns.Log(module, msg, ...)
    if select("#", ...) > 0 then
        msg = msg:format(...)
    end
    local line = ("%s: %s"):format(module, tostring(msg))
    table.insert(ns.log, line)
    if #ns.log > MAX_LOG then
        table.remove(ns.log, 1)
    end
end

---------------------------------------------------------------------------
-- Event dispatcher
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {} -- event -> list of {owner, fn}
ns.eventFrame = eventFrame

function ns.RegisterEvent(event, owner, fn)
    if not handlers[event] then
        handlers[event] = {}
        eventFrame:RegisterEvent(event)
    end
    table.insert(handlers[event], { owner = owner, fn = fn })
end

function ns.UnregisterAllEvents(owner)
    for event, list in pairs(handlers) do
        for i = #list, 1, -1 do
            if list[i].owner == owner then
                table.remove(list, i)
            end
        end
        if #list == 0 then
            handlers[event] = nil
            eventFrame:UnregisterEvent(event)
        end
    end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then
        return
    end
    -- copy so handlers may unregister while dispatching
    local snapshot = {}
    for i = 1, #list do
        snapshot[i] = list[i]
    end
    for i = 1, #snapshot do
        local entry = snapshot[i]
        local ok, err = xpcall(entry.fn, geterrorhandler(), entry.owner, event, ...)
        if not ok then
            ns.Log("Events", "%s handler error: %s", event, tostring(err))
        end
    end
end)

---------------------------------------------------------------------------
-- Module registry
-- A module is a table with Init / Enable / Disable / Refresh. Each call is
-- wrapped in xpcall so one broken module never takes the rest down.
---------------------------------------------------------------------------
function ns.RegisterModule(name, module)
    assert(not ns.modules[name], "module registered twice: " .. name)
    module.name = name
    module.state = "registered"
    ns.modules[name] = module
    table.insert(ns.moduleOrder, name)
    return module
end

local function callModule(module, method, ...)
    local fn = module[method]
    if not fn then
        return true
    end
    local ok, err = xpcall(fn, geterrorhandler(), module, ...)
    if not ok then
        module.state = "failed"
        module.lastError = tostring(err)
        ns.Log(module.name, "%s failed: %s", method, tostring(err))
        ns.Print(
            "module %s failed in %s, Blizzard frames left untouched. /fcui diag %s",
            module.name,
            method,
            module.name
        )
    end
    return ok
end

function ns.EnableModule(name)
    local module = ns.modules[name]
    if not module or module.state == "enabled" or module.state == "failed" then
        return
    end
    if not ns.db.modules[name] then
        module.state = "disabled"
        return
    end
    if not module.initialized then
        if not callModule(module, "Init") then
            return
        end
        module.initialized = true
        module.state = "initialized"
    end
    -- Mark enabled before Enable runs so layout functions the module calls from
    -- inside Enable (and hooks that fire during it) are not gated off.
    -- callModule flips the state to "failed" on error.
    module.state = "enabled"
    callModule(module, "Enable")
end

function ns.DisableModule(name)
    local module = ns.modules[name]
    if not module or module.state ~= "enabled" then
        return
    end
    if callModule(module, "Disable") then
        module.state = "disabled"
    end
end

function ns.RefreshModule(name)
    local module = ns.modules[name]
    if module and module.state == "enabled" then
        callModule(module, "Refresh")
    end
end

function ns.RefreshAll()
    for _, name in ipairs(ns.moduleOrder) do
        ns.RefreshModule(name)
    end
end

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------
ns.RegisterEvent("ADDON_LOADED", ns, function(_, _, loaded)
    if loaded ~= ADDON then
        return
    end
    ns.DB.RegisterCVar()
    ns.DB.Adopt("ADDON_LOADED")
    if not ns.db then
        ns.DB.Load()
        ns.DB.loadedAt = "ADDON_LOADED(defaults)"
    end
    ns.Assets.Verify()
    ns.loaded = true
end)

-- the saved table may only appear after ADDON_LOADED; take it as soon as it does
ns.RegisterEvent("VARIABLES_LOADED", ns, function()
    ns.DB.Adopt("VARIABLES_LOADED")
end)

ns.RegisterEvent("PLAYER_LOGIN", ns, function()
    if not ns.loaded then
        return
    end
    ns.DB.Adopt("PLAYER_LOGIN")
    for _, name in ipairs(ns.moduleOrder) do
        ns.EnableModule(name)
    end
    ns.RegisterEvent("PLAYER_ENTERING_WORLD", ns, function()
        -- too late to switch silently: modules already run on the other table
        if ns.DB.Adopt("PLAYER_ENTERING_WORLD") then
            ns.Print("saved settings arrived late, /reload once to apply them")
        end
        ns.DB.Flush()
    end)
    ns.RegisterEvent("PLAYER_LOGOUT", ns, function()
        ns.DB.Flush()
    end)
    ns.RegisterEvent("PLAYER_ENTERING_WORLD", ns, function()
        ns.RefreshAll()
    end)
    ns.Options.RegisterSettings()
    local seen = {}
    for _, event in ipairs({ "ADDON_LOADED", "VARIABLES_LOADED", "PLAYER_LOGIN" }) do
        seen[#seen + 1] = event .. "=" .. tostring(ns.DB.seen[event])
    end
    ns.Log("DB", "saved table by event: %s; loaded at %s", table.concat(seen, " "), tostring(ns.DB.loadedAt))
    local off = {}
    for _, name in ipairs(ns.moduleOrder) do
        if ns.modules[name].state ~= "enabled" then
            off[#off + 1] = name .. " (" .. ns.modules[name].state .. ")"
        end
    end
    ns.Print(
        "build %s loaded, settings from %s; parts off: %s; dark mode %s",
        ns.BUILD,
        ns.DB.loadedFromFile
                and ("your saved file, %s store written %s, login #%d"):format(
                    tostring(ns.DB.loadedSource),
                    tostring(ns.DB.loadedWritten),
                    tonumber(ns.db.logins) or 0
                )
            or ("defaults (no saved file at " .. tostring(ns.DB.loadedAt) .. "), login #1"),
        #off > 0 and table.concat(off, ", ") or "none",
        ns.Dark.Enabled() and "on" or "off"
    )
end)

---------------------------------------------------------------------------
-- /fcui slash command
---------------------------------------------------------------------------
local function status()
    local facts = ns.Compat.Facts()
    ns.Print("addon build %s", ns.BUILD)
    ns.Print(
        "client %s (%s) interface %s, project %s",
        facts.version,
        facts.build,
        facts.interface,
        tostring(facts.projectID)
    )
    ns.Print(
        "EditMode=%s SecretValues=%s C_AddOns=%s C_UnitAuras=%s C_Spell=%s Settings=%s",
        tostring(facts.hasEditMode),
        tostring(facts.hasSecretValues),
        tostring(facts.hasCAddOns),
        tostring(facts.hasCUnitAuras),
        tostring(facts.hasCSpell),
        tostring(facts.hasSettings)
    )
    for _, name in ipairs(ns.moduleOrder) do
        local module = ns.modules[name]
        ns.Print("  %-12s %s%s", name, module.state, module.lastError and (" (" .. module.lastError .. ")") or "")
    end
    ns.Print("settings at login: %s (loaded at %s)", tostring(ns.DB.loadedSummary), tostring(ns.DB.loadedAt))
    for _, line in ipairs(ns.log) do
        if line:find("saved table by event", 1, true) then
            ns.Print(line)
        end
    end
    ns.Print(
        "settings now: darkMode=%s Bags=%s (encoded %s chars, saved global=%s)",
        tostring(ns.db.darkMode),
        tostring(ns.db.modules.Bags),
        tostring(ns.DB.flushed),
        type(EfinixClassicUICharSettings)
    )
    local mediaCount = ns.Assets.MediaCount()
    if mediaCount > 0 then
        ns.Print("local Blizzard art: %d old texture paths served from Media\\Blizzard", mediaCount)
    end
    local missing = ns.Assets.Missing()
    if #missing > 0 then
        ns.Print("missing textures (%d): %s", #missing, table.concat(missing, ", "))
    else
        ns.Print("all %d verified textures present", ns.Assets.Count())
    end
    -- modules that probe their own files log "missing texture <path>"
    for _, line in ipairs(ns.log) do
        if line:find("missing texture", 1, true) then
            ns.Print(line)
        end
    end
end

-- module lookup for the slash command, which lowercases its input
local function findModule(name)
    name = (name or ""):lower()
    for _, key in ipairs(ns.moduleOrder) do
        if key:lower() == name then
            return ns.modules[key], key
        end
    end
end

local function diag(name)
    if name and name ~= "" then
        local module
        module, name = findModule(name)
        if not module then
            ns.Print("no module named %s", name)
            return
        end
        ns.Print("%s: state=%s", name, module.state)
        if module.Diag then
            xpcall(module.Diag, geterrorhandler(), module)
        end
        for _, line in ipairs(ns.log) do
            if line:sub(1, #name + 1) == name .. ":" then
                ns.Print(line)
            end
        end
    else
        for _, line in ipairs(ns.log) do
            ns.Print(line)
        end
    end
end

SlashCmdList.FCUI = function(input)
    input = (input or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = input:match("^(%S*)%s*(.-)$")
    if cmd == "" or cmd == "options" or cmd == "config" then
        ns.Options.Toggle()
    elseif cmd == "status" then
        status()
    elseif cmd == "diag" then
        diag(rest)
    elseif cmd == "missing" then
        -- only the old art files this client does not ship, short enough for one screenshot
        local count = 0
        for _, name in ipairs(ns.Assets.Missing()) do
            ns.Print("missing: %s", ns.Assets.Path(name))
            count = count + 1
        end
        for _, line in ipairs(ns.log) do
            local path = line:match("missing texture (.+)$")
            if path then
                ns.Print("missing: %s", path)
                count = count + 1
            end
        end
        ns.Print("%d old texture files are not in this client", count)
    elseif cmd == "enable" or cmd == "disable" then
        local module, key = findModule(rest)
        if not module then
            ns.Print("no module named %s (parts: %s)", rest, table.concat(ns.moduleOrder, ", "))
            return
        end
        rest = key
        ns.db.modules[rest] = (cmd == "enable")
        ns.DB.Flush()
        -- run the lifecycle now so modules that changed a game setting can put it back
        if cmd == "disable" then
            ns.DisableModule(rest)
        else
            ns.EnableModule(rest)
        end
        ns.Print("%s %sd, /reload to apply fully", rest, cmd)
    elseif cmd == "scale" then
        local value = tonumber(rest)
        if value and value >= 0.5 and value <= 2 then
            ns.db.scale = value
            ns.DB.Flush()
            ns.RefreshAll()
            ns.Print("scale set to %.2f", value)
        else
            ns.Print("usage: /fcui scale 0.5-2.0 (current %.2f)", ns.db.scale)
        end
    elseif cmd == "move" then
        if not ns.UnitFrames then
            ns.Print("UnitFrames module not loaded")
        elseif rest == "reset" then
            ns.UnitFrames.ResetPositions()
        else
            ns.UnitFrames.SetMoveMode(not ns.UnitFrames.moveMode)
        end
    elseif cmd == "bags" then
        local kind, value = rest:match("^(%a+)%s+(%d+)$")
        if not ns.Bags then
            ns.Print("Bags module not loaded")
        elseif kind == "columns" and tonumber(value) then
            ns.Bags.SetColumns("inventory", math.max(4, math.min(20, tonumber(value))))
        elseif kind == "bankcolumns" and tonumber(value) then
            ns.Bags.SetColumns("bank", math.max(4, math.min(24, tonumber(value))))
        elseif rest == "shiftsell on" or rest == "shiftsell off" then
            ns.Bags.Junk.SetShiftSell(rest == "shiftsell on")
        elseif rest == "selljunk" then
            ns.Bags.Junk.Sell()
        elseif rest == "bank" then
            ns.Bags.ToggleBank()
        else
            ns.Print("usage: /fcui bags columns <4-20> | bankcolumns <4-24> | shiftsell on|off | selljunk | bank")
        end
    elseif cmd == "dark" then
        if rest == "on" or rest == "off" then
            ns.Dark.Set(rest == "on")
            ns.DB.Flush()
            ns.Print("dark mode %s", rest)
        else
            ns.Print("usage: /fcui dark on|off (currently %s)", ns.Dark.Enabled() and "on" or "off")
        end
    elseif cmd == "reset" then
        ns.DB.Reset()
        ns.Print("settings reset, /reload to apply")
    else
        ns.Print("commands: options, status, missing, diag [module], enable <module>, disable <module>, scale <n>")
        ns.Print("          move [reset], bags columns <n>, bags bankcolumns <n>, dark on|off, reset")
    end
end
_G.SLASH_FCUI1 = "/fcui"
