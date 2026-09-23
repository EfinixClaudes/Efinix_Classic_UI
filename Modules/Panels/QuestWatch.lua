local _, ns = ...

-- Quest watch (QuestWatchFrame 1.12): a plain text list under the minimap,
-- yellow quest titles with their objectives as " - " lines below, no boxes
-- and no animations. Two things 2006 did not have, both taken from the 2006
-- quest log instead: the watched quests are grouped under their quest-log
-- zone headers, and each zone folds with the log's plus/minus button. The
-- folded zones are remembered.
--
-- Strategy: replace. Blizzard's ObjectiveTrackerFrame (boxed blocks with
-- headers, icons and slide animations) is hidden while this runs.
local QW = ns.RegisterModule("QuestWatch", {})
ns.QuestWatch = QW

local WIDTH = 250
local RIGHT_INSET = 100 -- clear of MultiBarRight and MultiBarLeft (38 + 5 + 38 px plus the 7 px edge gap)
local LINE_GAP = 2
local GROUP_GAP = 8
local INDENT_QUEST = 18 -- text starts right of the 16 px plus/minus button
local INDENT_OBJECTIVE = 28
local PLUS = "Interface\\Buttons\\UI-PlusButton-Up"
local MINUS = "Interface\\Buttons\\UI-MinusButton-Up"
local PLUS_HIGHLIGHT = "Interface\\Buttons\\UI-PlusButton-Hilight"

-- one point larger than the 1.12 GameFontNormalSmall lines: zone 13, quest 12, objective 11
local function sizedFont(name, base, size)
    local font = CreateFont(name)
    font:SetFontObject(base)
    local path, _, flags = font:GetFont()
    font:SetFont(path, size, flags)
    return font
end
local FONT_ZONE = sizedFont("FCUI_QuestWatchZoneFont", GameFontNormal, 13)
local FONT_QUEST = sizedFont("FCUI_QuestWatchQuestFont", GameFontNormal, 12)
local FONT_OBJECTIVE = sizedFont("FCUI_QuestWatchObjectiveFont", GameFontNormal, 11)

local frame
local lines = {} -- pooled line buttons
local pending = false

local function settings()
    ns.db.questWatch = ns.db.questWatch or { collapsed = {} }
    ns.db.questWatch.collapsed = ns.db.questWatch.collapsed or {}
    return ns.db.questWatch
end

local function plain(value)
    if ns.Compat.IsSecret(value) then
        return nil
    end
    return value
end

---------------------------------------------------------------------------
-- Data: watched quests grouped by their quest-log zone header
---------------------------------------------------------------------------
local function buildGroups()
    local zoneOf, zoneOrder = {}, {}
    local currentZone = OTHER or "Other"
    local numEntries = C_QuestLog.GetNumQuestLogEntries() or 0
    for index = 1, numEntries do
        local info = C_QuestLog.GetInfo(index)
        if info then
            if info.isHeader then
                currentZone = info.title or currentZone
                if not zoneOrder[currentZone] then
                    zoneOrder[currentZone] = index
                end
            elseif info.questID then
                zoneOf[info.questID] = currentZone
            end
        end
    end

    local groups, byZone = {}, {}
    for watchIndex = 1, C_QuestLog.GetNumQuestWatches() or 0 do
        local questID = C_QuestLog.GetQuestIDForQuestWatchIndex(watchIndex)
        if questID then
            local zone = zoneOf[questID] or (OTHER or "Other")
            local group = byZone[zone]
            if not group then
                group = { zone = zone, order = zoneOrder[zone] or math.huge, quests = {} }
                byZone[zone] = group
                groups[#groups + 1] = group
            end
            local objectives = {}
            for _, objective in ipairs(C_QuestLog.GetQuestObjectives(questID) or {}) do
                local text = plain(objective.text)
                if type(text) == "string" and text ~= "" then
                    objectives[#objectives + 1] = { text = text, finished = plain(objective.finished) == true }
                end
            end
            local complete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID) == true
            if #objectives == 0 and complete then
                -- a quest without counters: the log's completion line, as the tracker shows it
                local logIndex = C_QuestLog.GetLogIndexForQuestID(questID)
                local text = logIndex and GetQuestLogCompletionText and GetQuestLogCompletionText(logIndex)
                if type(text) == "string" and text ~= "" then
                    objectives[1] = { text = text, finished = false }
                end
            end
            group.quests[#group.quests + 1] = {
                questID = questID,
                title = C_QuestLog.GetTitleForQuestID(questID) or ("Quest " .. questID),
                objectives = objectives,
                complete = complete,
            }
        end
    end
    table.sort(groups, function(a, b)
        if a.order ~= b.order then
            return a.order < b.order
        end
        return a.zone < b.zone
    end)
    return groups
end

---------------------------------------------------------------------------
-- Lines
---------------------------------------------------------------------------
local function onLineClick(self, mouseButton)
    if self.zone then
        local collapsed = settings().collapsed
        collapsed[self.zone] = not collapsed[self.zone] or nil
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        QW.Update()
    elseif self.questID then
        if IsModifiedClick("QUESTWATCHTOGGLE") or mouseButton == "RightButton" then
            C_QuestLog.RemoveQuestWatch(self.questID)
        elseif ChatEdit_TryInsertQuestLinkForQuestID and ChatEdit_TryInsertQuestLinkForQuestID(self.questID) then
            return
        elseif QuestMapFrame_OpenToQuestDetails then
            QuestMapFrame_OpenToQuestDetails(self.questID)
        end
    end
end

local function getLine(index)
    local line = lines[index]
    if line then
        return line
    end
    line = CreateFrame("Button", nil, frame)
    line:SetWidth(WIDTH)
    line:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    line.Toggle = line:CreateTexture(nil, "ARTWORK")
    line.Toggle:SetSize(16, 16)
    line.Toggle:SetPoint("TOPLEFT", line, "TOPLEFT", 0, 0)
    line.Text = line:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    line.Text:SetJustifyH("LEFT")
    line.Text:SetJustifyV("TOP")
    line.Text:SetWordWrap(true)
    line.Text:SetNonSpaceWrap(false)
    line:SetHighlightTexture(PLUS_HIGHLIGHT, "ADD")
    line:GetHighlightTexture():SetAllPoints(line.Toggle)
    line:SetScript("OnClick", onLineClick)
    line:SetScript("OnEnter", function(self)
        if self.questID then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText(self.Text:GetText(), 1, 0.82, 0)
            GameTooltip:AddLine(
                "Click: open in the quest log. Shift-click or right-click: stop watching.",
                0.8,
                0.8,
                0.8,
                true
            )
            GameTooltip:Show()
        elseif self.zone then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText(self.Text:GetText(), 1, 0.82, 0)
            GameTooltip:AddLine(
                settings().collapsed[self.zone] and "Click to show this zone" or "Click to fold this zone",
                0.8,
                0.8,
                0.8
            )
            GameTooltip:Show()
        end
    end)
    line:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    lines[index] = line
    return line
end

local function placeLine(line, y, indent, text, r, g, b, font)
    line.Text:SetFontObject(font)
    line.Text:ClearAllPoints()
    line.Text:SetPoint("TOPLEFT", line, "TOPLEFT", indent, 0)
    line.Text:SetWidth(WIDTH - indent)
    line.Text:SetText(text)
    line.Text:SetTextColor(r, g, b)
    local height = math.max(line.Text:GetStringHeight(), 16)
    line:SetHeight(height)
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, y)
    line:Show()
    return y - height - LINE_GAP
end

---------------------------------------------------------------------------
-- Update (QuestWatch_Update 1.12)
---------------------------------------------------------------------------
function QW.Update()
    if not frame then
        return
    end
    pending = false
    local groups = buildGroups()
    local collapsed = settings().collapsed
    local y = 0
    local used = 0
    for _, group in ipairs(groups) do
        used = used + 1
        local header = getLine(used)
        header.zone = group.zone
        header.questID = nil
        header:EnableMouse(true)
        header.Toggle:SetTexture(collapsed[group.zone] and PLUS or MINUS)
        header.Toggle:Show()
        local label = group.zone
        if collapsed[group.zone] then
            label = ("%s (%d)"):format(group.zone, #group.quests)
        end
        y = placeLine(header, y, INDENT_QUEST, label, 1, 0.82, 0, FONT_ZONE)
        if not collapsed[group.zone] then
            for _, quest in ipairs(group.quests) do
                used = used + 1
                local title = getLine(used)
                title.zone = nil
                title.questID = quest.questID
                title:EnableMouse(true)
                title.Toggle:Hide()
                local text = quest.title
                if quest.complete and #quest.objectives == 0 then
                    text = text .. " (" .. (COMPLETE or "Complete") .. ")"
                end
                y = placeLine(title, y, INDENT_QUEST, text, 1, 0.82, 0, FONT_QUEST)
                for _, objective in ipairs(quest.objectives) do
                    used = used + 1
                    local line = getLine(used)
                    line.zone = nil
                    line.questID = nil
                    line:EnableMouse(false)
                    line.Toggle:Hide()
                    if objective.finished then
                        y = placeLine(line, y, INDENT_OBJECTIVE, "- " .. objective.text, 0.6, 0.6, 0.6, FONT_OBJECTIVE)
                    else
                        y = placeLine(line, y, INDENT_OBJECTIVE, "- " .. objective.text, 1, 1, 1, FONT_OBJECTIVE)
                    end
                end
            end
        end
        y = y - GROUP_GAP
    end
    for index = used + 1, #lines do
        lines[index]:Hide()
        lines[index].zone = nil
        lines[index].questID = nil
    end
    frame:SetHeight(math.max(1, -y))
    frame:SetShown(used > 0)
end

local function scheduleUpdate()
    if pending then
        return
    end
    pending = true
    C_Timer.After(0.1, QW.Update)
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------
local function createFrame()
    frame = CreateFrame("Frame", "FCUI_QuestWatchFrame", UIParent)
    frame:SetSize(WIDTH, 1)
    -- 1.12: hanging under the minimap on the right; pulled in past the two
    -- vertical action bars at the screen edge
    if MinimapCluster then
        frame:SetPoint("TOPRIGHT", MinimapCluster, "BOTTOMRIGHT", -RIGHT_INSET, -12)
    else
        frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -RIGHT_INSET, -240)
    end
    frame:SetFrameStrata("BACKGROUND")
    frame:Hide()
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function QW:Init()
    if not C_QuestLog or not C_QuestLog.GetNumQuestWatches or not C_QuestLog.GetQuestIDForQuestWatchIndex then
        error("C_QuestLog watch API missing")
    end
    createFrame()
end

function QW:Enable()
    if ObjectiveTrackerFrame then
        ns.Hide(ObjectiveTrackerFrame)
    end
    for _, event in ipairs({
        "QUEST_WATCH_LIST_CHANGED",
        "QUEST_WATCH_UPDATE",
        "QUEST_LOG_UPDATE",
        "UNIT_QUEST_LOG_CHANGED",
        "QUEST_ACCEPTED",
        "QUEST_REMOVED",
        "QUEST_TURNED_IN",
        "PLAYER_ENTERING_WORLD",
    }) do
        ns.RegisterEvent(event, self, scheduleUpdate)
    end
    scheduleUpdate()
end

function QW:Disable()
    ns.UnregisterAllEvents(self)
    if frame then
        frame:Hide()
    end
    ns.Print("QuestWatch disabled, /reload to restore the Blizzard objective tracker")
end

function QW:Refresh()
    scheduleUpdate()
end

function QW:Diag()
    local groups = buildGroups()
    ns.Print(
        "  watched=%d zones=%d shown=%s",
        C_QuestLog.GetNumQuestWatches() or 0,
        #groups,
        tostring(frame and frame:IsShown())
    )
    for _, group in ipairs(groups) do
        ns.Print("  %s: %d quests%s", group.zone, #group.quests, settings().collapsed[group.zone] and " (folded)" or "")
    end
end
