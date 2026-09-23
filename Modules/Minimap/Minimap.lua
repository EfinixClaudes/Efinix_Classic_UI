local _, ns = ...

-- Minimap module: MinimapCluster reskinned in place to the 1.12 cluster
-- (Minimap.xml 1.12: cluster 192x192 at TOPRIGHT, top border 192x32,
-- zone text 128x12 at cluster CENTER -3,83, round map 140 at TOP 9,-92,
-- backdrop ring 192 at CENTER 0,-20, zoom buttons 32 at backdrop 77,-13 and
-- 51,-41, tracking 33 at TOPLEFT -15,0, mail 33 at TOPRIGHT 21,-38,
-- battlefield 33 at BOTTOMLEFT 13,-13, day/night 50 at TOPRIGHT 4,-19,
-- minimise button 32 at TOPRIGHT -15,-13).
--
-- Nothing on the cluster is protected, so every call here is safe in combat.
-- Blizzard's frames keep their scripts; we re-anchor with raw widget methods
-- after each of its layout passes and swap textures.
local Raw = ns.Raw

local MM = ns.RegisterModule("Minimap", {})
ns.Minimap = MM

local CLUSTER = 192 -- MinimapCluster 192x192
local MAP_SIZE = 140 -- Minimap 140x140
local hooked = {}
local suppressed = false

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

local function hookScript(frame, script, fn)
    if not frame or not frame.HookScript then
        return
    end
    local key = tostring(frame) .. ":script:" .. script
    if hooked[key] then
        return
    end
    hooked[key] = true
    frame:HookScript(script, fn)
end

local function hideTexture(region)
    if region then
        region:Hide()
        -- Blizzard re-shows the compass underlay on rotateMinimap changes
        hook(region, "Show", function(self)
            self:Hide()
        end)
    end
end

---------------------------------------------------------------------------
-- Our art: top border and backdrop ring, parented to the cluster
---------------------------------------------------------------------------
local function createArt()
    if MM.art then
        return
    end
    local art = CreateFrame("Frame", "FCUI_MinimapArt", MinimapCluster)
    art:SetSize(CLUSTER, CLUSTER)
    art:SetPoint("TOPRIGHT")
    art.ignoreInLayout = true -- our frame; keeps ResizeLayoutFrame from measuring it

    local border = ns.Assets.Get("Minimap.Border")
    if border then
        -- MinimapBorderTop 192x32 at TOPRIGHT, UI-Minimap-Border coords 0.25,1,0,0.125
        art.Top = art:CreateTexture(nil, "ARTWORK")
        art.Top:SetTexture(border)
        art.Top:SetSize(192, 32)
        art.Top:SetPoint("TOPRIGHT")
        art.Top:SetTexCoord(0.25, 1, 0, 0.125)
        -- MinimapBorder 192x192 at CENTER 0,-20, coords 0.25,1,0.125,0.875
        art.Ring = art:CreateTexture(nil, "ARTWORK")
        art.Ring:SetTexture(border)
        art.Ring:SetSize(192, 192)
        art.Ring:SetPoint("CENTER", art, "CENTER", 0, -20)
        art.Ring:SetTexCoord(0.25, 1, 0.125, 0.875)
        ns.Dark.Tint(art.Top)
        ns.Dark.Tint(art.Ring)
    end
    MM.art = art
end

-- MinimapToggleButton: 32x32 at CENTER of cluster TOPRIGHT -15,-13, UI-Panel-MinimizeButton
local function createToggle()
    if MM.toggle or not MM.art then
        return
    end
    local up = ns.Assets.Get("Panel.CloseUp")
    local down = ns.Assets.Get("Panel.CloseDown")
    local highlight = ns.Assets.Get("Panel.CloseHighlight")
    if not up or not down then
        return
    end
    local button = CreateFrame("Button", "FCUI_MinimapToggleButton", MM.art)
    button:SetSize(32, 32)
    button:SetPoint("CENTER", MM.art, "TOPRIGHT", -15, -13)
    button:SetNormalTexture(up)
    button:SetPushedTexture(down)
    if highlight then
        button:SetHighlightTexture(highlight, "ADD")
    end
    button:SetScript("OnClick", function()
        if ToggleMinimap then
            ToggleMinimap()
        end
    end)
    MM.toggle = button
end

---------------------------------------------------------------------------
-- Day/night indicator (GameTime.xml / GameTime.lua 1.12): 50x50 at TOPRIGHT 4,-19,
-- UI-TOD-Indicator, sun coords 0..50/128 x 0..50/64, moon +0.5 in x.
-- Dawn 5:30, dusk 21:00. Left click opens the calendar Blizzard hides behind
-- its own GameTimeFrame so that system stays reachable.
---------------------------------------------------------------------------
local GAMETIME_DAWN = 5 * 60 + 30
local GAMETIME_DUSK = 21 * 60
local TOD_UPDATE_SECONDS = 10

local function formatGameTime(hour, minute)
    local military = GetCVarBool and GetCVarBool("timeMgrUseMilitaryTime")
    if military then
        return ("%d:%02d"):format(hour, minute)
    end
    local suffix = hour >= 12 and "PM" or "AM"
    hour = hour % 12
    if hour == 0 then
        hour = 12
    end
    return ("%d:%02d %s"):format(hour, minute, suffix)
end

local function createGameTime()
    if MM.gameTime or not MM.art then
        return
    end
    local tex = ns.Assets.Get("Minimap.TimeOfDay")
    if not tex then
        return
    end
    local frame = CreateFrame("Button", "FCUI_GameTimeFrame", MM.art)
    frame:SetSize(50, 50)
    frame:SetPoint("TOPRIGHT", MM.art, "TOPRIGHT", 4, -19)
    frame:SetHitRectInsets(6, 0, 5, 10) -- GameTime.xml HitRectInsets left 6, right 0, top 5, bottom 10
    frame:SetFrameLevel(MM.art:GetFrameLevel() + 2)
    frame.Texture = frame:CreateTexture(nil, "ARTWORK")
    frame.Texture:SetTexture(tex)
    frame.Texture:SetAllPoints()
    frame.timeOfDay = -1
    frame:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = (self.elapsed or TOD_UPDATE_SECONDS) + elapsed
        if self.elapsed < TOD_UPDATE_SECONDS then
            return
        end
        self.elapsed = 0
        local hour, minute = GetGameTime()
        local time = hour * 60 + minute
        if time ~= self.timeOfDay then
            self.timeOfDay = time
            local minx, maxx = 0, 50 / 128
            if time < GAMETIME_DAWN or time >= GAMETIME_DUSK then
                minx, maxx = minx + 0.5, maxx + 0.5
            end
            self.Texture:SetTexCoord(minx, maxx, 0, 50 / 64)
            if GameTooltip:IsOwned(self) then
                GameTooltip:SetText(formatGameTime(hour, minute))
            end
        end
    end)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText(formatGameTime(GetGameTime()))
        if GameTimeFrame then
            GameTooltip:AddLine(ns.L["Click to open the calendar"], 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    frame:SetScript("OnClick", function()
        if GameTimeFrame and GameTimeFrame.Click then
            GameTimeFrame:Click()
        end
    end)
    MM.gameTime = frame
end

---------------------------------------------------------------------------
-- Tracking (Minimap.xml 1.12 MiniMapTrackingFrame): 33x33 at TOPLEFT -15,0,
-- icon 26 at 7,-6 under a 64x64 MiniMap-TrackingBorder. Forever's frame is a
-- dropdown menu for tracking filters; we keep it as the click target and
-- show the active tracking spell's icon like 1.12 did.
---------------------------------------------------------------------------
local function createTrackingArt()
    local tracking = MinimapCluster and MinimapCluster.Tracking
    if MM.trackingArt or not tracking then
        return
    end
    local border = ns.Assets.Get("Minimap.TrackingBorder")
    local art = CreateFrame("Frame", "FCUI_MinimapTrackingArt", tracking)
    art:SetAllPoints()
    art:SetFrameLevel(tracking:GetFrameLevel())
    art.Icon = art:CreateTexture(nil, "BACKGROUND")
    art.Icon:SetSize(26, 26)
    art.Icon:SetPoint("TOPLEFT", tracking, "TOPLEFT", 7, -6)
    if border then
        art.Border = art:CreateTexture(nil, "OVERLAY")
        art.Border:SetTexture(border)
        art.Border:SetSize(64, 64)
        art.Border:SetPoint("TOPLEFT", tracking, "TOPLEFT", 0, 0)
        ns.Dark.Tint(art.Border)
    end
    MM.trackingArt = art
end

function MM.UpdateTrackingIcon()
    local art = MM.trackingArt
    if not art or not C_Minimap or not C_Minimap.GetNumTrackingTypes then
        return
    end
    local icon
    for index = 1, C_Minimap.GetNumTrackingTypes() do
        local info = C_Minimap.GetTrackingInfo(index)
        -- 1.12 only ever showed tracking *spells* (GetTrackingTexture); townsfolk filters had no icon
        if info and info.active and info.spellID and info.texture then
            icon = info.texture
            break
        end
    end
    if icon then
        art.Icon:SetTexture(icon)
        art.Icon:SetTexCoord(0, 1, 0, 1)
    else
        local none = ns.Assets.Get("Minimap.TrackingNone")
        if none then
            art.Icon:SetTexture(none)
        else
            art.Icon:SetTexture(nil)
        end
    end
end

local function layoutTracking()
    local tracking = MinimapCluster and MinimapCluster.Tracking
    if not tracking then
        return
    end
    Raw.SetSize(tracking, 33, 33)
    Raw.ClearAllPoints(tracking)
    Raw.SetPoint(tracking, "TOPLEFT", MinimapCluster, "TOPLEFT", -15, 0)
    if tracking.Background then
        tracking.Background:Hide()
    end
    local button = tracking.Button
    if button then
        -- the dropdown button becomes the invisible click area over our icon
        Raw.SetSize(button, 26, 26)
        Raw.ClearAllPoints(button)
        Raw.SetPoint(button, "TOPLEFT", tracking, "TOPLEFT", 7, -6)
        for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }) do
            local region = button[getter] and button[getter](button)
            if region then
                region:SetAlpha(0)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Mail (Minimap.xml 1.12 MiniMapMailFrame): 33x33 at TOPRIGHT 21,-38,
-- INV_Letter_15 18x18 at 7,-6 under a 52x52 MiniMap-TrackingBorder.
---------------------------------------------------------------------------
local function createMailArt()
    local indicator = MinimapCluster and MinimapCluster.IndicatorFrame
    local mail = indicator and indicator.MailFrame
    if MM.mailArt or not mail then
        return
    end
    local border = ns.Assets.Get("Minimap.TrackingBorder")
    local art = CreateFrame("Frame", "FCUI_MinimapMailArt", mail)
    art:SetAllPoints()
    art:SetFrameLevel(mail:GetFrameLevel())
    if border then
        art.Border = art:CreateTexture(nil, "OVERLAY")
        art.Border:SetTexture(border)
        art.Border:SetSize(52, 52)
        art.Border:SetPoint("TOPLEFT", mail, "TOPLEFT", 0, 0)
        ns.Dark.Tint(art.Border)
    end
    MM.mailArt = art
end

local function styleMail()
    local indicator = MinimapCluster and MinimapCluster.IndicatorFrame
    local mail = indicator and indicator.MailFrame
    if not mail then
        return
    end
    Raw.SetSize(mail, 33, 33)
    local icon = mail.MailIcon
    if icon then
        local tex = ns.Assets.Get("Minimap.MailIcon")
        if tex then
            icon:SetTexture(tex)
            icon:SetTexCoord(0, 1, 0, 1)
        end
        icon:ClearAllPoints()
        icon:SetSize(18, 18)
        icon:SetPoint("TOPLEFT", mail, "TOPLEFT", 7, -6)
    end
    -- modern flipbook animations have no Vanilla counterpart; Blizzard hides the
    -- icon while they play and shows it when they finish, we show it at once
    if mail.NewMailFlipbook then
        mail.NewMailFlipbook:Hide()
    end
    if mail.MailReminderFlipbook then
        mail.MailReminderFlipbook:Hide()
    end
    if icon and HasNewMail and HasNewMail() then
        icon:Show()
    end
end

local function layoutIndicator()
    local indicator = MinimapCluster and MinimapCluster.IndicatorFrame
    if not indicator then
        return
    end
    -- Minimap.xml 1.12: MiniMapMailFrame is a child of the round map, its TOPRIGHT
    -- 21 px right of and 38 px below the map's TOPRIGHT (over the ring). The cluster
    -- sits at the screen edge here, so the same spot mirrored to the left ring,
    -- under the tracking icon, keeps the letter on screen. The layout frame wraps
    -- the mail frame exactly, so its corner is the mail frame's.
    Raw.ClearAllPoints(indicator)
    Raw.SetPoint(indicator, "TOPLEFT", Minimap, "TOPLEFT", -21, -38)
    if indicator.CraftingOrderFrame then
        ns.Suppress(indicator.CraftingOrderFrame)
    end
end

---------------------------------------------------------------------------
-- Zoom buttons: 32x32, always visible. Offsets derived from 1.12: backdrop
-- centre is cluster centre 0,-20; map centre is cluster centre 9,4; so
-- ZoomIn (backdrop 77,-13) is map centre 68,-37 and ZoomOut (51,-41) is 42,-65.
---------------------------------------------------------------------------
local function styleZoom(button, up, down, disabled, x, y)
    if not button then
        return
    end
    local upTex = ns.Assets.Get(up)
    local downTex = ns.Assets.Get(down)
    local disabledTex = ns.Assets.Get(disabled)
    local highlight = ns.Assets.Get("Minimap.ZoomHighlight")
    if upTex then
        button:SetNormalTexture(upTex)
    end
    if downTex then
        button:SetPushedTexture(downTex)
    end
    if disabledTex then
        button:SetDisabledTexture(disabledTex)
    end
    if highlight then
        button:SetHighlightTexture(highlight, "ADD")
    end
    Raw.SetSize(button, 32, 32)
    Raw.ClearAllPoints(button)
    Raw.SetPoint(button, "CENTER", Minimap, "CENTER", x, y)
    Raw.SetFrameLevel(button, Minimap:GetFrameLevel() + 3)
    Raw.Show(button)
end

local function showZoomButtons()
    if Minimap and Minimap.ZoomIn then
        Raw.Show(Minimap.ZoomIn)
    end
    if Minimap and Minimap.ZoomOut then
        Raw.Show(Minimap.ZoomOut)
    end
end

---------------------------------------------------------------------------
-- Queue status (LFG eye / battleground queue): 1.12 MiniMapBattlefieldFrame
-- sat 33x33 at cluster BOTTOMLEFT 13,-13. Its centre is 13+16.5, -13+16.5.
---------------------------------------------------------------------------
local function layoutQueueStatus()
    if not QueueStatusButton or not MinimapCluster then
        return
    end
    Raw.ClearAllPoints(QueueStatusButton)
    Raw.SetPoint(QueueStatusButton, "CENTER", MinimapCluster, "BOTTOMLEFT", 29.5, 3.5)
end

---------------------------------------------------------------------------
-- Mask: 1.12 maps were round (engine default); Forever masks with an atlas.
---------------------------------------------------------------------------
local applyingMask = false
local function applyMask()
    local mask = ns.Assets.Get("Minimap.Mask")
    if not mask or applyingMask or not Minimap or not Minimap.SetMaskTexture then
        return
    end
    applyingMask = true
    Minimap:SetMaskTexture(mask)
    applyingMask = false
end

---------------------------------------------------------------------------
-- Layout pass
---------------------------------------------------------------------------
function MM.Scale()
    local scale = ns.db.minimap and tonumber(ns.db.minimap.scale)
    return scale or 1
end

function MM.SetScale(scale)
    ns.db.minimap = ns.db.minimap or {}
    ns.db.minimap.scale = scale
    MM.Layout()
    if ns.Auras and ns.Auras.Position then
        ns.Auras.Position()
    end
end

local laying = false
function MM.Layout()
    if laying or MM.state ~= "enabled" or not MinimapCluster or not Minimap then
        return
    end
    laying = true
    local cluster = MinimapCluster
    -- global bar scale times the minimap's own size setting (1.12: 192 px cluster)
    local scale = (ns.db.scale or 1) * MM.Scale()

    Raw.SetScale(cluster, scale)
    Raw.ClearAllPoints(cluster)
    Raw.SetPoint(cluster, "TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
    Raw.SetSize(cluster, CLUSTER, CLUSTER)
    Raw.SetHitRectInsets(cluster, 0, 0, 0, 0)

    -- Edit Mode scales the container and moves the header; undo both.
    local container = cluster.MinimapContainer
    if container then
        Raw.SetScale(container, 1)
    end
    if cluster.BorderTop then
        Raw.SetAlpha(cluster.BorderTop, 0)
        Raw.SetScale(cluster.BorderTop, 1)
    end

    -- Minimap 140x140 at CENTER of cluster TOP 9,-92
    Raw.SetSize(Minimap, MAP_SIZE, MAP_SIZE)
    Raw.ClearAllPoints(Minimap)
    Raw.SetPoint(Minimap, "CENTER", cluster, "TOP", 9, -92)
    applyMask()

    -- Backdrop textures: Forever's atlas frame is replaced by our ring
    hideTexture(MinimapCompassTexture)
    hideTexture(MinimapCompassTextureUnderlay)

    if MM.art then
        MM.art:SetFrameLevel(Minimap:GetFrameLevel() + 1)
    end

    -- Zone text: MinimapZoneTextButton 128x12 at cluster CENTER -3,83 = TOP -3,-13
    local zone = cluster.ZoneTextButton
    if zone then
        Raw.SetScale(zone, 1)
        Raw.SetSize(zone, 128, 12)
        Raw.ClearAllPoints(zone)
        Raw.SetPoint(zone, "CENTER", cluster, "TOP", -3, -13)
        Raw.SetFrameLevel(zone, Minimap:GetFrameLevel() + 2)
    end
    if MinimapZoneText then
        MinimapZoneText:ClearAllPoints()
        MinimapZoneText:SetSize(128, 12)
        MinimapZoneText:SetPoint("TOP", zone or cluster, "TOP", 0, 0)
        MinimapZoneText:SetJustifyH("CENTER")
    end

    layoutTracking()
    layoutIndicator()
    styleMail()
    styleZoom(Minimap.ZoomIn, "Minimap.ZoomInUp", "Minimap.ZoomInDown", "Minimap.ZoomInDisabled", 68, -37)
    styleZoom(Minimap.ZoomOut, "Minimap.ZoomOutUp", "Minimap.ZoomOutDown", "Minimap.ZoomOutDisabled", 42, -65)
    layoutQueueStatus()

    if cluster.Tracking then
        Raw.SetFrameLevel(cluster.Tracking, Minimap:GetFrameLevel() + 2)
    end
    if cluster.IndicatorFrame then
        Raw.SetFrameLevel(cluster.IndicatorFrame, Minimap:GetFrameLevel() + 2)
    end

    -- Camelot day/night frame: replaced by our indicator when the 1.12 art ships,
    -- otherwise moved to the 1.12 GameTimeFrame spot.
    local diel = cluster.DielFrame
    if diel then
        if MM.gameTime then
            if not suppressed then
                ns.Suppress(diel)
                suppressed = true
            end
        else
            Raw.ClearAllPoints(diel)
            Raw.SetPoint(diel, "TOPRIGHT", cluster, "TOPRIGHT", 4, -19)
            Raw.SetScale(diel, 1)
        end
    end

    laying = false
end

---------------------------------------------------------------------------
-- Module lifecycle
---------------------------------------------------------------------------
function MM:Init()
    if not MinimapCluster or not Minimap then
        error("MinimapCluster not found; this client does not match docs/CLIENT_FACTS.md")
    end
    createArt()
    createToggle()
    createGameTime()
    createTrackingArt()
    createMailArt()
end

function MM:Enable()
    local cluster = MinimapCluster

    -- Systems 1.12 did not have
    for _, name in ipairs({ "GameTimeFrame", "TimeManagerClockButton", "AddonCompartmentFrame" }) do
        if _G[name] then
            ns.Suppress(_G[name])
        end
    end
    if cluster.InstanceDifficulty then
        ns.Suppress(cluster.InstanceDifficulty)
    end
    if cluster.MinimapContainer and cluster.MinimapContainer.PlayerCoords then
        ns.Suppress(cluster.MinimapContainer.PlayerCoords)
    end

    -- Layout passes that move things back
    hook(cluster, "ApplySystemAnchor", MM.Layout)
    hook(cluster, "Layout", MM.Layout)
    hook(cluster, "SetEditModeScale", MM.Layout)
    hook(cluster, "SetHeaderUnderneath", MM.Layout)
    hook(Minimap, "SetMaskTexture", function()
        if not applyingMask then
            applyMask()
        end
    end)
    if MiniMapIndicatorFrame_UpdatePosition then
        hooksecurefunc("MiniMapIndicatorFrame_UpdatePosition", layoutIndicator)
    end
    if QueueStatusButton then
        hook(QueueStatusButton, "UpdateDefaultAnchor", layoutQueueStatus)
        hook(QueueStatusButton, "ApplySystemAnchor", layoutQueueStatus)
    end

    -- Blizzard hides the zoom buttons when the mouse leaves the map
    hookScript(Minimap, "OnLeave", showZoomButtons)
    hookScript(Minimap.ZoomIn, "OnLeave", showZoomButtons)
    hookScript(Minimap.ZoomOut, "OnLeave", showZoomButtons)

    ns.RegisterEvent("PLAYER_ENTERING_WORLD", self, function()
        MM.Layout()
        MM.UpdateTrackingIcon()
    end)
    ns.RegisterEvent("MINIMAP_UPDATE_TRACKING", self, MM.UpdateTrackingIcon)
    ns.RegisterEvent("SPELLS_CHANGED", self, MM.UpdateTrackingIcon)
    ns.RegisterEvent("UPDATE_PENDING_MAIL", self, styleMail)
    ns.RegisterEvent("CVAR_UPDATE", self, function(_, _, name)
        if name == "rotateMinimap" then
            MM.Layout()
        end
    end)

    MM.Layout()
    MM.UpdateTrackingIcon()
end

function MM:Disable()
    ns.UnregisterAllEvents(self)
    if MM.art then
        MM.art:Hide()
    end
    ns.Print("Minimap disabled, /reload to restore the Blizzard minimap")
end

function MM:Refresh()
    MM.Layout()
end

function MM:Diag()
    if not MinimapCluster then
        ns.Print("MinimapCluster missing")
        return
    end
    local point, relativeTo, relativePoint, x, y = MinimapCluster:GetPoint(1)
    ns.Print(
        "  cluster %s -> %s %s (%.1f, %.1f) size %.0fx%.0f scale %.2f",
        tostring(point),
        tostring(relativeTo and relativeTo:GetName()),
        tostring(relativePoint),
        x or 0,
        y or 0,
        MinimapCluster:GetWidth(),
        MinimapCluster:GetHeight(),
        MinimapCluster:GetScale()
    )
    ns.Print(
        "  map %.0fx%.0f, art=%s gameTime=%s tracking=%s mail=%s",
        Minimap:GetWidth(),
        Minimap:GetHeight(),
        tostring(MM.art ~= nil),
        tostring(MM.gameTime ~= nil),
        tostring(MM.trackingArt ~= nil),
        tostring(MM.mailArt ~= nil)
    )
end
