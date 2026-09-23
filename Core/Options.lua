local _, ns = ...

-- Options window: one checkbox per module, the global scale and the bag
-- columns, in the 1.12 dialog look (UI-DialogBox-Background / -Border).
-- Opened with /fcui options (also /fcui with no argument) and listed under
-- Interface > AddOns through the Settings API. Module toggles apply at once
-- where the module supports it; a reload puts Blizzard's frames back for the
-- rest, which the window says.
local Options = {}
ns.Options = Options

-- order and player-facing names
local MODULES = {
    { key = "ActionBars", label = "Action bars, micro menu, bag buttons, XP bar" },
    { key = "UnitFrames", label = "Player, target, pet and party frames" },
    { key = "CastBar", label = "Cast bar" },
    { key = "SwingTimer", label = "Weapon swing timer" },
    { key = "Minimap", label = "Minimap" },
    { key = "Auras", label = "Buffs and debuffs" },
    { key = "Chat", label = "Chat frame" },
    { key = "Tooltip", label = "Tooltips" },
    { key = "Nameplates", label = "Classic nameplates" },
    { key = "RaidFrames", label = "Hide the modern raid frames" },
    { key = "LootFrame", label = "Loot window" },
    { key = "SpellBook", label = "Spellbook" },
    { key = "Talents", label = "Talent window" },
    { key = "Bags", label = "Bag window (all bags in one)" },
    { key = "Vendor", label = "Vendor: sell junk and repair while holding Shift" },
}

local BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

local WIDTH, ROW = 380, 24
local SLIDER_ROW = 44
local frame

local function needsReload(key)
    -- these cannot restore Blizzard's frames without a reload
    return key ~= "Nameplates" and key ~= "SwingTimer" and key ~= "Vendor"
end

local function createCheck(parent, entry, index)
    local check = CreateFrame("CheckButton", "FCUI_Option_" .. entry.key, parent, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("TOPLEFT", parent, "TOPLEFT", 24, -52 - (index - 1) * ROW)
    local text = check.Text or check.text or _G[check:GetName() .. "Text"]
    if text then
        text:SetFontObject(GameFontNormal)
        text:SetText(entry.label)
        text:ClearAllPoints()
        text:SetPoint("LEFT", check, "RIGHT", 4, 0)
    end
    check:SetScript("OnClick", function(self)
        local enabled = self:GetChecked() == true
        ns.db.modules[entry.key] = enabled
        ns.DB.Flush()
        ns.Print("%s %s (kept across reloads)", entry.key, enabled and "on" or "off")
        if enabled then
            ns.EnableModule(entry.key)
        else
            ns.DisableModule(entry.key)
        end
        if needsReload(entry.key) then
            frame.ReloadHint:Show()
        end
    end)
    return check
end

local function createSlider(parent, name, label, minValue, maxValue, step, y, get, set, format)
    local ok, slider = pcall(CreateFrame, "Slider", name, parent, "OptionsSliderTemplate")
    if not ok or not slider then
        -- the classic slider template is gone on this client: build the 1.12 look by hand
        slider = CreateFrame("Slider", name, parent, "BackdropTemplate")
        slider:SetOrientation("HORIZONTAL")
        slider:SetBackdrop({
            bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
            edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
            tile = true,
            tileSize = 8,
            edgeSize = 8,
            insets = { left = 3, right = 3, top = 6, bottom = 6 },
        })
        slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
        local low = slider:CreateFontString(name .. "Low", "ARTWORK", "GameFontHighlightSmall")
        low:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, 3)
        local high = slider:CreateFontString(name .. "High", "ARTWORK", "GameFontHighlightSmall")
        high:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", 0, 3)
        local text = slider:CreateFontString(name .. "Text", "ARTWORK", "GameFontNormal")
        text:SetPoint("BOTTOM", slider, "TOP", 0, 0)
    end
    slider:SetSize(200, 17)
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", 30, y)
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    local low, high, text = _G[name .. "Low"], _G[name .. "High"], _G[name .. "Text"]
    if low then
        low:SetText(format(minValue))
    end
    if high then
        high:SetText(format(maxValue))
    end
    slider.label = text
    slider.baseLabel = label
    slider.format = format
    slider:SetScript("OnValueChanged", function(self, value, userInput)
        if self.label then
            self.label:SetText(self.baseLabel .. ": " .. self.format(value))
        end
        if userInput then
            set(value)
        end
    end)
    slider.Refresh = function(self)
        self:SetValue(get())
        if self.label then
            self.label:SetText(self.baseLabel .. ": " .. self.format(get()))
        end
    end
    return slider
end

local function createFrame()
    frame = CreateFrame("Frame", "FCUI_OptionsFrame", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, 52 + (#MODULES + 2) * ROW + 150 + 2 * SLIDER_ROW)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop(BACKDROP)
    ns.Dark.Backdrop(frame, 1, 1, 1)
    frame:Hide()

    frame.Title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    frame.Title:SetPoint("TOP", frame, "TOP", 0, -20)
    frame.Title:SetText("Efinix Classic UI")

    frame.checks = {}
    for index, entry in ipairs(MODULES) do
        frame.checks[entry.key] = createCheck(frame, entry, index)
    end

    -- dark mode: an addon option, not a module; applies at once
    local dark = CreateFrame("CheckButton", "FCUI_Option_DarkMode", frame, "UICheckButtonTemplate")
    dark:SetSize(24, 24)
    dark:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -52 - #MODULES * ROW)
    local darkText = dark.Text or dark.text or _G[dark:GetName() .. "Text"]
    if darkText then
        darkText:SetFontObject(GameFontNormal)
        darkText:SetText("Dark mode (frame art tinted dark)")
        darkText:ClearAllPoints()
        darkText:SetPoint("LEFT", dark, "RIGHT", 4, 0)
    end
    dark:SetScript("OnClick", function(self)
        ns.Dark.Set(self:GetChecked() == true)
        ns.DB.Flush()
        ns.Print("dark mode %s (kept across reloads)", ns.Dark.Enabled() and "on" or "off")
    end)
    frame.DarkMode = dark

    local row = CreateFrame("CheckButton", "FCUI_Option_MicroMenuRow", frame, "UICheckButtonTemplate")
    row:SetSize(24, 24)
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -52 - (#MODULES + 1) * ROW)
    local rowText = row.Text or row.text or _G[row:GetName() .. "Text"]
    if rowText then
        rowText:SetFontObject(GameFontNormal)
        rowText:SetText("All menus in one micro menu row (bar grows; needs reload)")
        rowText:ClearAllPoints()
        rowText:SetPoint("LEFT", row, "RIGHT", 4, 0)
    end
    row:SetScript("OnClick", function(self)
        ns.db.microMenuRow = self:GetChecked() == true
        ns.DB.Flush()
        ns.Print("one micro menu row %s, takes effect after Save & Reload", ns.db.microMenuRow and "on" or "off")
    end)
    frame.MicroMenuRow = row

    local y = -52 - (#MODULES + 2) * ROW - 24
    frame.Scale = createSlider(frame, "FCUI_OptionScale", "Bar scale", 0.5, 2, 0.05, y, function()
        return ns.db.scale or 1
    end, function(value)
        ns.db.scale = math.floor(value * 100 + 0.5) / 100
        ns.RefreshAll()
    end, function(value)
        return ("%.2f"):format(value)
    end)
    frame.MinimapScale = createSlider(
        frame,
        "FCUI_OptionMinimapScale",
        "Minimap size",
        0.8,
        1.6,
        0.05,
        y - SLIDER_ROW,
        function()
            return ns.Minimap and ns.Minimap.Scale() or 1
        end,
        function(value)
            if ns.Minimap then
                ns.Minimap.SetScale(math.floor(value * 100 + 0.5) / 100)
            end
        end,
        function(value)
            return ("%.2f"):format(value)
        end
    )
    frame.PlateScale = createSlider(
        frame,
        "FCUI_OptionPlateScale",
        "Nameplate size",
        0.8,
        2,
        0.05,
        y - 2 * SLIDER_ROW,
        function()
            return ns.Nameplates and ns.Nameplates.Scale() or 1
        end,
        function(value)
            if ns.Nameplates then
                ns.Nameplates.SetScale(math.floor(value * 100 + 0.5) / 100)
            end
        end,
        function(value)
            return ("%.2f"):format(value)
        end
    )
    frame.Columns = createSlider(frame, "FCUI_OptionColumns", "Bag columns", 4, 20, 1, y - 3 * SLIDER_ROW, function()
        return ns.db.bags and ns.db.bags.columns or 10
    end, function(value)
        if ns.Bags then
            ns.Bags.SetColumns("inventory", math.floor(value + 0.5))
        end
    end, function(value)
        return ("%d"):format(value)
    end)

    frame.ReloadHint = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    frame.ReloadHint:SetPoint("BOTTOM", frame, "BOTTOM", 0, 52)
    frame.ReloadHint:SetText("Settings are saved on reload; some parts only switch fully after it")
    frame.ReloadHint:Hide()

    local reload = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    reload:SetSize(110, 22)
    reload:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 24, 20)
    reload:SetText("Save & Reload")
    reload:SetScript("OnClick", function()
        ns.DB.Flush()
        ReloadUI()
    end)
    local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    close:SetSize(110, 22)
    close:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -24, 20)
    close:SetText(CLOSE or "Close")
    close:SetScript("OnClick", function()
        frame:Hide()
    end)

    frame:SetScript("OnShow", Options.Refresh)
    table.insert(UISpecialFrames, "FCUI_OptionsFrame")
end

function Options.Refresh()
    if not frame then
        return
    end
    for key, check in pairs(frame.checks) do
        check:SetChecked(ns.db.modules[key] == true)
    end
    if frame.DarkMode then
        frame.DarkMode:SetChecked(ns.Dark.Enabled())
    end
    if frame.MicroMenuRow then
        frame.MicroMenuRow:SetChecked(ns.db.microMenuRow == true)
    end
    if frame.Scale then
        frame.Scale:Refresh()
    end
    for _, key in ipairs({ "MinimapScale", "PlateScale", "Columns" }) do
        if frame[key] then
            frame[key]:Refresh()
        end
    end
end

function Options.Toggle()
    if not frame then
        createFrame()
    end
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

-- Interface > AddOns entry: a small canvas with a button that opens our window
function Options.RegisterSettings()
    if not Settings or not Settings.RegisterCanvasLayoutCategory then
        return
    end
    local canvas = CreateFrame("Frame")
    local text = canvas:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    text:SetPoint("TOPLEFT", canvas, "TOPLEFT", 16, -16)
    text:SetText("Efinix Classic UI")
    local button = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
    button:SetSize(160, 22)
    button:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -12)
    button:SetText("Open options")
    button:SetScript("OnClick", Options.Toggle)
    local hint = canvas:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    hint:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -12)
    hint:SetText("Or type /fcui in the chat.")
    local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, canvas, "Efinix Classic UI")
    if ok and category and Settings.RegisterAddOnCategory then
        pcall(Settings.RegisterAddOnCategory, category)
        Options.categoryID = category:GetID()
    end
end
