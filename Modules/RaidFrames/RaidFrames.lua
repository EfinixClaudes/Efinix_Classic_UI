local _, ns = ...

-- RaidFrames module. 1.12 had no compact raid frames: raid members were
-- managed from the Raid tab of the social window (RaidFrame.xml) and shown
-- through the pull-out group frames of Blizzard_RaidUI, which Forever still
-- ships (RaidPulloutFrameTemplate). Forever's CompactRaidFrameManager and its
-- container (Blizzard_CompactRaidFrames, WotLK 3.3 design) are therefore
-- neutralised through ns.Hide; the manager re-shows itself on every group
-- change via SetShown, so the Show/OnShow guards do the rest out of combat.
--
-- The container is a secure unit-frame system: everything goes through the
-- combat queue in Core/Hide.lua and nothing is touched in combat.
local RaidFrames = ns.RegisterModule("RaidFrames", {})
ns.RaidFrames = RaidFrames

local FRAMES = { "CompactRaidFrameManager", "CompactRaidFrameContainer" }

function RaidFrames:Init()
    if not CompactRaidFrameManager then
        error("CompactRaidFrameManager not found; this client does not match docs/CLIENT_FACTS.md")
    end
end

function RaidFrames:Enable()
    -- Events stay registered: the manager's handlers also drive CompactPartyFrame and
    -- the container's roster bookkeeping, which other Blizzard code expects to keep running.
    local keepEvents = true
    for _, name in ipairs(FRAMES) do
        if _G[name] then
            ns.Hide(_G[name], keepEvents)
        end
    end
    -- Blizzard evaluates visibility on group changes; the Show/OnShow guards run then.
end

function RaidFrames:Disable()
    ns.UnregisterAllEvents(self)
    ns.Print("RaidFrames disabled, /reload to restore the Blizzard raid frames")
end

function RaidFrames:Refresh() end

function RaidFrames:Diag()
    for _, name in ipairs(FRAMES) do
        local frame = _G[name]
        ns.Print(
            "  %-26s hidden=%s shown=%s",
            name,
            tostring(frame and ns.IsHidden(frame)),
            tostring(frame and ns.Raw.IsShown(frame))
        )
    end
    ns.Print("  combat queue pending: %d", ns.Combat.Pending())
end
