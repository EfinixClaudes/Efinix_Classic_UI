local ADDON, ns = ...

-- Single addon table. Nothing else goes into _G except SavedVariables (see DB.lua)
-- and the slash command registration at the bottom of this file.
ns.name = ADDON
ns.BUILD = "2026-09-18.4" -- bump on every change that is tested in game
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
    ns.DB.Load()
    ns.Assets.Verify()
    ns.loaded = true
end)

ns.RegisterEvent("PLAYER_LOGIN", ns, function()
    if not ns.loaded then
        return
    end
    for _, name in ipairs(ns.moduleOrder) do
        ns.EnableModule(name)
    end
    ns.RegisterEvent("PLAYER_ENTERING_WORLD", ns, function()
        ns.RefreshAll()
    end)
    ns.Print("build %s loaded", ns.BUILD)
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

local function diag(name)
    if name and name ~= "" then
        local module = ns.modules[name]
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
    if cmd == "status" or cmd == "" then
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
        local module = ns.modules[rest]
        if not module then
            ns.Print("no module named %s", rest)
            return
        end
        ns.db.modules[rest] = (cmd == "enable")
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
        else
            ns.Print("usage: /fcui bags columns <4-20> | bankcolumns <4-24> | shiftsell on|off | selljunk")
        end
    elseif cmd == "reset" then
        ns.DB.Reset()
        ns.Print("settings reset, /reload to apply")
    else
        ns.Print("commands: status, missing, diag [module], enable <module>, disable <module>, scale <n>")
        ns.Print("          move [reset], bags columns <n>, bags bankcolumns <n>, reset")
    end
end
_G.SLASH_FCUI1 = "/fcui"
