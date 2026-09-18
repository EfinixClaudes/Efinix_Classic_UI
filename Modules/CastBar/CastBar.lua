local _, ns = ...

-- CastBar module: PlayerCastingBarFrame reskinned in place to the 1.12
-- CastingBarFrame (CastingBarFrame.xml: 195x13 at BOTTOM 0,55, border
-- UI-CastingBar-Border 256x64 at TOP 0,28, spark 32x32, flash 256x64,
-- text GameFontHighlight 185x16 at TOP 0,5, fill UI-StatusBar).
-- Colours from CastingBarFrame.lua 1.12: casting 1,0.7,0; finished 0,1,0;
-- failed/interrupted 1,0,0.
--
-- The Forever bar owns the cast events, secret-value handling and the fade
-- animations; we only swap art and geometry after its own updates.
-- PlayerCastingBarFrame is not protected, so every call here is safe in combat.
local Raw = ns.Raw

local CB = ns.RegisterModule("CastBar", {})
ns.CastBar = CB

-- 1.12 UIParent.lua UIPARENT_MANAGED_FRAME_POSITIONS["CastingBarFrame"]
local BASE_Y = 60
local OFFSET_BOTTOM_EITHER = 40
local OFFSET_PET = 40
local OFFSET_REPUTATION = 9
local OFFSET_BOTTOMLEFT_AND_PET = 23 -- UIParent_ManageFramePositions: hasBottomLeft and hasPetBar

local COLOR_CASTING = { 1, 0.7, 0 }
local COLOR_FINISHED = { 0, 1, 0 }
local COLOR_FAILED = { 1, 0, 0 }

-- Modern FX regions that have no Vanilla counterpart. Hidden after every
-- Blizzard pass that could show them again.
local FX_KEYS = {
    "TextBorder",
    "DropShadow",
    "InterruptGlow",
    "ChargeGlow",
    "EnergyGlow",
    "Flakes01",
    "Flakes02",
    "Flakes03",
    "BaseGlow",
    "WispGlow",
    "Sparkles01",
    "Sparkles02",
    "ChargeFlash",
    "Shine",
    "StandardGlow",
    "CraftGlow",
    "ChannelShadow",
    "Icon",
    "CastTimeText",
}
local FINISH_ANIMS = { "StandardFinish", "CraftingFinish", "ChannelFinish" }

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

local function shown(frame)
    return frame and Raw.IsShown(frame) or false
end

local function hideFX(frame)
    for _, key in ipairs(FX_KEYS) do
        local region = frame[key]
        if region then
            region:Hide()
        end
    end
end

local function stopFinishAnims(frame)
    for _, key in ipairs(FINISH_ANIMS) do
        local anim = frame[key]
        if anim and anim.Stop then
            anim:Stop()
        end
    end
    hideFX(frame)
end

---------------------------------------------------------------------------
-- Art
---------------------------------------------------------------------------
local function fillColor(frame, isFull)
    -- CastingBarType is a Blizzard global table; read only.
    local barType = frame.barType
    if CastingBarType and barType == CastingBarType.Interrupted then
        return COLOR_FAILED
    end
    if isFull then
        return COLOR_FINISHED
    end
    -- 1.12 casts and channels both ran yellow; uninterruptible casts did not exist
    return COLOR_CASTING
end

local function applyFill(frame, isFull)
    local tex = ns.Assets.Get("MainBar.StatusBar")
    if tex then
        frame:SetStatusBarTexture(tex)
    end
    local color = fillColor(frame, isFull)
    frame:SetStatusBarColor(color[1], color[2], color[3])
end

local function applySpark(frame)
    local spark = frame.Spark
    if not spark then
        return
    end
    local tex = ns.Assets.Get("CastBar.Spark")
    if tex then
        spark:SetTexture(tex)
    end
    spark:SetBlendMode("ADD")
    spark:SetSize(32, 32) -- CastingBarSpark 32x32
end

local function applyFlash(frame)
    local flash = frame.Flash
    if not flash then
        return
    end
    local tex = ns.Assets.Get("CastBar.Flash")
    if tex then
        flash:SetTexture(tex)
    end
    flash:SetBlendMode("ADD")
    flash:ClearAllPoints()
    flash:SetSize(256, 64) -- CastingBarFlash 256x64 at TOP 0,28
    flash:SetPoint("TOP", frame, "TOP", 0, 28)
end

local function applyLook(frame)
    Raw.SetSize(frame, 195, 13) -- CastingBarFrame 195x13

    local border = frame.Border
    if border then
        local tex = ns.Assets.Get("CastBar.Border")
        if tex then
            border:SetTexture(tex)
        end
        border:ClearAllPoints()
        border:SetSize(256, 64) -- CastingBarBorder 256x64 at TOP 0,28
        border:SetPoint("TOP", frame, "TOP", 0, 28)
        border:Show()
    end

    local background = frame.Background
    if background then
        -- 1.12 BACKGROUND layer: plain black at 50% covering the bar
        background:SetTexture(nil)
        background:SetColorTexture(0, 0, 0, 0.5)
        background:ClearAllPoints()
        background:SetAllPoints(frame)
        background:Show()
    end

    local text = frame.Text
    if text then
        text:SetFontObject(GameFontHighlight)
        text:ClearAllPoints()
        text:SetSize(185, 16) -- CastingBarText 185x16 at TOP 0,5
        text:SetPoint("TOP", frame, "TOP", 0, 5)
        text:Show()
    end

    if frame.BorderShield then
        frame.BorderShield:Hide()
    end

    applySpark(frame)
    applyFlash(frame)
    applyFill(frame, false)
    hideFX(frame)
end

---------------------------------------------------------------------------
-- Position (1.12 UIParent_ManageFramePositions)
---------------------------------------------------------------------------
function CB.LayoutY()
    local y = BASE_Y
    local bottomLeft = shown(MultiBarBottomLeft)
    local bottomRight = shown(MultiBarBottomRight)
    local pet = shown(PetActionBar) or shown(StanceBar)
    if bottomLeft or bottomRight then
        y = y + OFFSET_BOTTOM_EITHER
    end
    if pet then
        y = y + OFFSET_PET
    end
    if bottomLeft and pet then
        y = y + OFFSET_BOTTOMLEFT_AND_PET
    end
    local statusBars = ns.ActionBars and ns.ActionBars.StatusBars
    if statusBars and statusBars.IsReputationStacked() then
        y = y + OFFSET_REPUTATION
    end
    return y
end

local positioning = false
function CB.Position()
    local frame = PlayerCastingBarFrame
    if positioning or not frame or CB.state ~= "enabled" then
        return
    end
    positioning = true
    local scale = ns.db.scale or 1
    Raw.SetScale(frame, scale)
    -- a bar the player dragged in Edit Mode keeps that position
    if ns.Compat.InEditModeDefault(frame) then
        Raw.ClearAllPoints(frame)
        -- CastingBarFrame.lua 1.12: SetPoint("BOTTOM", UIParent, "BOTTOM", 0, castingBarPosition)
        Raw.SetPoint(frame, "BOTTOM", UIParent, "BOTTOM", 0, CB.LayoutY() / scale)
    end
    positioning = false
end

---------------------------------------------------------------------------
-- Module lifecycle
---------------------------------------------------------------------------
function CB:Init()
    if not PlayerCastingBarFrame then
        error("PlayerCastingBarFrame not found; this client does not match docs/CLIENT_FACTS.md")
    end
end

function CB:Enable()
    local frame = PlayerCastingBarFrame

    -- Blizzard re-applies its own geometry in SetLook (called from Edit Mode
    -- attach/detach) and its atlases in UpdateBarFillTexture / ShowSpark.
    hook(frame, "SetLook", applyLook)
    hook(frame, "UpdateBarFillTexture", applyFill)
    hook(frame, "ShowSpark", function(bar)
        applySpark(bar)
        hideFX(bar)
    end)
    hook(frame, "PlayFinishAnim", stopFinishAnims)
    hook(frame, "UpdateIconShown", hideFX)
    hook(frame, "UpdateCastTimeTextShown", hideFX)
    if frame.Flash then
        -- HandleCastStop / FinishSpell swap the flash atlas on every finished cast
        hook(frame.Flash, "SetAtlas", function()
            applyFlash(frame)
        end)
    end

    -- Layout passes that move the bar: the bottom managed container, Edit Mode
    -- system anchors and its bar-size setting.
    if BottomManagedFrameContainer then
        hook(BottomManagedFrameContainer, "Layout", CB.Position)
    end
    hook(frame, "ApplySystemAnchor", CB.Position)
    hook(frame, "UpdateSystemSettingBarSize", CB.Position)

    -- Pet cast bar did not exist in 1.12 (PetFrame.xml has none).
    if PetCastingBarFrame then
        ns.Suppress(PetCastingBarFrame)
    end

    ns.RegisterEvent("PLAYER_ENTERING_WORLD", self, function()
        applyLook(frame)
        CB.Position()
    end)

    applyLook(frame)
    CB.Position()
end

function CB:Disable()
    ns.UnregisterAllEvents(self)
    ns.Print("CastBar disabled, /reload to restore the Blizzard cast bar")
end

function CB:Refresh()
    if PlayerCastingBarFrame then
        applyLook(PlayerCastingBarFrame)
    end
    CB.Position()
end

function CB:Diag()
    local frame = PlayerCastingBarFrame
    if not frame then
        ns.Print("PlayerCastingBarFrame missing")
        return
    end
    local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
    ns.Print(
        "  cast bar %s -> %s %s (%.1f, %.1f) size %.0fx%.0f scale %.2f parent %s",
        tostring(point),
        tostring(relativeTo and relativeTo:GetName()),
        tostring(relativePoint),
        x or 0,
        y or 0,
        frame:GetWidth(),
        frame:GetHeight(),
        frame:GetScale(),
        tostring(frame:GetParent() and frame:GetParent():GetName())
    )
    ns.Print("  layout y %d, look %s", CB.LayoutY(), tostring(frame.look))
end
