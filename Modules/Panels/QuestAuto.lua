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

local function paused()
    return IsShiftKeyDown()
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
    for _, quest in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
        if quest.isComplete then
            C_GossipInfo.SelectActiveQuest(quest.questID)
            return
        end
    end
    for _, quest in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
        if not quest.isTrivial or settings().trivial then
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
        return -- the game asks for confirmation; leave that to you
    end
    if QuestGetAutoAccept and QuestGetAutoAccept() then
        AcknowledgeAutoAcceptQuest()
    else
        AcceptQuest()
    end
end

local function onProgress()
    if not paused() and IsQuestCompletable() then
        CompleteQuest()
    end
end

local function onComplete()
    if paused() then
        return
    end
    local choices = GetNumQuestChoices() or 0
    if choices > 1 then
        return -- pick your reward yourself
    end
    local money = GetQuestMoneyToGet and GetQuestMoneyToGet() or 0
    if money and money > 0 then
        return -- a hand-in that costs gold
    end
    GetQuestReward(choices == 1 and 1 or 0)
end

function QA:Init() end

function QA:Enable()
    ns.RegisterEvent("GOSSIP_SHOW", self, onGossip)
    ns.RegisterEvent("QUEST_GREETING", self, onGreeting)
    ns.RegisterEvent("QUEST_DETAIL", self, onDetail)
    ns.RegisterEvent("QUEST_PROGRESS", self, onProgress)
    ns.RegisterEvent("QUEST_COMPLETE", self, onComplete)
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
end
