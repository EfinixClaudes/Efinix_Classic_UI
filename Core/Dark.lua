local _, ns = ...

-- Dark mode (addon option, not a 1.12 feature): every piece of frame art the
-- modules draw or retexture is registered here with its normal vertex colour.
-- With the option on, the art is tinted down to a dark grey; off, the normal
-- colour is put back. Blizzard re-textures some of these regions on its own
-- (unit frame borders, cast bar border), so the modules call Dark.Tint again
-- after each of their own re-texture passes. Bars, icons, text and portraits
-- are never tinted, only frame art.
local Dark = {}
ns.Dark = Dark

local TINT = 0.35 -- vertex colour multiplier for frame art in dark mode

local textures = setmetatable({}, { __mode = "k" }) -- texture -> {r, g, b} normal colour
local backdrops = setmetatable({}, { __mode = "k" }) -- backdrop frame -> {r, g, b} normal border colour

function Dark.Enabled()
    return ns.db ~= nil and ns.db.darkMode == true
end

local function applyTexture(texture, base)
    if Dark.Enabled() then
        texture:SetVertexColor(base[1] * TINT, base[2] * TINT, base[3] * TINT)
    else
        texture:SetVertexColor(base[1], base[2], base[3])
    end
end

local function applyBackdrop(frame, base)
    if not frame.SetBackdropBorderColor then
        return
    end
    if Dark.Enabled() then
        frame:SetBackdropBorderColor(base[1] * TINT, base[2] * TINT, base[3] * TINT)
    else
        frame:SetBackdropBorderColor(base[1], base[2], base[3])
    end
end

-- Register (or re-apply to) a texture region. r, g, b is its normal colour, white by default.
function Dark.Tint(texture, r, g, b)
    if not texture or type(texture.SetVertexColor) ~= "function" then
        return
    end
    local base = textures[texture]
    if not base or r then
        if r then
            base = { r, g or 1, b or 1 }
        else
            -- Blizzard art may already carry a tint of its own; keep it as the normal colour
            local cr, cg, cb = texture:GetVertexColor()
            base = { cr or 1, cg or 1, cb or 1 }
        end
        textures[texture] = base
    end
    applyTexture(texture, base)
end

-- Register a BackdropTemplate frame whose border colour follows the mode.
function Dark.Backdrop(frame, r, g, b)
    if not frame then
        return
    end
    local base = backdrops[frame]
    if not base or r then
        base = { r or 1, g or 1, b or 1 }
        backdrops[frame] = base
    end
    applyBackdrop(frame, base)
end

function Dark.Apply()
    for texture, base in pairs(textures) do
        applyTexture(texture, base)
    end
    for frame, base in pairs(backdrops) do
        applyBackdrop(frame, base)
    end
end

---------------------------------------------------------------------------
-- Blizzard panels (quest, gossip, vendor, character, ...). Their art is not
-- ours, so it is found by walking the frame: every texture in the BACKGROUND
-- and BORDER layers of plain frames is frame art (nine-slice pieces,
-- parchment, insets, name plates). Buttons are skipped (their textures are
-- icons and button faces), as are portraits. The walk repeats on every show
-- because Blizzard builds parts of these panels from frame pools.
---------------------------------------------------------------------------
local PANELS = {
    "QuestFrame",
    "GossipFrame",
    "MerchantFrame",
    "CharacterFrame",
    "TaxiFrame",
    "TradeFrame",
    "MailFrame",
    "OpenMailFrame",
    "ItemTextFrame",
    "TabardFrame",
    "PetStableFrame",
    "ClassTrainerFrame",
    "GameMenuFrame",
    "FriendsFrame",
    "PVEFrame",
    "DressUpFrame",
    "PlayerSpellsFrame",
    "ProfessionsFrame",
    "AuctionHouseFrame",
    "GuildBankFrame",
    "InspectFrame",
    "MacroFrame",
    "AddonList",
    "HelpFrame",
    "EncounterJournal",
    "CollectionsJournal",
    "CommunitiesFrame",
    "SettingsPanel",
    "QuestLogPopupDetailFrame",
    "BankFrame",
    "GuildRegistrarFrame",
    "PetitionFrame",
    "ItemSocketingFrame",
    "HousingDashboardFrame",
    "StackSplitFrame",
    "ReadyCheckFrame",
    "TimeManagerFrame",
    "CalendarFrame",
    "AchievementFrame",
    "StaticPopup1",
    "StaticPopup2",
    "StaticPopup3",
    "StaticPopup4",
}

local SKIP_TYPES = { Button = true, CheckButton = true, ItemButton = true }
local walkedPanels = {} -- name -> true once hooked

-- Forbidden frames (store, secure Blizzard UI) throw on any access from addon code;
-- IsForbidden is the one method allowed on them.
local function forbidden(object)
    return type(object.IsForbidden) == "function" and object:IsForbidden()
end

local function isFrameArt(region, parent)
    if forbidden(region) or region:GetObjectType() ~= "Texture" then
        return false
    end
    if region == parent.portrait or region == parent.Portrait or region == parent.Icon or region == parent.icon then
        return false
    end
    local layer = region:GetDrawLayer()
    return layer == "BACKGROUND" or layer == "BORDER"
end

local function walk(frame, depth)
    if depth > 12 or forbidden(frame) or SKIP_TYPES[frame:GetObjectType()] then
        return
    end
    for _, region in ipairs({ frame:GetRegions() }) do
        if isFrameArt(region, frame) then
            Dark.Tint(region)
        end
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        walk(child, depth + 1)
    end
end

function Dark.SkinPanel(name)
    local frame = _G[name]
    if walkedPanels[name] or type(frame) ~= "table" or type(frame.GetRegions) ~= "function" then
        return
    end
    walkedPanels[name] = true
    if forbidden(frame) then
        return
    end
    -- a panel that still trips on something unexpected is logged, never breaks loading
    local ok, err = pcall(walk, frame, 0)
    if not ok then
        ns.Log("Dark", "%s: %s", name, tostring(err))
    end
    frame:HookScript("OnShow", function(self)
        if Dark.Enabled() then
            pcall(walk, self, 0)
        end
    end)
end

local function skinPanels()
    for _, name in ipairs(PANELS) do
        Dark.SkinPanel(name)
    end
end

---------------------------------------------------------------------------
-- Black text on parchment (quest text, books, vendor names) becomes unreadable
-- on dark parchment; the dark font objects are lightened while the mode is on.
---------------------------------------------------------------------------
local DARK_FONTS = {
    "QuestFont",
    "QuestFontLeft",
    "QuestFontNormalSmall",
    "QuestFontNormalLarge",
    "QuestFontNormalHuge",
    "QuestTitleFontBlackShadow",
    "ItemTextFontNormal",
    "GameFontBlack",
    "GameFontBlackSmall",
    "GameFontBlackMedium",
    "GameFontBlackTiny",
}
local LIGHT_TEXT = { 0.85, 0.85, 0.85 }
local fontColors = {} -- font object -> original {r, g, b}

local function applyFonts()
    for _, name in ipairs(DARK_FONTS) do
        local font = _G[name]
        if font and font.GetTextColor then
            local base = fontColors[font]
            if not base then
                local r, g, b = font:GetTextColor()
                base = { r or 0, g or 0, b or 0 }
                fontColors[font] = base
            end
            -- only fonts that really are dark; coloured quest fonts keep their colour
            if base[1] + base[2] + base[3] < 0.9 then
                if Dark.Enabled() then
                    font:SetTextColor(LIGHT_TEXT[1], LIGHT_TEXT[2], LIGHT_TEXT[3])
                else
                    font:SetTextColor(base[1], base[2], base[3])
                end
            end
        end
    end
end

local baseApply = Dark.Apply
function Dark.Apply()
    baseApply()
    applyFonts()
end

---------------------------------------------------------------------------
-- Quest, gossip and book text: Blizzard's own "quest text contrast"
-- accessibility setting (questTextContrast cvar) has a level 4 that draws a
-- dark background with light text through QuestTextContrast.lua, which is
-- the real dark parchment. Dark mode switches to it and remembers the
-- player's own value for when the mode is turned off.
---------------------------------------------------------------------------
local CONTRAST_CVAR = "questTextContrast"
local CONTRAST_DARK = "4" -- QuestTextContrast.UseLightText: dark background, light text

local function applyContrast()
    if not C_CVar or not C_CVar.GetCVar or not C_CVar.SetCVar then
        return
    end
    local current = C_CVar.GetCVar(CONTRAST_CVAR)
    if current == nil then
        return -- no such setting on this client
    end
    if Dark.Enabled() then
        if current ~= CONTRAST_DARK then
            if ns.db.darkContrastPrevious == nil then
                ns.db.darkContrastPrevious = current
            end
            C_CVar.SetCVar(CONTRAST_CVAR, CONTRAST_DARK)
        end
    elseif ns.db.darkContrastPrevious ~= nil then
        if current == CONTRAST_DARK then
            C_CVar.SetCVar(CONTRAST_CVAR, tostring(ns.db.darkContrastPrevious))
        end
        ns.db.darkContrastPrevious = nil
    elseif current == CONTRAST_DARK then
        -- dark mode is off but the game still has our value (settings were lost): back to the default
        C_CVar.SetCVar(CONTRAST_CVAR, "0")
        ns.Log("Dark", "questTextContrast was left at 4, reset to 0")
    end
end

function Dark.Set(enabled)
    ns.db.darkMode = enabled == true
    Dark.Apply()
    applyContrast()
end

-- Panels that exist at login are walked once the settings are known; load-on-demand
-- panels (trainer, auction house, professions, ...) when their addon arrives.
ns.RegisterEvent("PLAYER_LOGIN", Dark, function()
    skinPanels()
    applyFonts()
    applyContrast()
end)
ns.RegisterEvent("ADDON_LOADED", Dark, function()
    if ns.db then
        skinPanels()
    end
end)
