local _, ns = ...

-- Nameplates module. 1.12 nameplates were drawn by the engine: a 128x16
-- bordered health bar (Interface\Tooltips\Nameplate-Border), the level in
-- the border's right pocket, a white centred name above and the raid icon.
--
-- Forever's Blizzard_NamePlates ships exactly that look as its hidden
-- "Classic" style (Enum.NamePlateStyle.Classic: CLASSIC_* constants in
-- Camelot/Blizzard_NamePlateConstants.lua, useClassicHealthBar /
-- useClassicCastBar in NamePlateDriverMixin:UpdateNamePlateOptions), but the
-- Camelot settings dropdown does not offer it. Nameplates are secure and
-- their values may be secret, so rebuilding them is out; we select
-- Blizzard's own classic style through the nameplateStyle cvar and remember
-- the player's previous choice so disabling the module restores it.
--
-- Cast bars, auras, soft-target icons and class colours on nameplates stay
-- under the player's own nameplate settings.
local Nameplates = ns.RegisterModule("Nameplates", {})
ns.Nameplates = Nameplates

local STYLE_CVAR = "nameplateStyle"

local function classicStyle()
    return Enum and Enum.NamePlateStyle and Enum.NamePlateStyle.Classic
end

local function currentStyle()
    local value = C_CVar and C_CVar.GetCVar and C_CVar.GetCVar(STYLE_CVAR)
    return tonumber(value)
end

function Nameplates.Apply()
    local classic = classicStyle()
    if not classic then
        ns.Log("Nameplates", "Enum.NamePlateStyle.Classic missing, nameplates left untouched")
        return false
    end
    local current = currentStyle()
    if current == classic then
        return true
    end
    -- remember what the player had so Disable can put it back
    if current and ns.db.nameplates.previousStyle == nil then
        ns.db.nameplates.previousStyle = current
    end
    C_CVar.SetCVar(STYLE_CVAR, tostring(classic))
    ns.Log("Nameplates", "nameplateStyle %s -> %d", tostring(current), classic)
    return true
end

function Nameplates.Restore()
    local previous = ns.db.nameplates.previousStyle
    if previous ~= nil and C_CVar and C_CVar.SetCVar then
        C_CVar.SetCVar(STYLE_CVAR, tostring(previous))
        ns.db.nameplates.previousStyle = nil
    end
end

function Nameplates:Init()
    ns.db.nameplates = ns.db.nameplates or {}
    if not NamePlateDriverFrame then
        error("NamePlateDriverFrame not found; this client does not match docs/CLIENT_FACTS.md")
    end
end

-- Camelot adds a separate level box (NameplateLevelFrame, atlas
-- ui-hud-nameplates-levelindicator) next to every plate. The classic style
-- already prints the level in the border's pocket (LevelFrame), which is
-- where 1.12 had it, so the box is hidden on every unit frame that gets used.
local levelBoxHooked = setmetatable({}, { __mode = "k" })
local function hideLevelBox(unitFrame)
    local box = unitFrame and unitFrame.PlayerLevelDiffFrame
    if not box then
        return
    end
    box:Hide()
    if not levelBoxHooked[box] then
        levelBoxHooked[box] = true
        hooksecurefunc(box, "Show", function(self)
            self:Hide()
        end)
    end
end

local function onNamePlateAdded(_, unitToken)
    local base = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unitToken)
    if base then
        hideLevelBox(base.UnitFrame)
    end
end

function Nameplates:Enable()
    Nameplates.Apply()
    if NamePlateDriverFrame and type(NamePlateDriverFrame.OnNamePlateAdded) == "function" then
        hooksecurefunc(NamePlateDriverFrame, "OnNamePlateAdded", onNamePlateAdded)
    end
    -- the cvar is per character; re-apply when settings are (re)loaded
    ns.RegisterEvent("VARIABLES_LOADED", self, Nameplates.Apply)
    ns.RegisterEvent("PLAYER_ENTERING_WORLD", self, Nameplates.Apply)
end

function Nameplates:Disable()
    ns.UnregisterAllEvents(self)
    Nameplates.Restore()
    ns.Print("Nameplates: Blizzard nameplate style restored")
end

function Nameplates:Refresh()
    Nameplates.Apply()
end

function Nameplates:Diag()
    ns.Print(
        "  nameplateStyle=%s classic=%s previous=%s",
        tostring(currentStyle()),
        tostring(classicStyle()),
        tostring(ns.db.nameplates and ns.db.nameplates.previousStyle)
    )
end
