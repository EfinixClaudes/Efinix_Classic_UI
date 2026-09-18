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

-- 1.12 plate art. The engine drew a flat coloured bar with a thin black frame
-- and the level as plain text right of the bar; the bordered bar with the
-- round level pocket only arrived with 2.0. Interface\TargetingFrame\Nameplates
-- is the 1.12 sheet: its black 128x10 strip (rows 32-42 of 128) is the frame.
local SHEET = "Interface\\TargetingFrame\\Nameplates"
local SHEET_FRAME_COORDS = { 0, 0.5, 0.25, 0.328125 }
local LEVEL_GAP = 22 -- room right of the bar for the level text

local AGGRO_KEYS = { "aggroHighlightBase", "aggroHighlightAdditive", "aggroHighlightMask", "aggroFlash" }

local skinned = setmetatable({}, { __mode = "k" })
local function hideRegion(region)
    if region then
        region:Hide()
        if not skinned[region] then
            skinned[region] = true
            hooksecurefunc(region, "Show", function(self)
                self:Hide()
            end)
        end
    end
end

local function applyPlateArt(unitFrame)
    local container = unitFrame.HealthBarsContainer
    local healthBar = container and container.healthBar
    if not healthBar then
        return
    end
    -- bar: full container width minus the level gap, 1.12 style flat fill
    healthBar:ClearAllPoints()
    healthBar:SetPoint("TOPLEFT", container, "TOPLEFT", 1, 0)
    healthBar:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -LEVEL_GAP, 0)
    -- black frame from the 1.12 sheet, one pixel around the fill
    local bg = healthBar.bgTexture
    if bg then
        bg:SetTexture(ns.Assets.Resolve(SHEET))
        bg:SetTexCoord(unpack(SHEET_FRAME_COORDS))
        bg:SetDrawLayer("BACKGROUND", 0)
        bg:ClearAllPoints()
        bg:SetPoint("TOPLEFT", healthBar, "TOPLEFT", -1, 1)
        bg:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 1, -1)
    end
    -- modern extras: aggro flare, selection border, dimming overlay
    for _, key in ipairs(AGGRO_KEYS) do
        hideRegion(unitFrame[key])
    end
    hideRegion(healthBar.selectedBorder)
    hideRegion(healthBar.deselectedOverlay)
    -- level as plain text right of the bar
    local level = unitFrame.LevelFrame
    if level then
        level:ClearAllPoints()
        level:SetPoint("LEFT", healthBar, "RIGHT", 3, 0)
        if level.LevelText then
            level.LevelText:ClearAllPoints()
            level.LevelText:SetPoint("LEFT", level, "LEFT", 0, 0)
            level.LevelText:SetJustifyH("LEFT")
        end
    end
end

local function skinUnitFrame(unitFrame)
    if not unitFrame then
        return
    end
    hideLevelBox(unitFrame)
    applyPlateArt(unitFrame)
    if not skinned[unitFrame] then
        skinned[unitFrame] = true
        -- Blizzard re-anchors everything in UpdateAnchors (options, size, faction changes)
        hooksecurefunc(unitFrame, "UpdateAnchors", applyPlateArt)
    end
end

local function onNamePlateAdded(_, unitToken)
    local base = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unitToken)
    if base then
        skinUnitFrame(base.UnitFrame)
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
