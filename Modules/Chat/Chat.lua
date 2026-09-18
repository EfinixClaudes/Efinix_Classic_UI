local _, ns = ...

-- Chat module: Forever's floating chat frames reskinned to 1.12
-- (FloatingChatFrame.xml / FloatingChatFrame.lua / ChatFrame.xml 1.12).
--
-- 1.12: ChatFrame1 430x120 at BOTTOMLEFT 32, chatOffset (85, +15 with a
-- bottom-left bar or pet/stance bar, +55 with both); tabs 64x32 from the
-- ChatFrameTab sheet, invisible until the mouse is over the frame (1.0
-- selected, 0.5 others); a column of 32x32 buttons left of the frame:
-- scroll-to-end at BOTTOMLEFT -32,-4, scroll down, scroll up, chat menu;
-- edit box 32 high below the frame with UI-ChatInputBorder-Left/Right.
--
-- Chat frames are not protected. Messages, filters and the edit box logic
-- stay Blizzard's; we re-anchor, retexture and hide what 1.12 lacked.
local Raw = ns.Raw

local Chat = ns.RegisterModule("Chat", {})
ns.Chat = Chat

local NUM_CHAT_WINDOWS = 10 -- FloatingChatFrame.xml: ChatFrame1..10
local CHAT_OFFSET_BASE = 85 -- FCF_UpdateDockPosition 1.12
local CHAT_OFFSET_BAR = 15 -- one of bottom-left bar / pet bar shown
local CHAT_OFFSET_BOTH = 55 -- bottom-left bar and a pet/stance bar
local TAB_SELECTED_ALPHA = 1.0 -- FCF_OnUpdate 1.12: UIFrameFadeIn(chatTab) to 1
local TAB_NORMAL_ALPHA = 0.5 -- ...or 0.5 for unselected docked tabs
local SCROLL_UPDATE_SECONDS = 0.1

local hooked = {}
local function hook(target, method, fn)
    if not target or type(target[method]) ~= "function" then
        return
    end
    local key = tostring(target) .. ":" .. method
    if hooked[key] then
        return
    end
    hooked[key] = true
    hooksecurefunc(target, method, fn)
end

local function hookGlobal(name, fn)
    if type(_G[name]) ~= "function" or hooked[name] then
        return
    end
    hooked[name] = true
    hooksecurefunc(name, fn)
end

local function hideTexture(region)
    if region then
        region:Hide()
        hook(region, "Show", function(self)
            self:Hide()
        end)
    end
end

local function shown(frame)
    return frame and Raw.IsShown(frame) or false
end

---------------------------------------------------------------------------
-- Position (FCF_UpdateDockPosition 1.12). Only while ChatFrame1 sits in its
-- Edit Mode default position; a player-moved frame is respected, as
-- IsUserPlaced() was in 1.12.
---------------------------------------------------------------------------
local function chatOffset()
    local bottomLeft = shown(MultiBarBottomLeft)
    local pet = (GetNumShapeshiftForms and GetNumShapeshiftForms() or 0) > 0
        or (HasPetUI and HasPetUI())
        or (PetHasActionBar and PetHasActionBar())
    local offset = CHAT_OFFSET_BASE
    if pet and bottomLeft then
        offset = offset + CHAT_OFFSET_BOTH
    elseif pet or bottomLeft then
        offset = offset + CHAT_OFFSET_BAR
    end
    return offset
end

local function inDefaultPosition(frame)
    if type(frame.IsInDefaultPosition) ~= "function" then
        return true
    end
    local ok, result = pcall(frame.IsInDefaultPosition, frame)
    return ok and result ~= false
end

local positioning = false
function Chat.Position()
    local frame = ChatFrame1
    if positioning or Chat.state ~= "enabled" or not frame then
        return
    end
    positioning = true
    if inDefaultPosition(frame) then
        Raw.ClearAllPoints(frame)
        -- FCF_UpdateDockPosition 1.12: SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 32, chatOffset)
        Raw.SetPoint(frame, "BOTTOMLEFT", UIParent, "BOTTOMLEFT", 32, chatOffset())
    end
    Chat.UpdateButtonSide()
    positioning = false
end

---------------------------------------------------------------------------
-- Frame chrome: 1.12 ChatFrameBorder pieces around the background, faded
-- with the window alpha like Blizzard's own border textures.
---------------------------------------------------------------------------
-- ChatFrameBorder sheet coords (FloatingChatFrameTemplate 1.12 resize buttons)
local BORDER_PIECES = {
    { key = "TopLeft", point = "TOPLEFT", x = -2, y = 2, coords = { 0, 0.25, 0, 0.125 } },
    { key = "TopRight", point = "TOPRIGHT", x = 2, y = 2, coords = { 0.75, 1, 0, 0.125 } },
    { key = "BottomLeft", point = "BOTTOMLEFT", x = -2, y = -3, coords = { 0, 0.25, 0.7265625, 0.8515625 } },
    { key = "BottomRight", point = "BOTTOMRIGHT", x = 2, y = -3, coords = { 0.75, 1, 0.7265625, 0.8515625 } },
}

local borders = {} -- chatFrame -> our border frame

local function createBorder(chatFrame)
    local tex = ns.Assets.Get("Chat.Border")
    if not tex or borders[chatFrame] then
        return
    end
    local background = _G[chatFrame:GetName() .. "Background"]
    if not background then
        return
    end
    local frame = CreateFrame("Frame", nil, chatFrame)
    frame:SetAllPoints(background)
    frame:SetFrameLevel(chatFrame:GetFrameLevel())
    local pieces = {}
    for _, piece in ipairs(BORDER_PIECES) do
        local corner = frame:CreateTexture(nil, "BORDER")
        corner:SetTexture(tex)
        corner:SetSize(16, 16)
        corner:SetPoint(piece.point, background, piece.point, piece.x, piece.y)
        corner:SetTexCoord(unpack(piece.coords))
        pieces[piece.key] = corner
    end
    -- edges stretch between the corners; the sheet's edge strips are 16 px wide
    local top = frame:CreateTexture(nil, "BORDER")
    top:SetTexture(tex)
    top:SetHeight(16)
    top:SetPoint("LEFT", pieces.TopLeft, "RIGHT")
    top:SetPoint("RIGHT", pieces.TopRight, "LEFT")
    top:SetTexCoord(0.25, 0.75, 0, 0.125)
    local bottom = frame:CreateTexture(nil, "BORDER")
    bottom:SetTexture(tex)
    bottom:SetHeight(16)
    bottom:SetPoint("LEFT", pieces.BottomLeft, "RIGHT")
    bottom:SetPoint("RIGHT", pieces.BottomRight, "LEFT")
    bottom:SetTexCoord(0.25, 0.75, 0.7265625, 0.8515625)
    local left = frame:CreateTexture(nil, "BORDER")
    left:SetTexture(tex)
    left:SetWidth(16)
    left:SetPoint("TOP", pieces.TopLeft, "BOTTOM")
    left:SetPoint("BOTTOM", pieces.BottomLeft, "TOP")
    left:SetTexCoord(0, 0.25, 0.125, 0.7265625)
    local right = frame:CreateTexture(nil, "BORDER")
    right:SetTexture(tex)
    right:SetWidth(16)
    right:SetPoint("TOP", pieces.TopRight, "BOTTOM")
    right:SetPoint("BOTTOM", pieces.BottomRight, "TOP")
    right:SetTexCoord(0.75, 1, 0.125, 0.7265625)
    for _, piece in pairs(pieces) do
        ns.Dark.Tint(piece)
    end
    ns.Dark.Tint(top)
    ns.Dark.Tint(bottom)
    ns.Dark.Tint(left)
    ns.Dark.Tint(right)
    borders[chatFrame] = frame
end

local function syncBorderAlpha(chatFrame)
    local frame = borders[chatFrame]
    local background = _G[chatFrame:GetName() .. "Background"]
    if frame and background then
        frame:SetAlpha(background:GetAlpha())
    end
end

-- Blizzard's WotLK-style corner/edge textures (FloatingBorderedFrame)
local MODERN_BORDER_KEYS = {
    "TopLeftTexture",
    "BottomLeftTexture",
    "TopRightTexture",
    "BottomRightTexture",
    "LeftTexture",
    "RightTexture",
    "BottomTexture",
    "TopTexture",
}

local function styleFrame(chatFrame)
    local name = chatFrame:GetName()
    for _, key in ipairs(MODERN_BORDER_KEYS) do
        hideTexture(_G[name .. key])
    end
    createBorder(chatFrame)
    syncBorderAlpha(chatFrame)
    -- 1.12 had no scrollbar, no size grabber and no scroll-to-bottom flash button
    if chatFrame.ScrollBar then
        ns.Suppress(chatFrame.ScrollBar)
    end
    if chatFrame.ScrollToBottomButton then
        ns.Suppress(chatFrame.ScrollToBottomButton)
    end
    if chatFrame.ResizeButton then
        ns.Suppress(chatFrame.ResizeButton)
    end
    -- the modern side panel (minimize, voice, TTS); ChatFrameMenuButton is moved out of it below
    if chatFrame.buttonFrame then
        ns.Suppress(chatFrame.buttonFrame)
    end
end

---------------------------------------------------------------------------
-- Tabs (ChatTabTemplate 1.12): ChatFrameTab sheet, left 0-0.25, middle
-- 0.25-0.75, right 0.75-1; no selected/highlight glow art.
---------------------------------------------------------------------------
local function styleTab(tab)
    if not tab or hooked[tab] then
        return
    end
    hooked[tab] = true
    local sheet = ns.Assets.Get("Chat.Tab")
    if sheet then
        if tab.Left then
            tab.Left:SetTexture(sheet)
            tab.Left:SetTexCoord(0, 0.25, 0, 1)
        end
        if tab.Middle then
            tab.Middle:SetTexture(sheet)
            tab.Middle:SetHorizTile(false)
            tab.Middle:SetTexCoord(0.25, 0.75, 0, 1)
        end
        if tab.Right then
            tab.Right:SetTexture(sheet)
            tab.Right:SetTexCoord(0.75, 1, 0, 1)
        end
    end
    for _, key in ipairs({
        "ActiveLeft",
        "ActiveMiddle",
        "ActiveRight",
        "HighlightLeft",
        "HighlightMiddle",
        "HighlightRight",
        "glow",
    }) do
        hideTexture(tab[key])
    end
    if tab.conversationIcon then
        tab.conversationIcon:Hide()
    end
    local highlight = ns.Assets.Get("Chat.TabHighlight")
    if highlight then
        -- ChatTabTemplate 1.12 HighlightTexture: UI-Character-Tab-Highlight, ADD, LEFT/RIGHT of the art, -7
        tab:SetHighlightTexture(highlight, "ADD")
        local region = tab:GetHighlightTexture()
        if region and tab.Left and tab.Right then
            region:ClearAllPoints()
            region:SetPoint("LEFT", tab.Left, "LEFT", 0, -7)
            region:SetPoint("RIGHT", tab.Right, "RIGHT", 0, -7)
            region:SetHeight(32)
        end
    end
end

local function resetTabColors(tab)
    if not tab or not hooked[tab] then
        return
    end
    for _, key in ipairs({ "Left", "Middle", "Right" }) do
        if tab[key] then
            ns.Dark.Tint(tab[key], 1, 1, 1)
        end
    end
    for _, key in ipairs({ "ActiveLeft", "ActiveMiddle", "ActiveRight" }) do
        if tab[key] then
            tab[key]:Hide()
        end
    end
end

-- 1.12 tabs were hidden until the mouse hovered the frame; Blizzard keeps
-- them at 0.4 / 0.2. SetTabAlphas is Blizzard's own accessor for the alpha
-- table its fades read from.
local function resetTabAlpha(chatFrame)
    local tab = _G[chatFrame:GetName() .. "Tab"]
    if not tab or not hooked[tab] or not ChatFrameUtil or type(ChatFrameUtil.SetTabAlphas) ~= "function" then
        return
    end
    local selected = not chatFrame.isDocked
        or (
            FCFDock_GetSelectedWindow
            and GENERAL_CHAT_DOCK
            and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK) == chatFrame
        )
    local mouseOver = selected and TAB_SELECTED_ALPHA or TAB_NORMAL_ALPHA
    ChatFrameUtil.SetTabAlphas(tab, mouseOver, 0)
    if chatFrame.hasBeenFaded then
        tab:SetAlpha(mouseOver)
    else
        tab:SetAlpha(0)
    end
end

---------------------------------------------------------------------------
-- Edit box (ChatFrameEditBoxTemplate 1.12): UI-ChatInputBorder-Left 256x32
-- at LEFT, UI-ChatInputBorder-Right 16x32 at RIGHT (coords 0.9375-1), the
-- rest of the right file stretched between them.
---------------------------------------------------------------------------
local function styleEditBox(editBox)
    if not editBox or hooked[editBox] then
        return
    end
    hooked[editBox] = true
    local name = editBox:GetName()
    local left = ns.Assets.Get("Chat.InputLeft")
    local right = ns.Assets.Get("Chat.InputRight")
    local leftTex, rightTex, midTex = _G[name .. "Left"], _G[name .. "Right"], _G[name .. "Mid"]
    if left and leftTex then
        leftTex:SetTexture(left)
        leftTex:SetTexCoord(0, 1, 0, 1)
        leftTex:SetSize(256, 32)
        ns.Dark.Tint(leftTex)
    end
    if right and rightTex then
        rightTex:SetTexture(right)
        rightTex:SetTexCoord(0.9375, 1, 0, 1)
        rightTex:SetSize(16, 32)
        ns.Dark.Tint(rightTex)
    end
    if right and midTex then
        ns.Dark.Tint(midTex)
        midTex:SetTexture(right)
        midTex:SetHorizTile(false)
        midTex:SetTexCoord(0, 0.9375, 0, 1)
    end
    -- focus glow art (WotLK) has no 1.12 counterpart
    hideTexture(editBox.focusLeft)
    hideTexture(editBox.focusMid)
    hideTexture(editBox.focusRight)
    if editBox.header then
        editBox.header:ClearAllPoints()
        editBox.header:SetPoint("LEFT", editBox, "LEFT", 13, 0) -- $parentHeader LEFT 13,0
    end
end

---------------------------------------------------------------------------
-- Button column (FloatingChatFrameTemplate 1.12): scroll-to-end, down, up,
-- then ChatFrameMenuButton, 32x32 each, left of the frame (or right when
-- the frame sits on the right half of the screen).
---------------------------------------------------------------------------
local function createScrollButton(parent, key, up, down, disabled, onClick)
    local button = CreateFrame("Button", "FCUI_ChatFrame1" .. key, parent)
    button:SetSize(32, 32)
    local upTex, downTex, disabledTex = ns.Assets.Get(up), ns.Assets.Get(down), ns.Assets.Get(disabled)
    if upTex then
        button:SetNormalTexture(upTex)
    end
    if downTex then
        button:SetPushedTexture(downTex)
    end
    if disabledTex then
        button:SetDisabledTexture(disabledTex)
    end
    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    button:SetScript("OnClick", onClick)
    return button
end

local function createButtons()
    if Chat.buttons or not ChatFrame1 then
        return
    end
    local chatFrame = ChatFrame1
    local column = CreateFrame("Frame", "FCUI_ChatButtons", chatFrame)
    column:SetSize(32, 128)
    column:SetFrameStrata("LOW")

    column.Bottom = createScrollButton(
        column,
        "BottomButton",
        "Chat.ScrollEndUp",
        "Chat.ScrollEndDown",
        "Chat.ScrollEndDisabled",
        function()
            chatFrame:ScrollToBottom()
        end
    )
    column.Bottom:SetPoint("BOTTOMLEFT", column, "BOTTOMLEFT", 0, 0)
    local flash = ns.Assets.Get("Chat.ScrollFlash")
    if flash then
        column.Flash = column.Bottom:CreateTexture(nil, "OVERLAY")
        column.Flash:SetTexture(flash)
        column.Flash:SetAllPoints()
        column.Flash:Hide()
    end

    column.Down = createScrollButton(
        column,
        "DownButton",
        "Chat.ScrollDownUp",
        "Chat.ScrollDownDown",
        "Chat.ScrollDownDisabled",
        function()
            if IsShiftKeyDown() then
                chatFrame:ScrollToBottom()
            else
                chatFrame:ScrollDown()
            end
            PlaySound(SOUNDKIT.IG_CHAT_SCROLL_DOWN)
        end
    )
    column.Down:SetPoint("BOTTOM", column.Bottom, "TOP", 0, -2) -- $parentDownButton BOTTOM of BottomButton TOP 0,-2

    column.Up = createScrollButton(
        column,
        "UpButton",
        "Chat.ScrollUpUp",
        "Chat.ScrollUpDown",
        "Chat.ScrollUpDisabled",
        function()
            if IsShiftKeyDown() then
                chatFrame:ScrollToTop()
            else
                chatFrame:ScrollUp()
            end
            PlaySound(SOUNDKIT.IG_CHAT_SCROLL_UP)
        end
    )
    column.Up:SetPoint("BOTTOM", column.Down, "TOP", 0, 0)

    -- ChatFrameMenuButton 1.12: BOTTOM of ChatFrame1UpButton TOP
    if ChatFrameMenuButton then
        Raw.SetParent(ChatFrameMenuButton, column)
        Raw.ClearAllPoints(ChatFrameMenuButton)
        Raw.SetPoint(ChatFrameMenuButton, "BOTTOM", column.Up, "TOP", 0, 0)
        Raw.SetSize(ChatFrameMenuButton, 32, 32)
        Raw.SetAlpha(ChatFrameMenuButton, 1)
        Raw.Show(ChatFrameMenuButton)
    end

    -- MessageFrameScrollButton_OnUpdate 1.12: disable at the ends, flash the end button on new lines
    column.elapsed = 0
    column:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed < SCROLL_UPDATE_SECONDS then
            return
        end
        self.elapsed = 0
        local atTop = chatFrame:AtTop()
        local atBottom = chatFrame:AtBottom()
        self.Up:SetEnabled(not atTop)
        self.Down:SetEnabled(not atBottom)
        self.Bottom:SetEnabled(not atBottom)
        if atBottom and self.Flash then
            self.Flash:Hide()
        end
    end)
    hook(chatFrame, "AddMessage", function()
        if column.Flash and not chatFrame:AtBottom() then
            column.Flash:Show()
        end
    end)
    Chat.buttons = column
end

-- FCF_UpdateButtonSide 1.12: buttons go on the side with more room
function Chat.UpdateButtonSide()
    local column = Chat.buttons
    local chatFrame = ChatFrame1
    if not column or not chatFrame then
        return
    end
    local left = chatFrame:GetLeft() or 0
    local right = GetScreenWidth() - (chatFrame:GetRight() or 0)
    column:ClearAllPoints()
    if (left > 0 and left <= right) or right < 0 then
        -- FCF_SetButtonSide "left": BottomButton BOTTOMLEFT of chatFrame BOTTOMLEFT -32,-4
        column:SetPoint("BOTTOMLEFT", chatFrame, "BOTTOMLEFT", -32, -4)
    else
        column:SetPoint("BOTTOMLEFT", chatFrame, "BOTTOMRIGHT", 0, -4)
    end
end

---------------------------------------------------------------------------
-- Apply to every window
---------------------------------------------------------------------------
local function styleAll()
    for i = 1, NUM_CHAT_WINDOWS do
        local chatFrame = _G["ChatFrame" .. i]
        if chatFrame then
            styleFrame(chatFrame)
            styleTab(_G["ChatFrame" .. i .. "Tab"])
            styleEditBox(chatFrame.editBox or _G["ChatFrame" .. i .. "EditBox"])
        end
    end
end

---------------------------------------------------------------------------
-- Module lifecycle
---------------------------------------------------------------------------
function Chat:Init()
    if not ChatFrame1 then
        error("ChatFrame1 not found; this client does not match docs/CLIENT_FACTS.md")
    end
end

function Chat:Enable()
    styleAll()
    createButtons()

    -- Systems 1.12 did not have next to the chat frame
    for _, name in ipairs({
        "ChatFrameToggleVoiceDeafenButton",
        "ChatFrameToggleVoiceMuteButton",
        "QuickJoinToastButton",
    }) do
        if _G[name] then
            ns.Suppress(_G[name])
        end
    end

    -- Blizzard passes that restore its own look
    hookGlobal("FCFTab_UpdateColors", resetTabColors)
    hookGlobal("FCFTab_UpdateAlpha", resetTabAlpha)
    hookGlobal("FCF_SetWindowAlpha", syncBorderAlpha)
    hookGlobal("FCF_FadeInChatFrame", function(chatFrame)
        local frame = borders[chatFrame]
        if frame then
            frame:SetAlpha(math.max(chatFrame.oldAlpha or 0, DEFAULT_CHATFRAME_ALPHA or 0.25))
        end
    end)
    hookGlobal("FCF_FadeOutChatFrame", function(chatFrame)
        local frame = borders[chatFrame]
        if frame then
            frame:SetAlpha(chatFrame.oldAlpha or DEFAULT_CHATFRAME_ALPHA or 0.25)
        end
    end)
    hookGlobal("FCF_OpenTemporaryWindow", styleAll)
    hookGlobal("FCF_OpenNewWindow", styleAll)
    hookGlobal("FCF_SetButtonSide", Chat.UpdateButtonSide)
    hookGlobal("FCF_UpdateButtonSide", Chat.UpdateButtonSide)
    hook(ChatFrame1, "ApplySystemAnchor", Chat.Position)
    hook(ChatFrame1, "UpdateSystemSettingWidth", Chat.UpdateButtonSide)
    hook(ChatFrame1, "UpdateSystemSettingHeight", Chat.UpdateButtonSide)
    hook(ChatFrame1, "SetPoint", Chat.UpdateButtonSide)

    ns.RegisterEvent("PLAYER_ENTERING_WORLD", self, function()
        styleAll()
        Chat.Position()
    end)
    ns.RegisterEvent("UPDATE_CHAT_WINDOWS", self, styleAll)
    ns.RegisterEvent("UPDATE_SHAPESHIFT_FORMS", self, Chat.Position)
    ns.RegisterEvent("PET_BAR_UPDATE", self, Chat.Position)
    ns.RegisterEvent("UNIT_PET", self, Chat.Position)

    Chat.Position()
end

function Chat:Disable()
    ns.UnregisterAllEvents(self)
    if Chat.buttons then
        Chat.buttons:Hide()
    end
    ns.Print("Chat disabled, /reload to restore the Blizzard chat frame")
end

function Chat:Refresh()
    Chat.Position()
end

function Chat:Diag()
    if not ChatFrame1 then
        ns.Print("ChatFrame1 missing")
        return
    end
    local point, relativeTo, relativePoint, x, y = ChatFrame1:GetPoint(1)
    ns.Print(
        "  ChatFrame1 %s -> %s %s (%.1f, %.1f) size %.0fx%.0f default=%s offset %d",
        tostring(point),
        tostring(relativeTo and relativeTo:GetName()),
        tostring(relativePoint),
        x or 0,
        y or 0,
        ChatFrame1:GetWidth(),
        ChatFrame1:GetHeight(),
        tostring(inDefaultPosition(ChatFrame1)),
        chatOffset()
    )
    ns.Print("  buttons=%s border=%s", tostring(Chat.buttons ~= nil), tostring(borders[ChatFrame1] ~= nil))
end
