local _, ns = ...

-- Quest automation: pressing Interact with Target (or right-clicking) on a
-- quest giver walks through the quest dialogs by itself. Each dialog the
-- game opens is answered at once: a finished quest is handed in, a new one
-- is picked from the list and accepted, and the reward is taken when there
-- is nothing to choose. So spamming the interact key accepts and turns in
-- everything the NPC has.
--
-- Stops and leaves the choice to you: a reward with several items to pick,
-- a hand-in that costs money, a quest that flags you for PvP, grey (trivial)
-- quests, and anything while Shift is held.
local QA = ns.RegisterModule("QuestAuto", {})
ns.QuestAuto = QA

QA.trace = {} -- last events and what was done, for /fcui diag QuestAuto
local function note(text, ...)
    if select("#", ...) > 0 then
        text = text:format(...)
    end
    table.insert(QA.trace, 1, date("%H:%M:%S") .. " " .. text)
    QA.trace[9] = nil
end

local function paused()
    if IsShiftKeyDown() then
        note("Shift held, left to you")
        return true
    end
    return false
end

local function settings()
    ns.db.questAuto = ns.db.questAuto or { trivial = false }
    return ns.db.questAuto
end

-- gossip window (C_GossipInfo): hand in first, then take the first new quest
local function onGossip()
    if paused() or not C_GossipInfo then
        return
    end
    local active = C_GossipInfo.GetActiveQuests() or {}
    local available = C_GossipInfo.GetAvailableQuests() or {}
    note("gossip: %d active, %d available", #active, #available)
    for _, quest in ipairs(active) do
        if quest.isComplete then
            note("  hand in %s", tostring(quest.title))
            C_GossipInfo.SelectActiveQuest(quest.questID)
            return
        end
    end
    for _, quest in ipairs(available) do
        if not quest.isTrivial or settings().trivial then
            note("  pick %s", tostring(quest.title))
            C_GossipInfo.SelectAvailableQuest(quest.questID)
            return
        end
    end
end

-- quest greeting window (older NPCs without gossip): same order, by index
local function onGreeting()
    if paused() then
        return
    end
    local numActive = GetNumActiveQuests() or 0
    note("greeting: %d active, %d available", numActive, GetNumAvailableQuests() or 0)
    for i = 1, numActive do
        local _, isComplete = GetActiveTitle(i)
        if isComplete then
            SelectActiveQuest(i)
            return
        end
    end
    for i = 1, GetNumAvailableQuests() or 0 do
        local isTrivial = GetAvailableQuestInfo(i)
        if not isTrivial or settings().trivial then
            SelectAvailableQuest(i)
            return
        end
    end
end

local function onDetail()
    if paused() then
        return
    end
    if QuestFlagsPVP and QuestFlagsPVP() then
        note("detail: PvP quest, left to you")
        return -- the game asks for confirmation; leave that to you
    end
    if QuestGetAutoAccept and QuestGetAutoAccept() then
        note("detail: auto-accept quest acknowledged")
        AcknowledgeAutoAcceptQuest()
    else
        note("detail: accepted %s", tostring(GetTitleText and GetTitleText()))
        AcceptQuest()
    end
end

local function onProgress()
    if paused() then
        return
    end
    local completable = IsQuestCompletable()
    note("progress: completable=%s", tostring(completable))
    if completable then
        CompleteQuest()
    end
end

local function onComplete()
    if paused() then
        return
    end
    local choices = GetNumQuestChoices() or 0
    local money = GetQuestMoneyToGet and GetQuestMoneyToGet() or 0
    note("complete: %d reward choices, costs %s", choices, tostring(money))
    if choices > 1 then
        return -- pick your reward yourself
    end
    if money and money > 0 then
        return -- a hand-in that costs gold
    end
    GetQuestReward(choices == 1 and 1 or 0)
end

function QA:Init() end

-- One frame later: Blizzard's own quest and gossip windows handle the same
-- event and must be set up before the dialog is answered.
local function later(fn)
    return function()
        C_Timer.After(0, function()
            local ok, err = pcall(fn)
            if not ok then
                note("error: %s", tostring(err))
            end
        end)
    end
end

function QA:Enable()
    ns.RegisterEvent("GOSSIP_SHOW", self, later(onGossip))
    ns.RegisterEvent("QUEST_GREETING", self, later(onGreeting))
    ns.RegisterEvent("QUEST_DETAIL", self, later(onDetail))
    ns.RegisterEvent("QUEST_PROGRESS", self, later(onProgress))
    ns.RegisterEvent("QUEST_COMPLETE", self, later(onComplete))
    note("enabled")
end

function QA:Disable()
    ns.UnregisterAllEvents(self)
    ns.Print("QuestAuto disabled: quest dialogs wait for your clicks again")
end

function QA:Refresh() end

function QA.SetTrivial(enabled)
    settings().trivial = enabled
    ns.DB.Flush()
    ns.Print("automatic quests: grey (trivial) quests are %s", enabled and "taken too" or "skipped")
end

function QA:Diag()
    ns.Print("  trivial quests taken=%s; hold Shift to pause", tostring(settings().trivial))
    if #QA.trace == 0 then
        ns.Print("  no quest dialog seen yet")
    end
    for _, line in ipairs(QA.trace) do
        ns.Print("  %s", line)
    end
end
