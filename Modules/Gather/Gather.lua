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
local PIN_LEVEL = 1500 -- under Blizzard's pins (2000+), over the map art
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

local function save()
    local parts = {}
    for p, list in pairs(nodes) do
        for _, node in ipairs(list) do
            parts[#parts + 1] = ("%s,%d,%d,%d,%d,%s"):format(
                p,
                node.map,
                math.floor(node.x * 10000 + 0.5),
                math.floor(node.y * 10000 + 0.5),
                node.count,
                ns.DB.Escape(node.name or "")
            )
        end
    end
    ns.DB.SetBlob(BLOB, table.concat(parts, ";"))
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

local function getPin(index)
    local pin = pins[index]
    if pin then
        return pin
    end
    pin = CreateFrame("Button", nil, overlay)
    pin:SetSize(PIN_SIZE, PIN_SIZE)
    pin:SetFrameLevel(PIN_LEVEL)
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

local function pinScale()
    local scale = WorldMapFrame and WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale() or 1
    if not scale or scale <= 0 then
        scale = 1
    end
    return 1 / scale
end

local function placePin(pin, node)
    local child = canvas()
    local scale = pinScale()
    pin:SetScale(scale)
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", child, "TOPLEFT", (child:GetWidth() * node.x) / scale, -(child:GetHeight() * node.y) / scale)
end

function Gather.RefreshMap()
    if not overlay or not WorldMapFrame or not WorldMapFrame:IsShown() then
        return
    end
    load()
    local mapID = WorldMapFrame:GetMapID()
    local used = 0
    local shown = settings()
    for _, profession in ipairs({ "m", "h" }) do
        local wanted = (profession == "m" and shown.showMining) or (profession == "h" and shown.showHerbs)
        if wanted then
            for _, node in ipairs(nodes[profession]) do
                if node.map == mapID then
                    used = used + 1
                    local pin = getPin(used)
                    pin.node = node
                    pin.profession = profession
                    pin.Icon:SetTexture(ICONS[profession])
                    placePin(pin, node)
                    pin:Show()
                end
            end
        end
    end
    for index = used + 1, #pins do
        pins[index]:Hide()
    end
end

local function rescale()
    for _, pin in ipairs(pins) do
        if pin:IsShown() and pin.node then
            placePin(pin, pin.node)
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

local function attachToMap()
    if overlay or not canvas() then
        return
    end
    overlay = CreateFrame("Frame", "FCUI_GatherOverlay", canvas())
    overlay:SetAllPoints()
    overlay:SetFrameLevel(PIN_LEVEL)
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
-- Commands and lifecycle
---------------------------------------------------------------------------
function Gather.Command(rest)
    load()
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
    ns.Print("  /fcui gather clear [mining|herbs] forgets them")
end

function Gather:Init()
    settings()
end

function Gather:Enable()
    load()
    ns.RegisterEvent("UNIT_SPELLCAST_SENT", self, onSent)
    ns.RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", self, onSucceeded)
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
        "  mining=%d herbs=%d (here: %d / %d, map %s) overlay=%s pending=%s",
        #nodes.m,
        #nodes.h,
        here.m,
        here.h,
        tostring(mapID),
        tostring(overlay ~= nil),
        tostring(pending and pending.name)
    )
end
