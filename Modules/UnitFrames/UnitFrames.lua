local _, ns = ...

-- UnitFrames module, first slice: player-movable frames.
-- The Vanilla reskin of PlayerFrame/TargetFrame follows later; this file
-- only provides "/fcui move", a drag overlay per frame, and re-applies the
-- saved position after every Edit Mode layout pass.
--
-- PlayerFrame and TargetFrame are protected (SecureUnitButtonTemplate), so
-- their SetPoint goes through the combat queue. The overlay itself is ours
-- and never protected.
local Raw = ns.Raw
local Combat = ns.Combat

local UF = ns.RegisterModule("UnitFrames", {})
ns.UnitFrames = UF

-- 1.12 default anchors (PlayerFrame.xml, TargetFrame.xml, PetFrame.xml, PartyFrame.xml).
-- FocusFrame did not exist in Vanilla and keeps Blizzard's default.
local MOVABLE = {
    { name = "PlayerFrame", label = "Player", default = { point = "TOPLEFT", x = -19, y = -4 } },
    { name = "TargetFrame", label = "Target", default = { point = "TOPLEFT", x = 250, y = -4 } },
    { name = "FocusFrame", label = "Focus" },
    {
        name = "PetFrame",
        label = "Pet",
        default = { point = "TOPLEFT", relativeTo = "PlayerFrame", relativePoint = "TOPLEFT", x = 80, y = -60 },
    },
    { name = "PartyFrame", label = "Party", default = { point = "TOPLEFT", x = 10, y = -128 } },
}

UF.movers = {}
UF.moveMode = false

local function savedPosition(name)
    return ns.db.positions and ns.db.positions[name]
end

local function entryFor(name)
    for _, entry in ipairs(MOVABLE) do
        if entry.name == name then
            return entry
        end
    end
    return nil
end

-- Apply the saved position, or the 1.12 default, to the Blizzard frame. Out of combat only.
function UF.ApplyPosition(name)
    local frame = _G[name]
    if not frame then
        return
    end
    local pos = savedPosition(name)
    local entry = entryFor(name)
    Combat.Run("ufpos:" .. name, function()
        if pos then
            Raw.ClearAllPoints(frame)
            Raw.SetPoint(frame, pos.point, UIParent, pos.point, pos.x, pos.y)
        elseif entry and entry.default then
            local default = entry.default
            local relativeTo = default.relativeTo and _G[default.relativeTo] or UIParent
            Raw.ClearAllPoints(frame)
            Raw.SetPoint(frame, default.point, relativeTo, default.relativePoint or default.point, default.x, default.y)
        end
    end)
end

function UF.ApplyAll()
    for _, entry in ipairs(MOVABLE) do
        UF.ApplyPosition(entry.name)
    end
end

local function savePositionFromMover(mover)
    local frame = mover.target
    local point, _, _, x, y = mover:GetPoint(1)
    ns.db.positions[frame:GetName()] = { point = point, x = x, y = y }
    UF.ApplyPosition(frame:GetName())
end

local function createMover(entry)
    local frame = _G[entry.name]
    if not frame then
        return nil
    end
    local mover = CreateFrame("Frame", "FCUI_Mover_" .. entry.name, UIParent, "BackdropTemplate")
    mover.target = frame
    mover:SetFrameStrata("DIALOG")
    mover:SetMovable(true)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    mover:SetClampedToScreen(true)
    mover:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    mover:SetBackdropColor(0, 0.6, 0, 0.5)
    mover:SetBackdropBorderColor(1, 0.82, 0, 1)
    mover.Label = mover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mover.Label:SetPoint("CENTER")
    mover.Label:SetText(entry.label)
    mover:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    mover:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Re-anchor to UIParent with a single point so the saved data is stable.
        local left, bottom = self:GetLeft(), self:GetBottom()
        local width, height = self:GetSize()
        local x = left + width / 2
        local y = bottom + height / 2
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
        savePositionFromMover(self)
    end)
    mover:Hide()
    return mover
end

local function syncMoverToFrame(mover)
    local frame = mover.target
    local width, height = frame:GetSize()
    mover:SetSize(math.max(width, 40), math.max(height, 20))
    local x, y = frame:GetCenter()
    mover:ClearAllPoints()
    if x and y then
        mover:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    else
        mover:SetPoint("CENTER")
    end
end

function UF.SetMoveMode(enabled)
    if enabled and InCombatLockdown() then
        ns.Print("cannot move frames in combat")
        return
    end
    UF.moveMode = enabled
    for _, mover in pairs(UF.movers) do
        if enabled then
            syncMoverToFrame(mover)
            mover:Show()
        else
            mover:Hide()
        end
    end
    if enabled then
        ns.Print("move mode on: drag the green boxes, then /fcui move to lock. /fcui move reset restores defaults")
    else
        ns.Print("move mode off")
    end
end

function UF.ResetPositions()
    ns.db.positions = {}
    ns.Print("frame positions reset, /reload to let Edit Mode restore the defaults")
end

function UF:Init()
    ns.db.positions = ns.db.positions or {}
    for _, entry in ipairs(MOVABLE) do
        local mover = createMover(entry)
        if mover then
            UF.movers[entry.name] = mover
        end
    end
end

function UF:Enable()
    for _, entry in ipairs(MOVABLE) do
        local frame = _G[entry.name]
        if frame then
            -- Edit Mode re-anchors unit frames in ApplySystemAnchor; restore ours afterwards.
            if type(frame.ApplySystemAnchor) == "function" then
                hooksecurefunc(frame, "ApplySystemAnchor", function()
                    UF.ApplyPosition(entry.name)
                end)
            end
        end
    end
    -- Blizzard's player-bottom container re-anchors PetFrame in its Layout
    if PlayerBottomManagedFrameContainer and type(PlayerBottomManagedFrameContainer.Layout) == "function" then
        hooksecurefunc(PlayerBottomManagedFrameContainer, "Layout", function()
            UF.ApplyPosition("PetFrame")
        end)
    end
    ns.RegisterEvent("PLAYER_ENTERING_WORLD", self, function()
        UF.ApplyAll()
        if UF.Skin then
            UF.Skin.Refresh()
        end
    end)
    ns.RegisterEvent("PLAYER_REGEN_DISABLED", self, function()
        if UF.moveMode then
            UF.SetMoveMode(false)
        end
    end)
    if UF.Skin then
        UF.Skin.Enable()
    end
    if UF.Party then
        UF.Party.Enable()
    end
    UF.ApplyAll()
end

function UF:Disable()
    ns.UnregisterAllEvents(self)
    UF.SetMoveMode(false)
end

function UF:Refresh()
    UF.ApplyAll()
end

function UF:Diag()
    for _, entry in ipairs(MOVABLE) do
        local pos = savedPosition(entry.name)
        ns.Print(
            "  %-12s %s",
            entry.name,
            pos and ("%s %.0f, %.0f"):format(pos.point, pos.x, pos.y) or "default (Edit Mode)"
        )
    end
end
