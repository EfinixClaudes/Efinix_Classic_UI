local _, ns = ...

-- LootFrame module: the 1.12 loot window (LootFrame.xml / LootFrame.lua 1.12),
-- built as our own frame. Forever's LootFrame is a scrolling flat panel with
-- animated cards and cannot be shaped into the 256x256 panel; it is
-- neutralised with ns.Hide (events off, so it never opens) and our window
-- takes the loot events instead.
--
-- 1.12: LootFrame 256x256 at TOPLEFT 0,-104, UI-LootPanel art, TargetDead
-- overlay 58 at 10,-8, "Items" title at CENTER -12,102, close button at
-- TOPRIGHT -81,-26, four 37x37 item buttons from TOPLEFT 24,-80 with 4 px
-- gaps, name plate UI-QuestItemNameFrame 130x62, page arrows at the bottom.
-- More than four items: three per page with Prev/Next.
local Raw = ns.Raw

local Loot = ns.RegisterModule("LootFrame", {})
ns.LootFrame = Loot

local NUM_BUTTONS = 4 -- LOOTFRAME_NUMBUTTONS
local B = "Interface\\Buttons\\"
local FILES = {
    panel = "Interface\\LootFrame\\UI-LootPanel",
    dead = "Interface\\TargetingFrame\\TargetDead",
    fishing = "Interface\\LootFrame\\FishingLoot-Icon",
    nameFrame = "Interface\\QuestFrame\\UI-QuestItemNameFrame",
    slot = B .. "UI-Quickslot2",
    slotPushed = B .. "UI-Quickslot-Depress",
    slotHighlight = B .. "ButtonHilight-Square",
    mouseHighlight = B .. "UI-Common-MouseHilight",
    closeUp = B .. "UI-Panel-MinimizeButton-Up",
    closeDown = B .. "UI-Panel-MinimizeButton-Down",
    closeHighlight = B .. "UI-Panel-MinimizeButton-Highlight",
    upUp = "Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Up",
    upDown = "Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Down",
    upDisabled = "Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Disabled",
    downUp = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up",
    downDown = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down",
    downDisabled = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Disabled",
}

local function tex(key)
    return ns.Assets.Resolve(FILES[key])
end

-- The panel art is the one file that must exist for the window to make sense.
local function artAvailable()
    return ns.Assets.HasMedia(FILES.panel) or ns.Compat.TextureExists(FILES.panel)
end

local frame -- our window
local page = 1
local numLootItems = 0

local function itemsPerPage()
    if numLootItems > NUM_BUTTONS then
        return NUM_BUTTONS - 1
    end
    return NUM_BUTTONS
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function createButton(parent, index)
    local button = CreateFrame("Button", "FCUI_LootButton" .. index, parent)
    button:SetSize(37, 37) -- ItemButtonTemplate 1.12
    button:SetID(index)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetNormalTexture(tex("slot"))
    local normal = button:GetNormalTexture()
    normal:ClearAllPoints()
    normal:SetSize(64, 64)
    normal:SetPoint("CENTER", button, "CENTER", 0, -1)
    button:SetPushedTexture(tex("slotPushed"))
    button:SetHighlightTexture(tex("slotHighlight"), "ADD")

    button.Icon = button:CreateTexture(nil, "BORDER")
    button.Icon:SetAllPoints()
    button.Count = button:CreateFontString(nil, "ARTWORK", "NumberFontNormal")
    button.Count:SetJustifyH("RIGHT")
    button.Count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -5, 2)
    -- LootButtonTemplate: name plate 130x62 at LEFT 30,0, text 93x38 at LEFT of RIGHT 8,0
    button.NameFrame = button:CreateTexture(nil, "ARTWORK")
    button.NameFrame:SetTexture(tex("nameFrame"))
    button.NameFrame:SetSize(130, 62)
    button.NameFrame:SetPoint("LEFT", button, "LEFT", 30, 0)
    button.Text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    button.Text:SetJustifyH("LEFT")
    button.Text:SetSize(93, 38)
    button.Text:SetPoint("LEFT", button, "RIGHT", 8, 0)

    button:SetScript("OnClick", function(self)
        local slot = self.slot
        if not slot then
            return
        end
        if IsModifiedClick() then
            local link = GetLootSlotLink(slot)
            if link then
                HandleModifiedItemClick(link)
            end
            return
        end
        StaticPopup_Hide("CONFIRM_LOOT_DISTRIBUTION")
        LootSlot(slot)
    end)
    button:SetScript("OnEnter", function(self)
        if not self.slot then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local slotType = GetLootSlotType(self.slot)
        if slotType == Enum.LootSlotType.Item or slotType == Enum.LootSlotType.Currency then
            GameTooltip:SetLootItem(self.slot)
        else
            GameTooltip:SetText(self.Text:GetText() or "", 1, 1, 1)
        end
        GameTooltip:Show()
        CursorUpdate(self)
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
        ResetCursor()
    end)
    button:SetScript("OnUpdate", function(self)
        CursorOnUpdate(self)
    end)
    return button
end

local function createFrame()
    frame = CreateFrame("Frame", "FCUI_LootFrame", UIParent)
    frame:SetSize(256, 256)
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -104)
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    frame.Panel = frame:CreateTexture(nil, "BACKGROUND")
    frame.Panel:SetTexture(tex("panel"))
    frame.Panel:SetAllPoints()
    ns.Dark.Tint(frame.Panel)
    -- LootFramePortraitOverlay 58x58 at TOPLEFT 10,-8
    frame.Overlay = frame:CreateTexture(nil, "ARTWORK")
    frame.Overlay:SetTexture(tex("dead"))
    frame.Overlay:SetSize(58, 58)
    frame.Overlay:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -8)
    frame.Title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    frame.Title:SetText(ITEMS or "Items")
    frame.Title:SetPoint("CENTER", frame, "CENTER", -12, 102)

    -- LootCloseButton 32x32 at CENTER of TOPRIGHT -81,-26
    local close = CreateFrame("Button", nil, frame)
    close:SetSize(32, 32)
    close:SetPoint("CENTER", frame, "TOPRIGHT", -81, -26)
    close:SetNormalTexture(tex("closeUp"))
    close:SetPushedTexture(tex("closeDown"))
    close:SetHighlightTexture(tex("closeHighlight"), "ADD")
    close:SetScript("OnClick", function()
        frame:Hide()
    end)

    frame.buttons = {}
    for i = 1, NUM_BUTTONS do
        local button = createButton(frame, i)
        if i == 1 then
            button:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -80)
        else
            button:SetPoint("TOP", frame.buttons[i - 1], "BOTTOM", 0, -4)
        end
        frame.buttons[i] = button
    end

    -- LootFrameUpButton 32x32 at BOTTOMLEFT 25,16, "Prev" text at BOTTOMLEFT 57,27
    frame.Up = CreateFrame("Button", nil, frame)
    frame.Up:SetSize(32, 32)
    frame.Up:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 25, 16)
    frame.Up:SetNormalTexture(tex("upUp"))
    frame.Up:SetPushedTexture(tex("upDown"))
    frame.Up:SetDisabledTexture(tex("upDisabled"))
    frame.Up:SetHighlightTexture(tex("mouseHighlight"), "ADD")
    frame.Up:SetScript("OnClick", function()
        page = page - 1
        Loot.Update()
    end)
    frame.PrevText = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    frame.PrevText:SetText(PREV or "Prev")
    frame.PrevText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 57, 27)
    -- LootFrameDownButton LEFT of the up button RIGHT +86, "Next" text to its left
    frame.Down = CreateFrame("Button", nil, frame)
    frame.Down:SetSize(32, 32)
    frame.Down:SetPoint("LEFT", frame.Up, "RIGHT", 86, 0)
    frame.Down:SetNormalTexture(tex("downUp"))
    frame.Down:SetPushedTexture(tex("downDown"))
    frame.Down:SetDisabledTexture(tex("downDisabled"))
    frame.Down:SetHighlightTexture(tex("mouseHighlight"), "ADD")
    frame.Down:SetScript("OnClick", function()
        page = page + 1
        Loot.Update()
    end)
    frame.NextText = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    frame.NextText:SetText(NEXT or "Next")
    frame.NextText:SetPoint("RIGHT", frame.Down, "LEFT", -2, 0)

    frame:SetScript("OnShow", function()
        numLootItems = GetNumLootItems()
        Loot.Update()
        frame.Overlay:SetTexture(tex("dead"))
        if numLootItems == 0 then
            PlaySound(SOUNDKIT.LOOT_WINDOW_OPEN_EMPTY)
        elseif IsFishingLoot and IsFishingLoot() then
            PlaySound(SOUNDKIT.FISHING_REEL_IN)
            frame.Overlay:SetTexture(tex("fishing"))
        end
    end)
    frame:SetScript("OnHide", function()
        -- LootFrame_OnHide 1.12
        CloseLoot()
        StaticPopup_Hide("LOOT_BIND")
    end)
    -- Escape closes it like a panel
    table.insert(UISpecialFrames, "FCUI_LootFrame")
end

---------------------------------------------------------------------------
-- Contents (LootFrame_Update 1.12)
---------------------------------------------------------------------------
function Loot.Update()
    if not frame or not frame:IsShown() then
        return
    end
    local perPage = itemsPerPage()
    for index = 1, NUM_BUTTONS do
        local button = frame.buttons[index]
        local slot = perPage * (page - 1) + index
        local slotType = slot <= numLootItems and GetLootSlotType(slot) or nil
        if slotType and slotType ~= Enum.LootSlotType.None and index <= perPage then
            local texture, item, quantity, currencyID, quality = GetLootSlotInfo(slot)
            if currencyID and CurrencyContainerUtil and CurrencyContainerUtil.GetCurrencyContainerInfo then
                item, texture, quantity, quality =
                    CurrencyContainerUtil.GetCurrencyContainerInfo(currencyID, quantity, item, texture, quality)
            end
            local color = ITEM_QUALITY_COLORS[quality or 1] or ITEM_QUALITY_COLORS[1]
            button.Icon:SetTexture(texture)
            button.Text:SetText(item)
            if color then
                button.Text:SetVertexColor(color.r, color.g, color.b)
            end
            if quantity and quantity > 1 then
                button.Count:SetText(quantity)
                button.Count:Show()
            else
                button.Count:Hide()
            end
            button.slot = slot
            button:Show()
        else
            button.slot = nil
            button:Hide()
        end
    end
    local shown = page > 1
    frame.Up:SetShown(shown)
    frame.PrevText:SetShown(shown)
    local lastPage = numLootItems == 0 or page >= math.ceil(numLootItems / perPage)
    frame.Down:SetShown(not lastPage)
    frame.NextText:SetShown(not lastPage)
end

local function open()
    page = 1
    if GetCVarBool("lootUnderMouse") then
        -- LootFrameMixin:Open: under the cursor, at least 350 from the bottom
        local x, y = GetCursorPosition()
        local scale = frame:GetEffectiveScale()
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale - 30, math.max(y / scale + 50, 350))
    else
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -104)
    end
    frame:Show()
    frame:Raise()
end

---------------------------------------------------------------------------
-- Module lifecycle
---------------------------------------------------------------------------
function Loot:Init()
    if not artAvailable() then
        error("Interface\\LootFrame\\UI-LootPanel is not available; run tools/import_blizzard_art.py")
    end
    createFrame()
end

function Loot:Enable()
    if LootFrame then
        ns.Hide(LootFrame)
    end
    ns.RegisterEvent("LOOT_OPENED", self, function()
        open()
        if not frame:IsVisible() then
            CloseLoot(true) -- 1.12: tell the game we could not open the window
        end
    end)
    ns.RegisterEvent("LOOT_SLOT_CLEARED", self, function(_, _, slot)
        if not frame:IsVisible() then
            return
        end
        local perPage = itemsPerPage()
        local index = slot - (page - 1) * perPage
        if index > 0 and index <= perPage then
            local button = frame.buttons[index]
            button.slot = nil
            button:Hide()
        end
        -- move to the next page when this one is empty
        local anyShown = false
        for i = 1, NUM_BUTTONS do
            if frame.buttons[i]:IsShown() then
                anyShown = true
            end
        end
        if not anyShown and frame.Down:IsShown() then
            page = page + 1
            Loot.Update()
        end
    end)
    ns.RegisterEvent("LOOT_SLOT_CHANGED", self, function()
        Loot.Update()
    end)
    ns.RegisterEvent("LOOT_CLOSED", self, function()
        StaticPopup_Hide("LOOT_BIND")
        Raw.Hide(frame)
    end)
end

function Loot:Disable()
    ns.UnregisterAllEvents(self)
    if frame then
        frame:Hide()
    end
    ns.Print("LootFrame disabled, /reload to restore the Blizzard loot window")
end

function Loot:Refresh() end

function Loot:Diag()
    ns.Print(
        "  window=%s shown=%s items=%d page=%d",
        tostring(frame ~= nil),
        tostring(frame and frame:IsShown()),
        numLootItems,
        page
    )
end
