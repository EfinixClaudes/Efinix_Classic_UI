local _, ns = ...

-- Micro menu (MainMenuBarMicroButtons.xml / .lua 1.12): eight 29x58 buttons
-- starting at BOTTOMLEFT 552,2 of the art frame, each overlapping the
-- previous by 3 px, Vanilla textures, portrait on the character button.
--
-- Forever has no Socials or World Map micro button, so those two are ours.
-- Buttons for systems Vanilla did not have (professions book, legacy,
-- housing, guild/communities, group finder, collections, adventure guide,
-- shop) are our own buttons: the 1.12 character button frame (the one
-- empty micro button frame Vanilla shipped: UI-MicroButtonCharacter-Up, with
-- the portrait window left dark) with a Vanilla-era icon in that window. A
-- click is forwarded to Blizzard's button, which is suppressed, so the
-- game's own toggle, kiosk and keybind-mode checks run and none of its art
-- (atlases at native size, alert pulses, notification overlays) can show.
-- By default they continue the micro menu row and the bar art grows to fit
-- (ActionBars.MICRO_EXTRA); with that option off they form a second group
-- to the right of the right gryphon, since the 1024 bar has no free pixels
-- between the micro menu and the bag buttons.
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

-- icon: a Vanilla-era spell/item icon that reads at 18x25 (all of these ship
-- in every client since 1.x); the modern atlas art stays as the fallback.
local ICONS = "Interface\\Icons\\"
local MODERN = {
    { key = "Profession", frame = "ProfessionMicroButton", modern = true, icon = ICONS .. "Trade_BlackSmithing" },
    { key = "Guild", frame = "GuildMicroButton", modern = true, icon = ICONS .. "INV_Shield_04" },
    { key = "LFD", frame = "LFDMicroButton", modern = true, icon = ICONS .. "INV_Misc_GroupLooking" },
    { key = "Legacy", frame = "LegacyMicroButton", modern = true, icon = ICONS .. "INV_Misc_Book_11" },
    {
        key = "Collections",
        frame = "CollectionsMicroButton",
        modern = true,
        icon = ICONS .. "Ability_Mount_RidingHorse",
    },
    { key = "EJ", frame = "EJMicroButton", modern = true, icon = ICONS .. "INV_Misc_Bone_HumanSkull_01" },
    -- housing: the hearthstone, home
    { key = "Housing", frame = "HousingMicroButton", modern = true, icon = ICONS .. "INV_Misc_Rune_01" },
    { key = "Store", frame = "StoreMicroButton", modern = true, icon = ICONS .. "INV_Misc_Coin_02" },
}

-- MainMenuBar.xml: right gryphon spans 544-64 .. 544+64 from the bar centre,
-- i.e. it ends 96 px past the bar's right edge. The modern group starts just
-- beyond its tail, bottom-aligned with the classic buttons.
local MODERN_GROUP_OFFSET_X = 100
local MICRO_STRIDE = 29 - 3 -- MainMenuBarMicroButtons.xml: 29 wide, each overlapping the previous by 3

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

-- Alert pulse (MicroButtonPulse -> UIFrameFlash on FlashBorder/FlashContent:
-- shows both at their native atlas size and animates their alpha, so alpha 0
-- does not hold). 1.12 had no pulsing micro buttons; the two textures lose
-- their art and are kept hidden.
local flashHooked = setmetatable({}, { __mode = "k" })

local function neutraliseFlash(button)
    for _, key in ipairs({ "FlashBorder", "FlashContent" }) do
        local tex = button[key]
        if tex then
            tex:SetTexture(nil)
            tex:SetAlpha(0)
            tex:Hide()
            if not flashHooked[tex] then
                flashHooked[tex] = true
                hooksecurefunc(tex, "Show", function(self)
                    self:Hide()
                end)
                hooksecurefunc(tex, "SetAtlas", function(self)
                    self:SetTexture(nil)
                end)
            end
        end
    end
end

-- Classic frame around a modern-only menu: character button frame, the
-- menu's Vanilla icon where the portrait would be (18x25 at TOP 0,-28).
local modernIcons = setmetatable({}, { __mode = "k" }) -- button -> our icon texture

local function classicIconAvailable(entry)
    if not entry.icon then
        return false
    end
    if entry.iconExists == nil then
        local exists = ns.Compat.TextureExists(entry.icon)
        entry.iconExists = exists ~= false -- unknown counts as present; the client shows a green square if not
    end
    return entry.iconExists
end

local function applyClassicModernTextures(button, entry)
    local up = Assets.Get("Micro.CharacterUp")
    local down = Assets.Get("Micro.CharacterDown")
    if not up or not classicIconAvailable(entry) then
        applyModernTextures(button)
        return
    end
    button:SetNormalTexture(up)
    button:GetNormalTexture():SetAllPoints(button)
    button:SetPushedTexture(down or up)
    button:GetPushedTexture():SetAllPoints(button)
    button:SetDisabledTexture(up)
    local disabled = button:GetDisabledTexture()
    disabled:SetAllPoints(button)
    disabled:SetDesaturated(true)
    -- the modern backdrop and shadow pieces
    for _, key in ipairs({ "Background", "PushedBackground", "Shadow", "PushedShadow" }) do
        if button[key] then
            button[key]:SetAlpha(0)
        end
    end
    local icon = modernIcons[button]
    if not icon then
        icon = button:CreateTexture(nil, "OVERLAY")
        modernIcons[button] = icon
    end
    icon:SetTexture(entry.icon)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetSize(18, 25)
    icon:ClearAllPoints()
    icon:SetPoint("TOP", button, "TOP", 0, -28)
    icon:SetDesaturated(not button:IsEnabled())
    icon:Show()
end

-- Pushed: the icon dims like the character portrait does (CharacterMicroButton_SetPushed)
local function applyModernIconState(button, pushed)
    local icon = modernIcons[button]
    if icon then
        icon:SetAlpha(pushed and 0.5 or 1)
    end
end

function applyTextures(button)
    local entry = reskinned[button]
    if not entry or applying then
        return
    end
    applying = true
    if entry.modern then
        applyClassicModernTextures(button, entry)
        local highlight = Assets.Get("Micro.Hilight")
        if highlight and modernIcons[button] then
            button:SetHighlightTexture(highlight, "BLEND")
            local tex = button:GetHighlightTexture()
            tex:SetAllPoints(button)
            tex:SetAlpha(1)
        end
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
    for _, key in ipairs({ "Background", "PushedBackground", "Shadow", "PushedShadow" }) do
        if button[key] then
            button[key]:SetAlpha(0)
        end
    end
    neutraliseFlash(button)
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
        elseif entry.modern then
            applyModernIconState(self, true)
        end
    end)
    AB.Hook(button, "SetNormal", function(self)
        applyTextures(self)
        if entry.character then
            applyPortrait(self, false)
        elseif entry.modern then
            applyModernIconState(self, false)
        end
    end)
    -- Enable/Disable (e.g. the shop in combat): the icon greys out with the frame
    if entry.modern then
        AB.Hook(button, "Enable", function(self)
            local icon = modernIcons[self]
            if icon then
                icon:SetDesaturated(false)
            end
        end)
        AB.Hook(button, "Disable", function(self)
            local icon = modernIcons[self]
            if icon then
                icon:SetDesaturated(true)
            end
        end)
    end
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
        local button = createOwnButton(
            "Spellbook",
            SPELLBOOK_ABILITIES_BUTTON or "Spellbook",
            "TOGGLESPELLBOOK",
            function()
                ns.SpellBook.Toggle()
            end,
            function()
                return ns.SpellBook.IsShown()
            end
        )
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

-- Forever-only menus: our own classic buttons in front of Blizzard's
local function createModernButtons()
    for _, entry in ipairs(MODERN) do
        local blizzard = _G[entry.frame]
        if blizzard and not MicroMenu.own[entry.key] then
            -- a game rule can keep a menu out of Blizzard's micro menu; then ours stays hidden too
            entry.inMenu = blizzard:GetParent() == _G.MicroMenu
            local label = entry.frame:gsub("MicroButton$", "")
            local button = createOwnButton(entry.key, label, nil, function(_, mouseButton)
                if blizzard:IsEnabled() then
                    blizzard:Click(mouseButton)
                end
            end, function()
                return blizzard:GetButtonState() == "PUSHED"
            end)
            button.blizzard = blizzard
            button:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(blizzard.tooltipText or label, 1, 1, 1)
                if not blizzard:IsEnabled() then
                    local why = blizzard.disabledTooltip
                    if type(why) == "function" then
                        why = why()
                    end
                    if type(why) == "string" then
                        GameTooltip:AddLine(why, 1, 0.1, 0.1, true)
                    end
                end
                GameTooltip:Show()
            end)
            applyClassicModernTextures(button, entry)
            if not modernIcons[button] then
                -- no classic frame or icon file: the modern art, scaled to the classic footprint
                local pairs_ = {
                    { "GetNormalTexture", "SetNormalAtlas" },
                    { "GetPushedTexture", "SetPushedAtlas" },
                    { "GetDisabledTexture", "SetDisabledAtlas" },
                    { "GetHighlightTexture", "SetHighlightAtlas" },
                }
                for _, pair in ipairs(pairs_) do
                    local source = blizzard[pair[1]](blizzard)
                    local atlas = source and source:GetAtlas()
                    if atlas then
                        button[pair[2]](button, atlas)
                        fitModernRegion(button, button[pair[1]](button))
                    end
                end
            end
            -- Blizzard's button keeps its events and state (UpdateMicroButtons drives it), just never shows
            ns.Suppress(blizzard)
            for _, method in ipairs({ "SetPushed", "SetNormal", "Enable", "Disable" }) do
                AB.Hook(blizzard, method, function()
                    MicroMenu.UpdateOwnStates()
                end)
            end
            if not entry.inMenu then
                button:Hide()
            end
        end
    end
end

local function updateOwnStates()
    for _, button in pairs(MicroMenu.own) do
        button:UpdateState()
        local blizzard = button.blizzard
        if blizzard then
            local enabled = blizzard:IsEnabled()
            button:SetEnabled(enabled)
            local icon = modernIcons[button]
            if icon then
                icon:SetDesaturated(not enabled)
                icon:SetAlpha(button:GetButtonState() == "PUSHED" and 0.5 or 1)
            end
        end
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
    -- the bar's extra length follows the number of extra buttons the game shows
    local count = 0
    if ns.db.microMenuRow then
        for _, entry in ipairs(MODERN) do
            local button = MicroMenu.own[entry.key]
            if button and Raw.IsShown(button) then
                count = count + 1
            end
        end
    end
    AB.SetExtraWidth(count * MICRO_STRIDE)
    local scale = ns.db.scale or 1
    if MicroMenu.blizzardMenu then
        Raw.SetScale(MicroMenu.blizzardMenu, scale)
    end
    local previous
    for _, entry in ipairs(CLASSIC) do
        local button = entry.own and MicroMenu.own[entry.own] or _G[entry.frame]
        if button and Raw.IsShown(button) then
            -- our spellbook button is a secure handler: its anchors are left alone in combat
            if AB.CanAnchor(button) then
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

    -- Forever-only systems: on the longer bar they continue the row, on the
    -- 1.12-wide bar they form a second group right of the right gryphon
    if AB.extraWidth == 0 then
        previous = nil
    end
    for _, entry in ipairs(MODERN) do
        local button = MicroMenu.own[entry.key]
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

    createModernButtons()

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
