local _, ns = ...

-- Micro menu (MainMenuBarMicroButtons.xml / .lua 1.12): eight 29x58 buttons
-- starting at BOTTOMLEFT 552,2 of the art frame, each overlapping the
-- previous by 3 px, Vanilla textures, portrait on the character button.
--
-- Forever has no Socials or World Map micro button, so those two are ours.
-- Buttons for systems Vanilla did not have (professions book, legacy,
-- housing, guild/communities, group finder, collections, adventure guide,
-- shop) stay visible: they get the classic 29x58 footprint and spacing with
-- their modern icons, in a second group to the right of the right gryphon,
-- because the Vanilla bar has no free pixels between the micro menu and the
-- bag buttons.
local Raw = ns.Raw
local Assets = ns.Assets
local AB = ns.ActionBars

local MicroMenu = {}
AB.MicroMenu = MicroMenu

local CLASSIC = {
    { frame = "CharacterMicroButton", character = true },
    -- our own button when the SpellBook module runs, Blizzard's otherwise
    { own = "Spellbook", frame = "SpellbookMicroButton", asset = "Micro.Spellbook" },
    { frame = "TalentMicroButton", asset = "Micro.Talents" },
    { frame = "QuestLogMicroButton", asset = "Micro.Quest" },
    { own = "Socials", asset = "Micro.Socials" },
    { own = "WorldMap", asset = "Micro.World" },
    { frame = "MainMenuMicroButton", asset = "Micro.MainMenu" },
    { frame = "HelpMicroButton", asset = "Micro.Help" },
}

local MODERN = {
    { frame = "ProfessionMicroButton", modern = true },
    { frame = "GuildMicroButton", modern = true },
    { frame = "LFDMicroButton", modern = true },
    { frame = "LegacyMicroButton", modern = true },
    { frame = "CollectionsMicroButton", modern = true },
    { frame = "EJMicroButton", modern = true },
    { frame = "HousingMicroButton", modern = true },
    { frame = "StoreMicroButton", modern = true },
}

-- MainMenuBar.xml: right gryphon spans 544-64 .. 544+64 from the bar centre,
-- i.e. it ends 96 px past the bar's right edge. The modern group starts just
-- beyond its tail, bottom-aligned with the classic buttons.
local MODERN_GROUP_OFFSET_X = 100

local reskinned = setmetatable({}, { __mode = "k" }) -- button -> entry
MicroMenu.own = {}

---------------------------------------------------------------------------
-- Texture application
---------------------------------------------------------------------------
-- Modern buttons keep their atlases but are laid out on the classic footprint:
-- the 32x40 art is scaled to 29x36 and sits at the bottom of the 29x58 button.
local MODERN_W, MODERN_H = 29, 36
local modernRegionHooked = setmetatable({}, { __mode = "k" })
local applying = false
local applyTextures

local function fitModernRegion(button, tex)
    tex:ClearAllPoints()
    tex:SetPoint("BOTTOM", button, "BOTTOM", 0, 0)
    tex:SetSize(MODERN_W, MODERN_H)
    -- SetAtlas(atlas, true) on the region itself resizes it to the atlas; put it back
    if not modernRegionHooked[tex] then
        modernRegionHooked[tex] = true
        hooksecurefunc(tex, "SetAtlas", function()
            if not applying then
                applyTextures(button)
            end
        end)
    end
end

local function applyModernTextures(button)
    for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do
        local tex = button[getter] and button[getter](button)
        if tex then
            fitModernRegion(button, tex)
        end
    end
    for _, key in ipairs({ "Background", "PushedBackground", "FlashBorder", "FlashContent" }) do
        local tex = button[key]
        if tex then
            fitModernRegion(button, tex)
        end
    end
    -- any other texture the template or a later patch added that is larger than the footprint
    for _, region in ipairs({ button:GetRegions() }) do
        if region:GetObjectType() == "Texture" and (region:GetWidth() > MODERN_W or region:GetHeight() > MODERN_H) then
            fitModernRegion(button, region)
        end
    end
end

function applyTextures(button)
    local entry = reskinned[button]
    if not entry or applying then
        return
    end
    applying = true
    if entry.modern then
        applyModernTextures(button)
        applying = false
        return
    end
    local highlight = Assets.Get("Micro.Hilight")
    if entry.character then
        -- CharacterMicroButton_OnLoad: UI-MicroButtonCharacter-Up / -Down
        local up = Assets.Get("Micro.CharacterUp")
        local down = Assets.Get("Micro.CharacterDown")
        if up then
            button:SetNormalTexture(up)
            button:GetNormalTexture():SetAllPoints(button)
        end
        if down then
            button:SetPushedTexture(down)
            button:GetPushedTexture():SetAllPoints(button)
        end
    else
        local base = Assets.Get(entry.asset)
        if base then
            -- LoadMicroButtonTextures: <base>-Up / -Down / -Disabled
            button:SetNormalTexture(base .. "-Up")
            button:GetNormalTexture():SetAllPoints(button)
            button:SetPushedTexture(base .. "-Down")
            button:GetPushedTexture():SetAllPoints(button)
            button:SetDisabledTexture(base .. "-Disabled")
            button:GetDisabledTexture():SetAllPoints(button)
        end
    end
    if highlight then
        button:SetHighlightTexture(highlight, "BLEND")
        local tex = button:GetHighlightTexture()
        tex:SetAllPoints(button)
        tex:SetAlpha(1)
    end
    applying = false
end

local function applyPortrait(button, pushed)
    local portrait = button.Portrait
    if not portrait then
        return
    end
    -- MainMenuBarMicroButtons.xml MicroButtonPortrait: 18x25 at TOP 0,-28
    portrait:ClearAllPoints()
    portrait:SetSize(18, 25)
    portrait:SetPoint("TOP", button, "TOP", 0, -28)
    if pushed then
        -- CharacterMicroButton_SetPushed
        portrait:SetTexCoord(0.2666, 0.8666, 0, 0.8333)
        portrait:SetAlpha(0.5)
    else
        -- CharacterMicroButton_SetNormal
        portrait:SetTexCoord(0.2, 0.8, 0.0666, 0.9)
        portrait:SetAlpha(1)
    end
end

local function reskin(button, entry)
    if reskinned[button] then
        return
    end
    reskinned[button] = entry

    -- MainMenuBarMicroButton: 29x58, HitRectInsets top 18
    Raw.SetSize(button, 29, 58)
    Raw.SetHitRectInsets(button, 0, 0, 18, 0)

    -- Modern backdrop pieces; Blizzard toggles them in SetPushed/SetNormal so alpha 0 is the durable way
    if not entry.modern then
        for _, key in ipairs({ "Background", "PushedBackground", "Shadow", "PushedShadow" }) do
            if button[key] then
                button[key]:SetAlpha(0)
            end
        end
    end
    if button.PortraitMask and button.Portrait and button.Portrait.RemoveMaskTexture then
        pcall(button.Portrait.RemoveMaskTexture, button.Portrait, button.PortraitMask)
    end
    if entry.character then
        applyPortrait(button, false)
    end
    applyTextures(button)

    -- Blizzard re-applies atlases outside SetPushed/SetNormal too: MainMenuMicroButtonMixin:OnUpdate
    -- swaps the streaming-status texture kit every tick (SetNormalAtlas & co. at native atlas
    -- size), which is why the main menu, adventure guide and housing buttons kept growing back.
    for _, method in ipairs({ "SetNormalAtlas", "SetPushedAtlas", "SetDisabledAtlas", "SetHighlightAtlas" }) do
        AB.Hook(button, method, function(self)
            if not applying then
                applyTextures(self)
            end
        end)
    end

    -- SetPushed/SetNormal swap the highlight atlas and move the portrait
    AB.Hook(button, "SetPushed", function(self)
        applyTextures(self)
        if entry.character then
            applyPortrait(self, true)
        end
    end)
    AB.Hook(button, "SetNormal", function(self)
        applyTextures(self)
        if entry.character then
            applyPortrait(self, false)
        end
    end)
end

---------------------------------------------------------------------------
-- Our own Socials and World Map buttons
---------------------------------------------------------------------------
local function tooltipText(label, binding)
    if MicroButtonTooltipText then
        return MicroButtonTooltipText(label, binding)
    end
    return label
end

local function createOwnButton(key, label, binding, onClick, isPushed, template)
    local button = CreateFrame("Button", "FCUI_" .. key .. "MicroButton", AB.frame, template)
    button:SetSize(29, 58)
    button:SetHitRectInsets(0, 0, 18, 0)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    if onClick then
        button:SetScript("OnClick", onClick)
    end
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(tooltipText(label, binding), 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    button.UpdateState = function(self)
        if isPushed() then
            self:SetButtonState("PUSHED", true)
        else
            self:SetButtonState("NORMAL")
        end
    end
    MicroMenu.own[key] = button
    return button
end

local function createOwnButtons()
    if not MicroMenu.own.Spellbook and ns.db.modules.SpellBook and ns.SpellBook then
        -- secure click handler: the book can then be opened and closed in combat too
        local button = createOwnButton(
            "Spellbook",
            SPELLBOOK_ABILITIES_BUTTON or "Spellbook",
            "TOGGLESPELLBOOK",
            nil,
            function()
                return ns.SpellBook.IsShown()
            end,
            "SecureHandlerClickTemplate"
        )
        ns.SpellBook.SecureToggle(button)
        reskin(button, { asset = "Micro.Spellbook" })
        if not Assets.Get("Micro.Spellbook") then
            button:Hide()
        end
    end
    if not MicroMenu.own.Socials then
        local button = createOwnButton("Socials", SOCIAL_BUTTON or "Social", "TOGGLESOCIAL", function()
            if ToggleFriendsFrame then
                ToggleFriendsFrame()
            end
        end, function()
            return FriendsFrame and FriendsFrame:IsShown()
        end)
        reskin(button, { asset = "Micro.Socials" })
        if not Assets.Get("Micro.Socials") then
            button:Hide()
        end
    end
    if not MicroMenu.own.WorldMap then
        local button = createOwnButton("WorldMap", WORLDMAP_BUTTON or "World Map", "TOGGLEWORLDMAP", function()
            if ToggleWorldMap then
                ToggleWorldMap()
            end
        end, function()
            return WorldMapFrame and WorldMapFrame:IsShown()
        end)
        reskin(button, { asset = "Micro.World" })
        if not Assets.Get("Micro.World") then
            button:Hide()
        end
    end
end

local function updateOwnStates()
    for _, button in pairs(MicroMenu.own) do
        button:UpdateState()
    end
end
MicroMenu.UpdateOwnStates = updateOwnStates

---------------------------------------------------------------------------
-- Positioning (MainMenuBarMicroButtons.xml: first at BOTTOMLEFT 552,2 of the
-- art frame, each next BOTTOMLEFT to previous BOTTOMRIGHT -3,0)
---------------------------------------------------------------------------
function MicroMenu.Position()
    local art = AB.frame
    if MicroMenu.own.Socials == nil then
        return
    end
    local scale = ns.db.scale or 1
    if MicroMenu.blizzardMenu then
        Raw.SetScale(MicroMenu.blizzardMenu, scale)
    end
    local previous
    local locked = InCombatLockdown()
    for _, entry in ipairs(CLASSIC) do
        local button = entry.own and MicroMenu.own[entry.own] or _G[entry.frame]
        if button and Raw.IsShown(button) then
            -- our spellbook button is a secure handler: its anchors are left alone in combat
            if not (locked and button:IsProtected()) then
                Raw.ClearAllPoints(button)
                if previous then
                    Raw.SetPoint(button, "BOTTOMLEFT", previous, "BOTTOMRIGHT", -3, 0)
                else
                    Raw.SetPoint(button, "BOTTOMLEFT", art, "BOTTOMLEFT", 552, 2)
                end
            end
            previous = button
        end
    end

    -- Second group: Forever-only systems, right of the right gryphon
    previous = nil
    for _, entry in ipairs(MODERN) do
        local button = _G[entry.frame]
        if button and Raw.IsShown(button) then
            Raw.ClearAllPoints(button)
            if previous then
                Raw.SetPoint(button, "BOTTOMLEFT", previous, "BOTTOMRIGHT", -3, 0)
            else
                Raw.SetPoint(button, "BOTTOMLEFT", art, "BOTTOMRIGHT", MODERN_GROUP_OFFSET_X, 2)
            end
            previous = button
        end
    end
end

function MicroMenu.Enable()
    createOwnButtons()

    -- Camelot's MicroMenu (Blizzard_MicroMenu/Camelot/MainMenuBarMicroMenu.xml) carries
    -- its own frame and background art (UI-HUD-ActionBar-Frame / -IconFrame-Background)
    -- around the buttons; 1.12 had none, the buttons sat straight on the bar art.
    for _, key in ipairs({ "BorderArt", "BackgroundArt" }) do
        local art = _G.MicroMenu and _G.MicroMenu[key]
        if art then
            art:Hide()
            AB.Hook(art, "Show", function(self)
                self:Hide()
            end)
        end
    end

    for _, entry in ipairs(CLASSIC) do
        if entry.frame then
            local button = _G[entry.frame]
            if button and entry.own and MicroMenu.own[entry.own] then
                -- replaced by our own button (its click must not go through Blizzard's panel code)
                ns.Suppress(button)
            elseif button then
                reskin(button, entry)
                AB.HookScript(button, "OnShow", MicroMenu.Position)
                AB.HookScript(button, "OnHide", MicroMenu.Position)
            end
        end
    end

    -- HelpOpenWebTicketButton (Blizzard_HelpFrame): a 34x35 red "?" Blizzard anchors 25 px
    -- above the outer micro button; 1.12 had no such button, tickets live in the help panel.
    -- Blizzard_HelpFrame can load after us, so keep trying until the button exists.
    local function suppressTicketButton()
        if HelpOpenWebTicketButton then
            ns.Suppress(HelpOpenWebTicketButton)
            return true
        end
        return false
    end
    if not suppressTicketButton() then
        ns.RegisterEvent("ADDON_LOADED", MicroMenu, function(_, _, name)
            if name == "Blizzard_HelpFrame" then
                suppressTicketButton()
            end
        end)
        ns.RegisterEvent("PLAYER_ENTERING_WORLD", MicroMenu, suppressTicketButton)
    end

    for _, entry in ipairs(MODERN) do
        local button = _G[entry.frame]
        if button then
            reskin(button, entry)
            AB.HookScript(button, "OnShow", MicroMenu.Position)
            AB.HookScript(button, "OnHide", MicroMenu.Position)
        end
    end

    -- Blizzard's latency strip lives on the main menu button; ours is on the art frame
    if MainMenuMicroButton and MainMenuMicroButton.MainMenuBarPerformanceBar then
        MainMenuMicroButton.MainMenuBarPerformanceBar:SetAlpha(0)
    end

    -- LoadMicroButtonTextures re-applies atlases on state changes (e.g. talent alerts)
    if LoadMicroButtonTextures then
        hooksecurefunc("LoadMicroButtonTextures", function(button)
            if reskinned[button] then
                applyTextures(button)
            end
        end)
    end
    if UpdateMicroButtons then
        hooksecurefunc("UpdateMicroButtons", function()
            updateOwnStates()
            MicroMenu.Position()
        end)
    end

    -- MicroMenu (GridLayoutFrame) re-anchors its children on every Layout
    local menu = _G.MicroMenu
    if menu then
        MicroMenu.blizzardMenu = menu
        AB.Hook(menu, "Layout", MicroMenu.Position)
        AB.Hook(menu, "UpdateScale", MicroMenu.Position)
    end
    if MicroMenuContainer then
        AB.Hook(MicroMenuContainer, "ApplySystemAnchor", MicroMenu.Position)
    end

    updateOwnStates()
    MicroMenu.Position()
end
