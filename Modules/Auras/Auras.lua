local _, ns = ...

-- Auras module: BuffFrame and DebuffFrame reskinned in place to the 1.12
-- layout (BuffFrame.xml / BuffFrame.lua 1.12).
--
-- 1.12 geometry: TemporaryEnchantFrame at TOPRIGHT -175,-13 holds the weapon
-- enchants; buffs continue to its left with 5 px gaps, 8 per row, 30x30
-- icons, duration text below (row pitch 45 with durations shown); debuffs
-- start a fixed third row at TOPRIGHT -175,-103 (TemporaryEnchantFrame
-- TOPRIGHT 0,-90). Forever's BuffFrame already lists the weapon enchants
-- first and lays auras out in a 30x40 grid with padding 5 and stride 8, so
-- with default Edit Mode settings its grid matches; we anchor the frames,
-- swap the debuff border art and hide what 1.12 did not have.
--
-- Nothing here reads aura data. Blizzard fills the buttons (secret-value
-- safe); we only touch textures, colours and anchors of unprotected frames.
local Raw = ns.Raw

local Auras = ns.RegisterModule("Auras", {})
ns.Auras = Auras

-- 1.12 BuffFrame.lua DebuffTypeColor
local DEBUFF_COLORS = {
    none = { 0.80, 0, 0 },
    Magic = { 0.20, 0.60, 1.00 },
    Curse = { 0.60, 0.00, 1.00 },
    Disease = { 0.60, 0.40, 0 },
    Poison = { 0.00, 0.60, 0 },
}

-- BuffFrame.xml 1.12: TemporaryEnchantFrame TOPRIGHT -175,-13; first enchant at its TOPRIGHT.
local BUFFS_X, BUFFS_Y = -175, -13
-- BuffButtons_UpdatePositions 1.12: debuff row at TemporaryEnchantFrame TOPRIGHT 0,-90 with durations
local DEBUFFS_X, DEBUFFS_Y = -175, -13 - 90
-- Forever BuffFrame: AuraContainer anchors to CollapseAndExpandButton (15 wide) at the frame's right edge
local COLLAPSE_BUTTON_WIDTH = 15

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

---------------------------------------------------------------------------
-- Debuff border: UI-Debuff-Overlays 33x32, coords 0.296875,0.5703125,0,0.515625,
-- vertex colour by dispel type (BuffButtonHarmful 1.12 + BuffButton_Update).
---------------------------------------------------------------------------
local function styleDebuffBorder(border, dispelType)
    local tex = ns.Assets.Get("Auras.DebuffOverlay")
    if not border or not tex then
        return
    end
    border:SetTexture(tex)
    border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
    local color = DEBUFF_COLORS[dispelType] or DEBUFF_COLORS.none
    border:SetVertexColor(color[1], color[2], color[3])
end

local ourBorders = setmetatable({}, { __mode = "k" }) -- DebuffBorder texture -> aura button

local function styleButton(button)
    if hooked[button] then
        return
    end
    hooked[button] = true
    if button.DebuffBorder then
        ourBorders[button.DebuffBorder] = button
        button.DebuffBorder:ClearAllPoints()
        button.DebuffBorder:SetSize(33, 32)
        button.DebuffBorder:SetPoint("CENTER", button.Icon or button, "CENTER", 0, 0)
    end
    if button.Symbol then
        button.Symbol:Hide()
    end
    -- Blizzard swaps the duration font for long buffs (Localization.lua); 1.12 used one font
    hook(button, "UpdateDuration", function(self)
        if self.Duration then
            self.Duration:SetFontObject(GameFontNormalSmall)
        end
    end)
end

local function styleButtons(frame)
    if not frame or type(frame.auraFrames) ~= "table" then
        return
    end
    for _, button in ipairs(frame.auraFrames) do
        if not button.isAuraAnchor then
            styleButton(button)
        end
    end
end

---------------------------------------------------------------------------
-- Positions
---------------------------------------------------------------------------
local positioning = false
function Auras.Position()
    if positioning or Auras.state ~= "enabled" then
        return
    end
    positioning = true
    local scale = ns.db.scale or 1
    if BuffFrame then
        Raw.SetScale(BuffFrame, scale)
        Raw.ClearAllPoints(BuffFrame)
        Raw.SetPoint(
            BuffFrame,
            "TOPRIGHT",
            UIParent,
            "TOPRIGHT",
            (BUFFS_X + COLLAPSE_BUTTON_WIDTH) / scale,
            BUFFS_Y / scale
        )
    end
    if DebuffFrame then
        Raw.SetScale(DebuffFrame, scale)
        Raw.ClearAllPoints(DebuffFrame)
        Raw.SetPoint(DebuffFrame, "TOPRIGHT", UIParent, "TOPRIGHT", DEBUFFS_X / scale, DEBUFFS_Y / scale)
    end
    positioning = false
end

---------------------------------------------------------------------------
-- Module lifecycle
---------------------------------------------------------------------------
function Auras:Init()
    if not BuffFrame or not DebuffFrame then
        error("BuffFrame/DebuffFrame not found; this client does not match docs/CLIENT_FACTS.md")
    end
end

function Auras:Enable()
    -- 1.12 had no collapse arrow, consolidated buffs, deadly debuff banner or external defensives
    if BuffFrame.CollapseAndExpandButton then
        ns.Suppress(BuffFrame.CollapseAndExpandButton)
    end
    if BuffFrame.ConsolidatedBuffs then
        ns.Suppress(BuffFrame.ConsolidatedBuffs)
    end
    if DeadlyDebuffFrame then
        ns.Suppress(DeadlyDebuffFrame)
    end
    if ExternalDefensivesFrame then
        ns.Suppress(ExternalDefensivesFrame)
    end

    -- Debuff border art: Blizzard sets an atlas per dispel type; we replace it afterwards.
    if AuraUtil and type(AuraUtil.SetAuraBorderAtlas) == "function" then
        hooksecurefunc(AuraUtil, "SetAuraBorderAtlas", function(border, dispelType)
            if ourBorders[border] then
                styleDebuffBorder(border, dispelType)
            end
        end)
    end
    if AuraUtil and type(AuraUtil.SetAuraSymbol) == "function" then
        hooksecurefunc(AuraUtil, "SetAuraSymbol", function(fontString)
            local button = fontString and fontString:GetParent()
            if button and hooked[button] then
                fontString:Hide()
            end
        end)
    end

    -- Buttons are pooled on demand; style each new one after Blizzard fills the pool.
    for _, frame in ipairs({ BuffFrame, DebuffFrame }) do
        hook(frame, "UpdateAuraButtons", styleButtons)
        hook(frame, "ApplySystemAnchor", Auras.Position)
        styleButtons(frame)
    end

    ns.RegisterEvent("PLAYER_ENTERING_WORLD", self, function()
        Auras.Position()
        styleButtons(BuffFrame)
        styleButtons(DebuffFrame)
    end)

    Auras.Position()
end

function Auras:Disable()
    ns.UnregisterAllEvents(self)
    ns.Print("Auras disabled, /reload to restore the Blizzard buff frame")
end

function Auras:Refresh()
    Auras.Position()
end

function Auras:Diag()
    for _, frame in ipairs({ BuffFrame, DebuffFrame }) do
        if frame then
            local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
            local container = frame.AuraContainer
            ns.Print(
                "  %-12s %s -> %s %s (%.1f, %.1f) buttons %d stride %s padding %s horizontal %s",
                frame:GetName(),
                tostring(point),
                tostring(relativeTo and relativeTo:GetName()),
                tostring(relativePoint),
                x or 0,
                y or 0,
                type(frame.auraFrames) == "table" and #frame.auraFrames or 0,
                tostring(container and container.iconStride),
                tostring(container and container.iconPadding),
                tostring(container and container.isHorizontal)
            )
        end
    end
end
