local _, ns = ...

-- Bags module: one combined inventory window and one bank window in the
-- look of a 2005 all-in-one bag addon (tooltip-style border, dark
-- background, 37 px Quickslot2 item buttons), with the Bagnon feature set
-- that matters day to day: continuous item grid, per-bag toggles, search,
-- sort, money, keyring, quality borders, quest markers, cooldowns, movable
-- and remembered position, configurable columns.
--
-- Item buttons are Blizzard's ContainerFrameItemButtonTemplate so clicks,
-- drags, tooltips, splitting and vendor selling run Blizzard's own (secure)
-- handlers. We only feed them bag/slot ids and paint their state.
-- Blizzard's container frames keep working invisibly (see Blizzard.lua) so
-- every "open bags" path in the game drives our window.
local Assets = ns.Assets

local Bags = ns.RegisterModule("Bags", {})
ns.Bags = Bags

-- ItemButtonTemplate.xml 1.12: 37x37 item buttons
local SLOT = 37
local SPACING = 4
local PADDING = 10
local HEADER = 62 -- title row + bag toggle row
local FOOTER = 30 -- search + sort + money row
local TOGGLE = 24

local BagIndex = Enum and Enum.BagIndex or {}
local BACKPACK = BagIndex.Backpack or 0
local KEYRING = BagIndex.Keyring or -1
local REAGENT_BAG = BagIndex.ReagentBag or 5
local NUM_BAGS = NUM_BAG_SLOTS or 4

Bags.windows = {} -- kind -> window frame

---------------------------------------------------------------------------
-- Bag lists
---------------------------------------------------------------------------
local function inventoryBagIDs()
    local ids = { BACKPACK }
    for i = 1, NUM_BAGS do
        ids[#ids + 1] = i
    end
    -- Reagent bag is not Vanilla; only listed if the client gives it slots.
    if C_Container.GetContainerNumSlots(REAGENT_BAG) > 0 then
        ids[#ids + 1] = REAGENT_BAG
    end
    if C_ActionBar and C_ActionBar.ShouldShowKeyring and C_ActionBar.ShouldShowKeyring() then
        ids[#ids + 1] = KEYRING
    end
    return ids
end

local function bankBagIDs()
    local ids = {}
    if C_Bank and C_Bank.FetchPurchasedBankTabIDs and Enum.BankType then
        local ok, tabs = pcall(C_Bank.FetchPurchasedBankTabIDs, Enum.BankType.Character)
        if ok and type(tabs) == "table" then
            for _, id in ipairs(tabs) do
                ids[#ids + 1] = id
            end
        end
    end
    return ids
end

local function bankTabName(bagID)
    if C_Bank and C_Bank.FetchPurchasedBankTabData and Enum.BankType then
        local ok, tabs = pcall(C_Bank.FetchPurchasedBankTabData, Enum.BankType.Character)
        if ok and type(tabs) == "table" then
            for _, data in ipairs(tabs) do
                if data.ID == bagID then
                    return data.name, data.icon
                end
            end
        end
    end
    return nil
end

local function bagIDsFor(kind)
    if kind == "bank" then
        return bankBagIDs()
    end
    return inventoryBagIDs()
end

local function settings()
    return ns.db.bags
end

local function isBagHidden(kind, bagID)
    local hidden = settings().hidden[kind]
    return hidden and hidden[bagID] or false
end

---------------------------------------------------------------------------
-- Classic widgets
---------------------------------------------------------------------------
local BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local function createPanelButton(parent, text, width)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width or 60, 22)
    -- UI-Panel-Button-Up/Down/Highlight are the 1.12 UIPanelButtonTemplate textures
    -- (referenced by loaded Forever code, so they ship). Left/right halves of the sheet.
    button:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up")
    button:GetNormalTexture():SetTexCoord(0, 0.625, 0, 0.6875)
    button:SetPushedTexture("Interface\\Buttons\\UI-Panel-Button-Down")
    button:GetPushedTexture():SetTexCoord(0, 0.625, 0, 0.6875)
    button:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight", "ADD")
    button:GetHighlightTexture():SetTexCoord(0, 0.625, 0, 0.6875)
    button:SetNormalFontObject(GameFontNormalSmall)
    button:SetHighlightFontObject(GameFontHighlightSmall)
    button:SetText(text)
    return button
end

local function createCloseButton(parent, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(32, 32)
    button:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -2, -2)
    local up = Assets.Get("Panel.CloseUp")
    if up then
        button:SetNormalTexture(up)
        button:SetPushedTexture(Assets.Path("Panel.CloseDown"))
        button:SetHighlightTexture(Assets.Path("Panel.CloseHighlight"), "ADD")
    else
        -- Modern fallback used by UIPanelCloseButtonNoScripts
        pcall(button.SetNormalAtlas, button, "RedButton-Exit")
        pcall(button.SetPushedAtlas, button, "RedButton-Exit-Pressed")
        pcall(button.SetHighlightAtlas, button, "RedButton-Highlight", "ADD")
        button:SetSize(24, 24)
    end
    button:SetScript("OnClick", onClick)
    return button
end

---------------------------------------------------------------------------
-- Item buttons
---------------------------------------------------------------------------
local function createBagHolder(window, bagID)
    local holder = CreateFrame("Frame", nil, window.Items)
    holder:SetID(bagID)
    holder:SetAllPoints(window.Items)
    -- ContainerFrameItemButtonMixin reads these from its parent in a few
    -- tooltip/tutorial paths. The holder is our frame, so adding methods is fine.
    holder.IsCombinedBagContainer = function()
        return false
    end
    holder.MatchesBagID = function(self, id)
        return self:GetID() == id
    end
    holder.GetBagID = function(self)
        return self:GetID()
    end
    holder.IsBackpack = function(self)
        return self:GetID() == BACKPACK
    end
    holder.buttons = {}
    return holder
end

local function styleItemButton(button)
    -- Modern decorations that Vanilla never had
    for _, key in ipairs({
        "NewItemTexture",
        "BattlepayItemTexture",
        "JunkIcon",
        "UpgradeIcon",
        "flash",
        "BagIndicator",
        "ExtendedSlot",
        "Highlight",
    }) do
        local tex = button[key]
        if tex then
            tex:SetAlpha(0)
            tex:Hide()
        end
    end
    -- Our frame: dropping the modern empty-slot atlas keeps the classic dark slot
    button.emptyBackgroundAtlas = nil
    -- ItemButton intrinsic already uses Quickslot2 / Depress / ButtonHilight-Square
    if button.Cooldown then
        button.Cooldown:SetAllPoints(button)
    end
end

local function getItemButton(window, bagID, slot)
    local holder = window.holders[bagID]
    if not holder then
        holder = createBagHolder(window, bagID)
        window.holders[bagID] = holder
    end
    local button = holder.buttons[slot]
    if not button then
        local name = ("FCUI_Bags_%s_%d_%d"):format(window.kind, bagID, slot)
        button = CreateFrame("ItemButton", name, holder, "ContainerFrameItemButtonTemplate")
        button:SetID(slot)
        button:SetBagID(bagID)
        button:SetSize(SLOT, SLOT)
        styleItemButton(button)
        holder.buttons[slot] = button
    end
    return button
end

local function updateItemButton(button, bagID, slot)
    local info = C_Container.GetContainerItemInfo(bagID, slot)
    local hasItem = info ~= nil
    SetItemButtonTexture(button, hasItem and info.iconFileID or nil)
    SetItemButtonCount(button, hasItem and info.stackCount or 0)
    SetItemButtonDesaturated(button, hasItem and info.isLocked)
    if hasItem and info.quality then
        SetItemButtonQuality(button, info.quality, info.hyperlink)
    else
        SetItemButtonQuality(button, nil)
    end
    button:SetHasItem(hasItem)
    button:SetReadable(hasItem and info.isReadable)

    -- Cooldown
    if button.Cooldown then
        local start, duration, enable = C_Container.GetContainerItemCooldown(bagID, slot)
        CooldownFrame_Set(button.Cooldown, start, duration, enable)
    end

    -- Quest markers (ContainerFrame UpdateItems logic, Vanilla-era textures)
    local questTexture = button.IconQuestTexture
    if questTexture then
        local questInfo = hasItem and C_Container.GetContainerItemQuestInfo(bagID, slot) or nil
        if questInfo and questInfo.questID and not questInfo.isActive then
            questTexture:SetTexture(TEXTURE_ITEM_QUEST_BANG)
            questTexture:Show()
        elseif questInfo and (questInfo.questID or questInfo.isQuestItem) then
            questTexture:SetTexture(TEXTURE_ITEM_QUEST_BORDER)
            questTexture:Show()
        else
            questTexture:Hide()
        end
    end

    -- Search: C_Container.SetItemSearch marks non-matching items as filtered
    if hasItem and info.isFiltered then
        button:SetAlpha(0.25)
    else
        button:SetAlpha(1)
    end
end

---------------------------------------------------------------------------
-- Bag toggle row
---------------------------------------------------------------------------
local function bagIcon(kind, bagID)
    if kind == "bank" then
        local _, icon = bankTabName(bagID)
        return icon
    end
    if bagID == BACKPACK then
        return Assets.Get("Bags.Backpack") or "Interface\\Buttons\\Button-Backpack-Up"
    elseif bagID == KEYRING then
        return "Interface\\ContainerFrame\\KeyRing-Bag-Icon"
    end
    local invSlot = C_Container.ContainerIDToInventoryID(bagID)
    return GetInventoryItemTexture("player", invSlot) or Assets.Get("Bags.EmptySlot")
end

local function bagLabel(kind, bagID)
    if kind == "bank" then
        return bankTabName(bagID) or (BANK or "Bank")
    end
    if bagID == BACKPACK then
        return BACKPACK_TOOLTIP or "Backpack"
    elseif bagID == KEYRING then
        return KEYRING or "Keyring"
    end
    local link = GetInventoryItemLink("player", C_Container.ContainerIDToInventoryID(bagID))
    if link then
        local name = C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(link)
        if name then
            return name
        end
    end
    return EMPTY or "Empty"
end

local function getToggle(window, index)
    local toggle = window.toggles[index]
    if toggle then
        return toggle
    end
    toggle = CreateFrame("Button", nil, window)
    toggle:SetSize(TOGGLE, TOGGLE)
    toggle.Icon = toggle:CreateTexture(nil, "ARTWORK")
    toggle.Icon:SetAllPoints()
    toggle.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    toggle.Border = toggle:CreateTexture(nil, "OVERLAY")
    toggle.Border:SetTexture(Assets.Get("Button.Normal") or "Interface\\Buttons\\UI-Quickslot2")
    toggle.Border:SetPoint("CENTER", 0, -1)
    toggle.Border:SetSize(TOGGLE * 64 / 37, TOGGLE * 64 / 37)
    toggle:SetHighlightTexture(Assets.Get("Button.Highlight") or "Interface\\Buttons\\ButtonHilight-Square", "ADD")
    toggle:SetScript("OnClick", function(self)
        local hidden = settings().hidden
        hidden[window.kind] = hidden[window.kind] or {}
        hidden[window.kind][self.bagID] = not hidden[window.kind][self.bagID] or nil
        Bags.RefreshWindow(window.kind, true)
    end)
    toggle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(bagLabel(window.kind, self.bagID), 1, 1, 1)
        GameTooltip:AddLine(
            isBagHidden(window.kind, self.bagID) and "Hidden, click to show" or "Click to hide",
            0.8,
            0.8,
            0.8
        )
        GameTooltip:Show()
    end)
    toggle:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    window.toggles[index] = toggle
    return toggle
end

local function layoutToggles(window, bagIDs)
    local x = PADDING
    for index, bagID in ipairs(bagIDs) do
        local toggle = getToggle(window, index)
        toggle.bagID = bagID
        toggle.Icon:SetTexture(bagIcon(window.kind, bagID))
        local hidden = isBagHidden(window.kind, bagID)
        toggle.Icon:SetDesaturated(hidden)
        toggle.Icon:SetAlpha(hidden and 0.4 or 1)
        toggle:ClearAllPoints()
        toggle:SetPoint("TOPLEFT", window, "TOPLEFT", x, -30)
        toggle:Show()
        x = x + TOGGLE + 4
    end
    for index = #bagIDs + 1, #window.toggles do
        window.toggles[index]:Hide()
    end
end

---------------------------------------------------------------------------
-- Layout and refresh
---------------------------------------------------------------------------
local function columnsFor(kind)
    if kind == "bank" then
        return settings().bankColumns or 14
    end
    return settings().columns or 10
end

function Bags.RefreshWindow(kind, relayout)
    local window = Bags.windows[kind]
    if not window or not window:IsShown() then
        return
    end
    local bagIDs = bagIDsFor(kind)
    layoutToggles(window, bagIDs)

    local columns = columnsFor(kind)
    local stride = SLOT + SPACING
    local index = 0
    local seen = {}
    for _, bagID in ipairs(bagIDs) do
        seen[bagID] = true
        local numSlots = C_Container.GetContainerNumSlots(bagID) or 0
        local holder = window.holders[bagID]
        if isBagHidden(kind, bagID) or numSlots == 0 then
            if holder then
                holder:Hide()
            end
        else
            for slot = 1, numSlots do
                local button = getItemButton(window, bagID, slot)
                index = index + 1
                local col = (index - 1) % columns
                local row = math.floor((index - 1) / columns)
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", window.Items, "TOPLEFT", col * stride, -row * stride)
                button:Show()
                updateItemButton(button, bagID, slot)
            end
            holder = window.holders[bagID]
            for slot = numSlots + 1, #holder.buttons do
                holder.buttons[slot]:Hide()
            end
            holder:Show()
        end
    end
    for bagID, holder in pairs(window.holders) do
        if not seen[bagID] then
            holder:Hide()
        end
    end

    local rows = math.max(1, math.ceil(index / columns))
    local width = PADDING * 2 + columns * stride - SPACING
    local height = HEADER + rows * stride - SPACING + FOOTER + PADDING
    window:SetSize(width, height)
    window.Items:SetSize(columns * stride - SPACING, rows * stride - SPACING)
    if index == 0 then
        window.Empty:Show()
    else
        window.Empty:Hide()
    end
    if relayout and window.Search then
        window.Search:ClearFocus()
    end
end

function Bags.UpdateSlot(kind, bagID, slot)
    local window = Bags.windows[kind]
    if not window or not window:IsShown() then
        return
    end
    local holder = window.holders[bagID]
    local button = holder and holder.buttons[slot]
    if button and button:IsShown() then
        updateItemButton(button, bagID, slot)
    end
end

function Bags.UpdateBag(kind, bagID)
    local window = Bags.windows[kind]
    if not window or not window:IsShown() then
        return
    end
    local holder = window.holders[bagID]
    if not holder or not holder:IsShown() then
        return
    end
    for slot, button in ipairs(holder.buttons) do
        if button:IsShown() then
            updateItemButton(button, bagID, slot)
        end
    end
end

function Bags.RefreshAll(relayout)
    for kind in pairs(Bags.windows) do
        Bags.RefreshWindow(kind, relayout)
    end
end

---------------------------------------------------------------------------
-- Windows
---------------------------------------------------------------------------
local DEFAULT_POSITION = {
    -- Vanilla bags opened above the bag buttons at the bottom right
    inventory = { point = "BOTTOMRIGHT", x = -10, y = 105 },
    bank = { point = "TOPLEFT", x = 20, y = -100 },
}

local function restorePosition(window)
    local pos = settings().positions[window.kind] or DEFAULT_POSITION[window.kind]
    window:ClearAllPoints()
    window:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
end

local function savePosition(window)
    local point, _, _, x, y = window:GetPoint(1)
    settings().positions[window.kind] = { point = point, x = x, y = y }
end

local function createWindow(kind, title)
    local window = CreateFrame("Frame", "FCUI_Bags_" .. kind, UIParent, "BackdropTemplate")
    window.kind = kind
    window.holders = {}
    window.toggles = {}
    window:SetFrameStrata("HIGH")
    window:SetToplevel(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:SetClampedToScreen(true)
    window:RegisterForDrag("LeftButton")
    window:SetBackdrop(BACKDROP)
    window:SetBackdropColor(0.05, 0.05, 0.05, 0.92)
    window:SetBackdropBorderColor(1, 1, 1, 1)
    window:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    window:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition(self)
    end)
    window:SetScript("OnShow", function(self)
        Bags.RefreshWindow(self.kind, true)
        if self.Money then
            MoneyFrame_UpdateMoney(self.Money)
        end
    end)
    window:SetScript("OnHide", function(self)
        if self.Search and self.Search:GetText() ~= "" then
            self.Search:SetText("")
        end
    end)
    window:Hide()

    window.Title = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    window.Title:SetPoint("TOP", window, "TOP", 0, -12)
    window.Title:SetText(title)

    window.Close = createCloseButton(window, function()
        Bags.Close(kind)
    end)

    window.Items = CreateFrame("Frame", nil, window)
    window.Items:SetPoint("TOPLEFT", window, "TOPLEFT", PADDING, -HEADER)
    window.Items:SetSize(1, 1)

    window.Empty = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    window.Empty:SetPoint("CENTER", window.Items, "CENTER")
    window.Empty:SetText(kind == "bank" and "No bank tabs" or "No bags")
    window.Empty:Hide()

    -- Search (InputBoxTemplate is the classic input look)
    window.Search = CreateFrame("EditBox", "FCUI_Bags_" .. kind .. "_Search", window, "InputBoxTemplate")
    window.Search:SetSize(110, 20)
    window.Search:SetAutoFocus(false)
    window.Search:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", PADDING + 6, PADDING)
    window.Search:SetScript("OnTextChanged", function(self)
        if C_Container.SetItemSearch then
            C_Container.SetItemSearch(self:GetText())
        end
    end)
    window.Search:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    window.Search:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    window.SearchLabel = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    window.SearchLabel:SetPoint("LEFT", window.Search, "LEFT", 4, 0)
    window.SearchLabel:SetText(SEARCH or "Search")
    window.Search:HookScript("OnTextChanged", function(self)
        window.SearchLabel:SetShown(self:GetText() == "" and not self:HasFocus())
    end)
    window.Search:HookScript("OnEditFocusGained", function()
        window.SearchLabel:Hide()
    end)
    window.Search:HookScript("OnEditFocusLost", function(self)
        window.SearchLabel:SetShown(self:GetText() == "")
    end)

    -- Sort
    window.Sort = createPanelButton(window, "Sort", 56)
    window.Sort:SetPoint("LEFT", window.Search, "RIGHT", 6, 0)
    window.Sort:SetScript("OnClick", function()
        if kind == "bank" then
            C_Container.SortBankBags()
        else
            C_Container.SortBags()
        end
    end)

    -- Sell junk (inventory only)
    if kind == "inventory" then
        window.Junk = Bags.Junk.CreateButton(window, TOGGLE)
        window.Junk:SetPoint("LEFT", window.Sort, "RIGHT", 8, 0)
    end

    -- Money
    window.Money = CreateFrame("Frame", "FCUI_Bags_" .. kind .. "_Money", window, "SmallMoneyFrameTemplate")
    window.Money:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -6, PADDING)

    if kind == "bank" then
        window.BlizzardBank = createPanelButton(window, "Blizzard bank", 96)
        window.BlizzardBank:SetPoint("LEFT", window.Sort, "RIGHT", 6, 0)
        window.BlizzardBank:SetScript("OnClick", function()
            Bags.Blizzard.ToggleBlizzardBank()
        end)
    end

    restorePosition(window)
    return window
end

function Bags.Show(kind)
    local window = Bags.windows[kind]
    if window and not window:IsShown() then
        window:Show()
    end
end

function Bags.Hide(kind)
    local window = Bags.windows[kind]
    if window and window:IsShown() then
        window:Hide()
    end
end

-- Close through Blizzard so its own open/closed bookkeeping stays right.
function Bags.Close(kind)
    if kind == "bank" then
        if BankFrame and BankFrame:IsShown() and not InCombatLockdown() then
            HideUIPanel(BankFrame)
        else
            Bags.Hide("bank")
        end
    else
        if Bags.Blizzard.AnyBlizzardBagShown() then
            CloseAllBags()
        end
        Bags.Hide("inventory")
    end
end

function Bags.SetColumns(kind, columns)
    if kind == "bank" then
        settings().bankColumns = columns
    else
        settings().columns = columns
    end
    Bags.RefreshWindow(kind, true)
end

---------------------------------------------------------------------------
-- Module lifecycle
---------------------------------------------------------------------------
function Bags:Init()
    Bags.windows.inventory = createWindow("inventory", INVENTORY_TOOLTIP or "Inventory")
    Bags.windows.bank = createWindow("bank", BANK or "Bank")
end

function Bags:Enable()
    Bags.Blizzard.Enable()
    Bags.Junk.Enable()

    ns.RegisterEvent("BAG_UPDATE", self, function(_, _, bagID)
        Bags.UpdateBag("inventory", bagID)
        Bags.UpdateBag("bank", bagID)
    end)
    ns.RegisterEvent("BAG_UPDATE_DELAYED", self, function()
        Bags.RefreshAll()
    end)
    ns.RegisterEvent("BAG_CONTAINER_UPDATE", self, function()
        Bags.RefreshAll(true)
    end)
    ns.RegisterEvent("ITEM_LOCK_CHANGED", self, function(_, _, bagID, slot)
        if bagID and slot then
            Bags.UpdateSlot("inventory", bagID, slot)
            Bags.UpdateSlot("bank", bagID, slot)
        end
    end)
    ns.RegisterEvent("BAG_UPDATE_COOLDOWN", self, function()
        Bags.RefreshAll()
    end)
    ns.RegisterEvent("INVENTORY_SEARCH_UPDATE", self, function()
        Bags.RefreshAll()
    end)
    ns.RegisterEvent("QUEST_ACCEPTED", self, function()
        Bags.RefreshAll()
    end)
    ns.RegisterEvent("UNIT_QUEST_LOG_CHANGED", self, function()
        Bags.RefreshAll()
    end)
    ns.RegisterEvent("BANK_TABS_CHANGED", self, function()
        Bags.RefreshWindow("bank", true)
    end)
    ns.RegisterEvent("PLAYERBANKSLOTS_CHANGED", self, function()
        Bags.RefreshWindow("bank")
    end)
    ns.RegisterEvent("PLAYER_ENTERING_WORLD", self, function()
        Bags.RefreshAll(true)
    end)
end

function Bags:Disable()
    ns.UnregisterAllEvents(self)
    for _, window in pairs(Bags.windows) do
        window:Hide()
    end
    ns.Print("Bags disabled, /reload to restore the Blizzard bags")
end

function Bags:Refresh()
    Bags.RefreshAll(true)
end

function Bags:Diag()
    for kind, window in pairs(Bags.windows) do
        local count = 0
        for _, holder in pairs(window.holders) do
            count = count + #holder.buttons
        end
        ns.Print("  %-9s shown=%s buttons=%d columns=%d", kind, tostring(window:IsShown()), count, columnsFor(kind))
    end
    ns.Print("  inventory bags: %s", table.concat(inventoryBagIDs(), ", "))
    ns.Print("  bank tabs: %s", table.concat(bankBagIDs(), ", "))
    ns.Print("  blizzard bags shown=%s", tostring(Bags.Blizzard.AnyBlizzardBagShown()))
end
