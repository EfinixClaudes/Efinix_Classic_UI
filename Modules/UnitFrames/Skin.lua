local _, ns = ...

-- Vanilla art for PlayerFrame, TargetFrame, its target-of-target and PetFrame
-- (PlayerFrame.xml, TargetFrame.xml, PetFrame.xml 1.12). Reskin in place:
-- Blizzard's frames, mixins and secure behaviour stay; we retexture their
-- regions, re-anchor their bars with raw widget methods (through the combat
-- queue, the containers are secure) and hide the modern decorations.
--
-- Nothing here reads health or power values: bar fill and text are left to
-- Blizzard, which handles Secret Values. We only choose textures and colours.
local Raw = ns.Raw
local Combat = ns.Combat
local UF = ns.UnitFrames

local Skin = {}
UF.Skin = Skin

local T = "Interface\\TargetingFrame\\"
local C = "Interface\\CharacterFrame\\"
local G = "Interface\\GroupFrame\\"

-- Runtime-probed file paths (ActionBars' Assets table only lists bar art).
local FILES = {
    frame = T .. "UI-TargetingFrame",
    elite = T .. "UI-TargetingFrame-Elite",
    rare = T .. "UI-TargetingFrame-Rare",
    levelBackground = T .. "UI-TargetingFrame-LevelBackground",
    skull = T .. "UI-TargetingFrame-Skull",
    tot = T .. "UI-TargetofTargetFrame",
    small = T .. "UI-SmallTargetingFrame",
    statusBar = T .. "UI-StatusBar",
    playerStatus = C .. "UI-Player-Status",
    stateIcon = C .. "UI-StateIcon",
    petAttack = T .. "UI-Player-AttackStatus",
    leader = G .. "UI-Group-LeaderIcon",
    pvpAlliance = T .. "UI-PVP-Alliance",
    pvpHorde = T .. "UI-PVP-Horde",
    pvpFFA = T .. "UI-PVP-FFA",
}
local present = {}

local function file(key)
    if present[key] == nil then
        if ns.Assets.HasMedia(FILES[key]) then
            present[key] = true
        else
            local exists = ns.Compat.TextureExists(FILES[key])
            present[key] = exists ~= false
            if not present[key] then
                ns.Log("UnitFrames", "missing texture %s", FILES[key])
            end
        end
    end
    return present[key] and ns.Assets.Resolve(FILES[key]) or nil
end

-- 1.12 UnitFrame.lua ManaBarColor, by power token
local POWER_COLORS = {
    MANA = { 0, 0, 1 },
    RAGE = { 1, 0, 0 },
    FOCUS = { 1, 0.5, 0.25 },
    ENERGY = { 1, 1, 0 },
    HAPPINESS = { 0, 1, 1 },
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function hide(region)
    if region then
        region:SetAlpha(0)
        if region.Hide then
            region:Hide()
        end
    end
end

local function unmask(texture, mask)
    if texture and mask and texture.RemoveMaskTexture then
        pcall(texture.RemoveMaskTexture, texture, mask)
    end
end

local function styleBar(bar, mask, r, g, b)
    if not bar then
        return
    end
    local tex = file("statusBar")
    if tex then
        bar:SetStatusBarTexture(tex)
    end
    if r then
        bar:SetStatusBarColor(r, g, b)
    end
    local statusTexture = bar:GetStatusBarTexture()
    if statusTexture then
        unmask(statusTexture, mask)
        statusTexture:SetDesaturated(false)
        statusTexture:SetAlpha(1)
    end
    hide(bar.Spark)
end

-- Colour a power bar the 1.12 way from the unit's power token (a small
-- string, never secret).
local function stylePowerBar(bar, unit, mask)
    if not bar then
        return
    end
    local ok, _, token = pcall(UnitPowerType, unit)
    local color = ok and POWER_COLORS[token] or POWER_COLORS.MANA
    styleBar(bar, mask, color[1], color[2], color[3])
end

-- Protected geometry goes through the combat queue.
local function geometry(key, fn)
    Combat.Run("uf:" .. key, fn)
end

---------------------------------------------------------------------------
-- PlayerFrame (PlayerFrame.xml 1.12: 232x100, portrait 64 at 42,-12,
-- bars 119x12 at 106,-41 and 106,-52, name CENTER 50,19, level CENTER -63,-16)
---------------------------------------------------------------------------
local function playerArt()
    local frame = PlayerFrame
    local container = frame.PlayerFrameContainer
    local main = frame.PlayerFrameContent.PlayerFrameContentMain
    local contextual = frame.PlayerFrameContent.PlayerFrameContentContextual

    -- Frame texture: right half of UI-TargetingFrame, mirrored
    local art = file("frame")
    if art then
        container.FrameTexture:SetTexture(art)
        container.FrameTexture:SetTexCoord(1.0, 0.09375, 0, 0.78125)
        container.FrameTexture:ClearAllPoints()
        container.FrameTexture:SetAllPoints(frame)
        container.FrameTexture:SetAlpha(1)
        container.FrameTexture:Show()
    end
    hide(container.VehicleFrameTexture)
    hide(container.AlternatePowerFrameTexture)
    hide(container.FrameFlash)

    -- Portrait 64x64 at 42,-12, no rounded mask
    unmask(container.PlayerPortrait, container.PlayerPortraitMask)
    container.PlayerPortrait:ClearAllPoints()
    container.PlayerPortrait:SetSize(64, 64)
    container.PlayerPortrait:SetPoint("TOPLEFT", frame, "TOPLEFT", 42, -12)

    -- Status glow: UI-Player-Status 190x66 at 35,-8, additive (Blizzard pulses its alpha)
    local status = file("playerStatus")
    if status then
        main.StatusTexture:SetTexture(status)
        main.StatusTexture:SetTexCoord(0, 0.74609375, 0, 0.53125)
        main.StatusTexture:SetBlendMode("ADD")
        main.StatusTexture:ClearAllPoints()
        main.StatusTexture:SetSize(190, 66)
        main.StatusTexture:SetPoint("TOPLEFT", frame, "TOPLEFT", 35, -8)
    end

    -- Modern-only decorations
    hide(main.PvpBackgroundCircle)
    hide(main.PvpBackgroundIcon)
    hide(main.LevelBackgroundCircle)
    hide(contextual.PlayerPortraitCornerIcon)
    hide(contextual.RoleIcon)
    hide(contextual.GuideIcon)
    if contextual.PlayerRestLoop then
        ns.Suppress(contextual.PlayerRestLoop)
    end

    -- Attack icon: UI-StateIcon right half, 32x32 (Vanilla anchors it 1,1 off the rest icon at 37,-49)
    local state = file("stateIcon")
    if state and contextual.AttackIcon then
        contextual.AttackIcon:SetTexture(state)
        contextual.AttackIcon:SetTexCoord(0.5, 1.0, 0, 0.5)
        contextual.AttackIcon:ClearAllPoints()
        contextual.AttackIcon:SetSize(32, 32)
        contextual.AttackIcon:SetPoint("TOPLEFT", frame, "TOPLEFT", 38, -50)
    end

    -- Leader icon 16x16 at 44,-10
    local leader = file("leader")
    if leader and contextual.LeaderIcon then
        contextual.LeaderIcon:SetTexture(leader)
        contextual.LeaderIcon:ClearAllPoints()
        contextual.LeaderIcon:SetSize(16, 16)
        contextual.LeaderIcon:SetPoint("TOPLEFT", frame, "TOPLEFT", 44, -10)
    end

    -- Hit indicator CENTER at TOPLEFT 73,-42
    if main.HitIndicator and main.HitIndicator.HitText then
        main.HitIndicator.HitText:ClearAllPoints()
        main.HitIndicator.HitText:SetPoint("CENTER", frame, "TOPLEFT", 73, -42)
    end

    -- Name and level
    PlayerName:ClearAllPoints()
    PlayerName:SetSize(100, 10)
    PlayerName:SetJustifyH("CENTER")
    PlayerName:SetPoint("CENTER", frame, "CENTER", 50, 19)
    PlayerLevelText:SetFontObject(GameFontNormalSmall)
    PlayerLevelText:ClearAllPoints()
    PlayerLevelText:SetPoint("CENTER", frame, "CENTER", -63, -16)
    PlayerLevelText:SetVertexColor(1.0, 0.82, 0.0)

    -- Bars
    local healthContainer = main.HealthBarsContainer
    local healthBar = healthContainer.HealthBar
    local manaBar = main.ManaBarArea.ManaBar
    styleBar(healthBar, healthContainer.HealthBarMask, 0, 1, 0)
    stylePowerBar(manaBar, "player", manaBar.ManaBarMask)
    hide(healthContainer.LeftText)
    hide(healthContainer.RightText)
    hide(manaBar.LeftText)
    hide(manaBar.RightText)
    for _, key in ipairs({
        "PlayerFrameTempMaxHealthLoss",
        "PlayerFrameHealthBarAnimatedLoss",
        "TempMaxHealthLossDivider",
    }) do
        if healthContainer[key] then
            ns.Suppress(healthContainer[key])
        end
    end
    for _, key in ipairs({ "MyHealPredictionBar", "OtherHealPredictionBar", "HealAbsorbBar", "TotalAbsorbBar" }) do
        if healthBar[key] then
            ns.Suppress(healthBar[key])
        end
    end
    hide(healthBar.OverAbsorbGlow)
    hide(healthBar.OverHealAbsorbGlow)
    if manaBar.FullPowerFrame then
        ns.Suppress(manaBar.FullPowerFrame)
    end
    if manaBar.FeedbackFrame then
        ns.Suppress(manaBar.FeedbackFrame)
    end
    if manaBar.ManaCostPredictionBar then
        ns.Suppress(manaBar.ManaCostPredictionBar)
    end

    geometry("player", function()
        Raw.ClearAllPoints(healthContainer)
        Raw.SetSize(healthContainer, 119, 12)
        Raw.SetPoint(healthContainer, "TOPLEFT", frame, "TOPLEFT", 106, -41)
        Raw.ClearAllPoints(healthBar)
        Raw.SetSize(healthBar, 119, 12)
        Raw.SetPoint(healthBar, "TOPLEFT", healthContainer, "TOPLEFT", 0, 0)
        Raw.ClearAllPoints(manaBar)
        Raw.SetSize(manaBar, 119, 12)
        Raw.SetPoint(manaBar, "TOPLEFT", frame, "TOPLEFT", 106, -52)
    end)
end

local function playerBackground()
    if Skin.playerBackground then
        return
    end
    -- PlayerFrameBackground: black 50%, 119x41 at 106,-22 (under the bars)
    local bg = PlayerFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetColorTexture(0, 0, 0, 0.5)
    bg:SetSize(119, 41)
    bg:SetPoint("TOPLEFT", PlayerFrame, "TOPLEFT", 106, -22)
    Skin.playerBackground = bg

    -- Our overlay above Blizzard's content frames for the rest and PvP icons
    local overlay = CreateFrame("Frame", "FCUI_PlayerFrameOverlay", PlayerFrame)
    overlay:SetAllPoints(PlayerFrame)
    overlay:SetFrameLevel(PlayerFrame.PlayerFrameContent:GetFrameLevel() + 2)
    Skin.playerOverlay = overlay

    -- PlayerRestIcon: UI-StateIcon left half, 31x33 at 37,-49
    local rest = overlay:CreateTexture(nil, "OVERLAY")
    local state = file("stateIcon")
    if state then
        rest:SetTexture(state)
        rest:SetTexCoord(0, 0.5, 0, 0.421875)
    end
    rest:SetSize(31, 33)
    rest:SetPoint("TOPLEFT", PlayerFrame, "TOPLEFT", 37, -49)
    rest:Hide()
    Skin.playerRestIcon = rest

    -- PlayerPVPIcon 64x64 at 18,-20
    local pvp = overlay:CreateTexture(nil, "ARTWORK")
    pvp:SetSize(64, 64)
    pvp:SetPoint("TOPLEFT", PlayerFrame, "TOPLEFT", 18, -20)
    pvp:Hide()
    Skin.playerPvpIcon = pvp
end

local function playerStatus()
    if Skin.playerRestIcon then
        Skin.playerRestIcon:SetShown(IsResting())
    end
    local contextual = PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual
    hide(contextual.PlayerPortraitCornerIcon)
end

local function pvpTexture(unit)
    if UnitIsPVPFreeForAll(unit) then
        return file("pvpFFA")
    end
    local faction = UnitFactionGroup(unit)
    if faction == "Alliance" and UnitIsPVP(unit) then
        return file("pvpAlliance")
    elseif faction == "Horde" and UnitIsPVP(unit) then
        return file("pvpHorde")
    end
    return nil
end

local function playerPvp()
    local main = PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
    hide(main.PvpBackgroundCircle)
    hide(main.PvpBackgroundIcon)
    local icon = Skin.playerPvpIcon
    if not icon then
        return
    end
    local tex = pvpTexture("player")
    if tex then
        icon:SetTexture(tex)
        icon:Show()
    else
        icon:Hide()
    end
end

local function playerLevel()
    PlayerLevelText:SetVertexColor(1.0, 0.82, 0.0)
end

local function playerNameAnchor()
    PlayerName:ClearAllPoints()
    PlayerName:SetPoint("CENTER", PlayerFrame, "CENTER", 50, 19)
end

---------------------------------------------------------------------------
-- TargetFrame (TargetFrame.xml 1.12, mirrored player layout)
---------------------------------------------------------------------------
local function classificationTexture(unit)
    local classification = UnitClassification(unit)
    if classification == "worldboss" or classification == "rareelite" or classification == "elite" then
        return file("elite") or file("frame")
    elseif classification == "rare" then
        return file("rare") or file("frame")
    end
    return file("frame")
end

local function targetArt(frame)
    local container = frame.TargetFrameContainer
    local main = frame.TargetFrameContent.TargetFrameContentMain
    local contextual = frame.TargetFrameContent.TargetFrameContentContextual

    local art = classificationTexture(frame.unit or "target")
    if art then
        container.FrameTexture:SetTexture(art)
        container.FrameTexture:SetTexCoord(0.09375, 1.0, 0, 0.78125)
        container.FrameTexture:ClearAllPoints()
        container.FrameTexture:SetAllPoints(frame)
        container.FrameTexture:SetAlpha(1)
        container.FrameTexture:Show()
    end
    hide(container.BossPortraitFrameTexture)
    hide(container.Flash)

    unmask(container.Portrait, container.PortraitMask)
    container.Portrait:ClearAllPoints()
    container.Portrait:SetSize(64, 64)
    container.Portrait:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -42, -12)

    -- Name background: UI-TargetingFrame-LevelBackground 119x19 at TOPRIGHT -106,-22, coloured by Blizzard
    local levelBackground = file("levelBackground")
    if levelBackground then
        main.ReputationColor:SetTexture(levelBackground)
        main.ReputationColor:ClearAllPoints()
        main.ReputationColor:SetSize(119, 19)
        main.ReputationColor:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -106, -22)
    end

    main.Name:ClearAllPoints()
    main.Name:SetSize(100, 10)
    main.Name:SetJustifyH("CENTER")
    main.Name:SetPoint("CENTER", frame, "CENTER", -50, 19)

    hide(main.LevelBackgroundCircle)
    main.LevelText:SetFontObject(GameFontNormalSmall)
    main.LevelText:ClearAllPoints()
    main.LevelText:SetPoint("CENTER", frame, "CENTER", 63, -16)

    local skull = file("skull")
    if skull then
        contextual.HighLevelTexture:SetTexture(skull)
        contextual.HighLevelTexture:ClearAllPoints()
        contextual.HighLevelTexture:SetSize(16, 16)
        contextual.HighLevelTexture:SetPoint("CENTER", frame, "CENTER", 63, -16)
    end

    local leader = file("leader")
    if leader then
        contextual.LeaderIcon:SetTexture(leader)
        contextual.LeaderIcon:ClearAllPoints()
        contextual.LeaderIcon:SetSize(16, 16)
        contextual.LeaderIcon:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -44, -10)
    end
    hide(contextual.GuideIcon)
    hide(contextual.BossIcon)
    hide(contextual.QuestIcon)
    hide(contextual.PetBattleIcon)
    hide(contextual.PvpBackgroundCircle)
    hide(contextual.PvpBackgroundIcon)
    if contextual.NumericalThreat then
        ns.Suppress(contextual.NumericalThreat)
    end

    -- Raid target icon 26x26, CENTER at TOPRIGHT -73,-14
    contextual.RaidTargetIcon:ClearAllPoints()
    contextual.RaidTargetIcon:SetSize(26, 26)
    contextual.RaidTargetIcon:SetPoint("CENTER", frame, "TOPRIGHT", -73, -14)

    local healthContainer = main.HealthBarsContainer
    local healthBar = healthContainer.HealthBar
    local manaBar = main.ManaBar
    styleBar(healthBar, healthContainer.HealthBarMask, 0, 1, 0)
    stylePowerBar(manaBar, frame.unit or "target", manaBar.ManaBarMask)
    hide(healthContainer.LeftText)
    hide(healthContainer.RightText)
    hide(manaBar.LeftText)
    hide(manaBar.RightText)
    if healthContainer.TempMaxHealthLoss then
        ns.Suppress(healthContainer.TempMaxHealthLoss)
    end
    for _, key in ipairs({ "MyHealPredictionBar", "OtherHealPredictionBar", "HealAbsorbBar", "TotalAbsorbBar" }) do
        if healthBar[key] then
            ns.Suppress(healthBar[key])
        end
    end
    hide(healthBar.OverAbsorbGlow)
    hide(healthBar.OverHealAbsorbGlow)
    if healthContainer.DeadText then
        healthContainer.DeadText:ClearAllPoints()
        healthContainer.DeadText:SetPoint("CENTER", frame, "CENTER", -50, 3)
    end

    geometry(frame:GetName(), function()
        Raw.ClearAllPoints(healthContainer)
        Raw.SetSize(healthContainer, 119, 12)
        Raw.SetPoint(healthContainer, "TOPRIGHT", frame, "TOPRIGHT", -106, -41)
        Raw.ClearAllPoints(healthBar)
        Raw.SetSize(healthBar, 119, 12)
        Raw.SetPoint(healthBar, "TOPLEFT", healthContainer, "TOPLEFT", 0, 0)
        Raw.ClearAllPoints(manaBar)
        Raw.SetSize(manaBar, 119, 12)
        Raw.SetPoint(manaBar, "TOPRIGHT", frame, "TOPRIGHT", -106, -52)
    end)
end

local function targetBackground(frame)
    if Skin.targetBackground and Skin.targetBackground[frame] then
        return
    end
    Skin.targetBackground = Skin.targetBackground or {}
    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetColorTexture(0, 0, 0, 0.5)
    bg:SetSize(119, 41)
    bg:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -106, -22)
    Skin.targetBackground[frame] = bg

    local overlay = CreateFrame("Frame", nil, frame)
    overlay:SetAllPoints(frame)
    overlay:SetFrameLevel(frame.TargetFrameContent:GetFrameLevel() + 2)
    -- TargetPVPIcon 64x64 at TOPRIGHT 3,-20
    local pvp = overlay:CreateTexture(nil, "ARTWORK")
    pvp:SetSize(64, 64)
    pvp:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 3, -20)
    pvp:Hide()
    Skin.targetPvpIcon = Skin.targetPvpIcon or {}
    Skin.targetPvpIcon[frame] = pvp
end

local function targetPvp(frame)
    local contextual = frame.TargetFrameContent.TargetFrameContentContextual
    hide(contextual.PvpBackgroundCircle)
    hide(contextual.PvpBackgroundIcon)
    local icon = Skin.targetPvpIcon and Skin.targetPvpIcon[frame]
    if not icon then
        return
    end
    local tex = frame.unit and UnitExists(frame.unit) and pvpTexture(frame.unit) or nil
    if tex then
        icon:SetTexture(tex)
        icon:Show()
    else
        icon:Hide()
    end
end

---------------------------------------------------------------------------
-- Target of target (TargetFrame.xml 1.12: 93x45 at BOTTOMRIGHT -35,-10,
-- portrait 35 at 6,-6, bars 46x7 at TOPRIGHT -2,-15 / -2,-23, name BOTTOMLEFT 42,2)
---------------------------------------------------------------------------
local function totArt(frame)
    local art = file("tot")
    if art then
        frame.FrameTexture:SetTexture(art)
        frame.FrameTexture:SetTexCoord(0.015625, 0.7265625, 0, 0.703125)
        frame.FrameTexture:ClearAllPoints()
        frame.FrameTexture:SetAllPoints(frame)
    end
    unmask(frame.Portrait, frame.PortraitMask)
    frame.Portrait:ClearAllPoints()
    frame.Portrait:SetSize(35, 35)
    frame.Portrait:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -6)

    frame.Name:ClearAllPoints()
    frame.Name:SetSize(100, 10)
    frame.Name:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 42, 2)

    styleBar(frame.HealthBar, frame.HealthBar.HealthBarMask, 0, 1, 0)
    stylePowerBar(frame.ManaBar, frame.unit or "targettarget", frame.ManaBar.ManaBarMask)
    if frame.HealthBar.DeadText then
        frame.HealthBar.DeadText:ClearAllPoints()
        frame.HealthBar.DeadText:SetPoint("CENTER", frame, "CENTER", 15, 1)
    end

    geometry(frame:GetName(), function()
        Raw.SetSize(frame, 93, 45)
        Raw.ClearAllPoints(frame)
        Raw.SetPoint(frame, "BOTTOMRIGHT", frame:GetParent(), "BOTTOMRIGHT", -35, -10)
        Raw.ClearAllPoints(frame.HealthBar)
        Raw.SetSize(frame.HealthBar, 46, 7)
        Raw.SetPoint(frame.HealthBar, "TOPRIGHT", frame, "TOPRIGHT", -2, -15)
        Raw.ClearAllPoints(frame.ManaBar)
        Raw.SetSize(frame.ManaBar, 46, 7)
        Raw.SetPoint(frame.ManaBar, "TOPRIGHT", frame, "TOPRIGHT", -2, -23)
    end)
end

---------------------------------------------------------------------------
-- PetFrame (PetFrame.xml 1.12: 128x53 at PlayerFrame TOPLEFT 80,-60)
---------------------------------------------------------------------------
local function petArt()
    local frame = PetFrame
    local art = file("small")
    if art then
        PetFrameTexture:SetTexture(art)
        PetFrameTexture:SetTexCoord(0, 1, 0, 1)
        PetFrameTexture:ClearAllPoints()
        PetFrameTexture:SetSize(128, 64)
        PetFrameTexture:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -2)
    end
    hide(PetFrameFlash)
    unmask(frame.Portrait, frame.PortraitMask)
    frame.Portrait:ClearAllPoints()
    frame.Portrait:SetSize(37, 37)
    frame.Portrait:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, -6)

    PetName:ClearAllPoints()
    PetName:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 50, 33)

    local attack = file("petAttack")
    if attack and PetAttackModeTexture then
        PetAttackModeTexture:SetTexture(attack)
        PetAttackModeTexture:SetTexCoord(0.703125, 1.0, 0, 1.0)
        PetAttackModeTexture:ClearAllPoints()
        PetAttackModeTexture:SetSize(76, 64)
        PetAttackModeTexture:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -9)
    end

    styleBar(PetFrameHealthBar, PetFrameHealthBarMask, 0, 1, 0)
    stylePowerBar(PetFrameManaBar, "pet", PetFrameManaBarMask)
    hide(PetFrameHealthBarTextLeft)
    hide(PetFrameHealthBarTextRight)
    hide(PetFrameManaBarTextLeft)
    hide(PetFrameManaBarTextRight)
    for _, name in ipairs({
        "PetFrameMyHealPredictionBar",
        "PetFrameOtherHealPredictionBar",
        "PetFrameHealAbsorbBar",
        "PetFrameTotalAbsorbBar",
    }) do
        if _G[name] then
            ns.Suppress(_G[name])
        end
    end
    hide(PetFrameOverAbsorbGlow)
    hide(PetFrameOverHealAbsorbGlow)

    geometry("pet", function()
        Raw.SetSize(frame, 128, 53)
        Raw.SetHitRectInsets(frame, 7, 66, 6, 7)
        Raw.ClearAllPoints(PetFrameHealthBar)
        Raw.SetSize(PetFrameHealthBar, 70, 8)
        Raw.SetPoint(PetFrameHealthBar, "TOPLEFT", frame, "TOPLEFT", 47, -22)
        Raw.ClearAllPoints(PetFrameManaBar)
        Raw.SetSize(PetFrameManaBar, 70, 8)
        Raw.SetPoint(PetFrameManaBar, "TOPLEFT", frame, "TOPLEFT", 47, -29)
    end)
end

---------------------------------------------------------------------------
-- Power bar recolour after Blizzard swaps atlases on power type changes
---------------------------------------------------------------------------
local function onManaBarTypeUpdate(manaBar)
    local frame = manaBar and manaBar.unitFrame
    if not frame then
        return
    end
    if frame == PlayerFrame or frame == TargetFrame or frame == PetFrame or frame == TargetFrameToT then
        stylePowerBar(manaBar, manaBar.unit, manaBar.ManaBarMask)
    end
end

---------------------------------------------------------------------------
-- Enable
---------------------------------------------------------------------------
local hooked = {}
local function hookOnce(target, name, fn)
    local key = tostring(target) .. ":" .. name
    if hooked[key] then
        return
    end
    hooked[key] = true
    if type(target) == "string" then
        hooksecurefunc(target, fn)
    elseif type(target[name]) == "function" then
        hooksecurefunc(target, name, fn)
    end
end

function Skin.Enable()
    if PlayerFrame and PlayerFrame.PlayerFrameContainer then
        playerBackground()
        playerArt()
        playerStatus()
        playerPvp()
        -- Blizzard re-applies its atlases and anchors in these
        hookOnce("PlayerFrame_ToPlayerArt", "PlayerFrame_ToPlayerArt", function()
            playerArt()
            playerStatus()
            playerPvp()
        end)
        hookOnce("PlayerFrame_UpdatePlayerNameTextAnchor", "PlayerFrame_UpdatePlayerNameTextAnchor", playerNameAnchor)
        hookOnce("PlayerFrame_UpdateLevel", "PlayerFrame_UpdateLevel", playerLevel)
        hookOnce("PlayerFrame_UpdateStatus", "PlayerFrame_UpdateStatus", playerStatus)
        hookOnce("PlayerFrame_UpdatePvPStatus", "PlayerFrame_UpdatePvPStatus", playerPvp)
    end

    if TargetFrame and TargetFrame.TargetFrameContainer then
        targetBackground(TargetFrame)
        targetArt(TargetFrame)
        targetPvp(TargetFrame)
        hookOnce(TargetFrame, "CheckClassification", function(self)
            targetArt(self)
        end)
        hookOnce(TargetFrame, "CheckFaction", function(self)
            targetPvp(self)
        end)
        hookOnce(TargetFrame, "ShowPvPIcon", function(self)
            targetPvp(self)
        end)
        hookOnce(TargetFrame, "HidePvPFrames", function(self)
            targetPvp(self)
        end)
        if TargetFrameToT and TargetFrameToT.FrameTexture then
            totArt(TargetFrameToT)
        end
    end

    if PetFrame and PetFrameTexture then
        petArt()
    end

    hookOnce("UnitFrameManaBar_UpdateType", "UnitFrameManaBar_UpdateType", onManaBarTypeUpdate)
end

function Skin.Refresh()
    if Skin.playerBackground then
        playerStatus()
        playerPvp()
    end
    if TargetFrame and Skin.targetPvpIcon then
        targetPvp(TargetFrame)
    end
end
