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
        base = { r or 1, g or 1, b or 1 }
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

function Dark.Set(enabled)
    ns.db.darkMode = enabled == true
    Dark.Apply()
end
