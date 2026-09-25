local _, ns = ...

-- Bags module: one combined inventory window and one bank window in the
-- look of a 2005 all-in-one bag addon (tooltip-style border, dark
-- background, 37 px Quickslot2 item buttons), with the Bagnon feature set
-- that matters day to day: continuous item grid, per-bag toggles, search,
-- sort, money, keyring, quality borders, quest markers, cooldowns, movable
-- and remembered position, configurable columns, and a bank window that
-- shows the last visit's contents when no banker is near.
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

---------------------------------------------------------------------------
-- Bank snapshot
-- Bank slots only answer while a banker is open, so every visit is written
-- down (tabs, slot counts, item strings, counts, qualities, icons) and the
-- bank window shows that copy anywhere else. Stored through ns.DB.SetBlob
-- (a registered cvar, the store that comes back reliably on this client),
-- one entry per character, joined by "&":
--   <char>|<seen>|<tab>;<tab>...    tab = id,slots,name,icon,<slot>/<slot>...
--   slot = n=itemstring,count,quality,icon
-- Item strings hold only [%w:-]; names and the character key go through
-- DB.Escape, so no separator can appear inside a field.
---------------------------------------------------------------------------
local BANK_BLOB = "Bank"
local bankCache -- decoded snapshot for this character, or nil
local bankOpen = false -- BANKFRAME_OPENED .. BANKFRAME_CLOSED

local function bankLive()
    return bankOpen or (BankFrame ~= nil and BankFrame:IsShown())
end

local function charKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

local function cachedTab(bagID)
    if not bankCache then
        return nil
    end
    for _, tab in ipairs(bankCache.tabs) do
        if tab.id == bagID then
            return tab
        end
    end
    return nil
end

-- A value that may be a secret on this client is never compared; nil instead.
local function plain(value)
    if ns.Compat.IsSecret(value) then
        return nil
    end
    return value
end

local function itemString(link)
    if type(link) ~= "string" then
        return nil
    end
    local body = link:match("item:[%w:%-]+")
    if not body then
        return nil
    end
    return (body:gsub(":+$", ""))
end

local function encodeSnapshot(cache)
    local tabs = {}
    for _, tab in ipairs(cache.tabs) do
        local slots = {}
        for slot, item in pairs(tab.slots) do
            slots[#slots + 1] = ("%d=%s,%d,%d,%d"):format(
                slot,
                item.link,
                item.count,
                item.quality or -1,
                item.icon or 0
            )
        end
        table.sort(slots)
        tabs[#tabs + 1] = ("%d,%d,%s,%d,%s"):format(
            tab.id,
            tab.numSlots,
            ns.DB.Escape(tab.name or ""),
            tab.icon or 0,
            table.concat(slots, "/")
        )
    end
    return ("%s#%d#%s"):format(ns.DB.Escape(charKey()), cache.seen or 0, table.concat(tabs, ";"))
end

local function decodeSnapshot(entry)
    local seen, tabsText = entry:match("^[^|#]*[|#]([^|#]*)[|#](.*)$")
    if not seen then
        return nil
    end
    local cache = { seen = tonumber(seen) or 0, tabs = {} }
    for tabText in tabsText:gmatch("[^;]+") do
        local id, numSlots, name, icon, slotsText = tabText:match("^(%-?%d+),(%d+),([^,]*),(%-?%d*),(.*)$")
        if id then
            local tab = {
                id = tonumber(id),
                numSlots = tonumber(numSlots) or 0,
                name = ns.DB.Unescape(name),
                icon = tonumber(icon),
                slots = {},
            }
            for slotText in slotsText:gmatch("[^/]+") do
                local slot, link, count, quality, iconID = slotText:match("^(%d+)=([^,]*),(%d+),(%-?%d+),(%d+)$")
                if slot then
                    tab.slots[tonumber(slot)] = {
                        link = link,
                        count = tonumber(count) or 1,
                        quality = tonumber(quality),
                        icon = tonumber(iconID),
                    }
                end
            end
            cache.tabs[#cache.tabs + 1] = tab
        end
    end
    return cache
end

local function entryIsMine(entry)
    local key = ns.DB.Escape(charKey())
    local separator = entry:sub(#key + 1, #key + 1)
    return entry:sub(1, #key) == key and (separator == "#" or separator == "|")
end

-- Every stored copy is read (see DB.GetBlobSources): per character the
-- newest snapshot wins, so no copy can overwrite another character's bank.
local function allSnapshots()
    local byChar = {}
    for _, blob in ipairs(ns.DB.GetBlobSources(BANK_BLOB)) do
        for entry in blob:gmatch("[^&]+") do
            local key = entry:match("^([^|#]*)[|#]")
            local seen = tonumber(entry:match("^[^|#]*[|#](%d+)")) or 0
            if key and (not byChar[key] or byChar[key].seen < seen) then
                byChar[key] = { seen = seen, entry = entry }
            end
        end
    end
    return byChar
end

local function loadBankCache()
    for _, item in pairs(allSnapshots()) do
        if entryIsMine(item.entry) then
            bankCache = decodeSnapshot(item.entry)
        end
    end
end

local function saveBankCache()
    local entries = { encodeSnapshot(bankCache) }
    for _, item in pairs(allSnapshots()) do
        if not entryIsMine(item.entry) then
            entries[#entries + 1] = item.entry
        end
    end
    ns.DB.SetBlob(BANK_BLOB, table.concat(entries, "&"))
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
    local tab = cachedTab(bagID)
    if tab then
        return tab.name, tab.icon
    end
    return nil
end

-- Every bank visit is written down; see "Bank snapshot" above. A read that
-- finds no tabs at all (the session already gone) never replaces a snapshot.
local function snapshotBank()
    if not bankLive() then
        return
    end
    local cache = { seen = time(), tabs = {} }
    for _, id in ipairs(bankBagIDs()) do
        local name, icon = bankTabName(id)
        local numSlots = C_Container.GetContainerNumSlots(id) or 0
        local tab = { id = id, numSlots = numSlots, name = name, icon = icon, slots = {} }
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(id, slot)
            if info then
                local itemID = tonumber(plain(info.itemID))
                local link = itemString(plain(info.hyperlink)) or (itemID and ("item:" .. itemID))
                if link then
                    tab.slots[slot] = {
                        link = link,
                        count = tonumber(plain(info.stackCount)) or 1,
                        quality = tonumber(plain(info.quality)),
                        icon = tonumber(plain(info.iconFileID)),
                    }
                end
            end
        end
        if numSlots > 0 then
            cache.tabs[#cache.tabs + 1] = tab
        end
    end
    if #cache.tabs == 0 and bankCache then
        return
    end
    bankCache = cache
    saveBankCache()
end

local function bagIDsFor(kind)
    if kind == "bank" then
        if bankLive() then
            return bankBagIDs()
        end
        local ids = {}
        if bankCache then
            for _, tab in ipairs(bankCache.tabs) do
                ids[#ids + 1] = tab.id
            end
        end
        return ids
    end
    return inventoryBagIDs()
end

-- The keyring container reports its full capacity, but Blizzard's own bag
-- (MainMenuBarBagButtons.lua GetKeyRingSize) only shows the rows that hold
-- keys, rounded up to a multiple of four. Same rule here so the window does
-- not fill with empty key slots.
local function keyRingSize()
    local capacity = C_Container.GetContainerNumSlots(KEYRING) or 0
    local lastFilled, numItems = 0, 0
    for slot = 1, capacity do
        if C_Container.GetContainerItemInfo(KEYRING, slot) then
            lastFilled = slot
            numItems = numItems + 1
        end
    end
    local remainder = lastFilled % 4
    local size
    if remainder == 0 and numItems < lastFilled then
        size = lastFilled
    else
        size = lastFilled + (4 - remainder)
    end
    return math.min(size, capacity)
end

local function numSlotsFor(bagID)
    if bagID == KEYRING then
        return keyRingSize()
    end
    return C_Container.GetContainerNumSlots(bagID) or 0
end

local function settings()
    return ns.db.bags
end

local function isBagHidden(kind, bagID)
    local hidden = settings().hidden[kind]
    return hidden and hidden[bagID] or false
end

---------------------------------------------------------------------------
-- 1.12 bag chrome (ContainerFrame.xml / ContainerFrame_GenerateFrame):
-- UI-Bag-Components is a 256x512 sheet whose right 190 px hold the bag.
-- Measured on the sheet: title band rows 2-50 (portrait ring, leather bar,
-- close box; ring at texels 66-122, close box from 218), a cell row band at
-- rows 213-254 that repeats per row, cells 41.5 texels wide from texel 76
-- (four on the sheet, repeated across our columns), a 3 px left border
-- (texels 73-76) and a 12 px right border (242-254), the 10 px bottom edge
-- at rows 169-179, and the leather between bar and first row (rows 30-48)
-- for the bag-icon strip and the footer. The bank uses the "-Bank" sheet.
---------------------------------------------------------------------------
local ART = "Interface\\ContainerFrame\\UI-Bag-Components"
local ART_BANK = "Interface\\ContainerFrame\\UI-Bag-Components-Bank"
local SHEET_W, SHEET_H = 256, 512
local EDGE_LEFT, EDGE_RIGHT = 3, 12
-- the 1.12 title band (ring, name bar, close box) is left out: the bag icon row already shows the bags
local TOP_BAND = 0
local STRIP = 30 -- search/sort/money below the cells
local STRIP_TOP = 34 -- bag icons above the cells, with the close button at its right end
local BOTTOM = 10
local CELL = SLOT + SPACING -- 41: one baked cell per item button
local CELL_TEXELS = 41.5
local CELL_U0 = 76
local CELL_INSET = 3 -- the 37 px button inside its 41 px cell
local ROW_V0, ROW_V1 = 213, 254
local TOP_V0, TOP_V1 = 2, 50
local LEATHER_V0, LEATHER_V1 = 30, 48
local LEATHER_EDGE_V0 = 26 -- includes the bar's bottom line, a top edge for the strip that starts the window
local BOTTOM_V0, BOTTOM_V1 = 169, 179

local function artAvailable(file)
    return ns.Assets.HasMedia(file) or ns.Compat.TextureExists(file) == true
end

local function coords(texture, x0, x1, y0, y1)
    texture:SetTexCoord(x0 / SHEET_W, x1 / SHEET_W, y0 / SHEET_H, y1 / SHEET_H)
end

local function chromeTexture(window)
    local texture = window:CreateTexture(nil, "BACKGROUND")
    texture:SetTexture(window.artFile)
    ns.Dark.Tint(texture)
    return texture
end

-- left border, stretched leather, right border: the bag-icon strip and the footer
local function createStrip(window, withTopEdge)
    local strip = { left = chromeTexture(window), fill = chromeTexture(window), right = chromeTexture(window) }
    coords(strip.left, 73, 76, ROW_V0, ROW_V1)
    coords(strip.fill, 122, 218, withTopEdge and LEATHER_EDGE_V0 or LEATHER_V0, LEATHER_V1)
    coords(strip.right, 242, 254, ROW_V0, ROW_V1)
    return strip
end

local function placeStrip(strip, window, y, height, width)
    strip.left:SetSize(EDGE_LEFT, height)
    strip.left:SetPoint("TOPLEFT", window, "TOPLEFT", 0, y)
    strip.fill:SetSize(width - EDGE_LEFT - EDGE_RIGHT, height)
    strip.fill:SetPoint("TOPLEFT", window, "TOPLEFT", EDGE_LEFT, y)
    strip.right:SetSize(EDGE_RIGHT, height)
    strip.right:SetPoint("TOPRIGHT", window, "TOPRIGHT", 0, y)
end

local function createChrome(window)
    local chrome = { rows = {} }
    window.chrome = chrome
    if TOP_BAND > 0 then
        chrome.topLeft = chromeTexture(window)
        coords(chrome.topLeft, 66, 122, TOP_V0, TOP_V1)
        chrome.topLeft:SetSize(56, TOP_BAND)
        chrome.topLeft:SetPoint("TOPLEFT", window, "TOPLEFT", -7, 0) -- the ring overhangs the border as in 1.12
        chrome.topFill = chromeTexture(window)
        coords(chrome.topFill, 122, 218, TOP_V0, TOP_V1)
        chrome.topFill:SetPoint("TOPLEFT", chrome.topLeft, "TOPRIGHT", 0, 0)
        chrome.topRight = chromeTexture(window)
        coords(chrome.topRight, 218, 254, TOP_V0, TOP_V1)
        chrome.topRight:SetSize(36, TOP_BAND)
        chrome.topRight:SetPoint("TOPRIGHT", window, "TOPRIGHT", 0, 0)
        chrome.topFill:SetPoint("BOTTOMRIGHT", chrome.topRight, "BOTTOMLEFT", 0, 0)
    end
    chrome.toggleStrip = createStrip(window, TOP_BAND == 0)
    chrome.footer = createStrip(window)
    chrome.bottomLeft = chromeTexture(window)
    coords(chrome.bottomLeft, 73, 90, BOTTOM_V0, BOTTOM_V1)
    chrome.bottomLeft:SetSize(17, BOTTOM)
    chrome.bottomLeft:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 0, 0)
    chrome.bottomRight = chromeTexture(window)
    coords(chrome.bottomRight, 236, 254, BOTTOM_V0, BOTTOM_V1)
    chrome.bottomRight:SetSize(18, BOTTOM)
    chrome.bottomRight:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", 0, 0)
    chrome.bottomFill = chromeTexture(window)
    coords(chrome.bottomFill, 90, 236, BOTTOM_V0, BOTTOM_V1)
    chrome.bottomFill:SetPoint("TOPLEFT", chrome.bottomLeft, "TOPRIGHT", 0, 0)
    chrome.bottomFill:SetPoint("BOTTOMRIGHT", chrome.bottomRight, "BOTTOMLEFT", 0, 0)
end

-- one baked cell per column and row, borders left and right of every row
local function layoutChrome(window, columns, rows, slots)
    local chrome = window.chrome
    local width = EDGE_LEFT + columns * CELL + EDGE_RIGHT
    local y = -TOP_BAND
    placeStrip(chrome.toggleStrip, window, y, STRIP_TOP, width)
    y = y - STRIP_TOP
    for row = 1, rows do
        local pieces = chrome.rows[row]
        if not pieces then
            pieces = { left = chromeTexture(window), right = chromeTexture(window), cells = {} }
            coords(pieces.left, 73, 76, ROW_V0, ROW_V1)
            coords(pieces.right, 242, 254, ROW_V0, ROW_V1)
            chrome.rows[row] = pieces
        end
        pieces.left:SetSize(EDGE_LEFT, CELL)
        pieces.left:SetPoint("TOPLEFT", window, "TOPLEFT", 0, y)
        pieces.left:Show()
        pieces.right:SetSize(EDGE_RIGHT, CELL)
        pieces.right:SetPoint("TOPRIGHT", window, "TOPRIGHT", 0, y)
        pieces.right:Show()
        -- the last row carries cells only for real slots; leather fills the rest
        local cellsInRow = columns
        if row == rows and slots and slots > 0 then
            cellsInRow = slots - (rows - 1) * columns
        end
        for column = 1, cellsInRow do
            local cell = pieces.cells[column]
            if not cell then
                cell = chromeTexture(window)
                local slot = (column - 1) % 4
                coords(cell, CELL_U0 + slot * CELL_TEXELS, CELL_U0 + (slot + 1) * CELL_TEXELS, ROW_V0, ROW_V1)
                pieces.cells[column] = cell
            end
            cell:SetSize(CELL, CELL)
            cell:SetPoint("TOPLEFT", window, "TOPLEFT", EDGE_LEFT + (column - 1) * CELL, y)
            cell:Show()
        end
        for column = cellsInRow + 1, #pieces.cells do
            pieces.cells[column]:Hide()
        end
        if not pieces.fill then
            pieces.fill = chromeTexture(window)
            coords(pieces.fill, 122, 218, LEATHER_V0, LEATHER_V1)
        end
        if cellsInRow < columns then
            pieces.fill:SetSize((columns - cellsInRow) * CELL, CELL)
            pieces.fill:ClearAllPoints()
            pieces.fill:SetPoint("TOPLEFT", window, "TOPLEFT", EDGE_LEFT + cellsInRow * CELL, y)
            pieces.fill:Show()
        else
            pieces.fill:Hide()
        end
        y = y - CELL
    end
    for row = rows + 1, #chrome.rows do
        local pieces = chrome.rows[row]
        pieces.left:Hide()
        pieces.right:Hide()
        if pieces.fill then
            pieces.fill:Hide()
        end
        for _, cell in ipairs(pieces.cells) do
            cell:Hide()
        end
    end
    placeStrip(chrome.footer, window, y, STRIP, width)
    return width, TOP_BAND + STRIP_TOP + rows * CELL + STRIP + BOTTOM
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
    button:SetDisabledFontObject(GameFontDisableSmall)
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
        -- a secret cooldown cannot be handed to the widget from addon code
        if ns.Compat.IsSecret(start) or ns.Compat.IsSecret(duration) then
            button.Cooldown:Clear()
        else
            CooldownFrame_Set(button.Cooldown, start, duration, enable)
        end
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
-- Offline bank slots: plain item buttons painted from the snapshot. They
-- show tooltips and put links into chat; nothing can be moved.
---------------------------------------------------------------------------
local function getOfflineButton(window, index)
    local button = window.offline[index]
    if button then
        return button
    end
    button = CreateFrame("ItemButton", ("FCUI_Bags_%s_offline_%d"):format(window.kind, index), window.Items)
    button:SetSize(SLOT, SLOT)
    styleItemButton(button)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnEnter", function(self)
        if not self.link then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if not pcall(GameTooltip.SetHyperlink, GameTooltip, self.link) then
            GameTooltip:SetText(self.link)
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    button:SetScript("OnClick", function(self)
        if self.link and IsModifiedClick("CHATLINK") then
            local _, fullLink = C_Item.GetItemInfo(self.link)
            if fullLink then
                ChatEdit_InsertLink(fullLink)
            end
        end
    end)
    window.offline[index] = button
    return button
end

local function offlineName(link)
    local name = C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(link)
    return type(name) == "string" and name:lower() or nil
end

local function paintOfflineButton(button, item, search)
    button.link = item and item.link or nil
    local icon = item and item.icon ~= 0 and item.icon or nil
    if item and not icon and C_Item and C_Item.GetItemIconByID then
        icon = C_Item.GetItemIconByID(item.link)
    end
    SetItemButtonTexture(button, icon)
    SetItemButtonCount(button, item and item.count or 0)
    SetItemButtonDesaturated(button, false)
    if item and item.quality and item.quality >= 0 then
        SetItemButtonQuality(button, item.quality, item.link)
    else
        SetItemButtonQuality(button, nil)
    end
    local dim = false
    if item and search ~= "" then
        local name = offlineName(item.link)
        dim = name ~= nil and not name:find(search, 1, true)
    end
    button:SetAlpha(dim and 0.25 or 1)
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

-- Bags 1-4 (and the reagent bag) sit in inventory slots; the backpack, the
-- keyring and bank tabs do not. Only those slots can be picked up or filled.
local function equippedBagSlot(kind, bagID)
    if kind ~= "inventory" or bagID == BACKPACK or bagID == KEYRING then
        return nil
    end
    return C_Container.ContainerIDToInventoryID(bagID)
end

-- The item on the cursor goes to the bag slot: a bag equips or swaps with
-- the one there, any other item lands inside that bag. Same call as
-- Blizzard's own bag buttons make (MainMenuBarBagButtons.lua PutItemInBag).
local function putCursorInBag(kind, bagID)
    local invSlot = equippedBagSlot(kind, bagID)
    if not invSlot or not PutItemInBag or not CursorHasItem or not CursorHasItem() then
        return false
    end
    PutItemInBag(invSlot)
    return true
end

local function getToggle(window, index)
    local toggle = window.toggles[index]
    if toggle then
        return toggle
    end
    toggle = CreateFrame("Button", nil, window)
    toggle:SetSize(TOGGLE, TOGGLE)
    toggle:RegisterForDrag("LeftButton")
    toggle.Icon = toggle:CreateTexture(nil, "ARTWORK")
    toggle.Icon:SetAllPoints()
    toggle.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    toggle.Border = toggle:CreateTexture(nil, "OVERLAY")
    toggle.Border:SetTexture(Assets.Get("Button.Normal") or "Interface\\Buttons\\UI-Quickslot2")
    toggle.Border:SetPoint("CENTER", 0, -1)
    toggle.Border:SetSize(TOGGLE * 64 / 37, TOGGLE * 64 / 37)
    toggle:SetHighlightTexture(Assets.Get("Button.Highlight") or "Interface\\Buttons\\ButtonHilight-Square", "ADD")
    toggle:SetScript("OnClick", function(self)
        if CursorHasItem and CursorHasItem() then
            -- a click with an item on the cursor is a drop, never a hide
            putCursorInBag(window.kind, self.bagID)
            return
        end
        local hidden = settings().hidden
        hidden[window.kind] = hidden[window.kind] or {}
        hidden[window.kind][self.bagID] = not hidden[window.kind][self.bagID] or nil
        Bags.RefreshWindow(window.kind, true)
    end)
    -- Equip and unequip bags through the icons, as on the bottom bar
    toggle:SetScript("OnDragStart", function(self)
        local invSlot = equippedBagSlot(window.kind, self.bagID)
        if invSlot and PickupBagFromSlot then
            GameTooltip:Hide()
            PickupBagFromSlot(invSlot)
        end
    end)
    toggle:SetScript("OnReceiveDrag", function(self)
        putCursorInBag(window.kind, self.bagID)
    end)
    toggle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local invSlot = equippedBagSlot(window.kind, self.bagID)
        local equipped = false
        if invSlot and GetInventoryItemLink("player", invSlot) then
            -- the bag's own item tooltip, as the bottom bar shows it
            equipped = GameTooltip:SetInventoryItem("player", invSlot) and true or false
        end
        if not equipped then
            GameTooltip:SetText(bagLabel(window.kind, self.bagID), 1, 1, 1)
        end
        if invSlot then
            GameTooltip:AddLine(
                equipped and "Drag to unequip, drop a bag here to swap" or "Drop a bag here to equip",
                0.8,
                0.8,
                0.8
            )
        end
        if not invSlot or equipped then
            GameTooltip:AddLine(
                isBagHidden(window.kind, self.bagID) and "Hidden, click to show" or "Click to hide",
                0.8,
                0.8,
                0.8
            )
        end
        GameTooltip:Show()
        Bags.HighlightBag(window.kind, self.bagID, true)
    end)
    toggle:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        Bags.HighlightBag(window.kind, self.bagID, false)
    end)
    window.toggles[index] = toggle
    return toggle
end

local function layoutToggles(window, bagIDs)
    local x = window.chrome and 8 or PADDING
    local y = window.chrome and -(TOP_BAND + 5) or -30
    for index, bagID in ipairs(bagIDs) do
        local toggle = getToggle(window, index)
        toggle.bagID = bagID
        toggle.Icon:SetTexture(bagIcon(window.kind, bagID))
        local hidden = isBagHidden(window.kind, bagID)
        toggle.Icon:SetDesaturated(hidden)
        toggle.Icon:SetAlpha(hidden and 0.4 or 1)
        toggle:ClearAllPoints()
        toggle:SetPoint("TOPLEFT", window, "TOPLEFT", x, y)
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
    local offline = kind == "bank" and not bankLive()
    local bagIDs = bagIDsFor(kind)
    layoutToggles(window, bagIDs)

    local columns = columnsFor(kind)
    local stride = SLOT + SPACING
    local index = 0
    local seen = {}
    local offlineUsed = 0
    local search = offline and window.Search and window.Search:GetText():lower() or ""
    for _, bagID in ipairs(bagIDs) do
        seen[bagID] = true
        local tab = offline and cachedTab(bagID) or nil
        local numSlots = offline and (tab and tab.numSlots or 0) or numSlotsFor(bagID)
        local holder = window.holders[bagID]
        if isBagHidden(kind, bagID) or numSlots == 0 then
            if holder then
                holder:Hide()
            end
        elseif offline then
            if holder then
                holder:Hide()
            end
            for slot = 1, numSlots do
                offlineUsed = offlineUsed + 1
                local button = getOfflineButton(window, offlineUsed)
                index = index + 1
                local col = (index - 1) % columns
                local row = math.floor((index - 1) / columns)
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", window.Items, "TOPLEFT", col * stride, -row * stride)
                button:Show()
                paintOfflineButton(button, tab.slots[slot], search)
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
    for i = offlineUsed + 1, #window.offline do
        window.offline[i]:Hide()
    end

    local rows = math.max(1, math.ceil(index / columns))
    local width, height
    if window.chrome then
        width, height = layoutChrome(window, columns, rows, index)
    else
        width = PADDING * 2 + columns * stride - SPACING
        height = HEADER + rows * stride - SPACING + FOOTER + PADDING
    end
    window:SetSize(width, height)
    window.Items:SetSize(columns * stride - SPACING, rows * stride - SPACING)
    if index == 0 then
        if offline then
            window.Empty:SetText(bankCache and "No bank tabs" or "Not seen yet. Visit a banker once.")
        else
            window.Empty:SetText(kind == "bank" and "No bank tabs" or "No bags")
        end
        window.Empty:Show()
    else
        window.Empty:Hide()
    end
    if kind == "bank" then
        local title = BANK or "Bank"
        if offline and bankCache then
            title = ("%s (%s)"):format(title, date("%d.%m. %H:%M", bankCache.seen))
        end
        window.Title:SetText(title)
        window.Sort:SetEnabled(not offline)
        window.BlizzardBank:SetEnabled(not offline)
    end
    if relayout and window.Search then
        window.Search:ClearFocus()
    end
end

-- Light up every slot that belongs to one bag while its icon is hovered
-- (the bag toggle in the window or a bag button on the main bar). Uses the
-- item buttons' own highlight texture (ButtonHilight-Square), so it looks
-- like the mouse-over glow Vanilla slots had.
function Bags.HighlightBag(kind, bagID, on)
    local window = Bags.windows[kind]
    local holder = window and window.holders[bagID]
    if not holder or not holder:IsShown() then
        return
    end
    for _, button in ipairs(holder.buttons) do
        if button:IsShown() then
            if on then
                button:LockHighlight()
            else
                button:UnlockHighlight()
            end
        end
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

local refreshing = false
function Bags.RefreshAll(relayout)
    if refreshing then
        return
    end
    refreshing = true
    for kind in pairs(Bags.windows) do
        Bags.RefreshWindow(kind, relayout)
    end
    refreshing = false
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
    window.offline = {}
    window:SetFrameStrata("HIGH")
    window:SetToplevel(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:SetClampedToScreen(true)
    window:RegisterForDrag("LeftButton")
    window.artFile = kind == "bank" and ART_BANK or ART
    if not artAvailable(window.artFile) and artAvailable(ART) then
        window.artFile = ART
    end
    if artAvailable(window.artFile) then
        window.artFile = ns.Assets.Resolve(window.artFile)
        createChrome(window)
    else
        -- the 1.12 sheet is not on this machine: tooltip-style backdrop
        window.artFile = nil
        window:SetBackdrop(BACKDROP)
        window:SetBackdropColor(0.05, 0.05, 0.05, 0.92)
        ns.Dark.Backdrop(window, 1, 1, 1)
    end
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
        -- Escape (UISpecialFrames) hides this window first; a bank session
        -- the game still has open behind it ends with it.
        if self.kind == "bank" and BankFrame and BankFrame:IsShown() and not InCombatLockdown() then
            HideUIPanel(BankFrame)
        end
    end)
    window:Hide()

    if window.chrome then
        -- no title band: the name (for the bank, with the snapshot time) sits in the
        -- bag icon strip left of the close button; the inventory needs no name at all
        window.Title = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        window.Title:SetPoint("TOPRIGHT", window, "TOPRIGHT", -38, -11)
        window.Title:SetJustifyH("RIGHT")
    else
        window.Title = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        window.Title:SetPoint("TOP", window, "TOP", 0, -12)
    end
    window.Title:SetText(title)
    if window.chrome and kind == "inventory" then
        window.Title:Hide()
    end

    window.Close = createCloseButton(window, function()
        Bags.Close(kind)
    end)

    window.Items = CreateFrame("Frame", nil, window)
    if window.chrome then
        window.Items:SetPoint(
            "TOPLEFT",
            window,
            "TOPLEFT",
            EDGE_LEFT + CELL_INSET,
            -(TOP_BAND + STRIP_TOP + CELL_INSET)
        )
    else
        window.Items:SetPoint("TOPLEFT", window, "TOPLEFT", PADDING, -HEADER)
    end
    window.Items:SetSize(1, 1)

    window.Empty = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    window.Empty:SetPoint("CENTER", window.Items, "CENTER")
    window.Empty:SetText(kind == "bank" and "No bank tabs" or "No bags")
    window.Empty:Hide()

    -- Search (InputBoxTemplate is the classic input look)
    window.Search = CreateFrame("EditBox", "FCUI_Bags_" .. kind .. "_Search", window, "InputBoxTemplate")
    window.Search:SetSize(110, 20)
    window.Search:SetAutoFocus(false)
    if window.chrome then
        window.Search:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", EDGE_LEFT + 6, BOTTOM + 4)
    else
        window.Search:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", PADDING + 6, PADDING)
    end
    window.Search:SetScript("OnTextChanged", function(self)
        if C_Container.SetItemSearch then
            C_Container.SetItemSearch(self:GetText())
        end
        if kind == "bank" and not bankLive() then
            Bags.RefreshWindow(kind)
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
        -- the bank window anywhere (last visit's contents away from a banker)
        window.Bank = createPanelButton(window, BANK or "Bank", 50)
        window.Bank:SetPoint("LEFT", window.Junk, "RIGHT", 8, 0)
        window.Bank:SetScript("OnClick", function()
            Bags.ToggleBank()
        end)
    end

    -- Money
    window.Money = CreateFrame("Frame", "FCUI_Bags_" .. kind .. "_Money", window, "SmallMoneyFrameTemplate")
    if window.chrome then
        window.Money:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -EDGE_RIGHT - 2, BOTTOM + 4)
    else
        window.Money:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -6, PADDING)
    end

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

-- The bank window anywhere: live at a banker, the last snapshot elsewhere.
function Bags.ToggleBank()
    local window = Bags.windows.bank
    if not window then
        return
    end
    if window:IsShown() then
        Bags.Close("bank")
    else
        Bags.Show("bank")
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
    loadBankCache()
    -- Escape closes the bank window (and a live bank session with it, see OnHide)
    tinsert(UISpecialFrames, "FCUI_Bags_bank")
end

-- Main bar bag buttons (MainMenuBarBagButtons.xml): hovering one lights up its slots
local BAG_BAR_BUTTONS = {
    { name = "MainMenuBarBackpackButton", bagID = BACKPACK },
    { name = "CharacterBag0Slot", bagID = 1 },
    { name = "CharacterBag1Slot", bagID = 2 },
    { name = "CharacterBag2Slot", bagID = 3 },
    { name = "CharacterBag3Slot", bagID = 4 },
    { name = "CharacterReagentBag0Slot", bagID = REAGENT_BAG },
    { name = "KeyRingButton", bagID = KEYRING },
}

local function hookBagBarHighlights()
    for _, entry in ipairs(BAG_BAR_BUTTONS) do
        local button = _G[entry.name]
        if button and button.HookScript then
            button:HookScript("OnEnter", function()
                Bags.HighlightBag("inventory", entry.bagID, true)
            end)
            button:HookScript("OnLeave", function()
                Bags.HighlightBag("inventory", entry.bagID, false)
            end)
        end
    end
end

function Bags:Enable()
    Bags.Blizzard.Enable()
    hookBagBarHighlights()

    ns.RegisterEvent("BAG_UPDATE", self, function(_, _, bagID)
        Bags.UpdateBag("inventory", bagID)
        Bags.UpdateBag("bank", bagID)
    end)
    ns.RegisterEvent("BAG_UPDATE_DELAYED", self, function()
        snapshotBank()
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
        snapshotBank()
        Bags.RefreshWindow("bank", true)
    end)
    ns.RegisterEvent("PLAYERBANKSLOTS_CHANGED", self, function()
        snapshotBank()
        Bags.RefreshWindow("bank")
    end)
    ns.RegisterEvent("BANKFRAME_OPENED", self, function()
        bankOpen = true
        snapshotBank()
        Bags.RefreshWindow("bank", true)
    end)
    ns.RegisterEvent("BANKFRAME_CLOSED", self, function()
        bankOpen = false
        Bags.RefreshWindow("bank", true)
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
    ns.Print("  bank tabs: %s (bank %s)", table.concat(bankBagIDs(), ", "), bankLive() and "open" or "closed")
    local items = 0
    for _, tab in ipairs(bankCache and bankCache.tabs or {}) do
        for _ in pairs(tab.slots) do
            items = items + 1
        end
    end
    local blob = ns.DB.GetBlob(BANK_BLOB)
    ns.Print(
        "  bank snapshot: %s, %d tabs, %d items, stored %d chars",
        bankCache and date("%d.%m. %H:%M", bankCache.seen) or "none",
        bankCache and #bankCache.tabs or 0,
        items,
        blob and #blob or 0
    )
    ns.Print("  blizzard bags shown=%s", tostring(Bags.Blizzard.AnyBlizzardBagShown()))
end
