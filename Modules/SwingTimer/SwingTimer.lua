local _, ns = ...

-- SwingTimer module (addon feature, requested 2026-09-17; 1.12 had none).
-- Forever ships Blizzard_SwingTimer (Camelot only): SwingTimerMainHandFrame,
-- SwingTimerOffHandFrame and SwingTimerRangedFrame, fed by the engine's
-- PLAYER_SWING event and switched on with the "showSwingTimer" cvar. The
-- swing measurement, range dimming and the Edit Mode visibility setting
-- (always / in combat / hidden) stay Blizzard's. We switch the cvar on,
-- dress the bars like the 1.12 cast bar (195x13, UI-CastingBar-Border,
-- UI-StatusBar fill in cast-bar yellow, spark) and stack them above the
-- player cast bar. Disabling the module puts the cvar back.
local Raw = ns.Raw

local ST = ns.RegisterModule("SwingTimer", {})
ns.SwingTimer = ST

local CVAR = "showSwingTimer"
local BAR_WIDTH, BAR_HEIGHT = 195, 13 -- CastingBarFrame.xml 1.12
local GAP_ABOVE_CAST_BAR = 30 -- clears the cast bar's border art (TOP 0,28)
local ROW_PITCH = 24 -- bar height plus the border's visible ring
local FILL_COLOR = { 1, 0.7, 0 } -- CastingBarFrame.lua 1.12 casting colour

local FRAMES = { "SwingTimerMainHandFrame", "SwingTimerOffHandFrame", "SwingTimerRangedFrame" }

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

local borders = {} -- frame -> our border texture

---------------------------------------------------------------------------
-- Art
---------------------------------------------------------------------------
local function skin(frame)
    if not frame or borders[frame] then
        return
    end
    local statusBar = frame.StatusBar
    if not statusBar then
        return
    end

    -- 1.12 BACKGROUND: plain black at 50%
    if frame.Background then
        frame.Background:SetTexture(nil)
        frame.Background:SetColorTexture(0, 0, 0, 0.5)
    end
    if frame.Border then
        frame.Border:Hide()
    end

    -- fill: UI-StatusBar in cast-bar yellow, bar covering the whole frame
    statusBar:ClearAllPoints()
    statusBar:SetAllPoints(frame)
    local fill = ns.Assets.Get("MainBar.StatusBar")
    if fill then
        statusBar:SetStatusBarTexture(fill)
    end
    statusBar:SetStatusBarColor(FILL_COLOR[1], FILL_COLOR[2], FILL_COLOR[3])

    -- border above the fill: CastingBarBorder 256x64 at TOP 0,28
    local overlay = CreateFrame("Frame", nil, statusBar)
    overlay:SetAllPoints(statusBar)
    overlay:SetFrameLevel(statusBar:GetFrameLevel() + 1)
    local border = overlay:CreateTexture(nil, "ARTWORK")
    local borderTex = ns.Assets.Get("CastBar.Border")
    if borderTex then
        border:SetTexture(borderTex)
    end
    border:SetSize(256, 64)
    border:SetPoint("TOP", frame, "TOP", 0, 28)
    ns.Dark.Tint(border)
    borders[frame] = border

    -- spark: CastingBarSpark 32x32 additive, riding the fill's right edge
    local pip = statusBar.Pip
    if pip then
        local spark = ns.Assets.Get("CastBar.Spark")
        if spark then
            pip:SetTexture(spark)
        end
        pip:SetBlendMode("ADD")
        pip:SetSize(32, 32)
        pip:ClearAllPoints()
        pip:SetPoint("CENTER", statusBar:GetStatusBarTexture(), "RIGHT", 0, 0)
    end

    -- labels: small white text inside the bar, no shadow strip
    if statusBar.TypeLabelShadow then
        statusBar.TypeLabelShadow:Hide()
        hook(statusBar.TypeLabelShadow, "SetShown", function(self)
            self:Hide()
        end)
    end
    if statusBar.TypeLabel then
        statusBar.TypeLabel:SetFontObject(GameFontHighlightSmall)
        statusBar.TypeLabel:ClearAllPoints()
        statusBar.TypeLabel:SetPoint("LEFT", statusBar, "LEFT", 5, 0)
    end
    if statusBar.TimeLabel then
        statusBar.TimeLabel:SetFontObject(GameFontHighlightSmall)
        statusBar.TimeLabel:ClearAllPoints()
        statusBar.TimeLabel:SetPoint("RIGHT", statusBar, "RIGHT", -5, 0)
    end

    -- Blizzard dims its border when the target is out of range; follow it
    hook(frame, "ApplyRangePresentation", function(self)
        local ours = borders[self]
        if ours and self.Border then
            ours:SetAlpha(self.Border:GetAlpha())
        end
    end)
end

---------------------------------------------------------------------------
-- Position: stacked above the player cast bar, only bars the player can swing
---------------------------------------------------------------------------
local function canSwing(frame)
    if type(frame.CanSwing) ~= "function" then
        return true
    end
    local ok, result = pcall(frame.CanSwing, frame)
    return ok and result ~= false
end

local positioning = false
function ST.Position()
    if positioning or ST.state ~= "enabled" then
        return
    end
    positioning = true
    local scale = ns.db.scale or 1
    local castY = ns.CastBar and ns.CastBar.LayoutY and ns.CastBar.LayoutY() or 60
    local y = castY + BAR_HEIGHT + GAP_ABOVE_CAST_BAR
    for _, name in ipairs(FRAMES) do
        local frame = _G[name]
        if frame then
            Raw.SetScale(frame, scale)
            Raw.SetSize(frame, BAR_WIDTH, BAR_HEIGHT)
            -- a bar the player dragged in Edit Mode keeps that position and leaves the stack
            if ns.Compat.InEditModeDefault(frame) then
                Raw.ClearAllPoints(frame)
                Raw.SetPoint(frame, "BOTTOM", UIParent, "BOTTOM", 0, y / scale)
                if canSwing(frame) then
                    y = y + ROW_PITCH
                end
            end
        end
    end
    positioning = false
end

---------------------------------------------------------------------------
-- The cvar Blizzard's frames key on
---------------------------------------------------------------------------
local function cvarEnabled()
    local value = C_CVar and C_CVar.GetCVar and C_CVar.GetCVar(CVAR)
    return value == "1"
end

function ST.SwitchOn()
    if not C_CVar or not C_CVar.SetCVar or cvarEnabled() then
        return
    end
    if ns.db.swingTimer.previous == nil then
        ns.db.swingTimer.previous = C_CVar.GetCVar(CVAR) or "0"
    end
    C_CVar.SetCVar(CVAR, "1")
end

function ST.Restore()
    local previous = ns.db.swingTimer.previous
    if previous ~= nil and C_CVar and C_CVar.SetCVar then
        C_CVar.SetCVar(CVAR, previous)
        ns.db.swingTimer.previous = nil
    end
end

---------------------------------------------------------------------------
-- Module lifecycle
---------------------------------------------------------------------------
function ST:Init()
    ns.db.swingTimer = ns.db.swingTimer or {}
    if not SwingTimerMainHandFrame then
        error("SwingTimerMainHandFrame not found; Blizzard_SwingTimer is not loaded on this client")
    end
end

function ST:Enable()
    ST.SwitchOn()
    for _, name in ipairs(FRAMES) do
        local frame = _G[name]
        if frame then
            skin(frame)
            hook(frame, "ApplySystemAnchor", ST.Position)
            hook(frame, "UpdateSystemSettingWidth", ST.Position)
            hook(frame, "UpdateSystemSettingHeight", ST.Position)
            hook(frame, "UpdateSystemSettingScale", ST.Position)
        end
    end
    if BottomManagedFrameContainer then
        hook(BottomManagedFrameContainer, "Layout", ST.Position)
    end
    ns.RegisterEvent("PLAYER_ENTERING_WORLD", self, function()
        ST.SwitchOn()
        ST.Position()
    end)
    ns.RegisterEvent("UNIT_ATTACK_SPEED", self, function(_, _, unit)
        if unit == "player" then
            ST.Position()
        end
    end)
    ns.RegisterEvent("WEAPON_SLOT_CHANGED", self, ST.Position)
    ST.Position()
end

function ST:Disable()
    ns.UnregisterAllEvents(self)
    ST.Restore()
    ns.Print("SwingTimer disabled, /reload to restore the Blizzard swing timer look")
end

function ST:Refresh()
    ST.Position()
end

function ST:Diag()
    ns.Print("  showSwingTimer=%s previous=%s", tostring(cvarEnabled()), tostring(ns.db.swingTimer.previous))
    for _, name in ipairs(FRAMES) do
        local frame = _G[name]
        if frame then
            local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
            ns.Print(
                "  %-24s shown=%s canSwing=%s %s -> %s %s (%.1f, %.1f)",
                name,
                tostring(Raw.IsShown(frame)),
                tostring(canSwing(frame)),
                tostring(point),
                tostring(relativeTo and relativeTo:GetName()),
                tostring(relativePoint),
                x or 0,
                y or 0
            )
        end
    end
end
