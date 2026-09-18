local _, ns = ...

-- SpellBook module: the 1.12 spellbook (SpellBookFrame.xml / .lua 1.12) as
-- our own window. Forever's PlayerSpellsFrame is a 1618x883 Retail-style
-- book with atlas pages; it cannot be reshaped, so it is hidden again
-- whenever Blizzard opens it to the spellbook tab and our book opens instead.
--
-- 1.12: SpellBookFrame 384x512 at TOPLEFT 0,-104, four panel textures,
-- Spellbook-Icon 58 at 10,-8, title at CENTER 6,230, close at TOPRIGHT
-- -44,-25, twelve 37x37 spell buttons (two columns 157 apart, rows 14 px
-- apart) from TOPLEFT 34,-85, up to eight skill line tabs on the right edge
-- from TOPRIGHT -32,-65 every 17 px, Spellbook / Pet tabs at the bottom,
-- Prev / Next page buttons at BOTTOMLEFT 50,105 and 314,105.
--
-- Casting goes through SecureActionButtonTemplate attributes (set out of
-- combat), dragging through C_SpellBook.PickupSpellBookItem, tooltips
-- through GameTooltip:SetSpellBookItem. No spell data is interpreted here.
local Combat = ns.Combat

local SB = ns.RegisterModule("SpellBook", {})
ns.SpellBook = SB

local SPELLS_PER_PAGE = 12
local MAX_SKILLLINE_TABS = 8
local COLUMN_OFFSET = 157 -- SpellButton2 TOPLEFT of SpellButton1 +157
local ROW_GAP = 14 -- SpellButton3 TOPLEFT of SpellButton1 BOTTOMLEFT 0,-14

local B = "Interface\\Buttons\\"
local S = "Interface\\Spellbook\\"
local FILES = {
    icon = S .. "Spellbook-Icon",
    topLeft = S .. "UI-SpellbookPanel-TopLeft",
    topRight = S .. "UI-SpellbookPanel-TopRight",
    botLeft = S .. "UI-SpellbookPanel-BotLeft",
    botRight = S .. "UI-SpellbookPanel-BotRight",
    spellBackground = S .. "UI-Spellbook-SpellBackground",
    skillTab = S .. "SpellBook-SkillLineTab",
    tabUnselected = S .. "UI-SpellBook-Tab-Unselected",
    tabSelected = S .. "UI-SpellBook-Tab1-Selected",
    tabHighlight = S .. "UI-SpellbookPanel-Tab-Highlight",
    slot = B .. "UI-Quickslot2",
    slotPushed = B .. "UI-Quickslot-Depress",
    slotHighlight = B .. "ButtonHilight-Square",
    passiveHighlight = B .. "UI-PassiveHighlight",
    checked = B .. "CheckButtonHilight",
    autoCastable = B .. "UI-AutoCastableOverlay",
    mouseHighlight = B .. "UI-Common-MouseHilight",
    closeUp = B .. "UI-Panel-MinimizeButton-Up",
    closeDown = B .. "UI-Panel-MinimizeButton-Down",
    closeHighlight = B .. "UI-Panel-MinimizeButton-Highlight",
    prevUp = B .. "UI-SpellbookIcon-PrevPage-Up",
    prevDown = B .. "UI-SpellbookIcon-PrevPage-Down",
    prevDisabled = B .. "UI-SpellbookIcon-PrevPage-Disabled",
    nextUp = B .. "UI-SpellbookIcon-NextPage-Up",
    nextDown = B .. "UI-SpellbookIcon-NextPage-Down",
    nextDisabled = B .. "UI-SpellbookIcon-NextPage-Disabled",
}

local function tex(key)
    return ns.Assets.Resolve(FILES[key])
end

local function artAvailable()
    return ns.Assets.HasMedia(FILES.topLeft) or ns.Compat.TextureExists(FILES.topLeft)
end

local frame
local toggleButton -- hidden button the spellbook key binding is redirected to
local overlay -- the secure cast buttons, a separate frame under UIParent (see the Window section)
local bookType = "spell" -- "spell" | "pet"
local selectedLine = 1
local pageNumbers = {} -- skill line index -> page (SPELLBOOK_PAGENUMBERS)
local petPage = 1
local lines = {} -- {name, icon, slots = {slotIndex, ...}} per visible skill line
local petSlots = {}
local petTitle

local function playerBank()
    return Enum.SpellBookSpellBank.Player
end

local function petBank()
    return Enum.SpellBookSpellBank.Pet
end

---------------------------------------------------------------------------
-- Data (C_SpellBook). Only known, castable-in-Vanilla-sense items: spells
-- and pet actions. Future spells and flyouts did not exist in 1.12.
---------------------------------------------------------------------------
local function refreshLines()
    lines = {}
    local numLines = C_SpellBook.GetNumSpellBookSkillLines()
    for index = 1, numLines do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(index)
        if info and not info.shouldHide and not info.offSpecID then
            local line = { name = info.name, icon = info.iconID, slots = {} }
            for i = 1, info.numSpellBookItems do
                local slot = info.itemIndexOffset + i
                local item = C_SpellBook.GetSpellBookItemInfo(slot, playerBank())
                if item and item.itemType == Enum.SpellBookItemType.Spell and not item.isOffSpec then
                    line.slots[#line.slots + 1] = slot
                end
            end
            lines[#lines + 1] = line
        end
    end
    if selectedLine > #lines then
        selectedLine = 1
    end

    petSlots = {}
    petTitle = nil
    local numPetSpells, token = C_SpellBook.HasPetSpells()
    if numPetSpells and numPetSpells > 0 then
        for slot = 1, numPetSpells do
            petSlots[#petSlots + 1] = slot
        end
        petTitle = token and _G["PET_TYPE_" .. token] or PET or "Pet"
    end
end

local function currentSlots()
    if bookType == "pet" then
        return petSlots, petBank()
    end
    local line = lines[selectedLine]
    return line and line.slots or {}, playerBank()
end

local function currentPage()
    if bookType == "pet" then
        return petPage
    end
    return pageNumbers[selectedLine] or 1
end

local function setPage(value)
    if bookType == "pet" then
        petPage = value
    else
        pageNumbers[selectedLine] = value
    end
end

local function maxPages()
    local slots = currentSlots()
    return math.max(1, math.ceil(#slots / SPELLS_PER_PAGE))
end

---------------------------------------------------------------------------
-- Spell buttons
---------------------------------------------------------------------------
local function updateButton(button)
    local slots, bank = currentSlots()
    local index = (currentPage() - 1) * SPELLS_PER_PAGE + button:GetID()
    local slot = slots[index]
    button.slot = slot
    button.bank = bank
    if not slot then
        button.Icon:Hide()
        button.Name:Hide()
        button.SubName:Hide()
        button.Cooldown:Hide()
        button.AutoCastable:Hide()
        button:SetChecked(false)
        button:GetNormalTexture():SetVertexColor(1, 1, 1)
        button:Disable()
        button.spellID = nil
        button.isPassive = nil
        return
    end
    button:Enable()
    local info = C_SpellBook.GetSpellBookItemInfo(slot, bank)
    if not info then
        return
    end
    button.spellID = info.spellID
    button.isPassive = info.isPassive

    button.Icon:SetTexture(info.iconID)
    button.Icon:Show()
    -- SpellButton_UpdateButton 1.12: passive spells get a black slot and grey name
    if info.isPassive then
        button:GetNormalTexture():SetVertexColor(0, 0, 0)
        button:SetHighlightTexture(tex("passiveHighlight"), "ADD")
        local passiveColor = PASSIVE_SPELL_FONT_COLOR or GRAY_FONT_COLOR
        button.Name:SetTextColor(passiveColor:GetRGB())
    else
        button:GetNormalTexture():SetVertexColor(1, 1, 1)
        button:SetHighlightTexture(tex("slotHighlight"), "ADD")
        button.Name:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
    end
    button.Name:SetText(info.name)
    button.SubName:SetText(info.subName or "")
    button.Name:ClearAllPoints()
    if info.subName and info.subName ~= "" then
        button.Name:SetPoint("LEFT", button, "RIGHT", 4, 4)
    else
        button.Name:SetPoint("LEFT", button, "RIGHT", 4, 2)
    end
    button.Name:Show()
    button.SubName:Show()

    -- cooldown
    local ok, cooldown = pcall(C_SpellBook.GetSpellBookItemCooldown, slot, bank)
    if ok and type(cooldown) == "table" then
        CooldownFrame_Set(
            button.Cooldown,
            cooldown.startTime,
            cooldown.duration,
            cooldown.isEnabled,
            false,
            cooldown.modRate
        )
        if cooldown.isEnabled then
            button.Icon:SetVertexColor(1, 1, 1)
        else
            button.Icon:SetVertexColor(0.4, 0.4, 0.4)
        end
    else
        button.Cooldown:Hide()
    end

    -- pet autocast marker
    local allowed = false
    if bank == petBank() then
        local okAuto, autoCastAllowed = pcall(C_SpellBook.GetSpellBookItemAutoCast, slot, bank)
        allowed = okAuto and autoCastAllowed
    end
    button.AutoCastable:SetShown(allowed == true)

    -- checked while this spell is the current cast (IsCurrentCast 1.12)
    local current = info.spellID and IsCurrentSpell and IsCurrentSpell(info.spellID)
    button:SetChecked(current == true)

    if GameTooltip:IsOwned(button) or (button.secure and GameTooltip:IsOwned(button.secure)) then
        button:GetScript("OnEnter")(button)
    end
end

-- The secure cast button over a slot: plain left click casts. Attributes can
-- only change out of combat; in combat the overlay is hidden anyway.
local function updateAttributes(button)
    local secure = button.secure
    if not secure or InCombatLockdown() then
        return
    end
    if button.slot and button.spellID and not button.isPassive then
        secure:SetAttribute("type1", "spell")
        secure:SetAttribute("spell", button.spellID)
    else
        secure:SetAttribute("type1", nil)
        secure:SetAttribute("spell", nil)
    end
end

local function onSpellClick(button, mouseButton)
    if not button.slot then
        return
    end
    if IsModifiedClick("PICKUPACTION") then
        C_SpellBook.PickupSpellBookItem(button.slot, button.bank)
    elseif mouseButton ~= "LeftButton" and button.bank == petBank() then
        C_SpellBook.ToggleSpellBookItemAutoCast(button.slot, button.bank)
        updateButton(button)
    end
    button:SetChecked(button.spellID and IsCurrentSpell and IsCurrentSpell(button.spellID) == true)
end

local function onSpellEnter(button)
    if not button.slot then
        return
    end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetSpellBookItem(button.slot, button.bank)
    GameTooltip:Show()
end

local function onSpellLeave()
    GameTooltip:Hide()
end

local function createSpellButton(parent, id)
    local button = CreateFrame("CheckButton", "FCUI_SpellButton" .. id, parent)
    button:SetSize(37, 37)
    button:SetID(id)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    -- SpellButtonTemplate 1.12
    button.Background = button:CreateTexture(nil, "BACKGROUND")
    button.Background:SetTexture(tex("spellBackground"))
    button.Background:SetSize(64, 64)
    button.Background:SetPoint("TOPLEFT", button, "TOPLEFT", -3, 3)
    button.Icon = button:CreateTexture(nil, "BORDER")
    button.Icon:SetAllPoints()
    button.Name = button:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    button.Name:SetWidth(103)
    button.Name:SetJustifyH("LEFT")
    button.Name:SetPoint("LEFT", button, "RIGHT", 4, 2)
    button.SubName =
        button:CreateFontString(nil, "ARTWORK", SubSpellFont and "SubSpellFont" or "GameFontHighlightSmall")
    button.SubName:SetSize(79, 18)
    button.SubName:SetJustifyH("LEFT")
    button.SubName:SetPoint("TOPLEFT", button.Name, "BOTTOMLEFT", 0, 4)
    button.AutoCastable = button:CreateTexture(nil, "OVERLAY")
    button.AutoCastable:SetTexture(tex("autoCastable"))
    button.AutoCastable:SetSize(60, 60)
    button.AutoCastable:SetPoint("CENTER")
    button.AutoCastable:Hide()
    button.Cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.Cooldown:SetAllPoints()

    button:SetNormalTexture(tex("slot"))
    local normal = button:GetNormalTexture()
    normal:ClearAllPoints()
    normal:SetSize(64, 64)
    normal:SetPoint("CENTER", button, "CENTER", 0, 0)
    button:SetPushedTexture(tex("slotPushed"))
    button:SetHighlightTexture(tex("slotHighlight"), "ADD")
    button:SetCheckedTexture(tex("checked"), "ADD")

    -- pickup on shift-click, pet autocast on right click; a plain left click
    -- casts through the secure cast button that sits over this one out of combat
    button:SetScript("OnClick", onSpellClick)
    button:SetScript("OnDragStart", function(self)
        if self.slot then
            C_SpellBook.PickupSpellBookItem(self.slot, self.bank)
        end
    end)
    button:SetScript("OnEnter", onSpellEnter)
    button:SetScript("OnLeave", onSpellLeave)
    return button
end

-- Secure cast button over a visible slot button. It lives in the overlay
-- (parent UIParent), never anchored to the book, so the book itself stays an
-- ordinary frame that can be shown and hidden in combat.
local function createCastButton(parent, visible)
    local secure =
        CreateFrame("Button", "FCUI_SpellCastButton" .. visible:GetID(), parent, "SecureActionButtonTemplate")
    secure:SetSize(37, 37)
    secure:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    secure:RegisterForDrag("LeftButton")
    secure:SetAttribute("shift-type1", "none")
    secure:SetAttribute("type2", "none")
    secure:SetHighlightTexture(tex("slotHighlight"), "ADD")
    secure:SetPushedTexture(tex("slotPushed"))
    secure.visible = visible
    visible.secure = secure
    -- everything but the plain left click is handled like on the visible button
    secure:HookScript("OnClick", function(self, mouseButton)
        onSpellClick(self.visible, mouseButton)
    end)
    secure:SetScript("OnDragStart", function(self)
        if self.visible.slot then
            C_SpellBook.PickupSpellBookItem(self.visible.slot, self.visible.bank)
        end
    end)
    secure:SetScript("OnEnter", function(self)
        onSpellEnter(self.visible)
    end)
    secure:SetScript("OnLeave", onSpellLeave)
    return secure
end

---------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------
local function createSkillTab(parent, id)
    local tab = CreateFrame("CheckButton", "FCUI_SpellBookSkillLineTab" .. id, parent)
    tab:SetSize(32, 32)
    tab:SetID(id)
    tab.Background = tab:CreateTexture(nil, "BACKGROUND")
    tab.Background:SetTexture(tex("skillTab"))
    tab.Background:SetSize(64, 64)
    tab.Background:SetPoint("TOPLEFT", tab, "TOPLEFT", -3, 11)
    tab:SetHighlightTexture(tex("slotHighlight"), "ADD")
    tab:SetCheckedTexture(tex("checked"), "ADD")
    tab:SetScript("OnClick", function(self)
        selectedLine = self:GetID()
        SB.Update()
    end)
    tab:SetScript("OnEnter", function(self)
        if self.tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.tooltip)
        end
    end)
    tab:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    return tab
end

local function createBookTab(parent, id)
    local tab = CreateFrame("Button", "FCUI_SpellBookFrameTabButton" .. id, parent)
    tab:SetSize(128, 64)
    tab:SetID(id)
    tab:SetNormalFontObject(GameFontNormalSmall)
    tab:SetHighlightFontObject(GameFontHighlightSmall)
    tab:SetDisabledFontObject(GameFontHighlightSmall)
    tab:SetNormalTexture(tex("tabUnselected"))
    tab:SetDisabledTexture(tex("tabSelected"))
    tab:SetHighlightTexture(tex("tabHighlight"), "ADD")
    local text = tab:GetFontString()
    if text then
        text:ClearAllPoints()
        text:SetPoint("CENTER", tab, "CENTER", 0, 3)
    end
    tab:SetScript("OnClick", function(self)
        bookType = self.bookType or "spell"
        SB.Update()
        PlaySound(bookType == "pet" and SOUNDKIT.IG_ABILITY_OPEN or SOUNDKIT.IG_SPELLBOOK_OPEN)
    end)
    return tab
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
-- Combat. A frame that protected frames hang off (children or anchors) is
-- itself protected, and insecure code may not show, hide or move it in
-- combat. Forever's secure snippet environment is also broken on this game
-- type (loadstring_untainted is nil when RestrictedExecution loads), so
-- nothing here uses secure handlers. Instead the book is an ordinary frame
-- with ordinary slot buttons, and the secure cast buttons live in a separate
-- overlay under UIParent that is positioned by numbers, never anchored to
-- the book. Out of combat the overlay follows the book (shown, hidden,
-- moved by our code). A visibility state driver hides it for the duration of
-- combat, so the book can open and close freely in a fight: view, tooltips
-- and drag work, click-to-cast waits for the fight to end.
local OVERLAY_DRIVER = "[combat] hide; show"

local function createFrame()
    frame = CreateFrame("Frame", "FCUI_SpellBookFrame", UIParent)
    frame:SetSize(384, 512)
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -104)
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        -- the overlay cannot follow in combat (it is protected)
        if not InCombatLockdown() then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SB.SyncOverlay()
    end)
    frame:Hide()

    toggleButton = CreateFrame("Button", "FCUI_SpellBookToggle", UIParent)
    toggleButton:Hide()
    toggleButton:SetScript("OnClick", function()
        SB.Toggle()
    end)

    overlay = CreateFrame("Frame", "FCUI_SpellBookCastOverlay", UIParent)
    overlay:SetSize(384, 512)
    overlay:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -104)
    overlay:SetFrameStrata("HIGH") -- above the (toplevel, MEDIUM) book
    overlay:Hide()

    local function panel(key, width, height, point)
        local t = frame:CreateTexture(nil, "BACKGROUND")
        t:SetTexture(tex(key))
        t:SetSize(width, height)
        t:SetPoint(point)
        ns.Dark.Tint(t)
        return t
    end
    panel("topLeft", 256, 256, "TOPLEFT")
    panel("topRight", 128, 256, "TOPRIGHT")
    panel("botLeft", 256, 256, "BOTTOMLEFT")
    panel("botRight", 128, 256, "BOTTOMRIGHT")
    frame.Icon = frame:CreateTexture(nil, "ARTWORK")
    frame.Icon:SetTexture(tex("icon"))
    frame.Icon:SetSize(58, 58)
    frame.Icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -8)
    frame.Title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    frame.Title:SetPoint("CENTER", frame, "CENTER", 6, 230)
    frame.PageText = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    frame.PageText:SetWidth(102)
    frame.PageText:SetPoint("BOTTOM", frame, "BOTTOM", -14, 96)

    local close = CreateFrame("Button", nil, frame)
    close:SetSize(32, 32)
    close:SetPoint("CENTER", frame, "TOPRIGHT", -44, -25)
    close:SetNormalTexture(tex("closeUp"))
    close:SetPushedTexture(tex("closeDown"))
    close:SetHighlightTexture(tex("closeHighlight"), "ADD")
    close:SetScript("OnClick", function()
        SB.Toggle()
    end)

    -- SpellButton1 at TOPLEFT 34,-85; ids 1-6 down the left column, 7-12 down the right
    frame.buttons = {}
    for id = 1, SPELLS_PER_PAGE do
        local button = createSpellButton(frame, id)
        local column = id > 6 and 1 or 0
        local row = (id - 1) % 6
        local x, y = 34 + column * COLUMN_OFFSET, -85 - row * (37 + ROW_GAP)
        button:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
        frame.buttons[id] = button
        -- same spot inside the overlay, which mirrors the book's size and position
        local secure = createCastButton(overlay, button)
        secure:SetPoint("TOPLEFT", overlay, "TOPLEFT", x, y)
    end

    frame.skillTabs = {}
    for id = 1, MAX_SKILLLINE_TABS do
        local tab = createSkillTab(frame, id)
        if id == 1 then
            tab:SetPoint("TOPLEFT", frame, "TOPRIGHT", -32, -65)
        else
            tab:SetPoint("TOPLEFT", frame.skillTabs[id - 1], "BOTTOMLEFT", 0, -17)
        end
        frame.skillTabs[id] = tab
    end

    frame.bookTabs = {}
    for id = 1, 2 do
        local tab = createBookTab(frame, id)
        if id == 1 then
            tab:SetPoint("CENTER", frame, "BOTTOMLEFT", 79, 61)
        else
            tab:SetPoint("LEFT", frame.bookTabs[id - 1], "RIGHT", -20, 0)
        end
        frame.bookTabs[id] = tab
    end

    frame.Prev = CreateFrame("Button", nil, frame)
    frame.Prev:SetSize(32, 32)
    frame.Prev:SetPoint("CENTER", frame, "BOTTOMLEFT", 50, 105)
    frame.Prev:SetNormalTexture(tex("prevUp"))
    frame.Prev:SetPushedTexture(tex("prevDown"))
    frame.Prev:SetDisabledTexture(tex("prevDisabled"))
    frame.Prev:SetHighlightTexture(tex("mouseHighlight"), "ADD")
    frame.Prev:SetScript("OnClick", function()
        setPage(currentPage() - 1)
        SB.Update()
        PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN)
    end)
    frame.PrevText = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    frame.PrevText:SetText(PREV or "Prev")
    frame.PrevText:SetPoint("LEFT", frame.Prev, "RIGHT", 0, 0)

    frame.Next = CreateFrame("Button", nil, frame)
    frame.Next:SetSize(32, 32)
    frame.Next:SetPoint("CENTER", frame, "BOTTOMLEFT", 314, 105)
    frame.Next:SetNormalTexture(tex("nextUp"))
    frame.Next:SetPushedTexture(tex("nextDown"))
    frame.Next:SetDisabledTexture(tex("nextDisabled"))
    frame.Next:SetHighlightTexture(tex("mouseHighlight"), "ADD")
    frame.Next:SetScript("OnClick", function()
        setPage(currentPage() + 1)
        SB.Update()
        PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN)
    end)
    frame.NextText = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    frame.NextText:SetText(NEXT or "Next")
    frame.NextText:SetPoint("RIGHT", frame.Next, "LEFT", 0, 0)

    local function updateMicroButton()
        local micro = ns.ActionBars and ns.ActionBars.MicroMenu
        if micro and micro.UpdateOwnStates then
            micro.UpdateOwnStates()
        end
    end
    frame:SetScript("OnShow", function()
        bookType = "spell"
        refreshLines()
        SB.Update()
        PlaySound(bookType == "pet" and SOUNDKIT.IG_ABILITY_OPEN or SOUNDKIT.IG_SPELLBOOK_OPEN)
        updateMicroButton()
        SB.SyncOverlay()
    end)
    frame:SetScript("OnHide", function()
        PlaySound(bookType == "pet" and SOUNDKIT.IG_ABILITY_CLOSE or SOUNDKIT.IG_SPELLBOOK_CLOSE)
        updateMicroButton()
        SB.SyncOverlay()
    end)
    -- Escape closes the book; CloseSpecialWindows may hide it in combat, it is an ordinary frame
    table.insert(UISpecialFrames, "FCUI_SpellBookFrame")
end

-- Overlay follows the book: shown and placed over it while the book is open
-- (out of combat), hidden while it is closed. In combat the state driver owns
-- its visibility and this call is queued for the end of the fight.
function SB.SyncOverlay()
    if not overlay or not frame then
        return
    end
    Combat.Run("spellbook:overlay", function()
        if frame:IsShown() then
            local left, bottom = frame:GetLeft(), frame:GetBottom()
            if left and bottom then
                overlay:ClearAllPoints()
                overlay:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
            end
            overlay:Show()
            RegisterStateDriver(overlay, "visibility", OVERLAY_DRIVER)
        else
            UnregisterStateDriver(overlay, "visibility")
            overlay:Hide()
        end
    end)
end

---------------------------------------------------------------------------
-- Update (SpellBookFrame_Update 1.12)
---------------------------------------------------------------------------
function SB.Update()
    if not frame then
        return
    end
    if bookType == "pet" and #petSlots == 0 then
        bookType = "spell"
    end
    -- skill line tabs only in the spell book
    for id, tab in ipairs(frame.skillTabs) do
        local line = lines[id]
        if line and bookType == "spell" then
            tab:SetNormalTexture(line.icon)
            tab.tooltip = line.name
            tab:SetChecked(selectedLine == id)
            tab:SetEnabled(true)
            tab:Show()
        else
            tab:Hide()
        end
    end
    -- bottom tabs: only with a pet book
    local tab1, tab2 = frame.bookTabs[1], frame.bookTabs[2]
    if #petSlots > 0 then
        tab1.bookType = "spell"
        tab1:SetText(SPELLBOOK or "Spellbook")
        tab1:SetEnabled(bookType ~= "spell")
        tab1:Show()
        tab2.bookType = "pet"
        tab2:SetText(petTitle or PET or "Pet")
        tab2:SetEnabled(bookType ~= "pet")
        tab2:Show()
    else
        tab1:Hide()
        tab2:Hide()
    end
    frame.Title:SetText(bookType == "pet" and (petTitle or PET) or (SPELLBOOK or "Spellbook"))

    -- pages
    local pages = maxPages()
    if currentPage() > pages then
        setPage(pages)
    end
    local pageNum = currentPage()
    frame.PageText:SetFormattedText(PAGE_NUMBER or "Page %d", pageNum)
    frame.Prev:SetEnabled(pageNum > 1)
    frame.Next:SetEnabled(pageNum < pages)

    -- the visible slots follow at once; the secure cast buttons when combat allows
    for _, button in ipairs(frame.buttons) do
        updateButton(button)
    end
    Combat.Run("spellbook:attributes", function()
        for _, button in ipairs(frame.buttons) do
            updateAttributes(button)
        end
    end)
end

-- The spellbook key binding is redirected to our book with override bindings
-- (out of combat only; existing overrides keep working in combat). This way
-- Blizzard's PlayerSpellsFrame is never shown or hidden by our code, which
-- keeps the UI panel manager free of taint. The micro button is ours as well
-- (see ActionBars/MicroMenu.lua).
local function updateBindings()
    if not toggleButton then
        return
    end
    Combat.Run("spellbook:bindings", function()
        ClearOverrideBindings(toggleButton)
        local key1, key2 = GetBindingKey("TOGGLESPELLBOOK")
        for _, key in ipairs({ key1, key2 }) do
            if key then
                SetOverrideBindingClick(toggleButton, true, key, toggleButton:GetName())
            end
        end
    end)
end

---------------------------------------------------------------------------
-- Module lifecycle
---------------------------------------------------------------------------
function SB:Init()
    if not artAvailable() then
        error("Interface\\Spellbook\\UI-SpellbookPanel-TopLeft is not available; run tools/import_blizzard_art.py")
    end
    if not C_SpellBook or not C_SpellBook.GetSpellBookSkillLineInfo then
        error("C_SpellBook API missing")
    end
    createFrame()
end

function SB:Enable()
    updateBindings()
    ns.RegisterEvent("UPDATE_BINDINGS", self, updateBindings)
    -- also while hidden: the secure buttons must carry their spells before combat starts
    local function refresh()
        refreshLines()
        SB.Update()
    end
    refresh()
    ns.RegisterEvent("SPELLS_CHANGED", self, refresh)
    ns.RegisterEvent("SPELL_TEXT_UPDATE", self, refresh)
    ns.RegisterEvent("PLAYER_ENTERING_WORLD", self, refresh)
    ns.RegisterEvent("PET_BAR_UPDATE", self, refresh)
    ns.RegisterEvent("UNIT_PET", self, function(_, _, unit)
        if unit == "player" then
            refresh()
        end
    end)
    ns.RegisterEvent("SPELL_UPDATE_COOLDOWN", self, function()
        if frame:IsShown() then
            SB.Update()
        end
    end)
    ns.RegisterEvent("CURRENT_SPELL_CAST_CHANGED", self, function()
        if frame:IsShown() then
            for _, button in ipairs(frame.buttons) do
                button:SetChecked(button.spellID and IsCurrentSpell and IsCurrentSpell(button.spellID) == true)
            end
        end
    end)
    ns.RegisterEvent("PLAYER_REGEN_ENABLED", self, function()
        if frame:IsShown() then
            SB.Update()
        end
        SB.SyncOverlay()
    end)
end

function SB:Disable()
    ns.UnregisterAllEvents(self)
    if frame then
        frame:Hide() -- an ordinary frame; the overlay follows through SyncOverlay when combat allows
    end
    if toggleButton then
        Combat.Run("spellbook:bindings", function()
            ClearOverrideBindings(toggleButton)
        end)
    end
    ns.Print("SpellBook disabled, /reload to restore the Blizzard spellbook")
end

function SB:Refresh() end

function SB.Toggle()
    if not frame then
        return
    end
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

function SB.IsShown()
    return frame ~= nil and frame:IsShown()
end

function SB:Diag()
    ns.Print(
        "  window=%s shown=%s lines=%d selected=%d page=%d book=%s pet=%d",
        tostring(frame ~= nil),
        tostring(frame and frame:IsShown()),
        #lines,
        selectedLine,
        currentPage(),
        bookType,
        #petSlots
    )
end
