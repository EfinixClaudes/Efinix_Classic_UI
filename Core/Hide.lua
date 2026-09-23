local _, ns = ...

-- The one sanctioned way to neutralise a Blizzard frame:
--   * unregister its events so it stops updating itself,
--   * reparent it to a hidden holder so it and its children never render,
--   * guard Show() out of combat with hooksecurefunc.
-- We never replace frame methods, never nil globals, never write into the
-- frame's table. Frames managed by Edit Mode are additionally moved with
-- the raw widget methods so its layout passes cannot re-anchor them.
local Raw = ns.Raw

local holder = CreateFrame("Frame", nil, UIParent)
holder:Hide()
ns.hiddenHolder = holder

local hidden = {} -- frame -> true
local parked = {} -- frame -> true for ns.Hide (reparented), absent for ns.Suppress
ns.hiddenFrames = hidden

-- Only a protected frame has to wait for the end of combat; anything else
-- (the objective tracker, panels) can be put away at once, even in a fight.
local function canAct(frame)
    if not InCombatLockdown() then
        return true
    end
    return not (frame.IsProtected and frame:IsProtected())
end

-- Blizzard's managed-frame containers re-parent their frames on every
-- layout pass; a parked frame goes back into the holder when that happens.
local function putAway(frame)
    if parked[frame] and frame:GetParent() ~= holder then
        Raw.SetParent(frame, holder)
    end
    Raw.Hide(frame)
end

function ns.Hide(frame, keepEvents)
    if not frame or hidden[frame] then
        return
    end
    hidden[frame] = true
    parked[frame] = true

    local function apply()
        if not keepEvents and frame.UnregisterAllEvents then
            frame:UnregisterAllEvents()
        end
        putAway(frame)
    end

    ns.Combat.Run("hide:" .. tostring(frame:GetName() or frame), apply)

    hooksecurefunc(frame, "Show", function(self)
        if hidden[self] and canAct(self) then
            putAway(self)
        end
    end)
    -- SetShown(true) bypasses the Show hook; OnShow catches it.
    if frame.HookScript then
        frame:HookScript("OnShow", function(self)
            if hidden[self] and canAct(self) then
                putAway(self)
            end
        end)
    end
end

function ns.IsHidden(frame)
    return hidden[frame] == true
end

-- Lighter variant for frames that must stay where they are (their parent
-- iterates them by layout index): keep events and parent, just hide and
-- guard Show() out of combat.
function ns.Suppress(frame)
    if not frame or hidden[frame] then
        return
    end
    hidden[frame] = true
    ns.Combat.Run("suppress:" .. tostring(frame:GetName() or frame), function()
        Raw.Hide(frame)
    end)
    hooksecurefunc(frame, "Show", function(self)
        if hidden[self] and canAct(self) then
            Raw.Hide(self)
        end
    end)
    if frame.HookScript then
        frame:HookScript("OnShow", function(self)
            if hidden[self] and canAct(self) then
                Raw.Hide(self)
            end
        end)
    end
end

-- A hidden or suppressed frame that Blizzard showed during combat (the
-- guards above may not act then) is put away again when the fight ends.
ns.RegisterEvent("PLAYER_REGEN_ENABLED", hidden, function()
    for frame in pairs(hidden) do
        if Raw.IsShown(frame) or (parked[frame] and frame:GetParent() ~= holder) then
            putAway(frame)
        end
    end
end)
