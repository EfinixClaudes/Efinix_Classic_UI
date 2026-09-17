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
ns.hiddenFrames = hidden

function ns.Hide(frame, keepEvents)
    if not frame or hidden[frame] then
        return
    end
    hidden[frame] = true

    local function apply()
        if not keepEvents and frame.UnregisterAllEvents then
            frame:UnregisterAllEvents()
        end
        Raw.SetParent(frame, holder)
        Raw.Hide(frame)
    end

    ns.Combat.Run("hide:" .. tostring(frame:GetName() or frame), apply)

    hooksecurefunc(frame, "Show", function(self)
        if hidden[self] and not InCombatLockdown() then
            Raw.Hide(self)
        end
    end)
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
        if hidden[self] and not InCombatLockdown() then
            Raw.Hide(self)
        end
    end)
end
