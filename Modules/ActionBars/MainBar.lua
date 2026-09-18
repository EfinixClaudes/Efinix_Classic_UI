local _, ns = ...

-- Main bar art frame: the 1024x53 Dwarf bar, gryphons, page number, page
-- arrows and the latency bar. Blizzard's MainActionBar is anchored onto this
-- frame by ActionBars.Position().
local Raw = ns.Raw
local Assets = ns.Assets
local AB = ns.ActionBars

local MainBar = {}
AB.MainBar = MainBar

-- 1.12 MainMenuBar.xml MainMenuBarPerformanceBarFrame OnLoad
local PERFORMANCEBAR_LOW_LATENCY = 300
local PERFORMANCEBAR_MEDIUM_LATENCY = 600
local PERFORMANCEBAR_UPDATE_INTERVAL = 10

function MainBar.Create()
    local art = CreateFrame("Frame", "FCUI_MainMenuBar", UIParent)
    art:SetSize(AB.BAR_WIDTH, AB.BAR_HEIGHT) -- MainMenuBar.xml: 1024x53
    art:SetPoint("BOTTOM") -- MainMenuBar.xml: <Anchor point="BOTTOM"/>
    -- Blizzard bars live on MEDIUM strata; LOW keeps our art underneath the buttons.
    art:SetFrameStrata("LOW")
    art:SetFrameLevel(1)
    art:Hide()
    AB.frame = art

    local sheet = Assets.Get("MainBar.Art")
    if sheet then
        -- MainMenuBar.xml MainMenuBarTexture0..3: 256x43 at BOTTOM -384/-128/128/384 with these TexCoords
        local coords = {
            { 0.83203125, 1.0 },
            { 0.58203125, 0.75 },
            { 0.33203125, 0.5 },
            { 0.08203125, 0.25 },
        }
        local offsets = { -384, -128, 128, 384 }
        art.Textures = {}
        for i = 1, 4 do
            local tex = art:CreateTexture(nil, "ARTWORK")
            tex:SetTexture(sheet)
            tex:SetSize(256, 43)
            tex:SetPoint("BOTTOM", art, "BOTTOM", offsets[i], 0)
            tex:SetTexCoord(0, 1, coords[i][1], coords[i][2])
            ns.Dark.Tint(tex)
            art.Textures[i] = tex
        end
    end

    -- MainMenuBar.xml MainMenuBarLeftEndCap / RightEndCap: 128x128 at BOTTOM -544 / 544,
    -- the right one mirrored (TexCoords left=1 right=0). 1.12 uses the Dwarf gryphon for
    -- both factions; the Horde wyvern only arrived with 2.0.
    local endcap = Assets.Get("MainBar.EndCap")
    if endcap then
        art.LeftEndCap = art:CreateTexture(nil, "OVERLAY")
        art.LeftEndCap:SetTexture(endcap)
        art.LeftEndCap:SetSize(128, 128)
        art.LeftEndCap:SetPoint("BOTTOM", art, "BOTTOM", -544, 0)

        art.RightEndCap = art:CreateTexture(nil, "OVERLAY")
        art.RightEndCap:SetTexture(endcap)
        art.RightEndCap:SetSize(128, 128)
        art.RightEndCap:SetPoint("BOTTOM", art, "BOTTOM", 544, 0)
        art.RightEndCap:SetTexCoord(1, 0, 0, 1)
        ns.Dark.Tint(art.LeftEndCap)
        ns.Dark.Tint(art.RightEndCap)
    end

    MainBar.CreateLatencyBar(art)
end

---------------------------------------------------------------------------
-- Latency bar (MainMenuBar.xml MainMenuBarPerformanceBarFrame)
---------------------------------------------------------------------------
function MainBar.CreateLatencyBar(art)
    local tex = Assets.Get("MainBar.PerformanceBar")
    if not tex then
        return
    end
    local frame = CreateFrame("Frame", nil, art)
    frame:SetSize(16, 64)
    frame:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", -227, -10)
    frame.Bar = frame:CreateTexture(nil, "BACKGROUND")
    frame.Bar:SetTexture(tex)
    frame.Bar:SetSize(20, 66)
    frame.Bar:SetPoint("TOPRIGHT")

    local button = CreateFrame("Button", nil, frame)
    button:SetAllPoints(frame)
    button:SetFrameStrata("HIGH")

    local function latencyText(latency)
        return (MAINMENUBAR_LATENCY_LABEL or "Latency:") .. " " .. latency .. (MILLISECONDS_ABBR or "ms")
    end

    local function update()
        local _, _, latencyHome = GetNetStats()
        latencyHome = latencyHome or 0
        if latencyHome > PERFORMANCEBAR_MEDIUM_LATENCY then
            frame.Bar:SetVertexColor(1, 0, 0)
        elseif latencyHome > PERFORMANCEBAR_LOW_LATENCY then
            frame.Bar:SetVertexColor(1, 1, 0)
        else
            frame.Bar:SetVertexColor(0, 1, 0)
        end
        if frame.hover then
            GameTooltip:SetText(latencyText(latencyHome), 1, 1, 1)
        end
    end

    -- Throttled OnUpdate, same 10 second cadence as 1.12.
    frame.elapsed = PERFORMANCEBAR_UPDATE_INTERVAL
    frame:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed >= PERFORMANCEBAR_UPDATE_INTERVAL then
            self.elapsed = 0
            update()
        end
    end)
    button:SetScript("OnEnter", function()
        frame.hover = true
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        local _, _, latencyHome = GetNetStats()
        GameTooltip:SetText(latencyText(latencyHome or 0), 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        frame.hover = nil
        GameTooltip:Hide()
    end)
    art.LatencyBar = frame
end

---------------------------------------------------------------------------
-- Neutralise Blizzard's own bar art and reskin the page controls
---------------------------------------------------------------------------
local function hideBlizzardArt()
    local bar = MainActionBar
    if bar.BorderArt then
        bar.BorderArt:Hide()
    end
    if bar.EndCaps then
        Raw.Hide(bar.EndCaps)
    end
    if bar.HorizontalDividersPool then
        for divider in bar.HorizontalDividersPool:EnumerateActive() do
            Raw.Hide(divider)
        end
    end
    if bar.VerticalDividersPool then
        for divider in bar.VerticalDividersPool:EnumerateActive() do
            Raw.Hide(divider)
        end
    end
end

local function reskinPageControls()
    local art = AB.frame
    local pageFrame = MainActionBar.ActionBarPageNumber
    if not pageFrame then
        return
    end

    -- MainMenuBar.xml MainMenuBarPageNumber: GameFontNormalSmall, CENTER of MainMenuBarArtFrame 30,-5
    local text = pageFrame.Text
    if text then
        text:SetFontObject(GameFontNormalSmall)
        text:ClearAllPoints()
        text:SetPoint("CENTER", art, "CENTER", 30, -5)
    end

    -- ActionBarFrame.xml ActionBarUpButton / ActionBarDownButton: 32x32, CENTER of
    -- MainMenuBarArtFrame TOPLEFT 522,-22 and 522,-42, HitRectInsets 6,6,7,7
    local function reskinArrow(button, y, up, down, disabled, highlight)
        if not button then
            return
        end
        Raw.ClearAllPoints(button)
        Raw.SetPoint(button, "CENTER", art, "TOPLEFT", 522, y)
        Raw.SetSize(button, 32, 32)
        Raw.SetHitRectInsets(button, 6, 6, 7, 7)
        if up then
            button:SetNormalTexture(up)
            button:GetNormalTexture():SetAllPoints(button)
        end
        if down then
            button:SetPushedTexture(down)
            button:GetPushedTexture():SetAllPoints(button)
        end
        if disabled then
            button:SetDisabledTexture(disabled)
            button:GetDisabledTexture():SetAllPoints(button)
        end
        if highlight then
            button:SetHighlightTexture(highlight, "ADD")
            button:GetHighlightTexture():SetAllPoints(button)
        end
    end
    reskinArrow(
        pageFrame.UpButton,
        -22,
        Assets.Get("MainBar.PageUp"),
        Assets.Get("MainBar.PageUpDown"),
        Assets.Get("MainBar.PageUpDisabled"),
        Assets.Get("MainBar.PageUpHighlight")
    )
    reskinArrow(
        pageFrame.DownButton,
        -42,
        Assets.Get("MainBar.PageDown"),
        Assets.Get("MainBar.PageDownDown"),
        Assets.Get("MainBar.PageDownDisabled"),
        Assets.Get("MainBar.PageDownHighlight")
    )
end

function MainBar.Enable()
    hideBlizzardArt()
    -- Edit Mode re-shows the border on HideBarArt changes, the end caps on
    -- faction/visibility updates and rebuilds dividers on every relayout.
    AB.Hook(MainActionBar, "UpdateSystemSettingHideBarArt", hideBlizzardArt)
    AB.Hook(MainActionBar, "UpdateEndCaps", hideBlizzardArt)
    AB.Hook(MainActionBar, "UpdateDividers", hideBlizzardArt)
    reskinPageControls()
end
