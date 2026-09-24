local _, ns = ...

-- Gather: remembers every mining and herb node the player gathers, with its
-- map position, and draws those spots on the world map. Nobody has recorded
-- Forever's node spawns yet, so the map fills in as you play; after a few
-- laps of a zone the route through its nodes is on the map. Two checkboxes
-- on the map show or hide the mining and herb pins.
--
-- Recording: UNIT_SPELLCAST_SENT carries the node's name as the cast target
-- and UNIT_SPELLCAST_SUCCEEDED confirms the gather; the position comes from
-- C_Map.GetPlayerMapPosition on the player's current map. A node within
-- 0.4% of the map of a known one (about ten yards on a zone map) counts as
-- the same spot and only raises its count.
--
-- Storage: one text blob through ns.DB (registered cvar plus saved copy),
--   <p>,<mapID>,<x>,<y>,<count>,<name>;...   p = m|h, x/y in 1/10000 of the map
--
-- Map pins: a plain overlay on the map canvas, positioned the way
-- MapCanvasMixin:ApplyPinPosition anchors pins (CENTER to the canvas
-- TOPLEFT at the normalised position over the pin's own scale), scaled by
-- the inverse canvas scale so they keep their size while zooming.
local Gather = ns.RegisterModule("Gather", {})
ns.Gather = Gather

local BLOB = "Gather"
local MERGE_DISTANCE = 0.004
local PIN_SIZE = 12
local PIN_LEVEL_FALLBACK = 2100 -- above the map art pins (2000+), used when the level manager is missing
local ICONS = {
    m = "Interface\\Icons\\Trade_Mining",
    h = "Interface\\Icons\\Trade_Herbalism",
}
local LABELS = { m = "Mining", h = "Herbs" }

-- Gather spells of every rank, Classic through Retail; the names are the
-- fallback for ranks this list does not know (enUS).
local MINING_SPELLS = {
    [2575] = true,
    [2576] = true,
    [3564] = true,
    [10248] = true,
    [29354] = true,
    [50310] = true,
    [74519] = true,
    [102161] = true,
    [158754] = true,
    [195122] = true,
    [265837] = true,
    [265843] = true,
    [265847] = true,
    [265848] = true,
    [265853] = true,
    [265854] = true,
    [265856] = true,
}
local HERB_SPELLS = {
    [2366] = true,
    [2368] = true,
    [3570] = true,
    [11993] = true,
    [28695] = true,
    [50300] = true,
    [110413] = true,
    [158745] = true,
    [195114] = true,
    [265819] = true,
    [265825] = true,
    [265827] = true,
    [265829] = true,
    [265834] = true,
    [265835] = true,
    [265836] = true,
}
local MINING_NAMES = { ["Mining"] = true }
local HERB_NAMES = { ["Herb Gathering"] = true, ["Herbalism"] = true }

local nodes = { m = {}, h = {} } -- profession -> list of { map, x, y, count, name }
local pending -- { profession, name, castGUID } from UNIT_SPELLCAST_SENT
local overlay
local pins = {}
local checks = {}
local loaded = false

local function settings()
    ns.db.gather = ns.db.gather or { showMining = true, showHerbs = true }
    return ns.db.gather
end

local function plain(value)
    if ns.Compat.IsSecret(value) then
        return nil
    end
    return value
end

---------------------------------------------------------------------------
-- Storage
---------------------------------------------------------------------------
local function load()
    if loaded then
        return
    end
    loaded = true
    nodes = { m = {}, h = {} }
    local blob = ns.DB.GetBlob(BLOB)
    if type(blob) ~= "string" then
        return
    end
    for entry in blob:gmatch("[^;]+") do
        local p, map, x, y, count, name = entry:match("^([mh]),(%d+),(%d+),(%d+),(%d+),(.*)$")
        if p then
            nodes[p][#nodes[p] + 1] = {
                map = tonumber(map),
                x = tonumber(x) / 10000,
                y = tonumber(y) / 10000,
                count = tonumber(count) or 1,
                name = ns.DB.Unescape(name),
            }
        end
    end
end

local function encodeNode(p, node)
    return ("%s,%d,%d,%d,%d,%s"):format(
        p,
        node.map,
        math.floor(node.x * 10000 + 0.5),
        math.floor(node.y * 10000 + 0.5),
        node.count,
        ns.DB.Escape(node.name or "")
    )
end

local function decodeNode(entry)
    local p, map, x, y, count, name = entry:match("^([mh]),(%d+),(%d+),(%d+),(%d+),(.*)$")
    if not p then
        return nil
    end
    return p,
        {
            map = tonumber(map),
            x = tonumber(x) / 10000,
            y = tonumber(y) / 10000,
            count = tonumber(count) or 1,
            name = ns.DB.Unescape(name),
        }
end

local function save()
    local parts = {}
    for p, list in pairs(nodes) do
        for _, node in ipairs(list) do
            parts[#parts + 1] = encodeNode(p, node)
        end
    end
    ns.DB.SetBlob(BLOB, table.concat(parts, ";"))
end

-- Merge one spot into the list: a known spot within MERGE_DISTANCE takes
-- the count, anything else is new. Returns true when it was new.
local function merge(p, incoming)
    local list = nodes[p]
    for _, node in ipairs(list) do
        if
            node.map == incoming.map
            and math.abs(node.x - incoming.x) < MERGE_DISTANCE
            and math.abs(node.y - incoming.y) < MERGE_DISTANCE
        then
            node.count = math.min(999, node.count + (incoming.count or 1))
            if (node.name == nil or node.name == "") and incoming.name and incoming.name ~= "" then
                node.name = incoming.name
            end
            return false
        end
    end
    list[#list + 1] = incoming
    return true
end

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------
local function professionOf(spellID)
    if MINING_SPELLS[spellID] then
        return "m"
    elseif HERB_SPELLS[spellID] then
        return "h"
    end
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
    name = plain(name)
    if MINING_NAMES[name] then
        return "m"
    elseif HERB_NAMES[name] then
        return "h"
    end
    return nil
end

local function playerPosition()
    if not C_Map or not C_Map.GetBestMapForUnit then
        return nil
    end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then
        return nil
    end
    local position = C_Map.GetPlayerMapPosition(mapID, "player")
    if not position then
        return nil
    end
    local x, y = position:GetXY()
    x, y = plain(x), plain(y)
    if not x or not y or x <= 0 or y <= 0 then
        return nil
    end
    return mapID, x, y
end

local function record(profession, name)
    load()
    local mapID, x, y = playerPosition()
    if not mapID then
        return
    end
    local list = nodes[profession]
    for _, node in ipairs(list) do
        if node.map == mapID and math.abs(node.x - x) < MERGE_DISTANCE and math.abs(node.y - y) < MERGE_DISTANCE then
            node.count = node.count + 1
            if name and name ~= "" then
                node.name = name
            end
            save()
            Gather.RefreshMap()
            return
        end
    end
    list[#list + 1] = { map = mapID, x = x, y = y, count = 1, name = name or "" }
    save()
    Gather.RefreshMap()
    local mapName = C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    ns.Log(
        "Gather",
        "new %s node %s at %.1f, %.1f in %s (%d there now)",
        LABELS[profession],
        name or "?",
        x * 100,
        y * 100,
        mapName and mapName.name or mapID,
        #list
    )
end

local function onSent(_, _, unit, target, castGUID, spellID)
    if unit ~= "player" then
        return
    end
    local profession = professionOf(spellID)
    if not profession then
        return
    end
    pending = { profession = profession, name = plain(target), castGUID = castGUID, spellID = spellID }
end

local function onSucceeded(_, _, unit, castGUID, spellID)
    if unit ~= "player" then
        return
    end
    local profession = professionOf(spellID)
    if not profession then
        return
    end
    local name
    if pending and (pending.castGUID == castGUID or pending.spellID == spellID) then
        name = pending.name
    end
    pending = nil
    record(profession, name)
end

---------------------------------------------------------------------------
-- Map overlay
---------------------------------------------------------------------------
local function canvas()
    return WorldMapFrame and WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
end

-- The explored map art itself is drawn by pins (PIN_FRAME_LEVEL_MAP_EXPLORATION,
-- the lowest pin levels), so anything under the pin levels is hidden by the
-- map. Our pins take the area-POI level: above the art and highlights, under
-- quests, vignettes and the player arrow.
local function pinLevel()
    local manager = WorldMapFrame
        and WorldMapFrame.GetPinFrameLevelsManager
        and WorldMapFrame:GetPinFrameLevelsManager()
    if manager and manager.GetFrameLevelStart then
        local ok, level = pcall(manager.GetFrameLevelStart, manager, "PIN_FRAME_LEVEL_AREA_POI")
        if ok and type(level) == "number" then
            return level
        end
    end
    return PIN_LEVEL_FALLBACK
end

local attachToMap -- defined below, used by RefreshMap

local function getPin(index)
    local pin = pins[index]
    if pin then
        return pin
    end
    pin = CreateFrame("Button", nil, overlay)
    pin:SetSize(PIN_SIZE, PIN_SIZE)
    pin:SetFrameLevel(pinLevel())
    pin.Icon = pin:CreateTexture(nil, "ARTWORK")
    pin.Icon:SetAllPoints()
    pin.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    pin:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.node.name ~= "" and self.node.name or LABELS[self.profession], 1, 1, 1)
        GameTooltip:AddLine(
            ("%s, gathered %d time%s here"):format(
                LABELS[self.profession],
                self.node.count,
                self.node.count == 1 and "" or "s"
            ),
            0.8,
            0.8,
            0.8
        )
        GameTooltip:Show()
    end)
    pin:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    pins[index] = pin
    return pin
end

-- A spot recorded on one map drawn on another (its continent, a sub-map,
-- or simply a different id for the same zone): through world coordinates.
-- Returns nil when the spot lies outside the map being viewed.
local translated = {} -- node -> mapID -> { x, y } | false
local function positionOn(node, mapID)
    if node.map == mapID then
        return node.x, node.y
    end
    translated[node] = translated[node] or {}
    local cached = translated[node][mapID]
    if cached == nil then
        cached = false
        if C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos and CreateVector2D then
            local ok, continentID, world = pcall(C_Map.GetWorldPosFromMapPos, node.map, CreateVector2D(node.x, node.y))
            if ok and continentID and world then
                local ok2, targetMap, position = pcall(C_Map.GetMapPosFromWorldPos, continentID, world, mapID)
                if ok2 and targetMap == mapID and position then
                    local x, y = position:GetXY()
                    if x and y and x > 0 and x < 1 and y > 0 and y < 1 then
                        cached = { x = x, y = y }
                    end
                end
            end
        end
        translated[node][mapID] = cached
    end
    if cached then
        return cached.x, cached.y
    end
    return nil
end

local function pinScale()
    local scale = WorldMapFrame and WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale() or 1
    if not scale or scale <= 0 then
        scale = 1
    end
    return 1 / scale
end

local function placePin(pin, x, y)
    local child = canvas()
    local scale = pinScale()
    pin.mapX, pin.mapY = x, y
    pin:SetScale(scale)
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", child, "TOPLEFT", (child:GetWidth() * x) / scale, -(child:GetHeight() * y) / scale)
end

Gather.lastRefresh = "never"
function Gather.RefreshMap()
    if not overlay then
        attachToMap()
    end
    if not overlay or not WorldMapFrame or not WorldMapFrame:IsShown() then
        Gather.lastRefresh = "skipped (map hidden or no overlay)"
        return
    end
    local child = canvas()
    if not child or (child:GetWidth() or 0) < 1 then
        -- the canvas has no size yet (first show): once more after this frame
        C_Timer.After(0, Gather.RefreshMap)
        Gather.lastRefresh = "deferred (canvas not sized)"
        return
    end
    load()
    overlay:SetFrameLevel(pinLevel())
    local mapID = WorldMapFrame:GetMapID()
    local used = 0
    local shown = settings()
    for _, profession in ipairs({ "m", "h" }) do
        local wanted = (profession == "m" and shown.showMining) or (profession == "h" and shown.showHerbs)
        if wanted then
            for _, node in ipairs(nodes[profession]) do
                local x, y = positionOn(node, mapID)
                if x then
                    used = used + 1
                    local pin = getPin(used)
                    pin.node = node
                    pin.profession = profession
                    pin.Icon:SetTexture(ICONS[profession])
                    if not pin.Icon:GetTexture() then
                        -- icon file not on this client: a plain coloured dot
                        if profession == "m" then
                            pin.Icon:SetColorTexture(1, 0.8, 0.2, 1)
                        else
                            pin.Icon:SetColorTexture(0.3, 0.9, 0.3, 1)
                        end
                    end
                    placePin(pin, x, y)
                    pin:SetFrameLevel(pinLevel())
                    pin:Show()
                end
            end
        end
    end
    for index = used + 1, #pins do
        pins[index]:Hide()
    end
    Gather.lastRefresh = ("%d pins on map %s (canvas %.0fx%.0f, scale %.2f)"):format(
        used,
        tostring(mapID),
        child:GetWidth(),
        child:GetHeight(),
        1 / pinScale()
    )
end

local function rescale()
    for _, pin in ipairs(pins) do
        if pin:IsShown() and pin.node and pin.mapX then
            placePin(pin, pin.mapX, pin.mapY)
        end
    end
end

local function createCheck(key, label, x)
    local check = CreateFrame(
        "CheckButton",
        "FCUI_Gather_" .. key,
        WorldMapFrame.BorderFrame or WorldMapFrame,
        "UICheckButtonTemplate"
    )
    check:SetSize(22, 22)
    check:SetPoint("BOTTOMLEFT", WorldMapFrame.ScrollContainer, "BOTTOMLEFT", x, 6)
    check:SetFrameLevel((WorldMapFrame.BorderFrame and WorldMapFrame.BorderFrame:GetFrameLevel() or 100) + 5)
    local text = check.Text or check.text or _G[check:GetName() .. "Text"]
    if text then
        text:SetFontObject(GameFontNormalSmall)
        text:SetText(label)
        text:ClearAllPoints()
        text:SetPoint("LEFT", check, "RIGHT", 0, 0)
    end
    check:SetScript("OnClick", function(self)
        settings()[key] = self:GetChecked() == true
        ns.DB.Flush()
        Gather.RefreshMap()
    end)
    checks[key] = check
    return check
end

attachToMap = function()
    if overlay or not canvas() then
        return
    end
    overlay = CreateFrame("Frame", "FCUI_GatherOverlay", canvas())
    overlay:SetAllPoints()
    overlay:SetFrameLevel(pinLevel())
    createCheck("showMining", "Mining", 12)
    createCheck("showHerbs", "Herbs", 84)
    if WorldMapFrame.OnMapChanged then
        hooksecurefunc(WorldMapFrame, "OnMapChanged", Gather.RefreshMap)
    end
    if WorldMapFrame.OnCanvasScaleChanged then
        hooksecurefunc(WorldMapFrame, "OnCanvasScaleChanged", rescale)
    end
    WorldMapFrame:HookScript("OnShow", function()
        checks.showMining:SetChecked(settings().showMining ~= false)
        checks.showHerbs:SetChecked(settings().showHerbs ~= false)
        Gather.RefreshMap()
    end)
end

---------------------------------------------------------------------------
-- Sharing between players who run the addon (addon messages, 255 bytes each)
--   "S" .. entries      spots, one chunk of whole entries per message
--   "E" .. count        end of a share, count sent
--   "R"                 request: please share your spots with me
-- Spots from guild, party and raid members are taken as they come; spots
-- whispered by anyone else only while a request of ours is open, or from a
-- player you trust, or when whispers are accepted in general. Sending is
-- paced at five messages a second.
---------------------------------------------------------------------------
local PREFIX = "FCUIGather"
local CHUNK = 240
local SEND_INTERVAL = 0.2
local REQUEST_WINDOW = 180
local outbox = {}
local sendTicker
local requestedAt = 0
local incoming = {} -- sender -> { new, total, timer }
local saveTimer

local function myName()
    local name = UnitName("player")
    return name and name:lower() or ""
end

local function shortName(sender)
    return (sender or ""):match("^([^-]+)") or sender or ""
end

local function pumpOutbox()
    local item = table.remove(outbox, 1)
    if not item then
        if sendTicker then
            sendTicker:Cancel()
            sendTicker = nil
        end
        return
    end
    pcall(C_ChatInfo.SendAddonMessage, PREFIX, item.text, item.chatType, item.target)
end

local function queue(chatType, target, text)
    outbox[#outbox + 1] = { chatType = chatType, target = target, text = text }
    if not sendTicker then
        sendTicker = C_Timer.NewTicker(SEND_INTERVAL, pumpOutbox)
    end
end

local function shareTo(chatType, target)
    load()
    local chunk, count = "S", 0
    for p, list in pairs(nodes) do
        for _, node in ipairs(list) do
            local entry = encodeNode(p, node)
            if #chunk + #entry + 1 > CHUNK then
                queue(chatType, target, chunk)
                chunk = "S"
            end
            chunk = chunk .. (chunk == "S" and "" or ";") .. entry
            count = count + 1
        end
    end
    if chunk ~= "S" then
        queue(chatType, target, chunk)
    end
    queue(chatType, target, "E" .. count)
    return count
end

local function channelFor(word)
    word = (word or ""):lower()
    if word == "guild" then
        return IsInGuild and IsInGuild() and "GUILD" or nil, "you are not in a guild"
    elseif word == "party" then
        return IsInGroup and IsInGroup() and "PARTY" or nil, "you are not in a party"
    elseif word == "raid" then
        return IsInRaid and IsInRaid() and "RAID" or nil, "you are not in a raid"
    elseif word ~= "" then
        return "WHISPER", nil, word
    end
    return nil, "say guild, party, raid or a player name"
end

local function acceptFrom(channel, sender)
    local settingsTable = settings()
    if channel == "GUILD" or channel == "PARTY" or channel == "RAID" or channel == "INSTANCE_CHAT" then
        return settingsTable.acceptGroup ~= false
    end
    if channel == "WHISPER" then
        if settingsTable.acceptWhispers then
            return true
        end
        local trusted = settingsTable.trusted or {}
        if trusted[shortName(sender):lower()] then
            return true
        end
        return GetTime() - requestedAt < REQUEST_WINDOW
    end
    return false
end

local function reportIncoming(sender)
    local batch = incoming[sender]
    if not batch then
        return
    end
    incoming[sender] = nil
    ns.Print(
        "gather: %d spot%s from %s, %d new (%d mining, %d herbs known now)",
        batch.total,
        batch.total == 1 and "" or "s",
        shortName(sender),
        batch.new,
        #nodes.m,
        #nodes.h
    )
end

local function scheduleSave()
    if saveTimer then
        return
    end
    saveTimer = C_Timer.NewTimer(1, function()
        saveTimer = nil
        save()
        Gather.RefreshMap()
    end)
end

local function onAddonMessage(_, _, prefix, text, channel, sender)
    if prefix ~= PREFIX or type(text) ~= "string" then
        return
    end
    if shortName(sender):lower() == myName() then
        return -- our own broadcast coming back
    end
    local kind = text:sub(1, 1)
    if kind == "R" then
        if settings().answerRequests ~= false and channel ~= "WHISPER" then
            shareTo("WHISPER", shortName(sender))
        end
        return
    end
    if not acceptFrom(channel, sender) then
        return
    end
    load()
    local batch = incoming[sender]
    if not batch then
        batch = { new = 0, total = 0 }
        incoming[sender] = batch
    end
    if batch.timer then
        batch.timer:Cancel()
    end
    if kind == "S" then
        for entry in text:sub(2):gmatch("[^;]+") do
            local p, node = decodeNode(entry)
            if p and node.map and node.x > 0 and node.y > 0 and node.x < 1 and node.y < 1 then
                batch.total = batch.total + 1
                if merge(p, node) then
                    batch.new = batch.new + 1
                end
            end
        end
        scheduleSave()
        -- a share without its end marker still gets reported
        batch.timer = C_Timer.NewTimer(5, function()
            reportIncoming(sender)
        end)
    elseif kind == "E" then
        reportIncoming(sender)
    end
end

function Gather.Share(rest)
    local chatType, why, target = channelFor(rest)
    if not chatType then
        ns.Print("gather share: %s", why)
        return
    end
    load()
    local count = shareTo(chatType, target)
    ns.Print(
        "gather: sending %d spot%s to %s (%d messages, a few seconds)",
        count,
        count == 1 and "" or "s",
        target or chatType:lower(),
        #outbox
    )
end

function Gather.Request(rest)
    local chatType, why = channelFor(rest)
    if not chatType or chatType == "WHISPER" then
        ns.Print("gather request: %s", chatType == "WHISPER" and "say guild, party or raid" or why)
        return
    end
    requestedAt = GetTime()
    queue(chatType, nil, "R")
    ns.Print(
        "gather: asked the %s for their spots; whispers with spots are accepted for three minutes",
        chatType:lower()
    )
end

---------------------------------------------------------------------------
-- Commands and lifecycle
---------------------------------------------------------------------------
function Gather.Command(rest)
    load()
    local word, arg = (rest or ""):match("^(%S+)%s*(.-)$")
    if word == "share" then
        Gather.Share(arg)
        return
    elseif word == "request" then
        Gather.Request(arg)
        return
    elseif word == "trust" and arg ~= "" then
        settings().trusted = settings().trusted or {}
        local key = arg:lower()
        settings().trusted[key] = not settings().trusted[key] or nil
        ns.DB.Flush()
        ns.Print(
            "gather: spots whispered by %s are %s",
            arg,
            settings().trusted[key] and "accepted" or "no longer accepted"
        )
        return
    elseif word == "whispers" and (arg == "on" or arg == "off") then
        settings().acceptWhispers = arg == "on"
        ns.DB.Flush()
        ns.Print("gather: spots whispered by anyone are %s", arg == "on" and "accepted" or "ignored")
        return
    elseif word == "answer" and (arg == "on" or arg == "off") then
        settings().answerRequests = arg == "on"
        ns.DB.Flush()
        ns.Print("gather: requests from guild, party and raid are %s", arg == "on" and "answered" or "ignored")
        return
    end
    if rest == "clear" or rest == "clear mining" or rest == "clear herbs" then
        if rest == "clear" then
            nodes = { m = {}, h = {} }
        else
            nodes[rest == "clear mining" and "m" or "h"] = {}
        end
        save()
        Gather.RefreshMap()
        ns.Print("gather records cleared (%s)", rest == "clear" and "all" or rest:sub(7))
        return
    end
    local maps = {}
    for _, list in pairs(nodes) do
        for _, node in ipairs(list) do
            maps[node.map] = true
        end
    end
    local count = 0
    for _ in pairs(maps) do
        count = count + 1
    end
    ns.Print(
        "gather: %d mining and %d herb spots on %d maps; pins on the M map, checkboxes bottom left",
        #nodes.m,
        #nodes.h,
        count
    )
    ns.Print("  stores: %s", ns.DB.BlobReport())
    ns.Print("  share guild|party|raid|<player>, request guild|party|raid, trust <player>,")
    ns.Print("  whispers on|off, answer on|off, clear [mining|herbs]")
end

function Gather:Init()
    settings()
end

function Gather:Enable()
    load()
    ns.RegisterEvent("UNIT_SPELLCAST_SENT", self, onSent)
    ns.RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", self, onSucceeded)
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
        ns.RegisterEvent("CHAT_MSG_ADDON", self, onAddonMessage)
    end
    if canvas() then
        attachToMap()
    else
        ns.RegisterEvent("ADDON_LOADED", self, function(_, _, name)
            if name == "Blizzard_WorldMap" then
                attachToMap()
            end
        end)
        ns.RegisterEvent("PLAYER_ENTERING_WORLD", self, attachToMap)
    end
end

function Gather:Disable()
    ns.UnregisterAllEvents(self)
    for _, pin in ipairs(pins) do
        pin:Hide()
    end
    for _, check in pairs(checks) do
        check:Hide()
    end
    ns.Print("Gather disabled: nodes are no longer recorded or drawn")
end

function Gather:Refresh()
    Gather.RefreshMap()
end

function Gather:Diag()
    load()
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local here = { m = 0, h = 0 }
    for p, list in pairs(nodes) do
        for _, node in ipairs(list) do
            if node.map == mapID then
                here[p] = here[p] + 1
            end
        end
    end
    ns.Print(
        "  mining=%d herbs=%d (here: %d / %d, player map %s) overlay=%s pending=%s",
        #nodes.m,
        #nodes.h,
        here.m,
        here.h,
        tostring(mapID),
        tostring(overlay ~= nil),
        tostring(pending and pending.name)
    )
    local maps = {}
    for _, list in pairs(nodes) do
        for _, node in ipairs(list) do
            maps[node.map] = (maps[node.map] or 0) + 1
        end
    end
    local parts = {}
    for id, count in pairs(maps) do
        parts[#parts + 1] = tostring(id) .. ":" .. count
    end
    ns.Print(
        "  maps with spots: %s; window map=%s shown=%s; checks mining=%s herbs=%s; last refresh: %s",
        table.concat(parts, " "),
        tostring(WorldMapFrame and WorldMapFrame:GetMapID()),
        tostring(WorldMapFrame and WorldMapFrame:IsShown()),
        tostring(settings().showMining),
        tostring(settings().showHerbs),
        Gather.lastRefresh
    )
    local child = canvas()
    if child then
        ns.Print(
            "  canvas %.0fx%.0f scale %.2f level %d shown=%s; overlay level %s shown=%s",
            child:GetWidth(),
            child:GetHeight(),
            child:GetEffectiveScale(),
            child:GetFrameLevel(),
            tostring(child:IsVisible()),
            tostring(overlay and overlay:GetFrameLevel()),
            tostring(overlay and overlay:IsVisible())
        )
    end
    local pin = pins[1]
    if pin then
        local point, relativeTo, relativePoint, x, y = pin:GetPoint(1)
        ns.Print(
            "  pin1 shown=%s visible=%s %s -> %s %s (%.0f, %.0f) size %.0f scale %.2f level %d texture=%s",
            tostring(pin:IsShown()),
            tostring(pin:IsVisible()),
            tostring(point),
            tostring(relativeTo and relativeTo:GetName()),
            tostring(relativePoint),
            x or 0,
            y or 0,
            pin:GetWidth(),
            pin:GetScale(),
            pin:GetFrameLevel(),
            tostring(pin.Icon:GetTexture())
        )
    else
        ns.Print("  no pin frames created yet")
    end
end
