local _, ns = ...

-- All API differences live here. Modules never feature-detect on their own.
-- Facts recorded from the exported Forever source (docs/CLIENT_FACTS.md);
-- everything is still probed at runtime so a wrong assumption degrades
-- instead of erroring.
local Compat = {}
ns.Compat = Compat

local version, build, _, interface = GetBuildInfo()

Compat.HasEditMode = (EditModeManagerFrame ~= nil)
Compat.HasSecretValues = (issecretvalue ~= nil)
Compat.HasCAddOns = (C_AddOns ~= nil)
Compat.HasCUnitAuras = (C_UnitAuras ~= nil)
Compat.HasCSpell = (C_Spell ~= nil)
Compat.HasSettings = (Settings ~= nil)

function Compat.Facts()
    return {
        version = version,
        build = build,
        interface = interface,
        projectID = WOW_PROJECT_ID,
        hasEditMode = Compat.HasEditMode,
        hasSecretValues = Compat.HasSecretValues,
        hasCAddOns = Compat.HasCAddOns,
        hasCUnitAuras = Compat.HasCUnitAuras,
        hasCSpell = Compat.HasCSpell,
        hasSettings = Compat.HasSettings,
    }
end

-- Max level check without touching XP values that may be secret.
function Compat.IsPlayerMaxLevel()
    local maxLevel
    if GetMaxLevelForPlayerExpansion then
        maxLevel = GetMaxLevelForPlayerExpansion()
    elseif GetMaxPlayerLevel then
        maxLevel = GetMaxPlayerLevel()
    end
    if not maxLevel then
        return false
    end
    return UnitLevel("player") >= maxLevel
end

-- Texture existence. GetFileIDFromPath is documented in the Forever client
-- (ClientDocumentation.lua) and returns nil for unknown paths.
function Compat.TextureExists(path)
    if not GetFileIDFromPath then
        return nil -- unknown, caller decides
    end
    local ok, id = pcall(GetFileIDFromPath, path)
    return ok and id ~= nil and id ~= 0
end

-- Rest state without comparing possibly-secret XP values: GetRestState
-- returns a small enum (1 = rested, 2 = normal) that is safe to branch on.
function Compat.IsRested()
    local state = GetRestState()
    return state == 1
end

-- Edit Mode: has the player left this system frame where Blizzard puts it.
-- Our 1.12 default positions only apply then; a frame the player dragged in
-- Edit Mode keeps the position Edit Mode saved for it. Frames without the
-- Edit Mode system mixin count as "default".
function Compat.InEditModeDefault(frame)
    if not frame or type(frame.IsInDefaultPosition) ~= "function" then
        return true
    end
    local ok, result = pcall(frame.IsInDefaultPosition, frame)
    return ok and result ~= false
end

-- Edit Mode: is the manager currently open. Only used to avoid fighting the
-- user while they drag frames around; never used in combat paths.
function Compat.IsEditModeActive()
    if not Compat.HasEditMode then
        return false
    end
    local ok, active = pcall(EditModeManagerFrame.IsEditModeActive, EditModeManagerFrame)
    return ok and active or false
end
