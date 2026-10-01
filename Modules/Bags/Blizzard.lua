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

-- The container frames' own slot buttons are what the bag window shows: they
-- are created by Blizzard's code, so using an item from them (scrolls,
-- recipes, armor kits, potions in combat) is never blocked, which addon-made
-- copies of the same template could not avoid. So a parked container frame
-- keeps full size and alpha, sits off screen, and only its own art is made
-- invisible; Bags.RefreshWindow anchors its slot buttons into our grid.
-- DIALOG strata keeps those buttons above the HIGH bag window.
local function hideArt(frame)
    for _, region in ipairs({ frame:GetRegions() }) do
        region:SetAlpha(0)
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        if child:GetObjectType() ~= "ItemButton" then
            Raw.SetAlpha(child, 0)
        end
    end
end

local function park(frame)
    Raw.SetAlpha(frame, 1)
    Raw.SetScale(frame, 1)
    Raw.SetFrameStrata(frame, "DIALOG")
    Raw.ClearAllPoints(frame)
    Raw.SetPoint(frame, "TOPLEFT", UIParent, "TOPRIGHT", 4000, 4000)
    hideArt(frame)
    parked[frame] = true
end

-- The game's own slot button for bag/slot, from whichever container frame
-- (single bags or the combined bag) currently shows that bag; nil if none.
function Blizzard.FindButton(bagID, slot)
    for _, name in ipairs(CONTAINER_FRAMES) do
        local frame = _G[name]
        if frame and Raw.IsShown(frame) and type(frame.Items) == "table" then
            for _, button in ipairs(frame.Items) do
                if button:GetID() == slot and button.GetBagID and button:GetBagID() == bagID then
                    return button
                end
            end
        end
    end
    return nil
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
            -- Blizzard re-anchors its slot buttons whenever it lays the bag out
            if type(frame.UpdateItemLayout) == "function" then
                hooksecurefunc(frame, "UpdateItemLayout", function()
                    C_Timer.After(0, function()
                        Bags.RefreshWindow("inventory", true)
                    end)
                end)
            end
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
