local _, ns = ...

-- Bag bar (MainMenuBarBagButtons.xml 1.12): backpack 37x37 at BOTTOMRIGHT
-- -6,2 of the art frame, bags to its left with 5 px gaps, keyring 18x39
-- left of the last bag. Blizzard's BagsBar keeps ownership of the buttons;
-- we re-anchor and retexture after each of its Layout / UpdateTextures.
local Raw = ns.Raw
local Assets = ns.Assets
local AB = ns.ActionBars

local BagBar = {}
AB.BagBar = BagBar

local BAG_NAMES = {
    "CharacterBag0Slot",
    "CharacterBag1Slot",
    "CharacterBag2Slot",
    "CharacterBag3Slot",
    "CharacterReagentBag0Slot", -- not Vanilla; only positioned if Blizzard shows it
}

local hooked = setmetatable({}, { __mode = "k" })

local function hideDividers(bar)
    if bar.BorderArt then
        bar.BorderArt:Hide()
    end
    for _, key in ipairs({ "HorizontalDividersPool", "VerticalDividersPool" }) do
        local pool = bar[key]
        if pool then
            for divider in pool:EnumerateActive() do
                Raw.Hide(divider)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Textures (ItemButtonTemplate.xml 1.12)
---------------------------------------------------------------------------
local function applyBagTextures(button)
    local normal = Assets.Get("Button.Normal")
    if normal then
        button:SetNormalTexture(normal)
        local tex = button:GetNormalTexture()
        tex:ClearAllPoints()
        tex:SetPoint("CENTER", button, "CENTER", 0, -1) -- NormalTexture 64x64 CENTER 0,-1
        tex:SetSize(64, 64)
    end
    local pushed = Assets.Get("Button.Pushed")
    if pushed then
        button:SetPushedTexture(pushed)
        local tex = button:GetPushedTexture()
        tex:ClearAllPoints()
        tex:SetAllPoints(button)
    end
    local highlight = Assets.Get("Button.Highlight")
    if highlight then
        button:SetHighlightTexture(highlight, "ADD")
        local tex = button:GetHighlightTexture()
        tex:ClearAllPoints()
        tex:SetAllPoints(button)
        tex:SetAlpha(1)
    end
    -- Open-bag highlight: CheckButtonHilight ADD (BagSlotButtonTemplate CheckedTexture)
    local checked = Assets.Get("Button.Checked")
    if checked and button.SlotHighlightTexture then
        button.SlotHighlightTexture:SetTexture(checked)
        button.SlotHighlightTexture:SetBlendMode("ADD")
        button.SlotHighlightTexture:ClearAllPoints()
        button.SlotHighlightTexture:SetAllPoints(button)
    end
    if button.icon then
        button.icon:ClearAllPoints()
        button.icon:SetAllPoints(button)
        if button.SquareMask and button.icon.RemoveMaskTexture then
            pcall(button.icon.RemoveMaskTexture, button.icon, button.SquareMask)
        end
        if button == MainMenuBarBackpackButton then
            -- MainMenuBarBackpackButton OnLoad: Button-Backpack-Up
            local backpack = Assets.Get("Bags.Backpack")
            if backpack then
                button.icon:SetTexture(backpack)
            end
        end
    end
end

local function applyKeyringTextures(button)
    -- KeyRingButton: 18x39, UI-Button-KeyRing sheet with TexCoords 0-0.5625 / 0-0.609375
    local normal = Assets.Get("Bags.KeyRing")
    local highlight = Assets.Get("Bags.KeyRingHighlight")
    local pushed = Assets.Get("Bags.KeyRingDown")
    if normal then
        button:SetNormalTexture(normal)
        local tex = button:GetNormalTexture()
        tex:ClearAllPoints()
        tex:SetAllPoints(button)
        tex:SetTexCoord(0, 0.5625, 0, 0.609375)
        tex:SetRotation(0)
    end
    if highlight then
        button:SetHighlightTexture(highlight, "ADD")
        local tex = button:GetHighlightTexture()
        tex:ClearAllPoints()
        tex:SetAllPoints(button)
        tex:SetTexCoord(0, 0.5625, 0, 0.609375)
        tex:SetAlpha(1)
        tex:SetRotation(0)
    end
    if pushed then
        button:SetPushedTexture(pushed)
        local tex = button:GetPushedTexture()
        tex:ClearAllPoints()
        tex:SetAllPoints(button)
        tex:SetTexCoord(0, 0.5625, 0, 0.609375)
        tex:SetRotation(0)
    end
    if button.icon and normal then
        button.icon:SetAlpha(0) -- the sheet already draws the key
    end
    Raw.SetSize(button, 18, 39)
end

local function setupButton(button, isKeyring)
    if not button or hooked[button] then
        return
    end
    hooked[button] = true
    if isKeyring then
        applyKeyringTextures(button)
        AB.Hook(button, "UpdateTextures", applyKeyringTextures)
        AB.Hook(button, "UpdateOrientation", applyKeyringTextures)
    else
        Raw.SetSize(button, 37, 37)
        applyBagTextures(button)
        AB.Hook(button, "UpdateTextures", applyBagTextures)
    end
    AB.HookScript(button, "OnShow", BagBar.Position)
    AB.HookScript(button, "OnHide", BagBar.Position)
end

---------------------------------------------------------------------------
-- Positioning
---------------------------------------------------------------------------
local function updateKeyringArt(keyringShown)
    local art = AB.frame
    local textures = art and art.Textures
    if not textures then
        return
    end
    local keyringSheet = Assets.Get("MainBar.KeyRing")
    local dwarf = Assets.Get("MainBar.Art")
    if keyringShown and keyringSheet then
        -- MainMenuBar_UpdateKeyRing (1.12): right two bar segments swap to the keyring sheet
        textures[4]:SetTexture(keyringSheet)
        textures[4]:SetTexCoord(0, 1, 0.1640625, 0.5)
        textures[3]:SetTexture(keyringSheet)
        textures[3]:SetTexCoord(0, 1, 0.6640625, 1)
        if art.LatencyBar then
            art.LatencyBar:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", -235, -10)
        end
    elseif dwarf then
        textures[4]:SetTexture(dwarf)
        textures[4]:SetTexCoord(0, 1, 0.08203125, 0.25)
        textures[3]:SetTexture(dwarf)
        textures[3]:SetTexCoord(0, 1, 0.33203125, 0.5)
        if art.LatencyBar then
            art.LatencyBar:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", -227, -10)
        end
    end
end

function BagBar.Position()
    local art = AB.frame
    if not BagsBar or not MainMenuBarBackpackButton or not art then
        return
    end
    Raw.SetScale(BagsBar, ns.db.scale or 1)
    hideDividers(BagsBar)

    -- MainMenuBarBackpackButton: BOTTOMRIGHT of MainMenuBarArtFrame -6,2
    if AB.CanAnchor(MainMenuBarBackpackButton) then
        Raw.ClearAllPoints(MainMenuBarBackpackButton)
        Raw.SetPoint(MainMenuBarBackpackButton, "BOTTOMRIGHT", art, "BOTTOMRIGHT", -6, 2)
    end

    -- CharacterBag0..3Slot: RIGHT to previous LEFT -5,0
    local previous = MainMenuBarBackpackButton
    for _, name in ipairs(BAG_NAMES) do
        local button = _G[name]
        if button and Raw.IsShown(button) then
            if AB.CanAnchor(button) then
                Raw.ClearAllPoints(button)
                Raw.SetPoint(button, "RIGHT", previous, "LEFT", -5, 0)
            end
            previous = button
        end
    end

    -- KeyRingButton: RIGHT to CharacterBag3Slot LEFT -5,0
    local keyringShown = false
    if KeyRingButton and Raw.IsShown(KeyRingButton) then
        keyringShown = true
        if AB.CanAnchor(KeyRingButton) then
            Raw.ClearAllPoints(KeyRingButton)
            Raw.SetPoint(KeyRingButton, "RIGHT", previous, "LEFT", -5, 0)
        end
    end
    updateKeyringArt(keyringShown)
end

function BagBar.Enable()
    if not BagsBar or not MainMenuBarBackpackButton then
        ns.Log("ActionBars", "BagsBar missing, bag buttons left untouched")
        return
    end
    setupButton(MainMenuBarBackpackButton, false)
    for _, name in ipairs(BAG_NAMES) do
        setupButton(_G[name], false)
    end
    setupButton(KeyRingButton, true)

    AB.Hook(BagsBar, "Layout", BagBar.Position)
    AB.Hook(BagsBar, "UpdateDividers", BagBar.Position)
    AB.Hook(BagsBar, "ApplySystemAnchor", BagBar.Position)
    BagBar.Position()
end
