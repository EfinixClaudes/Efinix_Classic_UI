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
local LABELS = { m = "Mining", h = "Herbs", q = "Quests" }

-- Quest givers ("q" spots): Forever's world map has no quest data for the
-- Vanilla quests (C_QuestLine.GetAvailableQuestLines is empty), so every
-- quest a giver offers is recorded with its level and the giver's spot, and
-- shared with the guild like the gathering spots. The name field carries
-- "questID|level|title|giver"; level 0 means unknown.
local QUEST_PIN_SIZE = 16
local QUEST_LEVELS_ABOVE = 3 -- 1.12 shows quests up to a few levels above you as available

-- Per-node icons: the icon of the item the node yields. The client's item
-- cache is asked first (an ore or herb you have gathered is cached), these
-- Vanilla icons are the backup, and the pick or leaf the last resort.
local ICON_PATH = "Interface\\Icons\\"
local KNOWN_ICONS = {
    ["copper ore"] = ICON_PATH .. "INV_Ore_Copper_01",
    ["tin ore"] = ICON_PATH .. "INV_Ore_Tin_01",
    ["silver ore"] = ICON_PATH .. "INV_Ore_Silver_01",
    ["iron ore"] = ICON_PATH .. "INV_Ore_Iron_01",
    ["gold ore"] = ICON_PATH .. "INV_Ore_Gold_01",
    ["mithril ore"] = ICON_PATH .. "INV_Ore_Mithril_02",
    ["truesilver ore"] = ICON_PATH .. "INV_Ore_TrueSilver_01",
    ["dark iron ore"] = ICON_PATH .. "INV_Ore_Mithril_01",
    ["thorium ore"] = ICON_PATH .. "INV_Ore_Thorium_02",
    ["peacebloom"] = ICON_PATH .. "INV_Misc_Flower_02",
    ["silverleaf"] = ICON_PATH .. "INV_Misc_Herb_10",
    ["earthroot"] = ICON_PATH .. "INV_Misc_Root_01",
    ["golden sansam"] = ICON_PATH .. "INV_Misc_Herb_SansamRoot",
    ["dreamfoil"] = ICON_PATH .. "INV_Misc_Herb_Dreamfoil",
    ["mountain silversage"] = ICON_PATH .. "INV_Misc_Herb_SilverSage",
    ["plaguebloom"] = ICON_PATH .. "INV_Misc_Herb_Plaguebloom",
    ["icecap"] = ICON_PATH .. "INV_Misc_Herb_Icecap",
    ["black lotus"] = ICON_PATH .. "INV_Misc_Herb_BlackLotus",
}
local iconCache = {} -- item name (lower) -> icon | false

-- "Ooze Covered Rich Thorium Vein" -> "Thorium Ore", "Iron Deposit" -> "Iron Ore"
local function itemNameFor(profession, nodeName)
    if type(nodeName) ~= "string" or nodeName == "" then
        return nil
    end
    local name = nodeName:gsub("^Ooze Covered ", ""):gsub("^Rich ", ""):gsub("^Small ", "")
    if profession == "m" then
        name = name:gsub(" Mineral Vein$", " Ore"):gsub(" Vein$", " Ore"):gsub(" Deposit$", " Ore")
    end
    return name
end

local function iconFor(profession, nodeName)
    local item = itemNameFor(profession, nodeName)
    if not item then
        return nil
    end
    local key = item:lower()
    local cached = iconCache[key]
    if cached ~= nil then
        return cached or nil
    end
    local icon
    if C_Item and C_Item.GetItemIconByID then
        local ok, result = pcall(C_Item.GetItemIconByID, item)
        if ok and type(result) == "number" and result > 0 then
            icon = result
        end
    end
    icon = icon or KNOWN_ICONS[key]
    iconCache[key] = icon or false
    return icon
end

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

local nodes = { m = {}, h = {}, q = {} } -- profession -> list of { map, x, y, count, name }
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
local decodeNode, merge, save -- defined below

-- All stored copies are merged (see DB.GetBlobSources); if the merge found
-- more than any single copy held, the merged list is written back at once.
local function load()
    if loaded then
        return
    end
    loaded = true
    nodes = { m = {}, h = {}, q = {} }
    local sources = ns.DB.GetBlobSources(BLOB)
    local largest = 0
    for _, blob in ipairs(sources) do
        local count = 0
        for entry in blob:gmatch("[^;]+") do
            local p, node = decodeNode(entry)
            if p then
                count = count + 1
                merge(p, node)
            end
        end
        largest = math.max(largest, count)
    end
    if #nodes.m + #nodes.h + #nodes.q > largest then
        save()
    end
end

local function encodeNode(p, node)
    return ("%s,%d,%d,%d,%d,%s,%s"):format(
        p,
        node.map,
        math.floor(node.x * 10000 + 0.5),
        math.floor(node.y * 10000 + 0.5),
        node.count,
        ns.DB.Escape(node.name or ""),
        type(node.icon) == "number" and tostring(node.icon) or ""
    )
end

-- the icon field is optional (older entries have six fields)
decodeNode = function(entry)
    local p, map, x, y, count, name, icon = entry:match("^([mhq]),(%d+),(%d+),(%d+),(%d+),([^,]*),?(%d*)$")
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
            icon = tonumber(icon),
        }
end

save = function()
    local parts = {}
    for p, list in pairs(nodes) do
        for _, node in ipairs(list) do
            parts[#parts + 1] = encodeNode(p, node)
        end
    end
    ns.DB.SetBlob(BLOB, table.concat(parts, ";"))
end

-- Merge one received spot into the list: a known spot within MERGE_DISTANCE
-- keeps the larger count (the same map arriving twice must change nothing),
-- anything else is new. Returns true when it was new.
merge = function(p, incoming)
    local list = nodes[p]
    for _, node in ipairs(list) do
        if
            (p ~= "q" or node.name == incoming.name)
            and node.map == incoming.map
            and math.abs(node.x - incoming.x) < MERGE_DISTANCE
            and math.abs(node.y - incoming.y) < MERGE_DISTANCE
        then
            node.count = math.min(999, math.max(node.count, incoming.count or 1))
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
    local icon = iconFor(profession, name)
    list[#list + 1] = {
        map = mapID,
        x = x,
        y = y,
        count = 1,
        name = name or "",
        icon = type(icon) == "number" and icon or nil,
    }
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
        if self.quests then
            GameTooltip:SetText(self.giver ~= "" and self.giver or "Quest giver", 1, 1, 1)
            for _, quest in ipairs(self.quests) do
                local color = GetQuestDifficultyColor and quest.level > 0 and GetQuestDifficultyColor(quest.level)
                local label = quest.level > 0 and ("[%d] %s"):format(quest.level, quest.title) or quest.title
                if color then
                    GameTooltip:AddLine(label, color.r, color.g, color.b)
                else
                    GameTooltip:AddLine(label, 1, 0.82, 0)
                end
            end
            GameTooltip:Show()
            return
        end
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
                    pin.quests = nil
                    pin:SetSize(PIN_SIZE, PIN_SIZE)
                    pin.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    local icon = node.icon or iconFor(profession, node.name)
                    if type(icon) == "number" and not node.icon then
                        node.icon = icon -- learned from the cache; saved with the next change
                    end
                    pin.Icon:SetTexture(icon or ICONS[profession])
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
    if shown.showQuests ~= false then
        used = Gather.PlaceQuestPins(mapID, used)
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

-- the quest spots worth a "!" for this character: not done, not in the log,
-- not grey, at most a few levels above; unknown levels always count
local function questFields(node)
    local id, level, title, giver = (node.name or ""):match("^(%d+)|(%d*)|([^|]*)|?(.*)$")
    return tonumber(id), tonumber(level) or 0, title or "?", giver or ""
end

local function questWanted(questID, level)
    if not questID then
        return false
    end
    if C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(questID) then
        return false
    end
    if C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(questID) then
        return false
    end
    if level > 0 then
        local playerLevel = UnitLevel("player") or 1
        local trivial = UnitQuestTrivialLevelRange and UnitQuestTrivialLevelRange("player") or 8
        if level > playerLevel + QUEST_LEVELS_ABOVE or playerLevel - level > trivial then
            return false
        end
    end
    return true
end

-- one "!" per giver: quests recorded at the same spot share a pin
function Gather.PlaceQuestPins(mapID, used)
    local buckets, order = {}, {}
    for _, node in ipairs(nodes.q) do
        local questID, level, title, giver = questFields(node)
        if questWanted(questID, level) then
            local x, y = positionOn(node, mapID)
            if x then
                local key = math.floor(x / MERGE_DISTANCE + 0.5) .. ":" .. math.floor(y / MERGE_DISTANCE + 0.5)
                local bucket = buckets[key]
                if not bucket then
                    bucket = { x = x, y = y, giver = giver, quests = {} }
                    buckets[key] = bucket
                    order[#order + 1] = bucket
                end
                table.insert(bucket.quests, { level = level, title = title })
            end
        end
    end
    for _, bucket in ipairs(order) do
        table.sort(bucket.quests, function(a, b)
            return a.level < b.level
        end)
        used = used + 1
        local pin = getPin(used)
        pin.node = nil
        pin.profession = "q"
        pin.quests = bucket.quests
        pin.giver = bucket.giver
        pin:SetSize(QUEST_PIN_SIZE, QUEST_PIN_SIZE)
        local ok = pcall(pin.Icon.SetAtlas, pin.Icon, "QuestNormal")
        if not ok or not pin.Icon:GetAtlas() then
            pin.Icon:SetColorTexture(1, 0.82, 0, 1)
        end
        placePin(pin, bucket.x, bucket.y)
        pin:SetFrameLevel(pinLevel() + 1)
        pin:Show()
    end
    return used
end

---------------------------------------------------------------------------
-- Recording quest givers: every quest a giver offers, with its level when
-- the game tells it, at the player's spot (you stand next to the giver)
---------------------------------------------------------------------------
local function recordQuest(questID, level, title)
    if not questID or questID == 0 then
        return
    end
    load()
    local mapID, x, y = playerPosition()
    if not mapID then
        return
    end
    local giver = UnitName("questnpc") or UnitName("npc") or ""
    local name = ("%d|%d|%s|%s"):format(questID, tonumber(level) or 0, title or "", giver)
    -- a later visit can supply a level an earlier record lacked
    for _, node in ipairs(nodes.q) do
        local id, known = questFields(node)
        if id == questID and node.map == mapID then
            if known == 0 and (tonumber(level) or 0) > 0 then
                node.name = name
                save()
            end
            return
        end
    end
    if merge("q", { map = mapID, x = x, y = y, count = 1, name = name }) then
        save()
        Gather.RefreshMap()
    end
end

local function onQuestGossip()
    if not C_GossipInfo or not C_GossipInfo.GetAvailableQuests then
        return
    end
    for _, quest in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
        recordQuest(quest.questID, plain(quest.questLevel), quest.title)
    end
end

local function onQuestGreeting()
    for i = 1, (GetNumAvailableQuests and GetNumAvailableQuests() or 0) do
        local questID = select(5, GetAvailableQuestInfo(i))
        local level = GetAvailableLevel and GetAvailableLevel(i) or 0
        recordQuest(questID, level, GetAvailableTitle and GetAvailableTitle(i))
    end
end

local function onQuestDetail()
    local questID = GetQuestID and GetQuestID()
    if questID and questID > 0 then
        recordQuest(questID, 0, GetTitleText and GetTitleText())
    end
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
    createCheck("showQuests", "Quests", 150)
    if WorldMapFrame.OnMapChanged then
        hooksecurefunc(WorldMapFrame, "OnMapChanged", Gather.RefreshMap)
    end
    if WorldMapFrame.OnCanvasScaleChanged then
        hooksecurefunc(WorldMapFrame, "OnCanvasScaleChanged", rescale)
    end
    WorldMapFrame:HookScript("OnShow", function()
        checks.showMining:SetChecked(settings().showMining ~= false)
        checks.showHerbs:SetChecked(settings().showHerbs ~= false)
        checks.showQuests:SetChecked(settings().showQuests ~= false)
        Gather.RefreshMap()
    end)
end

---------------------------------------------------------------------------
-- Sharing between players who run the addon (addon messages, 255 bytes each)
--   "S" .. entries      spots, one chunk of whole entries per message
--   "E" .. count        end of a share, count sent
--   "R"                 request: please share your spots with me
--   "H"                 hello (guild, at login): who has spots?
--   "N" .. count        answer to a hello: I hold that many spots
-- Spots from guild, party and raid members are taken as they come; spots
-- whispered by anyone else only while a request of ours is open, or from a
-- player you trust, or when whispers are accepted in general. Sending is
-- paced at five messages a second.
--
-- Automatic sync at login: hello to the guild, every member with the addon
-- answers with a count, and after a few seconds the two largest holders are
-- asked for their whole map. A holder sends a given player at most once in
-- twelve hours, and a "R" by whisper is only answered right after such an
-- exchange (or from a trusted player), so nobody outside can pull maps.
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
local HELLO_WAIT = 8
local SYNC_SOURCES = 2
local SYNC_REPEAT = 12 * 60 * 60
local helloAt = 0
local offers = {} -- sender -> count, answers to our hello
local offered = {} -- sender -> GetTime() when we answered their hello
local helloTimer

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

local function totalSpots()
    return #nodes.m + #nodes.h + #nodes.q
end

-- after the hello wait: pull the whole map from the largest holders
local function finishHello()
    helloTimer = nil
    local list = {}
    for sender, count in pairs(offers) do
        if count > 0 then
            list[#list + 1] = { sender = sender, count = count }
        end
    end
    offers = {}
    table.sort(list, function(a, b)
        return a.count > b.count
    end)
    local asked = {}
    for i = 1, math.min(SYNC_SOURCES, #list) do
        queue("WHISPER", shortName(list[i].sender), "R")
        asked[#asked + 1] = shortName(list[i].sender) .. " (" .. list[i].count .. ")"
    end
    if #asked > 0 then
        requestedAt = GetTime()
        ns.Print("gather: syncing spots from %s", table.concat(asked, ", "))
    end
end

local function sendHello()
    if settings().autoSync == false or not (IsInGuild and IsInGuild()) then
        return
    end
    helloAt = GetTime()
    offers = {}
    queue("GUILD", nil, "H")
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
    local key = shortName(sender):lower()
    if kind == "H" then
        -- someone logged in: tell them what we hold, guild only
        if channel == "GUILD" and settings().autoSync ~= false and settings().answerRequests ~= false then
            load()
            local synced = settings().syncedWith or {}
            if totalSpots() > 0 and GetTime() > 0 and (time() - (synced[key] or 0)) > SYNC_REPEAT then
                offered[sender] = GetTime()
                queue("WHISPER", shortName(sender), "N" .. totalSpots())
            end
        end
        return
    elseif kind == "N" then
        if GetTime() - helloAt < HELLO_WAIT + 2 and channel == "WHISPER" then
            offers[sender] = tonumber(text:sub(2)) or 0
            if not helloTimer then
                helloTimer = C_Timer.NewTimer(HELLO_WAIT, finishHello)
            end
        end
        return
    elseif kind == "R" then
        if settings().answerRequests == false then
            return
        end
        local trusted = settings().trusted or {}
        local fromGroup = channel ~= "WHISPER"
        local afterHello = offered[sender] ~= nil and GetTime() - offered[sender] < 120
        if fromGroup or afterHello or trusted[key] then
            if afterHello then
                settings().syncedWith = settings().syncedWith or {}
                settings().syncedWith[key] = time()
                ns.DB.Flush()
            end
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
    elseif word == "auto" and (arg == "on" or arg == "off") then
        settings().autoSync = arg == "on"
        ns.DB.Flush()
        ns.Print("gather: automatic guild sync at login is %s", arg == "on" and "on" or "off")
        return
    elseif word == "sync" then
        sendHello()
        ns.Print("gather: asked the guild who holds spots")
        return
    end
    if rest == "clear" or rest == "clear mining" or rest == "clear herbs" then
        if rest == "clear" then
            nodes = { m = {}, h = {}, q = {} }
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
    ns.Print("  share guild|party|raid|<player>, request guild|party|raid, sync, trust <player>,")
    ns.Print("  auto on|off, whispers on|off, answer on|off, clear [mining|herbs]")
end

function Gather:Init()
    settings()
end

function Gather:Enable()
    load()
    ns.RegisterEvent("UNIT_SPELLCAST_SENT", self, onSent)
    ns.RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", self, onSucceeded)
    ns.RegisterEvent("GOSSIP_SHOW", self, onQuestGossip)
    ns.RegisterEvent("QUEST_GREETING", self, onQuestGreeting)
    ns.RegisterEvent("QUEST_DETAIL", self, onQuestDetail)
    -- the "!" disappear as quests are taken and done, and change with your level
    for _, event in ipairs({ "QUEST_ACCEPTED", "QUEST_TURNED_IN", "PLAYER_LEVEL_UP" }) do
        ns.RegisterEvent(event, self, function()
            C_Timer.After(0.5, Gather.RefreshMap)
        end)
    end
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
        ns.RegisterEvent("CHAT_MSG_ADDON", self, onAddonMessage)
        -- the guild roster and the others' addons need a moment after login
        ns.RegisterEvent("PLAYER_ENTERING_WORLD", self, function(_, _, isLogin, isReload)
            if isLogin or isReload then
                C_Timer.After(20, sendHello)
            end
        end)
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
