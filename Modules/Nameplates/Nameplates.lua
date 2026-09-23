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
local GLOBAL_SCALE_CVAR = "nameplateGlobalScale"
local BAR_HEIGHT = 14 -- 1.12 bar fill; with the 1 px frame it is the 16 px engine plate
local BAR_WIDTH = 126 -- 1.12 bar fill; with the frame the 128 px engine plate
local NAME_SPACING = 4 -- CLASSIC_HEALTH_BAR_TO_NAME_ABOVE_SPACING (Camelot constants)
local DEFAULT_SCALE = 1.3 -- players find the 128x16 engine plate small on today's screens

local function classicStyle()
    return Enum and Enum.NamePlateStyle and Enum.NamePlateStyle.Classic
end

local function getCVar(name)
    local value = C_CVar and C_CVar.GetCVar and C_CVar.GetCVar(name)
    return value
end

function Nameplates.Scale()
    local scale = ns.db.nameplates and tonumber(ns.db.nameplates.scale)
    return scale or DEFAULT_SCALE
end

-- cvars we set, with the value we want; the player's previous values are kept
-- in the DB so Disable can put them back. 1.12 drew every plate at one size:
-- no shrinking with distance (nameplateMin/MaxScale arrived with 7.0).
local function wantedCVars()
    local classic = classicStyle()
    return {
        { name = STYLE_CVAR, value = classic and tostring(classic) },
        { name = GLOBAL_SCALE_CVAR, value = ("%.2f"):format(Nameplates.Scale()) },
        { name = "nameplateMinScale", value = "1" },
        { name = "nameplateMaxScale", value = "1" },
        -- enemy players' bars in their class colour (Blizzard_NamePlates.lua reads
        -- this into NamePlateEnemyFrameOptions.useClassColors)
        { name = "nameplateShowClassColor", value = "1" },
    }
end

local function setCVar(name, value)
    if not C_CVar or not C_CVar.SetCVar then
        return
    end
    local current = getCVar(name)
    if current == nil or current == value then
        return -- unknown on this client, or already right
    end
    local previous = ns.db.nameplates.previous
    if previous[name] == nil then
        previous[name] = current
    end
    C_CVar.SetCVar(name, value)
    ns.Log("Nameplates", "%s %s -> %s", name, tostring(current), value)
end

function Nameplates.Apply()
    if not classicStyle() then
        ns.Log("Nameplates", "Enum.NamePlateStyle.Classic missing, nameplates left untouched")
        return false
    end
    for _, cvar in ipairs(wantedCVars()) do
        if cvar.value then
            setCVar(cvar.name, cvar.value)
        end
    end
    return true
end

function Nameplates.Restore()
    if not C_CVar or not C_CVar.SetCVar then
        return
    end
    for name, value in pairs(ns.db.nameplates.previous) do
        C_CVar.SetCVar(name, tostring(value))
        ns.db.nameplates.previous[name] = nil
    end
end

function Nameplates.SetScale(scale)
    ns.db.nameplates.scale = scale
    Nameplates.Apply()
    Nameplates.RefreshPlates()
end

function Nameplates:Init()
    ns.db.nameplates = ns.db.nameplates or {}
    ns.db.nameplates.previous = ns.db.nameplates.previous or {}
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
    -- 1.12 plate height; Blizzard's classic style uses 10, the engine plate was 16 with frame
    local options = NamePlateSetupOptions
    local vertical = options and tonumber(options.verticalScale) or 1
    local horizontal = options and tonumber(options.horizontalScale) or 1
    local inset = options and tonumber(options.insetWidth) or 0
    container:SetHeight(BAR_HEIGHT * vertical)
    -- clients without nameplateGlobalScale: scale the drawn frame instead
    if getCVar(GLOBAL_SCALE_CVAR) == nil then
        unitFrame:SetScale(Nameplates.Scale())
    end
    -- Blizzard narrows the container by its side insets and the (hidden) level box;
    -- the 1.12 bar had a fixed width, so it starts at the plate's left edge with that width
    healthBar:ClearAllPoints()
    healthBar:SetPoint("TOPLEFT", container, "TOPLEFT", 1 - inset, 0)
    healthBar:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 1 - inset, 0)
    healthBar:SetWidth(BAR_WIDTH * horizontal)
    -- name centred over the bar, not over the narrowed container
    local name = unitFrame.name
    if name and not (unitFrame.IsShowOnlyName and unitFrame:IsShowOnlyName()) then
        name:ClearAllPoints()
        name:SetPoint("BOTTOM", healthBar, "TOP", 0, NAME_SPACING * vertical)
    end
    if unitFrame.RaidTargetFrame then
        unitFrame.RaidTargetFrame:ClearAllPoints()
        unitFrame.RaidTargetFrame:SetPoint("RIGHT", healthBar, "LEFT", -2, 0)
    end
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

-- re-run the art on every plate currently shown (scale changes from the options window)
function Nameplates.RefreshPlates()
    if not C_NamePlate or not C_NamePlate.GetNamePlates then
        return
    end
    for _, base in ipairs(C_NamePlate.GetNamePlates()) do
        if base.UnitFrame then
            applyPlateArt(base.UnitFrame)
        end
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
    ns.Print("  classic style=%s scale=%.2f", tostring(classicStyle()), Nameplates.Scale())
    for _, cvar in ipairs(wantedCVars()) do
        ns.Print(
            "  %s=%s (want %s, previous %s)",
            cvar.name,
            tostring(getCVar(cvar.name)),
            tostring(cvar.value),
            tostring(ns.db.nameplates.previous[cvar.name])
        )
    end
end
