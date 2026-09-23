local _, ns = ...

-- ActionBars module: main bar art, gryphons, page arrows, XP/rep bar, micro
-- menu, bag bar, multi bars, stance bar and pet bar, all reskinned in place.
-- Strategy and reasoning: docs/adr/0002-actionbars-reskin-in-place.md.
--
-- Every number below comes from the 1.12 FrameXML in reference/vanilla/1.12
-- and is cited at the point of use.
local Raw = ns.Raw
local Combat = ns.Combat

local AB = ns.RegisterModule("ActionBars", {})
ns.ActionBars = AB

-- Layout constants (1.12 FrameXML)
AB.BAR_WIDTH = 1024 -- MainMenuBar.xml: MainMenuBar 1024x53
-- All menus in one micro menu row: the bar grows by the eight Forever-only
-- micro buttons (29 px overlapping 3, MainMenuBarMicroButtons.xml) so the
-- row and the bag buttons keep their 1.12 spacing. Set at MainBar.Create.
AB.MICRO_EXTRA = 8 * 26
AB.extraWidth = 0
function AB.BarWidth()
    return AB.BAR_WIDTH + (AB.extraWidth or 0)
end
AB.BAR_HEIGHT = 53
AB.BUTTON = 36 -- ActionButtonTemplate.xml: 36x36
AB.BUTTON_SPACING = 6 -- ActionBarFrame.xml: ActionButton2 LEFT of ActionButton1 RIGHT +6
AB.SMALL_BUTTON = 30 -- BonusActionBarFrame.xml ShapeshiftButtonTemplate / PetActionButtonTemplate 30x30
AB.STANCE_SPACING = 7 -- BonusActionBarFrame.xml: ShapeshiftButton2 LEFT +7
AB.PET_SPACING = 8 -- PetActionBarFrame.xml: PetActionButton2 LEFT +8
AB.MULTIBAR_VERTICAL_SPACING = 6 -- MultiActionBars.xml: $parentButton2 TOP of $parentButton1 BOTTOM -6
local MULTIBAR_LENGTH = 500 -- MultiActionBars.xml: HorizontalMultiBar 500x38, VerticalMultiBar 38x500
local MULTIBAR_THICKNESS = 38

-- 1.12 UIParent.lua UIPARENT_MANAGED_FRAME_POSITIONS offsets
local OFFSET_REPUTATION = 9 -- "reputation = 9": XP bar and rep watch bar both shown
local OFFSET_MAXLEVEL = -5 -- "maxLevel = -5": max level trim shown instead of XP bar
local OFFSET_STANCE_BOTTOMLEFT = 45 -- ShapeshiftBarFrame "bottomLeft = 45"
local OFFSET_PET_BOTTOMLEFT = 43 -- PETACTIONBAR_YPOS "bottomLeft = 43"
local PETACTIONBAR_YPOS = 97 -- PETACTIONBAR_YPOS "baseY = 97"
local PETACTIONBAR_XPOS = 36 -- PetActionBarFrame.lua: PETACTIONBAR_XPOS = 36

AB.hooked = {} -- frame -> true, so hooks are installed once

-- Bars we manage. Resolved at Init because a missing global must degrade, not error.
local BAR_NAMES = {
    "MainActionBar",
    "MultiBarBottomLeft",
    "MultiBarBottomRight",
    "MultiBarRight",
    "MultiBarLeft",
    "StanceBar",
    "PetActionBar",
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function shown(frame)
    -- Edit Mode overrides IsShown on action bars to report the *intended*
    -- state; we need the real one for layout. Raw.IsShown is the widget method.
    return frame and Raw.IsShown(frame) or false
end

function AB.Hook(frame, method, fn)
    if not frame or type(frame[method]) ~= "function" then
        return false
    end
    local key = tostring(frame) .. ":" .. method
    if AB.hooked[key] then
        return true
    end
    AB.hooked[key] = true
    hooksecurefunc(frame, method, fn)
    return true
end

function AB.HookScript(frame, script, fn)
    if not frame then
        return
    end
    local key = tostring(frame) .. ":script:" .. script
    if AB.hooked[key] then
        return
    end
    AB.hooked[key] = true
    frame:HookScript(script, fn)
end

---------------------------------------------------------------------------
-- Layout flags (1.12 UIParent_ManageFramePositions)
---------------------------------------------------------------------------
local function bottomLeftShown()
    return shown(MultiBarBottomLeft)
end

local function statusOffset()
    local y = 0
    if AB.StatusBars and AB.StatusBars.IsReputationStacked() then
        y = y + OFFSET_REPUTATION
    end
    if AB.StatusBars and AB.StatusBars.IsMaxLevelBarShown() then
        y = y + OFFSET_MAXLEVEL
    end
    return y
end

---------------------------------------------------------------------------
-- Positioning. Called after every Edit Mode layout pass and whenever a bar
-- shows or hides. Only raw widget methods on non-protected frames, so this
-- is safe in combat; button sizes are handled in Buttons.lua via the queue.
---------------------------------------------------------------------------
local positioning = false
local anchorDeferred = false

-- The bar containers (MainActionBar, MultiBar*, StanceBar, PetActionBar,
-- status bar containers) are plain frames: Blizzard re-anchors them from its
-- own Edit Mode layout during combat, and so may we. Only protected frames
-- (secure buttons, our secure spellbook micro button) must wait; those are
-- skipped in combat and the pass is repeated when the lockdown ends.
function AB.CanAnchor(frame)
    if not frame then
        return false
    end
    if InCombatLockdown() and frame:IsProtected() then
        anchorDeferred = true
        return false
    end
    return true
end
-- Blizzard re-anchors MainActionBar at every combat start and end
-- (EditModeActionBar_OnEvent PLAYER_REGEN_* -> UpdateVisibility ->
-- UpdateBottomActionBarPositions -> SetToLayoutAnchor): in Camelot the bar's
-- layout anchor is BOTTOMRIGHT to MicroMenuContainer BOTTOMLEFT (-4.5, -4).
-- In combat we may not anchor the bar back (its buttons are protected), so
-- the container is placed where that anchor lands the bar exactly on its
-- 1.12 spot and Blizzard's move becomes a no-op. Only while the bar is in
-- its Edit Mode default position; a player-moved bar is never re-stacked.
local MAIN_BAR_X, MAIN_BAR_Y = 8, 4 -- ActionButton1 at BOTTOMLEFT of MainMenuBarArtFrame 8,4
function AB.AlignMicroMenuContainer()
    local container, bar, art = MicroMenuContainer, MainActionBar, AB.frame
    if not (container and bar and art) then
        return
    end
    local point = MAIN_ACTION_BAR_POINT or "BOTTOMRIGHT"
    local relativeTo = MAIN_ACTION_BAR_RELATIVE_TO or "MicroMenuContainer"
    if point ~= "BOTTOMRIGHT" or relativeTo ~= "MicroMenuContainer" then
        ns.Log("ActionBars", "main bar layout anchor %s/%s not handled", tostring(point), tostring(relativeTo))
        return
    end
    if not AB.CanAnchor(container) then
        return
    end
    local gapX = -(MAIN_ACTION_BAR_OFFSET_X or -4.5)
    local gapY = -(MAIN_ACTION_BAR_OFFSET_Y or -4)
    local artScale, containerScale = art:GetEffectiveScale(), container:GetEffectiveScale()
    if not artScale or not containerScale or containerScale == 0 then
        return
    end
    -- offsets are in the anchored frame's scale; the bar shares the art's scale
    local ratio = artScale / containerScale
    Raw.ClearAllPoints(container)
    Raw.SetPoint(
        container,
        "BOTTOMLEFT",
        art,
        "BOTTOMLEFT",
        (MAIN_BAR_X + bar:GetWidth() + gapX) * ratio,
        (MAIN_BAR_Y + gapY) * ratio
    )
end

function AB.Position()
    if positioning or not AB.frame then
        return
    end
    positioning = true
    anchorDeferred = false

    local art = AB.frame
    local scale = ns.db.scale or 1
    local yStatus = statusOffset()

    -- protected buttons hang off the art, so its scale only changes out of combat
    if art:GetScale() ~= scale and AB.CanAnchor(art) then
        Raw.SetScale(art, scale)
    end

    -- Each bar is placed twice: its Blizzard container (so Edit Mode boxes and
    -- Blizzard's own bookkeeping line up) and its buttons, which are anchored
    -- to the art directly and therefore survive Blizzard's in-combat re-stack
    -- of the containers (see Buttons.Anchor).

    -- MainMenuBar.xml / ActionBarFrame.xml: ActionButton1 at BOTTOMLEFT of MainMenuBarArtFrame 8,4
    if AB.CanAnchor(MainActionBar) then
        Raw.SetScale(MainActionBar, scale)
        Raw.ClearAllPoints(MainActionBar)
        Raw.SetPoint(MainActionBar, "BOTTOMLEFT", art, "BOTTOMLEFT", MAIN_BAR_X, MAIN_BAR_Y)
    end
    AB.Buttons.Anchor(MainActionBar, "BOTTOMLEFT", art, "BOTTOMLEFT", MAIN_BAR_X, MAIN_BAR_Y)

    -- MultiActionBars.xml: MultiBarBottomLeft BOTTOMLEFT to ActionButton1 TOPLEFT 0,17
    -- (UIParent.lua: baseY 17, reputation +9, maxLevel -5)
    local yBottom = MAIN_BAR_Y + AB.BUTTON + 17 + yStatus
    if AB.CanAnchor(MultiBarBottomLeft) then
        Raw.SetScale(MultiBarBottomLeft, scale)
        Raw.ClearAllPoints(MultiBarBottomLeft)
        Raw.SetPoint(MultiBarBottomLeft, "BOTTOMLEFT", art, "BOTTOMLEFT", MAIN_BAR_X, yBottom)
    end
    AB.Buttons.Anchor(MultiBarBottomLeft, "BOTTOMLEFT", art, "BOTTOMLEFT", MAIN_BAR_X, yBottom)

    -- MultiActionBars.xml: MultiBarBottomRight LEFT to MultiBarBottomLeft (500 wide) RIGHT 10,0.
    -- Anchored to the art rather than to MultiBarBottomLeft, so Blizzard moving
    -- that bar in combat cannot drag this one along.
    local xBottomRight = MAIN_BAR_X + MULTIBAR_LENGTH + 10
    if AB.CanAnchor(MultiBarBottomRight) then
        Raw.SetScale(MultiBarBottomRight, scale)
        Raw.ClearAllPoints(MultiBarBottomRight)
        Raw.SetPoint(MultiBarBottomRight, "BOTTOMLEFT", art, "BOTTOMLEFT", xBottomRight, yBottom)
    end
    AB.Buttons.Anchor(MultiBarBottomRight, "BOTTOMLEFT", art, "BOTTOMLEFT", xBottomRight, yBottom)

    -- MultiActionBars.xml: MultiBarRight (38x500, buttons from TOPRIGHT) at BOTTOMRIGHT -7,98,
    -- so the first button's top edge sits at 598 from the screen bottom.
    local yRight = 98 + MULTIBAR_LENGTH
    if AB.CanAnchor(MultiBarRight) then
        Raw.SetScale(MultiBarRight, scale)
        Raw.ClearAllPoints(MultiBarRight)
        Raw.SetPoint(MultiBarRight, "TOPRIGHT", UIParent, "BOTTOMRIGHT", -7, yRight)
    end
    AB.Buttons.Anchor(MultiBarRight, "TOPRIGHT", UIParent, "BOTTOMRIGHT", -7, yRight)

    -- MultiActionBars.xml: MultiBarLeft TOPRIGHT to MultiBarRight (38 wide) TOPLEFT -5,0
    local xLeft = -7 - MULTIBAR_THICKNESS - 5
    if AB.CanAnchor(MultiBarLeft) then
        Raw.SetScale(MultiBarLeft, scale)
        Raw.ClearAllPoints(MultiBarLeft)
        Raw.SetPoint(MultiBarLeft, "TOPRIGHT", UIParent, "BOTTOMRIGHT", xLeft, yRight)
    end
    AB.Buttons.Anchor(MultiBarLeft, "TOPRIGHT", UIParent, "BOTTOMRIGHT", xLeft, yRight)

    -- BonusActionBarFrame.xml: ShapeshiftBarFrame BOTTOMLEFT to MainMenuBar TOPLEFT 30,0;
    -- ShapeshiftButton1 at 11,3 inside. UIParent.lua: bottomLeft +45, reputation +9, maxLevel -5.
    local stanceY = AB.BAR_HEIGHT + 3 + yStatus
    if bottomLeftShown() then
        stanceY = stanceY + OFFSET_STANCE_BOTTOMLEFT
    end
    if AB.CanAnchor(StanceBar) then
        Raw.SetScale(StanceBar, scale)
        Raw.ClearAllPoints(StanceBar)
        Raw.SetPoint(StanceBar, "BOTTOMLEFT", art, "BOTTOMLEFT", 30 + 11, stanceY)
    end
    AB.Buttons.Anchor(StanceBar, "BOTTOMLEFT", art, "BOTTOMLEFT", 30 + 11, stanceY)
    AB.UpdateStanceArt(stanceY)

    -- PetActionBarFrame.xml: PetActionBarFrame (509x43) TOPLEFT to MainMenuBar BOTTOMLEFT 36,PETACTIONBAR_YPOS;
    -- PetActionButton1 at BOTTOMLEFT 36,2 inside. UIParent.lua: baseY 97, bottomLeft +43, reputation +9, maxLevel -5.
    local petY = PETACTIONBAR_YPOS + yStatus
    if bottomLeftShown() then
        petY = petY + OFFSET_PET_BOTTOMLEFT
    end
    local petX = PETACTIONBAR_XPOS
    if StanceBar and shown(StanceBar) then
        -- PetActionBarFrame.lua: PETACTIONBAR_XPOS = last ShapeshiftButton:GetRight() + 20
        local stanceRight = StanceBar:GetRight()
        local artLeft = art:GetLeft()
        if stanceRight and artLeft then
            petX = (stanceRight - artLeft) / scale + 20
        end
    end
    if AB.CanAnchor(PetActionBar) then
        Raw.SetScale(PetActionBar, scale)
        Raw.ClearAllPoints(PetActionBar)
        Raw.SetPoint(PetActionBar, "BOTTOMLEFT", art, "BOTTOMLEFT", petX + 36, petY - 43 + 2)
    end
    AB.Buttons.Anchor(PetActionBar, "BOTTOMLEFT", art, "BOTTOMLEFT", petX + 36, petY - 43 + 2)
    AB.UpdatePetArt(petX, petY)

    if AB.StatusBars then
        AB.StatusBars.Position()
    end
    if AB.MicroMenu then
        AB.MicroMenu.Position()
    end
    AB.AlignMicroMenuContainer()
    if AB.BagBar then
        AB.BagBar.Position()
    end
    -- The cast bar sits above the bars we just moved (1.12 UIParent_ManageFramePositions).
    if ns.CastBar then
        ns.CastBar.Position()
    end
    if ns.SwingTimer then
        ns.SwingTimer.Position()
    end

    positioning = false
    if anchorDeferred then
        Combat.Queue("actionbars:position", AB.Position)
    end
end

---------------------------------------------------------------------------
-- Stance bar art (BonusActionBarFrame.xml / BonusActionBarFrame.lua ShapeshiftBar_Update)
---------------------------------------------------------------------------
function AB.CreateStanceArt()
    local ends = ns.Assets.Get("StanceBar.Ends")
    local middle = ns.Assets.Get("StanceBar.Middle")
    if not ends or not middle or AB.stanceArt then
        return
    end
    local frame = CreateFrame("Frame", nil, AB.frame)
    frame:SetSize(29, 32) -- ShapeshiftBarFrame 29x32
    frame:SetFrameLevel(AB.frame:GetFrameLevel())
    -- ShapeshiftBarLeft 45x50 at BOTTOMLEFT
    frame.Left = frame:CreateTexture(nil, "BACKGROUND")
    frame.Left:SetTexture(ends)
    frame.Left:SetSize(45, 50)
    frame.Left:SetPoint("BOTTOMLEFT")
    frame.Left:SetTexCoord(0, 0.703125, 0, 0.78125) -- ShapeshiftBarEnds left half: 45/64, 50/64
    -- ShapeshiftBarMiddle 38x50, horizontally tiled by ShapeshiftBar_Update
    frame.Middle = frame:CreateTexture(nil, "BACKGROUND")
    frame.Middle:SetTexture(middle, "REPEAT")
    frame.Middle:SetSize(38, 50)
    frame.Middle:SetPoint("LEFT", frame.Left, "RIGHT")
    -- ShapeshiftBarRight 42x50
    frame.Right = frame:CreateTexture(nil, "BACKGROUND")
    frame.Right:SetTexture(ends)
    frame.Right:SetSize(42, 50)
    frame.Right:SetTexCoord(0.34375, 1, 0, 0.78125) -- ShapeshiftBarEnds right half: 42/64 from the right
    ns.Dark.Tint(frame.Left)
    ns.Dark.Tint(frame.Middle)
    ns.Dark.Tint(frame.Right)
    frame:Hide()
    AB.stanceArt = frame
end

function AB.UpdateStanceArt(stanceY)
    local frame = AB.stanceArt
    if not frame then
        return
    end
    local numForms = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
    -- UIParent_ManageFramePositions: art hidden while MultiBarBottomLeft is shown
    if not StanceBar or not shown(StanceBar) or numForms == 0 or bottomLeftShown() then
        frame:Hide()
        return
    end
    frame:ClearAllPoints()
    -- ShapeshiftBarFrame BOTTOMLEFT to MainMenuBar TOPLEFT 30,yOffset
    frame:SetPoint("BOTTOMLEFT", AB.frame, "BOTTOMLEFT", 30, stanceY - 3)
    -- ShapeshiftBar_Update: 1 form -> right cap 12px into the left cap, 2 forms -> caps touch,
    -- more -> middle 38px per extra form with repeating texcoords
    frame.Right:ClearAllPoints()
    if numForms == 1 then
        frame.Middle:Hide()
        frame.Right:SetPoint("LEFT", frame.Left, "LEFT", 12, 0)
    elseif numForms == 2 then
        frame.Middle:Hide()
        frame.Right:SetPoint("LEFT", frame.Left, "RIGHT", 0, 0)
    else
        frame.Middle:Show()
        frame.Middle:SetWidth(38 * (numForms - 2))
        frame.Middle:SetTexCoord(0, numForms - 2, 0, 1)
        frame.Right:SetPoint("LEFT", frame.Middle, "RIGHT", 0, 0)
    end
    frame:Show()
end

---------------------------------------------------------------------------
-- Pet bar art (PetActionBarFrame.xml SlidingActionBarTexture0/1)
---------------------------------------------------------------------------
function AB.CreatePetArt()
    local tex = ns.Assets.Get("PetBar.Art")
    if not tex or AB.petArt then
        return
    end
    local frame = CreateFrame("Frame", nil, AB.frame)
    frame:SetSize(509, 43) -- PetActionBarFrame 509x43
    frame:SetFrameLevel(AB.frame:GetFrameLevel())
    local t0 = frame:CreateTexture(nil, "OVERLAY")
    t0:SetTexture(tex)
    t0:SetSize(256, 44)
    t0:SetPoint("TOPLEFT")
    t0:SetTexCoord(0, 1, 0.015625, 0.359375)
    local t1 = frame:CreateTexture(nil, "OVERLAY")
    t1:SetTexture(tex)
    t1:SetSize(184, 44)
    t1:SetPoint("LEFT", t0, "RIGHT")
    t1:SetTexCoord(0, 0.71875, 0.375, 0.71875)
    ns.Dark.Tint(t0)
    ns.Dark.Tint(t1)
    frame:Hide()
    AB.petArt = frame
end

function AB.UpdatePetArt(petX, petY)
    local frame = AB.petArt
    if not frame then
        return
    end
    -- UIParent_ManageFramePositions: SlidingActionBarTexture hidden while MultiBarBottomLeft is shown
    if not PetActionBar or not shown(PetActionBar) or bottomLeftShown() then
        frame:Hide()
        return
    end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", AB.frame, "BOTTOMLEFT", petX, petY)
    frame:Show()
end

---------------------------------------------------------------------------
-- Module lifecycle
---------------------------------------------------------------------------
function AB:Init()
    if not MainActionBar then
        error("MainActionBar not found; this client does not match docs/CLIENT_FACTS.md")
    end
    self.bars = {}
    for _, name in ipairs(BAR_NAMES) do
        local bar = _G[name]
        if bar then
            table.insert(self.bars, bar)
        else
            ns.Log("ActionBars", "bar %s missing", name)
        end
    end
    AB.MainBar.Create()
    AB.CreateStanceArt()
    AB.CreatePetArt()
end

-- EditModeActionBar_OnLoad registers PLAYER_REGEN_ENABLED/DISABLED on every
-- action bar for the Edit Mode "show in combat / out of combat" visibility
-- option; the handler ends in UpdateActionBarLayout, which re-stacks all
-- bottom bars in their Edit Mode default position at every combat start
-- and end. Those bars count as protected, so the 1.12 layout could not be
-- put back until the fight ended. 1.12 had no combat visibility option, so
-- the two events are taken off the bars while the module runs.
local COMBAT_EVENTS = { "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" }
local function setCombatRestack(enabled)
    for _, name in ipairs(BAR_NAMES) do
        local bar = _G[name]
        if bar and bar.UnregisterEvent then
            for _, event in ipairs(COMBAT_EVENTS) do
                if enabled then
                    bar:RegisterEvent(event)
                else
                    bar:UnregisterEvent(event)
                end
            end
        end
    end
end

function AB:Enable()
    local frame = AB.frame
    frame:Show()
    setCombatRestack(false)

    -- Buttons: reskin and lay out containers for every bar we own.
    for _, bar in ipairs(self.bars) do
        AB.Buttons.SetupBar(bar)
        AB.HookScript(bar, "OnShow", AB.Position)
        AB.HookScript(bar, "OnHide", AB.Position)
        -- Edit Mode re-anchors each system in ApplySystemAnchor and again in
        -- UpdateBottomActionBarPositions / UpdateRightActionBarPositions.
        AB.Hook(bar, "ApplySystemAnchor", AB.Position)
    end
    if EditModeManagerFrame then
        AB.Hook(EditModeManagerFrame, "UpdateBottomActionBarPositions", AB.Position)
        AB.Hook(EditModeManagerFrame, "UpdateRightActionBarPositions", AB.Position)
    end

    AB.MainBar.Enable()
    AB.StatusBars.Enable()
    AB.MicroMenu.Enable()
    AB.BagBar.Enable()

    -- Forever's extra bars 5-7 did not exist in 1.12; a bar with a single action
    -- shows that one button floating above the multibars. Neutralised out of combat.
    for _, name in ipairs({ "MultiBar5", "MultiBar6", "MultiBar7" }) do
        if _G[name] then
            ns.Hide(_G[name])
        end
    end

    ns.RegisterEvent("UPDATE_SHAPESHIFT_FORMS", self, AB.Position)
    ns.RegisterEvent("UPDATE_SHAPESHIFT_FORM", self, AB.Position)
    ns.RegisterEvent("PET_BAR_UPDATE", self, AB.Position)
    ns.RegisterEvent("PLAYER_ENTERING_WORLD", self, AB.Position)

    AB.Position()
end

function AB:Disable()
    -- Reskins cannot be fully undone without a reload; hide our art and stop reacting.
    ns.UnregisterAllEvents(self)
    setCombatRestack(true)
    if AB.frame then
        AB.frame:Hide()
    end
    ns.Print("ActionBars disabled, /reload to restore the Blizzard layout")
end

function AB:Refresh()
    AB.Position()
end

function AB:Diag()
    ns.Print("art frame shown=%s scale=%.2f", tostring(AB.frame and AB.frame:IsShown()), ns.db.scale or 1)
    local frames = {}
    for _, bar in ipairs(self.bars or {}) do
        frames[#frames + 1] = bar
    end
    frames[#frames + 1] = MicroMenuContainer
    for _, bar in ipairs(frames) do
        local point, relativeTo, relativePoint, x, y = bar:GetPoint(1)
        local protected = bar:IsProtected()
        local ok, default = pcall(bar.IsInDefaultPosition, bar)
        ns.Print(
            "  %-20s shown=%s %s -> %s %s (%.1f, %.1f) size %.0fx%.0f protected=%s default=%s buttonsOnArt=%s",
            bar:GetName(),
            tostring(shown(bar)),
            tostring(point),
            tostring(relativeTo and relativeTo:GetName()),
            tostring(relativePoint),
            x or 0,
            y or 0,
            bar:GetWidth(),
            bar:GetHeight(),
            tostring(protected),
            ok and tostring(default) or "?",
            tostring(AB.Buttons.Anchored(bar))
        )
    end
    -- micro buttons: the modern group's art sizes, for "icon too big" reports
    for _, name in ipairs({ "EJMicroButton", "HousingMicroButton", "CollectionsMicroButton", "HelpMicroButton" }) do
        local button = _G[name]
        if button then
            local parts = {}
            for _, region in ipairs({ button:GetRegions() }) do
                if region:GetObjectType() == "Texture" and Raw.IsShown(region) then
                    parts[#parts + 1] = ("%s %.0fx%.0f"):format(
                        region:GetDebugName():match("[^.]+$") or "?",
                        region:GetWidth(),
                        region:GetHeight()
                    )
                end
            end
            ns.Print(
                "  %s %.0fx%.0f scale %.2f eff %.2f: %s",
                name,
                button:GetWidth(),
                button:GetHeight(),
                button:GetScale(),
                button:GetEffectiveScale(),
                table.concat(parts, ", ")
            )
        end
    end
    ns.Print("combat queue pending: %d", Combat.Pending())
end
