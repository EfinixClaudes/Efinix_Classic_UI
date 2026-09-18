local _, ns = ...

-- Sell junk: grey (Poor quality) items go to the vendor
--   * from an icon in the bag window,
--   * from an icon next to the repair buttons in the vendor window
--     (replaces Blizzard's MerchantSellAllJunkButton, which always asks a
--     confirmation popup and can be disabled by a game rule),
--   * automatically when Shift is held while a vendor window opens, or held
--     for a second while it is open; that also repairs all gear if the
--     vendor can repair and you can pay.
--
-- Selling uses the client's own C_MerchantFrame.SellAllJunkItems when the
-- game allows it, otherwise each grey item is sold with
-- C_Container.UseContainerItem, which is what a click on the item would do.
local Assets = ns.Assets
local Bags = ns.Bags

local Junk = {}
Bags.Junk = Junk -- the bag window's coin icon uses Junk.CreateButton

-- Own module: the vendor features work with the bag window turned off.
local Vendor = ns.RegisterModule("Vendor", {})
ns.Vendor = Vendor

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

-- A value that may be a secret on this client is never compared; nil instead.
local function plain(value)
    if ns.Compat.IsSecret(value) then
        return nil
    end
    return value
end

---------------------------------------------------------------------------
-- Junk scan
---------------------------------------------------------------------------
local function sellPriceOf(link)
    if not link or not C_Item or not C_Item.GetItemInfo then
        return 0
    end
    local price = select(11, C_Item.GetItemInfo(link))
    return tonumber(plain(price)) or 0
end

-- Returns list of {bag, slot, count, value} and the total vendor value.
function Junk.Collect()
    local items = {}
    local total = 0
    local bags = { 0 }
    for i = 1, NUM_BAGS do
        bags[#bags + 1] = i
    end
    if (C_Container.GetContainerNumSlots(REAGENT_BAG) or 0) > 0 then
        bags[#bags + 1] = REAGENT_BAG
    end
    for _, bag in ipairs(bags) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and plain(info.quality) == POOR and not plain(info.hasNoValue) then
                local count = tonumber(plain(info.stackCount)) or 1
                local value = sellPriceOf(plain(info.hyperlink)) * count
                items[#items + 1] = { bag = bag, slot = slot, count = count, value = value }
                total = total + value
            end
        end
    end
    return items, total
end

function Junk.Count()
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

-- Returns the number of items sold and their value, or nil and a reason.
function Junk.Sell(quiet)
    if not merchantOpen() then
        if not quiet then
            ns.Print("open a vendor first")
        end
        return nil, "no vendor open"
    end
    local items, total = Junk.Collect()
    if #items == 0 then
        if not quiet then
            ns.Print("no junk to sell")
        end
        return nil, "no junk to sell"
    end
    if apiAvailable() then
        C_MerchantFrame.SellAllJunkItems()
    else
        for _, item in ipairs(items) do
            C_Container.UseContainerItem(item.bag, item.slot)
        end
    end
    if not quiet then
        ns.Print("sold %d junk item%s for %s", #items, #items == 1 and "" or "s", coins(total))
    end
    if SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end
    return #items, total
end

---------------------------------------------------------------------------
-- Repair (MerchantFrame.lua: GetRepairAllCost / RepairAllItems)
---------------------------------------------------------------------------
-- Returns the cost paid, or nil and a reason.
function Junk.Repair(quiet)
    if not merchantOpen() then
        return nil, "no vendor open"
    end
    if not CanMerchantRepair or not CanMerchantRepair() then
        return nil, "this vendor cannot repair"
    end
    local cost, canRepair = GetRepairAllCost()
    cost = tonumber(plain(cost)) or 0
    if not canRepair or cost <= 0 then
        return nil, "nothing to repair"
    end
    if GetMoney() < cost then
        if not quiet then
            ns.Print("not enough money to repair (%s)", coins(cost))
        end
        return nil, "not enough money to repair (" .. coins(cost) .. ")"
    end
    RepairAllItems()
    if not quiet then
        ns.Print("repaired all items for %s", coins(cost))
    end
    return cost
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
-- Shift: sell junk and repair
-- Acts right away when Shift is already held as the vendor window opens,
-- otherwise after Shift has been held for a second while it is open, and
-- again after the key was released and held once more. A C_Timer ticker
-- polls the key while the vendor is open; it is not tied to any frame, so
-- nothing the game does to the merchant frame can stop it. Every run prints
-- what it did, so a visit with nothing to sell or repair still answers.
---------------------------------------------------------------------------
local SHIFT_HOLD_SECONDS = 1
local TICK = 0.2
local shift = { ticker = nil, held = 0, done = false, last = "never" }
Junk.shift = shift

local function shiftAction(how)
    shift.done = true
    local parts = {}
    local sold, soldValue = Junk.Sell(true)
    if sold then
        parts[#parts + 1] = ("sold %d junk item%s for %s"):format(sold, sold == 1 and "" or "s", coins(soldValue))
    else
        parts[#parts + 1] = soldValue
    end
    local cost, reason = Junk.Repair(true)
    if cost then
        parts[#parts + 1] = "repaired for " .. coins(cost)
    else
        parts[#parts + 1] = reason
    end
    local summary = table.concat(parts, ", ")
    shift.last = ("%s (%s, %s)"):format(summary, how, date("%H:%M:%S"))
    ns.Print("Shift at vendor: %s", summary)
    refreshButtons()
end

local function shiftTick()
    if not merchantOpen() then
        Junk.StopShift()
        return
    end
    if not ns.db.bags.shiftSell then
        return
    end
    if IsShiftKeyDown() then
        shift.held = shift.held + TICK
        if not shift.done and shift.held >= SHIFT_HOLD_SECONDS then
            shiftAction("held")
        end
    else
        shift.held = 0
        shift.done = false
    end
end

function Junk.StartShift()
    Junk.StopShift()
    shift.done = false
    if not ns.db.bags.shiftSell then
        return
    end
    if IsShiftKeyDown() then
        -- Shift held while talking to the vendor: a moment for the window
        -- and the repair cost to be in place, then act.
        C_Timer.After(0.2, function()
            if merchantOpen() and not shift.done and IsShiftKeyDown() then
                shiftAction("held while opening")
            end
        end)
    end
    shift.ticker = C_Timer.NewTicker(TICK, shiftTick)
end

function Junk.StopShift()
    if shift.ticker then
        shift.ticker:Cancel()
        shift.ticker = nil
    end
    shift.held = 0
end

---------------------------------------------------------------------------
-- Enable
---------------------------------------------------------------------------
function Junk.Enable()
    createMerchantButton()
    ns.RegisterEvent("MERCHANT_SHOW", Junk, function()
        Junk.StartShift()
        refreshButtons()
    end)
    ns.RegisterEvent("MERCHANT_CLOSED", Junk, function()
        Junk.StopShift()
        refreshButtons()
    end)
    ns.RegisterEvent("MERCHANT_UPDATE", Junk, refreshButtons)
    ns.RegisterEvent("BAG_UPDATE_DELAYED", Junk, refreshButtons)
    refreshButtons()
    if merchantOpen() then
        Junk.StartShift()
    end
end

function Junk.SetShiftSell(enabled)
    ns.db.bags.shiftSell = enabled
    ns.DB.Flush()
    ns.Print("hold Shift at a vendor to sell junk and repair: %s", enabled and "on" or "off")
    if enabled and merchantOpen() then
        Junk.StartShift()
    elseif not enabled then
        Junk.StopShift()
    end
end

function Vendor:Init() end

function Vendor:Enable()
    Junk.Enable()
end

function Vendor:Disable()
    ns.UnregisterAllEvents(Junk)
    Junk.StopShift()
    if Junk.merchantButton then
        Junk.merchantButton:Hide()
    end
    ns.Print("Vendor: shift-to-sell and the vendor junk icon are off")
end

function Vendor:Refresh() end

function Vendor:Diag()
    local canRepair = CanMerchantRepair and merchantOpen() and CanMerchantRepair() or false
    local cost = 0
    if canRepair then
        cost = tonumber(plain((GetRepairAllCost()))) or 0
    end
    ns.Print(
        "  shiftSell=%s merchantOpen=%s ticker=%s held=%.1fs done=%s junk=%d canRepair=%s cost=%s",
        tostring(ns.db.bags.shiftSell),
        tostring(merchantOpen()),
        tostring(shift.ticker ~= nil),
        shift.held,
        tostring(shift.done),
        Junk.Count(),
        tostring(canRepair),
        coins(cost)
    )
    ns.Print("  last shift run: %s", shift.last)
end
