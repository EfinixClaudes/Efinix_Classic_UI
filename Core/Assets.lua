local _, ns = ...

-- Logical asset name -> texture path.
-- `verified = true` means the path is referenced by Blizzard UI code that
-- the Forever client loads (reference/forever, Camelot/Mainline/Shared
-- files only), so it must ship. Everything else is confirmed at runtime
-- through GetFileIDFromPath in Assets.Verify(); missing textures are listed
-- by /fcui status and marked in docs/PARITY.md.
local Assets = {}
ns.Assets = Assets

local B = "Interface\\Buttons\\"
local M = "Interface\\MainMenuBar\\"

local entries = {
    -- Main bar art (MainMenuBar.xml 1.12). Dwarf sheet referenced by Camelot PetExpBar.xml.
    ["MainBar.Art"] = { path = M .. "UI-MainMenuBar-Dwarf", verified = true },
    ["MainBar.EndCap"] = { path = M .. "UI-MainMenuBar-EndCap-Dwarf" },
    ["MainBar.MaxLevel"] = { path = M .. "UI-MainMenuBar-MaxLevel" },
    ["MainBar.KeyRing"] = { path = M .. "UI-MainMenuBar-KeyRing" },
    ["MainBar.PerformanceBar"] = { path = M .. "UI-MainMenuBar-PerformanceBar", verified = true },
    ["MainBar.PageUp"] = { path = M .. "UI-MainMenu-ScrollUpButton-Up", verified = true },
    ["MainBar.PageUpDown"] = { path = M .. "UI-MainMenu-ScrollUpButton-Down", verified = true },
    ["MainBar.PageUpHighlight"] = { path = M .. "UI-MainMenu-ScrollUpButton-Highlight", verified = true },
    ["MainBar.PageDown"] = { path = M .. "UI-MainMenu-ScrollDownButton-Up", verified = true },
    ["MainBar.PageDownDown"] = { path = M .. "UI-MainMenu-ScrollDownButton-Down", verified = true },
    ["MainBar.PageDownHighlight"] = { path = M .. "UI-MainMenu-ScrollDownButton-Highlight", verified = true },
    ["MainBar.PageUpDisabled"] = { path = B .. "UI-ScrollBar-ScrollUpButton-Disabled", verified = true },
    ["MainBar.PageDownDisabled"] = { path = B .. "UI-ScrollBar-ScrollDownButton-Disabled", verified = true },
    ["MainBar.ExhaustionTick"] = { path = M .. "UI-ExhaustionTickNormal", verified = true },
    ["MainBar.ExhaustionTickHighlight"] = { path = M .. "UI-ExhaustionTickHighlight", verified = true },
    ["MainBar.StatusBar"] = { path = "Interface\\TargetingFrame\\UI-StatusBar", verified = true },
    ["MainBar.ReputationWatchBar"] = { path = "Interface\\PaperDollInfoFrame\\UI-ReputationWatchBar" },

    -- Action buttons (ActionButtonTemplate.xml 1.12). Quickslot2/Depress/Hilight are the
    -- Forever ItemButton intrinsic defaults, so they ship.
    ["Button.Normal"] = { path = B .. "UI-Quickslot2", verified = true },
    ["Button.Empty"] = { path = B .. "UI-Quickslot" },
    ["Button.Pushed"] = { path = B .. "UI-Quickslot-Depress", verified = true },
    ["Button.Highlight"] = { path = B .. "ButtonHilight-Square", verified = true },
    ["Button.Checked"] = { path = B .. "CheckButtonHilight", verified = true },
    ["Button.Flash"] = { path = B .. "UI-QuickslotRed" },
    ["Button.Border"] = { path = B .. "UI-ActionButton-Border" },
    ["Button.AutoCastable"] = { path = B .. "UI-AutoCastableOverlay" },

    -- Stance and pet bar art (BonusActionBarFrame.xml / PetActionBarFrame.xml 1.12)
    ["StanceBar.Ends"] = { path = "Interface\\ShapeshiftBar\\ShapeshiftBarEnds" },
    ["StanceBar.Middle"] = { path = "Interface\\ShapeshiftBar\\ShapeshiftBarMiddle" },
    ["PetBar.Art"] = { path = "Interface\\PetActionBar\\UI-PetBar" },

    -- Micro buttons (MainMenuBarMicroButtons.lua 1.12)
    ["Micro.Hilight"] = { path = B .. "UI-MicroButton-Hilight" },
    ["Micro.CharacterUp"] = { path = B .. "UI-MicroButtonCharacter-Up", verified = true },
    ["Micro.CharacterDown"] = { path = B .. "UI-MicroButtonCharacter-Down" },
    ["Micro.Spellbook"] = { path = B .. "UI-MicroButton-Spellbook", verified = true },
    ["Micro.Talents"] = { path = B .. "UI-MicroButton-Talents" },
    ["Micro.Quest"] = { path = B .. "UI-MicroButton-Quest" },
    ["Micro.Socials"] = { path = B .. "UI-MicroButton-Socials" },
    ["Micro.World"] = { path = B .. "UI-MicroButton-World" },
    ["Micro.MainMenu"] = { path = B .. "UI-MicroButton-MainMenu" },
    ["Micro.Help"] = { path = B .. "UI-MicroButton-Help" },

    -- Bags (MainMenuBarBagButtons.xml 1.12)
    ["Bags.Backpack"] = { path = B .. "Button-Backpack-Up" },
    ["Bags.EmptySlot"] = { path = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag" },
    ["Bags.KeyRing"] = { path = B .. "UI-Button-KeyRing", verified = true },
    ["Bags.KeyRingHighlight"] = { path = B .. "UI-Button-KeyRing-Highlight", verified = true },
    ["Bags.KeyRingDown"] = { path = B .. "UI-Button-KeyRing-Down", verified = true },

    -- Classic panel chrome (UIPanelTemplates 1.12). Highlight is referenced by loaded code.
    ["Panel.CloseUp"] = { path = B .. "UI-Panel-MinimizeButton-Up" },
    ["Panel.CloseDown"] = { path = B .. "UI-Panel-MinimizeButton-Down" },
    ["Panel.CloseHighlight"] = { path = B .. "UI-Panel-MinimizeButton-Highlight", verified = true },
}

local missing = {}
local verifiedCount = 0

-- Micro button sheets are "<base>-Up/-Down/-Disabled"; verify the -Up file.
local function probePath(entry)
    local path = entry.path
    if entry.path:find("UI%-MicroButton%-") and not entry.path:find("Hilight") then
        path = path .. "-Up"
    end
    return path
end

function Assets.Verify()
    missing = {}
    verifiedCount = 0
    for name, entry in pairs(entries) do
        local exists = ns.Compat.TextureExists(probePath(entry))
        if exists == nil then
            entry.present = entry.verified or false
        else
            entry.present = exists
        end
        if entry.present then
            verifiedCount = verifiedCount + 1
        else
            table.insert(missing, name)
        end
    end
    table.sort(missing)
    if #missing > 0 then
        ns.Log("Assets", "missing: %s", table.concat(missing, ", "))
    end
end

-- Returns the path if the texture is present, otherwise nil.
function Assets.Get(name)
    local entry = entries[name]
    assert(entry, "unknown asset " .. tostring(name))
    if entry.present then
        return entry.path
    end
    return nil
end

-- Path regardless of presence, for callers that provide their own fallback.
function Assets.Path(name)
    local entry = entries[name]
    assert(entry, "unknown asset " .. tostring(name))
    return entry.path
end

function Assets.Missing()
    return missing
end

function Assets.Count()
    return verifiedCount
end
