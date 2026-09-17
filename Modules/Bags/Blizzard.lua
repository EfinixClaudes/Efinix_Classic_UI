local _, ns = ...

-- Blizzard side of the Bags module.
--
-- Blizzard's container frames stay alive and keep opening and closing
-- exactly as the game intends (B key, ToggleAllBags, merchants, mail,
-- bank), but they are parked: alpha 0, scaled to 1%, anchored far off
-- screen. Our windows mirror their shown state through OnShow/OnHide
-- hooks. That keeps IsBagOpen(), the bag-button highlight, the open/close
-- sounds and FRAME_THAT_OPENED_BAGS bookkeeping intact without replacing
-- a single Blizzard function.
--
-- The bank works the same way: BankFrame (a UIPanel) is parked while shown
-- so Escape and the panel manager still close the bank session; a
-- "Blizzard bank" button brings it back for buying tabs.
local Raw = ns.Raw
local Bags = ns.Bags

local Blizzard = {}
Bags.Blizzard = Blizzard

local CONTAINER_FRAMES = {
    "ContainerFrameCombinedBags",
    "ContainerFrame1",
    "ContainerFrame2",
    "ContainerFrame3",
    "ContainerFrame4",
    "ContainerFrame5",
    "ContainerFrame6",
    "ContainerFrame7",
}

local parked = {} -- frame -> true

local function park(frame)
    Raw.SetAlpha(frame, 0)
    Raw.SetScale(frame, 0.01)
    Raw.ClearAllPoints(frame)
    Raw.SetPoint(frame, "TOPLEFT", UIParent, "TOPRIGHT", 4000, 4000)
    parked[frame] = true
end

local function unpark(frame)
    Raw.SetAlpha(frame, 1)
    Raw.SetScale(frame, 1)
    parked[frame] = nil
end

function Blizzard.AnyBlizzardBagShown()
    for _, name in ipairs(CONTAINER_FRAMES) do
        local frame = _G[name]
        if frame and Raw.IsShown(frame) then
            return true
        end
    end
    return false
end

local function syncInventory()
    if Blizzard.AnyBlizzardBagShown() then
        Bags.Show("inventory")
    else
        Bags.Hide("inventory")
    end
end

local function parkContainers()
    for _, name in ipairs(CONTAINER_FRAMES) do
        local frame = _G[name]
        if frame then
            park(frame)
        end
    end
end

---------------------------------------------------------------------------
-- Bank
---------------------------------------------------------------------------
local function parkBank()
    if BankFrame and parked[BankFrame] ~= false then
        park(BankFrame)
    end
end

function Blizzard.ToggleBlizzardBank()
    if not BankFrame or not BankFrame:IsShown() then
        return
    end
    if parked[BankFrame] then
        unpark(BankFrame)
        parked[BankFrame] = false -- explicit: user wants it visible until the bank closes
        Raw.ClearAllPoints(BankFrame)
        Raw.SetPoint(BankFrame, "TOPLEFT", UIParent, "TOPLEFT", 16, -116)
    else
        parked[BankFrame] = nil
        parkBank()
    end
end

---------------------------------------------------------------------------
-- Enable
---------------------------------------------------------------------------
function Blizzard.Enable()
    parkContainers()
    for _, name in ipairs(CONTAINER_FRAMES) do
        local frame = _G[name]
        if frame then
            frame:HookScript("OnShow", function(self)
                park(self)
                syncInventory()
            end)
            frame:HookScript("OnHide", syncInventory)
        end
    end
    -- Blizzard re-anchors its container frames on every open/close and resize
    if UpdateContainerFrameAnchors then
        hooksecurefunc("UpdateContainerFrameAnchors", parkContainers)
    end

    if BankFrame then
        BankFrame:HookScript("OnShow", function()
            parked[BankFrame] = nil
            parkBank()
            Bags.Show("bank")
            Bags.Show("inventory")
        end)
        BankFrame:HookScript("OnHide", function()
            parked[BankFrame] = nil
            Bags.Hide("bank")
        end)
        -- The panel manager re-anchors UIPanels whenever any panel opens or closes
        if UpdateUIPanelPositions then
            hooksecurefunc("UpdateUIPanelPositions", function()
                if BankFrame:IsShown() and parked[BankFrame] then
                    park(BankFrame)
                end
            end)
        end
    end

    syncInventory()
end
