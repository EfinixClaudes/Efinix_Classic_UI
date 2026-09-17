local _, ns = ...

-- Tooltip module: Blizzard's tooltips get the 1.12 backdrop
-- (GameTooltipTemplate.xml 1.12: UI-Tooltip-Background / UI-Tooltip-Border,
-- edge 16, tile 16, insets 5; GameTooltip.lua 1.12: background 0.09,0.09,0.19,
-- border 1,1,1) and the 1.12 default anchor (GameTooltip_SetDefaultAnchor:
-- BOTTOMRIGHT of UIParent, -CONTAINER_OFFSET_X - 13, CONTAINER_OFFSET_Y).
--
-- Tooltip contents, fonts (FRIZQT 14/12, same in Forever), the unit health
-- bar (8 px, UI-TargetingFrame-BarFill, same in Forever) and comparison
-- placement stay Blizzard's. Tooltips are not protected.
local Raw = ns.Raw

local Tooltip = ns.RegisterModule("Tooltip", {})
ns.Tooltip = Tooltip

-- GameTooltip.lua 1.12
local BACKGROUND_COLOR = { 0.09, 0.09, 0.19 }
local BORDER_COLOR = { 1, 1, 1 }

-- 1.12 UIParent.lua UIPARENT_MANAGED_FRAME_POSITIONS
local CONTAINER_OFFSET_X_RIGHTLEFT = 90 -- "rightLeft = 90": MultiBarLeft shown
local CONTAINER_OFFSET_X_RIGHTRIGHT = 45 -- "rightRight = 45": only MultiBarRight shown
local CONTAINER_OFFSET_Y_BASE = 70 -- "baseY = 70"
local CONTAINER_OFFSET_Y_BOTTOM = 27 -- "bottomEither = 27"
local CONTAINER_OFFSET_Y_PET = 23 -- "pet = 23"
local CONTAINER_OFFSET_Y_REPUTATION = 9 -- "reputation = 9"
local TOOLTIP_ANCHOR_X = -13 -- GameTooltip_SetDefaultAnchor 1.12: -CONTAINER_OFFSET_X - 13

local TOOLTIPS = {
    "GameTooltip",
    "ShoppingTooltip1",
    "ShoppingTooltip2",
    "ItemRefTooltip",
    "ItemRefShoppingTooltip1",
    "ItemRefShoppingTooltip2",
    "GameSmallHeaderTooltip",
    "EmbeddedItemTooltip",
}

local BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = { left = 5, right = 5, top = 5, bottom = 5 },
}

local hooked = {}
local function hook(target, method, fn)
    if not target or type(target[method]) ~= "function" then
        return
    end
    local key = tostring(target) .. ":" .. method
    if hooked[key] then
        return
    end
    hooked[key] = true
    hooksecurefunc(target, method, fn)
end

local function hideTexture(region)
    if region then
        region:Hide()
        hook(region, "Show", function(self)
            self:Hide()
        end)
    end
end

local function shown(frame)
    return frame and Raw.IsShown(frame) or false
end

local backdrops = {} -- tooltip -> our backdrop frame

---------------------------------------------------------------------------
-- Backdrop
---------------------------------------------------------------------------
local function skin(tooltip)
    if not tooltip or backdrops[tooltip] then
        return
    end
    local frame = CreateFrame("Frame", nil, tooltip, "BackdropTemplate")
    frame:SetAllPoints(tooltip)
    frame:SetFrameLevel(tooltip:GetFrameLevel())
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(BACKGROUND_COLOR[1], BACKGROUND_COLOR[2], BACKGROUND_COLOR[3])
    frame:SetBackdropBorderColor(BORDER_COLOR[1], BORDER_COLOR[2], BORDER_COLOR[3])
    backdrops[tooltip] = frame

    -- Blizzard's nine-slice art stays in place but invisible; SharedTooltip_SetBackdropStyle
    -- re-applies atlases and Show() on every style change, neither touches frame alpha.
    if tooltip.NineSlice then
        Raw.SetAlpha(tooltip.NineSlice, 0)
    end
    hideTexture(tooltip.TopOverlay)
    hideTexture(tooltip.BottomOverlay)

    -- keep our backdrop directly under the text if the tooltip's level changes
    tooltip:HookScript("OnShow", function(self)
        local backdrop = backdrops[self]
        if backdrop then
            backdrop:SetFrameLevel(self:GetFrameLevel())
        end
    end)
end

---------------------------------------------------------------------------
-- Default anchor (UIParent_ManageFramePositions 1.12 for CONTAINER_OFFSET_X/Y)
---------------------------------------------------------------------------
function Tooltip.ContainerOffsets()
    local x = 0
    if shown(MultiBarLeft) then
        x = CONTAINER_OFFSET_X_RIGHTLEFT
    elseif shown(MultiBarRight) then
        x = CONTAINER_OFFSET_X_RIGHTRIGHT
    end
    local y = CONTAINER_OFFSET_Y_BASE
    if shown(MultiBarBottomLeft) or shown(MultiBarBottomRight) then
        y = y + CONTAINER_OFFSET_Y_BOTTOM
    end
    if shown(PetActionBar) or shown(StanceBar) then
        y = y + CONTAINER_OFFSET_Y_PET
    end
    local statusBars = ns.ActionBars and ns.ActionBars.StatusBars
    if statusBars and statusBars.IsReputationStacked() then
        y = y + CONTAINER_OFFSET_Y_REPUTATION
    end
    return x, y
end

local function containerInDefaultPosition()
    local container = GameTooltipDefaultContainer
    if not container or type(container.IsInDefaultPosition) ~= "function" then
        return true
    end
    local ok, result = pcall(container.IsInDefaultPosition, container)
    return ok and result ~= false
end

local function applyDefaultAnchor(tooltip)
    if not tooltip or not containerInDefaultPosition() then
        return
    end
    local x, y = Tooltip.ContainerOffsets()
    tooltip:ClearAllPoints()
    tooltip:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -x + TOOLTIP_ANCHOR_X, y)
end

---------------------------------------------------------------------------
-- Module lifecycle
---------------------------------------------------------------------------
function Tooltip:Init()
    if not GameTooltip then
        error("GameTooltip not found; this client does not match docs/CLIENT_FACTS.md")
    end
end

function Tooltip:Enable()
    for _, name in ipairs(TOOLTIPS) do
        skin(_G[name])
    end
    -- Edit Mode's tooltip container decides where the default anchor goes; 1.12 used the bar layout.
    if type(GameTooltip_SetDefaultAnchor) == "function" and not hooked.defaultAnchor then
        hooked.defaultAnchor = true
        hooksecurefunc("GameTooltip_SetDefaultAnchor", applyDefaultAnchor)
    end
end

function Tooltip:Disable()
    ns.UnregisterAllEvents(self)
    for tooltip, frame in pairs(backdrops) do
        frame:Hide()
        if tooltip.NineSlice then
            Raw.SetAlpha(tooltip.NineSlice, 1)
        end
    end
    ns.Print("Tooltip disabled, /reload to restore the Blizzard tooltip anchor")
end

function Tooltip:Refresh() end

function Tooltip:Diag()
    local x, y = Tooltip.ContainerOffsets()
    ns.Print(
        "  default anchor BOTTOMRIGHT %d, %d (container default=%s)",
        -x + TOOLTIP_ANCHOR_X,
        y,
        tostring(containerInDefaultPosition())
    )
    local count = 0
    for _ in pairs(backdrops) do
        count = count + 1
    end
    ns.Print("  skinned tooltips: %d", count)
end
