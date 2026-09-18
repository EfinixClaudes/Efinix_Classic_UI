local _, ns = ...

-- XP bar, reputation watch bar and max-level trim (MainMenuBar.xml,
-- ReputationFrame.xml, MainMenuBar.lua 1.12).
--
-- Forever keeps two Edit Mode containers (MainStatusTrackingBarContainer,
-- SecondaryStatusTrackingBarContainer) and assigns bars to them by priority:
-- reputation outranks experience, so with a watched faction the *main*
-- container holds reputation and the secondary one experience. Vanilla puts
-- the XP bar inside the top of the main bar and stacks the reputation bar
-- above it, and at max level the watched reputation takes the XP slot. We
-- therefore position containers by content, not by name.
local Raw = ns.Raw
local Assets = ns.Assets
local AB = ns.ActionBars

local StatusBars = {}
AB.StatusBars = StatusBars

local BarsEnum = StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum or {}
local XP_INDEX = BarsEnum.Experience or 4
local NONE_INDEX = BarsEnum.None or -1

-- Camelot/StatusTrackingBarConstants.lua: inner bars are container size minus 3
local STATUS_BAR_SIZE_ADJUSTMENT = 3

-- 1.12 MainMenuBar.lua ExhaustionTick_Update colours
local XP_COLOR = { 0.58, 0.0, 0.55 }
local RESTED_COLOR = { 0.0, 0.39, 0.88 }

local decorated = {} -- container -> art table
local styledBars = setmetatable({}, { __mode = "k" })

local function containers()
    return { MainStatusTrackingBarContainer, SecondaryStatusTrackingBarContainer }
end

local function barIndex(container)
    return container.pendingBarToShowIndex or container.shownBarIndex or NONE_INDEX
end

-- Which container goes into the XP slot (top of the main bar) and which one
-- stacks above it as the reputation watch bar.
function StatusBars.Slots()
    local xp, rep
    for _, container in ipairs(containers()) do
        if container and Raw.IsShown(container) then
            local index = barIndex(container)
            if index == XP_INDEX then
                xp = container
            elseif index ~= NONE_INDEX then
                rep = rep or container
            end
        end
    end
    if not xp and rep then
        -- ReputationWatchBar_Update: at max level the watched reputation replaces the XP bar
        xp, rep = rep, nil
    end
    return xp, rep
end

function StatusBars.IsReputationStacked()
    local xp, rep = StatusBars.Slots()
    return xp ~= nil and rep ~= nil
end

function StatusBars.IsMaxLevelBarShown()
    return StatusBars.maxLevelArt ~= nil and StatusBars.maxLevelArt:IsShown()
end

---------------------------------------------------------------------------
-- Bar styling
---------------------------------------------------------------------------
local function styleExpBar(bar, isRested)
    local statusBar = bar.StatusBar
    if not statusBar then
        return
    end
    local tex = Assets.Get("MainBar.StatusBar")
    if tex then
        statusBar:SetStatusBarTexture(tex) -- MainMenuBar.xml BarTexture UI-StatusBar
    end
    local color = isRested and RESTED_COLOR or XP_COLOR
    statusBar:SetStatusBarColor(color[1], color[2], color[3], 1)
    if statusBar.Background then
        statusBar.Background:Hide()
    end
    -- ExhaustionLevelFillBar: white texture tinted 15% (ExhaustionTick_Update)
    local fill = bar.ExhaustionLevelFillBar
    if fill then
        fill:SetColorTexture(1, 1, 1)
        fill:SetVertexColor(color[1], color[2], color[3], 0.15)
    end
    local tick = bar.ExhaustionTick
    if tick and tick.Highlight then
        tick.Highlight:SetVertexColor(color[1], color[2], color[3])
    end
end

local function styleRepBar(bar)
    local statusBar = bar.StatusBar
    if not statusBar then
        return
    end
    local tex = Assets.Get("MainBar.StatusBar")
    if tex then
        statusBar:SetStatusBarTexture(tex)
    end
    if statusBar.Background then
        statusBar.Background:Hide()
    end
    -- ReputationWatchBar_Update: FACTION_BAR_COLORS[reaction]. The reaction may be a
    -- secret value on this client, so the table lookup is guarded.
    if C_Reputation and C_Reputation.GetWatchedFactionData and FACTION_BAR_COLORS then
        local data = C_Reputation.GetWatchedFactionData()
        local ok, color = pcall(function()
            return data and FACTION_BAR_COLORS[data.reaction]
        end)
        if ok and color then
            statusBar:SetStatusBarColor(color.r, color.g, color.b, 1)
        end
    end
end

local function styleExhaustionTick(bar)
    local tick = bar.ExhaustionTick
    if not tick then
        return
    end
    -- MainMenuBar.xml ExhaustionTick: 32x32, UI-ExhaustionTickNormal / Highlight ADD
    local normal = Assets.Get("MainBar.ExhaustionTick")
    local highlight = Assets.Get("MainBar.ExhaustionTickHighlight")
    if normal then
        tick:SetNormalTexture(normal)
        tick:GetNormalTexture():SetAllPoints(tick)
    end
    if highlight then
        tick:SetHighlightTexture(highlight, "ADD")
        tick:GetHighlightTexture():SetAllPoints(tick)
    end
    if normal or highlight then
        Raw.SetSize(tick, 32, 32)
    end
end

local function styleBar(bar)
    if styledBars[bar] then
        return
    end
    styledBars[bar] = true
    if bar.isExpBar then
        styleExpBar(bar, ns.Compat.IsRested())
        styleExhaustionTick(bar)
        -- ExhaustionTick:UpdateExhaustionColor swaps the fill atlas on rest state changes
        AB.Hook(bar, "UpdateStatusBarTextures", function(self, isRested)
            styleExpBar(self, isRested)
        end)
    elseif bar.barIndex == BarsEnum.Reputation then
        styleRepBar(bar)
        -- ReputationStatusBarMixin:Update sets a coloured atlas on every update
        AB.Hook(bar, "Update", styleRepBar)
    end
end

---------------------------------------------------------------------------
-- Container decoration: Vanilla frame art on top of Blizzard's containers
---------------------------------------------------------------------------
local function hideBlizzardContainerArt(container)
    if container.BarFrameTexture then
        container.BarFrameTexture:Hide()
    end
    if container.HorizontalDividersPool then
        for divider in container.HorizontalDividersPool:EnumerateActive() do
            Raw.Hide(divider)
        end
    end
end

local function decorate(container)
    if decorated[container] then
        return decorated[container]
    end
    local art = { xp = {}, rep = {} }
    decorated[container] = art

    -- MainMenuExpBar BACKGROUND: black, alpha 0.5
    art.bg = container:CreateTexture(nil, "BACKGROUND")
    art.bg:SetColorTexture(0, 0, 0, 0.5)
    art.bg:SetAllPoints(container)

    -- MainMenuXPBarTexture0..3: Dwarf sheet 256x10 at BOTTOM -384/-128/128/384 y=3
    local sheet = Assets.Get("MainBar.Art")
    if sheet then
        local coords = {
            { 0.79296875, 0.83203125 },
            { 0.54296875, 0.58203125 },
            { 0.29296875, 0.33203125 },
            { 0.04296875, 0.08203125 },
        }
        local offsets = { -384, -128, 128, 384 }
        for i = 1, 4 do
            local tex = container:CreateTexture(nil, "OVERLAY")
            tex:SetTexture(sheet)
            tex:SetSize(256, 10)
            tex:SetPoint("BOTTOM", container, "BOTTOM", offsets[i], 3)
            tex:SetTexCoord(0, 1, coords[i][1], coords[i][2])
            ns.Dark.Tint(tex)
            art.xp[i] = tex
        end
    end

    -- ReputationWatchBarTexture0..3: UI-ReputationWatchBar 256x11 from TOPLEFT 0,2
    local repSheet = Assets.Get("MainBar.ReputationWatchBar")
    if repSheet then
        local coords = {
            { 0, 0.171875 },
            { 0.171875, 0.34375 },
            { 0.34375, 0.515625 },
            { 0.515625, 0.6875 },
        }
        local previous
        for i = 1, 4 do
            local tex = container:CreateTexture(nil, "OVERLAY")
            tex:SetTexture(repSheet)
            tex:SetSize(256, 11)
            if previous then
                tex:SetPoint("LEFT", previous, "RIGHT")
            else
                tex:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 2)
            end
            tex:SetTexCoord(0, 1, coords[i][1], coords[i][2])
            ns.Dark.Tint(tex)
            art.rep[i] = tex
            previous = tex
        end
    end

    hideBlizzardContainerArt(container)
    AB.Hook(container, "UpdateDividers", hideBlizzardContainerArt)

    for _, bar in pairs(container.bars or {}) do
        styleBar(bar)
    end
    return art
end

local function setArtMode(art, mode)
    for _, tex in ipairs(art.xp) do
        tex:SetShown(mode == "xp" or (mode == "rep" and #art.rep == 0))
    end
    for _, tex in ipairs(art.rep) do
        tex:SetShown(mode == "rep")
    end
end

---------------------------------------------------------------------------
-- Max level trim (MainMenuBar.xml MainMenuBarMaxLevelBar)
---------------------------------------------------------------------------
local function createMaxLevelArt()
    local tex = Assets.Get("MainBar.MaxLevel")
    if not tex or StatusBars.maxLevelArt then
        return
    end
    local frame = CreateFrame("Frame", nil, AB.frame)
    frame:SetSize(1024, 7)
    frame:SetPoint("TOP", AB.frame, "TOP", 0, -11)
    local coords = {
        { 0, 0.21875 },
        { 0.25, 0.46875 },
        { 0.5, 0.71875 },
        { 0.75, 0.96875 },
    }
    local previous
    for i = 1, 4 do
        local t = frame:CreateTexture(nil, "BACKGROUND")
        t:SetTexture(tex)
        t:SetSize(256, 7)
        if previous then
            t:SetPoint("LEFT", previous, "RIGHT")
        else
            t:SetPoint("BOTTOM", frame, "TOP", -384, 0)
        end
        t:SetTexCoord(0, 1, coords[i][1], coords[i][2])
        ns.Dark.Tint(t)
        previous = t
    end
    frame:Hide()
    StatusBars.maxLevelArt = frame
end

---------------------------------------------------------------------------
-- Positioning, called from ActionBars.Position()
---------------------------------------------------------------------------
local function sizeInnerBars(container, width, height)
    for _, bar in pairs(container.bars or {}) do
        Raw.SetSize(bar, width - STATUS_BAR_SIZE_ADJUSTMENT, height - STATUS_BAR_SIZE_ADJUSTMENT)
        if bar.StatusBar then
            Raw.SetSize(bar.StatusBar, width - STATUS_BAR_SIZE_ADJUSTMENT, height - STATUS_BAR_SIZE_ADJUSTMENT)
        end
    end
end

function StatusBars.Position()
    local art = AB.frame
    local scale = ns.db.scale or 1
    local xp, rep = StatusBars.Slots()

    for _, container in ipairs(containers()) do
        if AB.CanAnchor(container) then
            local deco = decorate(container)
            Raw.SetScale(container, scale)
            Raw.ClearAllPoints(container)
            if container == rep then
                -- ReputationWatchBar: 1024x11, BOTTOM to MainMenuBar TOP 0,-3
                Raw.SetSize(container, 1024, 11)
                Raw.SetPoint(container, "BOTTOM", art, "TOP", 0, -3)
                sizeInnerBars(container, 1024, 11)
                setArtMode(deco, "rep")
            else
                -- MainMenuExpBar: 1024x13 at TOP of MainMenuBar
                Raw.SetSize(container, 1024, 13)
                Raw.SetPoint(container, "TOP", art, "TOP", 0, 0)
                sizeInnerBars(container, 1024, 13)
                setArtMode(deco, "xp")
            end
        end
    end

    -- MainMenuBarMaxLevelBar shows when nothing occupies the XP slot at max level
    if StatusBars.maxLevelArt then
        StatusBars.maxLevelArt:SetShown(xp == nil and ns.Compat.IsPlayerMaxLevel())
    end
end

function StatusBars.Enable()
    if not StatusTrackingBarManager or not MainStatusTrackingBarContainer then
        ns.Log("ActionBars", "StatusTrackingBarManager missing, XP bar left untouched")
        return
    end
    createMaxLevelArt()
    for _, container in ipairs(containers()) do
        if container then
            decorate(container)
            AB.Hook(container, "ApplySystemAnchor", AB.Position)
            AB.Hook(container, "UpdateShownState", AB.Position)
            AB.HookScript(container, "OnShow", AB.Position)
            AB.HookScript(container, "OnHide", AB.Position)
        end
    end
    AB.Hook(StatusTrackingBarManager, "UpdateBarsShown", AB.Position)
    ns.RegisterEvent("PLAYER_LEVEL_UP", StatusBars, AB.Position)
    ns.RegisterEvent("UPDATE_EXHAUSTION", StatusBars, function()
        for _, container in ipairs(containers()) do
            for _, bar in pairs(container and container.bars or {}) do
                if bar.isExpBar then
                    styleExpBar(bar, ns.Compat.IsRested())
                end
            end
        end
    end)
end
