local _, ns = ...

-- Party member frames (PartyFrameTemplates.xml 1.12: 128x53, UI-PartyFrame
-- 128x64 at 0,-2, portrait 37 at 7,-6, name BOTTOMLEFT 50,43, health 70x8 at
-- 47,-12, mana 70x8 at 47,-21; pet 64x26 with UI-PartyFrame 64x32).
-- Forever keeps the four member frames in PartyFrame.PartyMemberFramePool.
local Raw = ns.Raw
local Combat = ns.Combat
local UF = ns.UnitFrames

local Party = {}
UF.Party = Party

local T = "Interface\\TargetingFrame\\"
local FILES = {
    party = T .. "UI-PartyFrame",
    statusBar = T .. "UI-StatusBar",
    leader = "Interface\\GroupFrame\\UI-Group-LeaderIcon",
    pvpAlliance = T .. "UI-PVP-Alliance",
    pvpHorde = T .. "UI-PVP-Horde",
    pvpFFA = T .. "UI-PVP-FFA",
}
local present = {}
local function file(key)
    if present[key] == nil then
        local exists = ns.Compat.TextureExists(FILES[key])
        present[key] = exists ~= false
    end
    return present[key] and FILES[key] or nil
end

local POWER_COLORS = {
    MANA = { 0, 0, 1 },
    RAGE = { 1, 0, 0 },
    FOCUS = { 1, 0.5, 0.25 },
    ENERGY = { 1, 1, 0 },
    HAPPINESS = { 0, 1, 1 },
}

local hooked = setmetatable({}, { __mode = "k" })

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
    bar:SetStatusBarColor(r, g, b)
    local statusTexture = bar:GetStatusBarTexture()
    if statusTexture then
        unmask(statusTexture, mask)
        statusTexture:SetDesaturated(false)
        statusTexture:SetAlpha(1)
    end
    hide(bar.Spark)
end

local function powerColor(unit)
    local ok, _, token = pcall(UnitPowerType, unit)
    local color = ok and POWER_COLORS[token] or POWER_COLORS.MANA
    return color[1], color[2], color[3]
end

local function memberUnit(frame)
    if frame.GetUnit then
        local ok, unit = pcall(frame.GetUnit, frame)
        if ok and unit then
            return unit
        end
    end
    return frame.unit or "party1"
end

---------------------------------------------------------------------------
-- Member frame
---------------------------------------------------------------------------
local function nameAnchor(frame)
    frame.Name:ClearAllPoints()
    frame.Name:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 50, 43)
end

local function pvp(frame)
    local icon = frame.PartyMemberOverlay and frame.PartyMemberOverlay.PVPIcon
    if not icon then
        return
    end
    local unit = memberUnit(frame)
    local tex
    if UnitIsPVPFreeForAll(unit) then
        tex = file("pvpFFA")
    else
        local faction = UnitFactionGroup(unit)
        if faction == "Alliance" and UnitIsPVP(unit) then
            tex = file("pvpAlliance")
        elseif faction == "Horde" and UnitIsPVP(unit) then
            tex = file("pvpHorde")
        end
    end
    if tex then
        icon:SetTexture(tex)
        icon:SetTexCoord(0, 1, 0, 1)
        icon:SetScale(1)
        icon:ClearAllPoints()
        icon:SetSize(32, 32)
        icon:SetPoint("TOPLEFT", frame, "TOPLEFT", -9, -15)
        icon:Show()
    else
        icon:Hide()
    end
end

local function memberArt(frame)
    local art = file("party")
    if art then
        frame.Texture:SetTexture(art)
        frame.Texture:SetTexCoord(0, 1, 0, 1)
        frame.Texture:ClearAllPoints()
        frame.Texture:SetSize(128, 64)
        frame.Texture:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -2)
        frame.Texture:Show()
    end
    hide(frame.VehicleTexture)
    hide(frame.Flash)

    unmask(frame.Portrait, frame.PortraitMask)
    frame.Portrait:ClearAllPoints()
    frame.Portrait:SetSize(37, 37)
    frame.Portrait:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, -6)

    frame.Name:SetWidth(100)
    nameAnchor(frame)

    local overlay = frame.PartyMemberOverlay
    if overlay then
        hide(overlay.Status)
        hide(overlay.GuideIcon)
        hide(overlay.RoleIcon)
        local leader = file("leader")
        if leader and overlay.LeaderIcon then
            overlay.LeaderIcon:SetTexture(leader)
            overlay.LeaderIcon:ClearAllPoints()
            overlay.LeaderIcon:SetSize(16, 16)
            overlay.LeaderIcon:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        end
        if overlay.Disconnect then
            overlay.Disconnect:ClearAllPoints()
            overlay.Disconnect:SetSize(64, 64)
            overlay.Disconnect:SetPoint("LEFT", frame, "LEFT", -7, -1)
        end
    end

    local healthContainer = frame.HealthBarContainer
    local healthBar = healthContainer and healthContainer.HealthBar
    local manaBar = frame.ManaBar
    if healthBar then
        styleBar(healthBar, healthContainer.HealthBarMask, 0, 1, 0)
        hide(healthContainer.LeftText)
        hide(healthContainer.RightText)
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
    end
    if manaBar then
        styleBar(manaBar, manaBar.ManaBarMask, powerColor(memberUnit(frame)))
        hide(manaBar.LeftText)
        hide(manaBar.RightText)
    end

    -- Pet frame: UI-PartyFrame at half size, portrait 18 at 3,-3, health 35x4 at 23,-6
    local pet = frame.PetFrame
    if pet then
        if art and pet.Texture then
            pet.Texture:SetTexture(art)
            pet.Texture:SetTexCoord(0, 1, 0, 1)
            pet.Texture:SetScale(1)
            pet.Texture:ClearAllPoints()
            pet.Texture:SetSize(64, 32)
            pet.Texture:SetPoint("TOPLEFT", pet, "TOPLEFT", 0, -1)
        end
        hide(pet.Flash)
        unmask(pet.Portrait, pet.PortraitMask)
        pet.Portrait:ClearAllPoints()
        pet.Portrait:SetSize(18, 18)
        pet.Portrait:SetPoint("TOPLEFT", pet, "TOPLEFT", 3, -3)
        if pet.HealthBar then
            styleBar(pet.HealthBar, nil, 0, 1, 0)
        end
    end

    Combat.Run("uf:party:" .. tostring(frame:GetName() or frame), function()
        Raw.SetSize(frame, 128, 53)
        if healthContainer then
            Raw.ClearAllPoints(healthContainer)
            Raw.SetSize(healthContainer, 70, 8)
            Raw.SetPoint(healthContainer, "TOPLEFT", frame, "TOPLEFT", 47, -12)
        end
        if healthBar then
            Raw.ClearAllPoints(healthBar)
            Raw.SetSize(healthBar, 70, 8)
            Raw.SetPoint(healthBar, "TOPLEFT", healthContainer, "TOPLEFT", 0, 0)
        end
        if manaBar then
            Raw.ClearAllPoints(manaBar)
            Raw.SetSize(manaBar, 70, 8)
            Raw.SetPoint(manaBar, "TOPLEFT", frame, "TOPLEFT", 47, -21)
        end
        if pet then
            Raw.SetSize(pet, 64, 26)
            if pet.HealthBar then
                Raw.SetScale(pet.HealthBar, 1)
                Raw.ClearAllPoints(pet.HealthBar)
                Raw.SetSize(pet.HealthBar, 35, 4)
                Raw.SetPoint(pet.HealthBar, "TOPLEFT", pet, "TOPLEFT", 23, -6)
            end
        end
    end)
end

local function setupMember(frame)
    memberArt(frame)
    pvp(frame)
    if hooked[frame] then
        return
    end
    hooked[frame] = true
    -- Blizzard re-applies atlases and anchors in these
    if type(frame.ToPlayerArt) == "function" then
        hooksecurefunc(frame, "ToPlayerArt", memberArt)
    end
    if type(frame.UpdateNameTextAnchors) == "function" then
        hooksecurefunc(frame, "UpdateNameTextAnchors", nameAnchor)
    end
    if type(frame.UpdatePvPStatus) == "function" then
        hooksecurefunc(frame, "UpdatePvPStatus", pvp)
    end
end

function Party.SetupAll()
    if not PartyFrame or not PartyFrame.PartyMemberFramePool then
        return
    end
    for frame in PartyFrame.PartyMemberFramePool:EnumerateActive() do
        setupMember(frame)
    end
end

function Party.Enable()
    if not PartyFrame then
        ns.Log("UnitFrames", "PartyFrame missing, party frames left untouched")
        return
    end
    Party.SetupAll()
    if type(PartyFrame.InitializePartyMemberFrames) == "function" then
        hooksecurefunc(PartyFrame, "InitializePartyMemberFrames", Party.SetupAll)
    end
end
