local _, ns = ...

-- Action button reskin (ActionButtonTemplate.xml 1.12) and per-bar container
-- layout. Buttons keep their secure attributes and bindings; we only touch
-- textures, font strings and the unprotected container frames Blizzard uses
-- to position them. The only protected call (button SetSize) goes through
-- the combat queue.
local Raw = ns.Raw
local Assets = ns.Assets
local Combat = ns.Combat
local AB = ns.ActionBars

local Buttons = {}
AB.Buttons = Buttons

local reskinned = setmetatable({}, { __mode = "k" }) -- button -> layout info

---------------------------------------------------------------------------
-- Per-bar geometry
---------------------------------------------------------------------------
local function layoutFor(bar)
    if bar == StanceBar then
        -- BonusActionBarFrame.xml: 30x30, +7 spacing; ShapeshiftBar_Update sizes the
        -- NormalTexture 64 (50 while MultiBarBottomLeft is shown)
        return { size = AB.SMALL_BUTTON, spacing = AB.STANCE_SPACING, horizontal = true, normal = 64 }
    elseif bar == PetActionBar then
        -- PetActionBarFrame.xml: 30x30, +8 spacing, NormalTexture2 54x54
        return { size = AB.SMALL_BUTTON, spacing = AB.PET_SPACING, horizontal = true, normal = 54 }
    elseif bar == MultiBarRight or bar == MultiBarLeft then
        return { size = AB.BUTTON, spacing = AB.MULTIBAR_VERTICAL_SPACING, horizontal = false, normal = 66 }
    end
    -- ActionButtonTemplate.xml: 36x36, NormalTexture 66x66 CENTER 0,-1
    return { size = AB.BUTTON, spacing = AB.BUTTON_SPACING, horizontal = true, normal = 66 }
end

local function stanceNormalSize()
    -- UIParent_ManageFramePositions: 50 while MultiBarBottomLeft is shown, else 64
    if MultiBarBottomLeft and Raw.IsShown(MultiBarBottomLeft) then
        return 50
    end
    return 64
end

---------------------------------------------------------------------------
-- Art
---------------------------------------------------------------------------
local function applyEmptyState(button)
    -- 1.12 ActionButton_Update: UI-Quickslot2 with an action, UI-Quickslot without.
    local info = reskinned[button]
    if not info or not info.emptyTexture then
        return
    end
    local hasAction = button.action and C_ActionBar.HasAction(button.action)
    button:SetNormalTexture(hasAction and info.normalTexture or info.emptyTexture)
    local normal = button:GetNormalTexture()
    normal:ClearAllPoints()
    normal:SetPoint("CENTER", button, "CENTER", 0, -1)
    normal:SetSize(info.normal, info.normal)
end

local function applyHotkey(button)
    -- ActionButtonTemplate.xml: HotKey 36x10 TOPLEFT -2,-2 justifyH RIGHT
    local info = reskinned[button]
    local hotkey = button.HotKey
    if not info or not hotkey then
        return
    end
    hotkey:ClearAllPoints()
    hotkey:SetPoint("TOPLEFT", button, "TOPLEFT", -2, -2)
    hotkey:SetSize(info.size, 10)
    hotkey:SetJustifyH("RIGHT")
end

function Buttons.ApplyArt(button)
    local info = reskinned[button]
    if not info then
        return
    end
    local size = info.size
    local normalSize = info.normal
    if info.bar == StanceBar then
        normalSize = stanceNormalSize()
    end

    -- NormalTexture: UI-Quickslot2, CENTER 0,-1, 66x66 (54 pet, 64/50 stance)
    local normalPath = Assets.Get("Button.Normal")
    if normalPath then
        button:SetNormalTexture(normalPath)
        local normal = button:GetNormalTexture()
        normal:ClearAllPoints()
        normal:SetPoint("CENTER", button, "CENTER", 0, -1)
        normal:SetSize(normalSize, normalSize)
        normal:SetDrawLayer("OVERLAY")
        info.normalTexture = normalPath
        info.normal = normalSize
        info.emptyTexture = Assets.Get("Button.Empty")
        applyEmptyState(button)
    end

    -- Modern slot art under the icon
    if button.SlotBackground then
        button.SlotBackground:Hide()
    end
    if button.SlotArt then
        button.SlotArt:Hide()
    end

    -- PushedTexture: UI-Quickslot-Depress filling the button
    local pushed = Assets.Get("Button.Pushed")
    if pushed then
        button:SetPushedTexture(pushed)
        local tex = button:GetPushedTexture()
        tex:ClearAllPoints()
        tex:SetAllPoints(button)
        tex:SetDrawLayer("OVERLAY")
    end

    -- HighlightTexture: ButtonHilight-Square ADD
    local highlight = Assets.Get("Button.Highlight")
    if highlight then
        button:SetHighlightTexture(highlight, "ADD")
        local tex = button:GetHighlightTexture()
        tex:ClearAllPoints()
        tex:SetAllPoints(button)
    end

    -- CheckedTexture: CheckButtonHilight ADD
    local checked = Assets.Get("Button.Checked")
    if checked and button.SetCheckedTexture then
        button:SetCheckedTexture(checked)
        local tex = button:GetCheckedTexture()
        if tex then
            tex:SetBlendMode("ADD")
            tex:ClearAllPoints()
            tex:SetAllPoints(button)
        end
    end

    -- Icon fills the button; drop the rounded-corner mask
    local icon = button.icon
    if icon then
        icon:ClearAllPoints()
        icon:SetAllPoints(button)
        if button.IconMask and icon.RemoveMaskTexture then
            pcall(icon.RemoveMaskTexture, icon, button.IconMask)
        end
    end

    -- Flash: UI-QuickslotRed filling the button
    if button.Flash then
        local flash = Assets.Get("Button.Flash")
        if flash then
            button.Flash:SetTexture(flash)
        end
        button.Flash:ClearAllPoints()
        button.Flash:SetAllPoints(button)
    end

    -- Border (equipped item): UI-ActionButton-Border 62x62 CENTER ADD
    if button.Border then
        local border = Assets.Get("Button.Border")
        button.Border:ClearAllPoints()
        button.Border:SetPoint("CENTER", button, "CENTER", 0, 0)
        if border then
            button.Border:SetTexture(border)
            button.Border:SetBlendMode("ADD")
            button.Border:SetSize(62 * size / AB.BUTTON, 62 * size / AB.BUTTON)
        else
            button.Border:SetSize(size + 2, size + 2)
        end
    end

    applyHotkey(button)

    -- Count: BOTTOMRIGHT -2,2
    if button.Count then
        button.Count:ClearAllPoints()
        button.Count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    end

    -- Name: 36x10 BOTTOM 0,2
    if button.Name then
        button.Name:ClearAllPoints()
        button.Name:SetPoint("BOTTOM", button, "BOTTOM", 0, 2)
        button.Name:SetSize(size, 10)
    end

    -- Cooldown: 36x36 CENTER 0,-1
    if button.cooldown then
        button.cooldown:ClearAllPoints()
        button.cooldown:SetPoint("CENTER", button, "CENTER", 0, -1)
        button.cooldown:SetSize(size, size)
    end
    for _, key in ipairs({ "chargeCooldown", "lossOfControlCooldown" }) do
        local cd = button[key]
        if cd and icon then
            cd:ClearAllPoints()
            cd:SetAllPoints(icon)
        end
    end

    -- Modern overlays sized to the atlas; shrink them to the button
    for _, key in ipairs({ "NewActionTexture", "SpellHighlightTexture", "QuickKeybindHighlightTexture" }) do
        local tex = button[key]
        if tex then
            tex:ClearAllPoints()
            tex:SetPoint("CENTER", button, "CENTER", 0, 0)
            tex:SetSize(size, size)
        end
    end
end

local function applySize(button)
    local info = reskinned[button]
    if not info then
        return
    end
    local size = info.size
    Combat.Run("buttonsize:" .. tostring(button:GetName() or button), function()
        Raw.SetSize(button, size, size)
    end)
    local container = button.container
    if container then
        Raw.SetSize(container, size, size)
        Raw.SetScale(container, 1)
    end
end

function Buttons.Reskin(button, bar, layout)
    if reskinned[button] then
        return
    end
    reskinned[button] = {
        bar = bar,
        size = layout.size,
        normal = layout.normal,
    }
    Buttons.ApplyArt(button)
    applySize(button)

    -- Blizzard re-applies atlases in UpdateButtonArt (Edit Mode HideBarArt changes),
    -- re-anchors the hotkey in UpdateHotkeys (UPDATE_BINDINGS) and refreshes the
    -- slot in Update. Post-hooks restore the Vanilla look each time.
    AB.Hook(button, "UpdateButtonArt", Buttons.ApplyArt)
    AB.Hook(button, "UpdateHotkeys", applyHotkey)
    AB.Hook(button, "Update", applyEmptyState)
end

---------------------------------------------------------------------------
-- Container layout: Blizzard anchors every button to the CENTER of its own
-- container frame and lays the containers out with GridLayoutUtil. We
-- re-anchor the containers (plain frames, safe in combat) to the Vanilla
-- stride and resize the bar to the Vanilla footprint.
---------------------------------------------------------------------------
function Buttons.LayoutBar(bar)
    local layout = layoutFor(bar)
    local stride = layout.size + layout.spacing
    local shownCount = 0
    for i, button in ipairs(bar.actionButtons or {}) do
        local container = button.container
        if container then
            Raw.SetSize(container, layout.size, layout.size)
            Raw.SetScale(container, 1)
            Raw.ClearAllPoints(container)
            if layout.horizontal then
                Raw.SetPoint(container, "BOTTOMLEFT", bar, "BOTTOMLEFT", (i - 1) * stride, 0)
            else
                -- MultiActionBars.xml: first button at TOPRIGHT, each next below the previous
                Raw.SetPoint(container, "TOPRIGHT", bar, "TOPRIGHT", 0, -(i - 1) * stride)
            end
            if Raw.IsShown(container) then
                shownCount = shownCount + 1
            end
        end
        if bar == StanceBar then
            Buttons.ApplyArt(button)
        end
    end
    local count = math.max(shownCount, 1)
    local length = count * stride - layout.spacing
    if layout.horizontal then
        Raw.SetSize(bar, length, layout.size)
    else
        Raw.SetSize(bar, layout.size, length)
    end
end

---------------------------------------------------------------------------
-- Button anchors. Every button is anchored to the bar art (or UIParent)
-- itself, never to its Blizzard bar. Edit Mode re-stacks the bottom bars
-- in combat whenever the button grid shows (dragging anything) or a bar's
-- visibility changes (EditModeActionBarMixin:UpdateVisibility ->
-- UpdateBottomActionBarPositions, offsets 22 and 606 from the main bar);
-- we may not anchor those bars back until the fight ends. Blizzard only
-- ever anchors a button once, to its container's CENTER at load
-- (ActionBar.lua ActionBar_OnLoad), so a button anchored elsewhere stays
-- put while its container moves. Buttons are protected: the anchors are
-- applied out of combat and queued otherwise.
---------------------------------------------------------------------------
local anchors = setmetatable({}, { __mode = "k" }) -- bar -> anchor

local function applyAnchors(bar)
    local anchor = anchors[bar]
    if not anchor then
        return
    end
    local layout = layoutFor(bar)
    local stride = layout.size + layout.spacing
    for i, button in ipairs(bar.actionButtons or {}) do
        Raw.ClearAllPoints(button)
        if layout.horizontal then
            Raw.SetPoint(
                button,
                anchor.point,
                anchor.relativeTo,
                anchor.relativePoint,
                anchor.x + (i - 1) * stride,
                anchor.y
            )
        else
            Raw.SetPoint(
                button,
                anchor.point,
                anchor.relativeTo,
                anchor.relativePoint,
                anchor.x,
                anchor.y - (i - 1) * stride
            )
        end
    end
end

-- point/x/y describe the first button; horizontal bars grow to the right
-- of it, vertical bars downwards, in the bar's 1.12 stride.
function Buttons.Anchor(bar, point, relativeTo, relativePoint, x, y)
    if not bar or not relativeTo then
        return
    end
    anchors[bar] = { point = point, relativeTo = relativeTo, relativePoint = relativePoint, x = x, y = y }
    Combat.Run("buttonanchor:" .. tostring(bar:GetName() or bar), function()
        applyAnchors(bar)
    end)
end

function Buttons.Anchored(bar)
    local button = bar and bar.actionButtons and bar.actionButtons[1]
    local anchor = anchors[bar]
    if not button or not anchor then
        return false
    end
    local _, relativeTo = button:GetPoint(1)
    return relativeTo == anchor.relativeTo
end

function Buttons.SetupBar(bar)
    local layout = layoutFor(bar)
    for _, button in ipairs(bar.actionButtons or {}) do
        Buttons.Reskin(button, bar, layout)
    end
    Buttons.LayoutBar(bar)
    local relayout = function()
        Buttons.LayoutBar(bar)
    end
    -- UpdateGridLayout: Blizzard's own layout pass (settings, stance count changes).
    -- Layout: ResizeLayoutFrame recomputing the bar size.
    -- UpdateSystemSettingIconSize: Edit Mode scaling the containers.
    AB.Hook(bar, "UpdateGridLayout", relayout)
    AB.Hook(bar, "Layout", relayout)
    AB.Hook(bar, "UpdateSystemSettingIconSize", relayout)
end
