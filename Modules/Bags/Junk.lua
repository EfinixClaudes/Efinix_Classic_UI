local _, ns = ...

-- Sell junk: grey (Poor quality) items go to the vendor
--   * from an icon in the bag window,
--   * from an icon next to the repair buttons in the vendor window
--     (replaces Blizzard's MerchantSellAllJunkButton, which always asks a
--     confirmation popup and can be disabled by a game rule),
--   * automatically when Shift is held for a moment while a vendor is open,
--     which also repairs all gear if the vendor can repair and you can pay.
--
-- Selling uses the client's own C_MerchantFrame.SellAllJunkItems when the
-- game allows it, otherwise each grey item is sold with
-- C_Container.UseContainerItem, which is what a click on the item would do.
local Raw = ns.Raw
local Assets = ns.Assets
local Bags = ns.Bags

local Junk = {}
Bags.Junk = Junk

local SHIFT_HOLD_SECONDS = 1.5
local POOR = Enum and Enum.ItemQuality and Enum.ItemQuality.Poor or 0
local NUM_BAGS = NUM_BAG_SLOTS or 4
local REAGENT_BAG = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag or 5
local JUNK_ATLAS = "SpellIcon-256x256-SellJunk" -- MerchantFrame.xml MerchantSellAllJunkButton.Icon

local buttons = {} -- every junk button we own, refreshed together

local function merchantOpen()
    return MerchantFrame ~= nil and MerchantFrame:IsShown()
end

local function apiAvailable()
    return C_MerchantFrame ~= nil
        and C_MerchantFrame.SellAllJunkItems ~= nil
        and C_MerchantFrame.IsSellAllJunkEnabled ~= nil
        and C_MerchantFrame.IsSellAllJunkEnabled()
end

---------------------------------------------------------------------------
-- Junk scan
---------------------------------------------------------------------------
local function sellPriceOf(link)
    if not link or not C_Item or not C_Item.GetItemInfo then
        return 0
    end
    local price = select(11, C_Item.GetItemInfo(link))
    return tonumber(price) or 0
end

-- Returns list of {bag, slot, count, value} and the total vendor value.
function Junk.Collect()
    local items = {}
    local total = 0
    local bags = { 0 }
    for i = 1, NUM_BAGS do
        bags[#bags + 1] = i
    end
    if C_Container.GetContainerNumSlots(REAGENT_BAG) > 0 then
        bags[#bags + 1] = REAGENT_BAG
    end
    for _, bag in ipairs(bags) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.quality == POOR and not info.hasNoValue then
                local value = sellPriceOf(info.hyperlink) * (info.stackCount or 1)
                items[#items + 1] = { bag = bag, slot = slot, count = info.stackCount or 1, value = value }
                total = total + value
            end
        end
    end
    return items, total
end

function Junk.Count()
    if apiAvailable() and C_MerchantFrame.GetNumJunkItems then
        return C_MerchantFrame.GetNumJunkItems()
    end
    local items = Junk.Collect()
    return #items
end

---------------------------------------------------------------------------
-- Selling
---------------------------------------------------------------------------
local function coins(amount)
    if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
        return C_CurrencyInfo.GetCoinTextureString(amount)
    elseif GetCoinTextureString then
        return GetCoinTextureString(amount)
    end
    return tostring(amount) .. "c"
end

function Junk.Sell()
    if not merchantOpen() then
        ns.Print("open a vendor first")
        return false
    end
    local items, total = Junk.Collect()
    if #items == 0 then
        ns.Print("no junk to sell")
        return false
    end
    if apiAvailable() then
        C_MerchantFrame.SellAllJunkItems()
    else
        for _, item in ipairs(items) do
            C_Container.UseContainerItem(item.bag, item.slot)
        end
    end
    ns.Print("sold %d junk item%s for %s", #items, #items == 1 and "" or "s", coins(total))
    if SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end
    return true
end

---------------------------------------------------------------------------
-- Repair (MerchantFrame.lua: GetRepairAllCost / RepairAllItems)
---------------------------------------------------------------------------
function Junk.Repair()
    if not merchantOpen() or not CanMerchantRepair or not CanMerchantRepair() then
        return false
    end
    local cost, canRepair = GetRepairAllCost()
    if not canRepair or not cost or cost <= 0 then
        return false
    end
    if GetMoney() < cost then
        ns.Print("not enough money to repair (%s)", coins(cost))
        return false
    end
    RepairAllItems()
    ns.Print("repaired all items for %s", coins(cost))
    return true
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------
local function refreshButtons()
    local enabled = merchantOpen() and Junk.Count() > 0
    for _, button in ipairs(buttons) do
        button:SetEnabled(enabled)
        button.Icon:SetDesaturated(not enabled)
        button.Icon:SetAlpha(enabled and 1 or 0.6)
    end
end

local function tooltip(button)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(SELL_ALL_JUNK_ITEMS or "Sell all junk", 1, 1, 1)
    if not merchantOpen() then
        GameTooltip:AddLine("Only at a vendor", 0.8, 0.8, 0.8)
    else
        local items, total = Junk.Collect()
        if #items > 0 then
            GameTooltip:AddLine(("%d item%s, %s"):format(#items, #items == 1 and "" or "s", coins(total)), 1, 1, 1)
        else
            GameTooltip:AddLine("Nothing to sell", 0.8, 0.8, 0.8)
        end
    end
    if ns.db.bags.shiftSell then
        GameTooltip:AddLine("Hold Shift at a vendor to sell junk and repair automatically", 0.8, 0.8, 0.8)
    end
    GameTooltip:Show()
end

-- size 36 mirrors MerchantRepairAllButton; the bag window uses 24 like its bag toggles
function Junk.CreateButton(parent, size)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size, size)
    -- MerchantSellAllJunkButton: UI-EmptySlot behind the icon, Quickslot-Depress pushed, ButtonHilight-Square highlight
    button.Slot = button:CreateTexture(nil, "BACKGROUND")
    button.Slot:SetTexture("Interface\\Buttons\\UI-EmptySlot")
    button.Slot:SetSize(size * 64 / 36, size * 64 / 36)
    button.Slot:SetPoint("CENTER", 0, -1)
    button.Icon = button:CreateTexture(nil, "BORDER")
    button.Icon:SetAllPoints(button)
    local ok = pcall(button.Icon.SetAtlas, button.Icon, JUNK_ATLAS)
    if not ok or not button.Icon:GetAtlas() then
        button.Icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
    end
    button:SetPushedTexture(Assets.Get("Button.Pushed") or "Interface\\Buttons\\UI-Quickslot-Depress")
    button:SetHighlightTexture(Assets.Get("Button.Highlight") or "Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button:SetScript("OnClick", function()
        GameTooltip:Hide()
        Junk.Sell()
        refreshButtons()
    end)
    button:SetScript("OnEnter", tooltip)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    buttons[#buttons + 1] = button
    refreshButtons()
    return button
end

local function createMerchantButton()
    if not MerchantFrame or Junk.merchantButton then
        return
    end
    -- Blizzard's button keeps being positioned next to the repair buttons by
    -- MerchantFrame_Update even while hidden, so ours simply sits on top of it.
    local blizzard = MerchantSellAllJunkButton
    local button = Junk.CreateButton(MerchantFrame, 36)
    if blizzard then
        ns.Suppress(blizzard)
        button:SetPoint("CENTER", blizzard, "CENTER", 0, 0)
    else
        -- MerchantFrame.lua fallback anchor when no repair is offered
        button:SetPoint("BOTTOMRIGHT", MerchantFrame, "BOTTOMRIGHT", -148, 33)
    end
    button:SetFrameLevel(MerchantFrame:GetFrameLevel() + 5)
    Junk.merchantButton = button
end

---------------------------------------------------------------------------
-- Shift hold
---------------------------------------------------------------------------
local watcher = CreateFrame("Frame")
watcher:Hide()
watcher.held = 0
watcher.sold = false
watcher:SetScript("OnUpdate", function(self, elapsed)
    if not ns.db.bags.shiftSell or not merchantOpen() then
        self.held = 0
        self.sold = false
        return
    end
    if IsShiftKeyDown() then
        self.held = self.held + elapsed
        if not self.sold and self.held >= SHIFT_HOLD_SECONDS then
            self.sold = true
            if Junk.Count() > 0 then
                Junk.Sell()
                refreshButtons()
            end
            Junk.Repair()
        end
    else
        self.held = 0
        self.sold = false
    end
end)

---------------------------------------------------------------------------
-- Enable
---------------------------------------------------------------------------
function Junk.Enable()
    createMerchantButton()
    ns.RegisterEvent("MERCHANT_SHOW", Junk, function()
        watcher.held = 0
        watcher.sold = false
        Raw.Show(watcher)
        refreshButtons()
    end)
    ns.RegisterEvent("MERCHANT_CLOSED", Junk, function()
        Raw.Hide(watcher)
        refreshButtons()
    end)
    ns.RegisterEvent("MERCHANT_UPDATE", Junk, refreshButtons)
    ns.RegisterEvent("BAG_UPDATE_DELAYED", Junk, refreshButtons)
    refreshButtons()
end

function Junk.SetShiftSell(enabled)
    ns.db.bags.shiftSell = enabled
    ns.Print("hold Shift at a vendor to sell junk and repair: %s", enabled and "on" or "off")
end
