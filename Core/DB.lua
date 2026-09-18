local _, ns = ...

local DB = {}
ns.DB = DB

local DEFAULTS = {
    version = 4,
    scale = 1,
    darkMode = false, -- frame art tinted dark grey (addon option)
    darkContrastPrevious = nil, -- questTextContrast cvar before dark mode set it to 4
    modules = {
        ActionBars = true,
        UnitFrames = true,
        CastBar = true,
        SwingTimer = true,
        Minimap = true,
        Auras = true,
        Chat = true,
        Tooltip = true,
        Nameplates = true,
        RaidFrames = true,
        LootFrame = true,
        SpellBook = true,
        Bags = true,
        Vendor = true,
    },
    -- Nameplates: plate scale and the player's cvar values before we changed them (name -> value)
    nameplates = { scale = 1.3, previous = {} },
    -- Minimap: extra scale on top of the global one
    minimap = { scale = 1.2 },
    -- SwingTimer: the player's showSwingTimer cvar before we switched it on
    swingTimer = { previous = nil },
    -- UnitFrames: player-chosen frame positions, name -> {point, x, y} on UIParent
    positions = {},
    bags = {
        columns = 10,
        bankColumns = 14,
        shiftSell = true, -- hold Shift at a vendor to sell grey items
        hidden = {}, -- kind -> bagID -> true
        positions = {}, -- kind -> {point, x, y}
    },
}

local function copyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = {}
            end
            copyDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

-- Migrations run in order from db.version up to DEFAULTS.version.
local migrations = {
    -- 2: added UnitFrames/Bags modules and their settings; copyDefaults fills them in.
    [2] = function(db)
        db.positions = db.positions or {}
    end,
    -- 3: frame positions are now centre offsets from the UIParent centre; the old
    -- entries mixed anchor points and are unusable, so they are dropped.
    [3] = function(db)
        db.positions = {}
    end,
    -- 4: Nameplates keeps every cvar it changes under nameplates.previous
    [4] = function(db)
        if type(db.nameplates) == "table" then
            db.nameplates.previous = db.nameplates.previous or {}
            if db.nameplates.previousStyle ~= nil then
                db.nameplates.previous.nameplateStyle = tostring(db.nameplates.previousStyle)
                db.nameplates.previousStyle = nil
            end
        end
    end,
}

-- Forever (build 69913) writes SavedVariables but does not load our
-- settings table back, account-wide or per character, while a small
-- per-character table holding only strings did come back (probed in game
-- 2026-09-18). So the settings are stored as ONE STRING inside a
-- per-character variable: { data = "<encoded>" }. Encode/Decode below is a
-- flat "path=value" format for plain tables (string/number keys,
-- string/number/boolean values), no Lua parsing needed. ns.db is always a
-- private table; the global only ever holds the encoded copy, refreshed by
-- DB.Flush after every settings change and at logout.
-- DB.seen records what each event found, for /fcui status.
DB.seen = {} -- event -> "file" | "none" | "legacy"

local function escape(text)
    return (tostring(text):gsub("[^%w]", function(c)
        return ("%%%02X"):format(c:byte())
    end))
end

local function unescape(text)
    return (text:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

local function encodeKey(key)
    if type(key) == "number" then
        return "n" .. tostring(key)
    end
    return "s" .. escape(key)
end

local function decodeKey(text)
    local kind, body = text:sub(1, 1), text:sub(2)
    if kind == "n" then
        return tonumber(body)
    end
    return unescape(body)
end

local function encodeValue(value)
    local kind = type(value)
    if kind == "boolean" then
        return value and "b1" or "b0"
    elseif kind == "number" then
        return "n" .. tostring(value)
    end
    return "s" .. escape(value)
end

local function decodeValue(text)
    local kind, body = text:sub(1, 1), text:sub(2)
    if kind == "b" then
        return body == "1"
    elseif kind == "n" then
        return tonumber(body)
    end
    return unescape(body)
end

local function encodeInto(out, tbl, prefix, depth)
    if depth > 8 then
        return
    end
    for key, value in pairs(tbl) do
        local keyKind, valueKind = type(key), type(value)
        if keyKind == "string" or keyKind == "number" then
            local path = prefix .. encodeKey(key)
            if valueKind == "table" then
                if next(value) == nil then
                    out[#out + 1] = path .. "=t" -- empty table
                else
                    encodeInto(out, value, path .. ".", depth + 1)
                end
            elseif valueKind == "string" or valueKind == "number" or valueKind == "boolean" then
                out[#out + 1] = path .. "=" .. encodeValue(value)
            end
        end
    end
end

function DB.Encode(tbl)
    local out = {}
    encodeInto(out, tbl, "", 0)
    table.sort(out)
    return table.concat(out, ";")
end

function DB.Decode(text)
    local root = {}
    if type(text) ~= "string" then
        return root
    end
    for entry in text:gmatch("[^;]+") do
        local path, value = entry:match("^(.-)=(.*)$")
        if path then
            local node = root
            local segments = {}
            for segment in path:gmatch("[^.]+") do
                segments[#segments + 1] = segment
            end
            for i = 1, #segments - 1 do
                local key = decodeKey(segments[i])
                if type(node[key]) ~= "table" then
                    node[key] = {}
                end
                node = node[key]
            end
            local last = decodeKey(segments[#segments])
            if last ~= nil then
                if value == "t" then
                    node[last] = {}
                else
                    node[last] = decodeValue(value)
                end
            end
        end
    end
    return root
end

-- Read the saved global if it holds settings we have not taken yet.
function DB.Adopt(event)
    local saved = EfinixClassicUICharSettings
    if type(saved) ~= "table" then
        DB.seen[event] = "none"
        return false
    end
    if DB.loadedFromFile then
        DB.seen[event] = "taken"
        return false
    end
    DB.seen[event] = type(saved.data) == "string" and "file" or "legacy"
    DB.Load()
    DB.loadedAt = event
    return true
end

-- Put the encoded settings into the saved global (a fresh, strings-only table).
function DB.Flush()
    if not ns.db then
        return
    end
    local data = DB.Encode(ns.db)
    EfinixClassicUICharSettings = { data = data, build = tostring(ns.BUILD), length = tostring(#data) }
    DB.flushed = #data
end

function DB.Load()
    local saved = EfinixClassicUICharSettings
    local db
    if type(saved) == "table" and type(saved.data) == "string" then
        db = DB.Decode(saved.data)
        DB.loadedFromFile = true
    elseif type(saved) == "table" and type(saved.modules) == "table" then
        db = saved -- a table from an earlier build, taken as is
        DB.loadedFromFile = true
    else
        db = {}
        DB.loadedFromFile = false
    end
    local from = tonumber(db.version) or 0
    for v = from + 1, DEFAULTS.version do
        if migrations[v] then
            migrations[v](db)
        end
    end
    copyDefaults(db, DEFAULTS)
    db.version = DEFAULTS.version
    ns.db = db
    local off = {}
    for name, enabled in pairs(db.modules) do
        if not enabled then
            off[#off + 1] = name
        end
    end
    table.sort(off)
    DB.loadedSummary = ("file=%s off=[%s] darkMode=%s"):format(
        tostring(DB.loadedFromFile),
        table.concat(off, ","),
        tostring(db.darkMode)
    )
    return db
end

function DB.Reset()
    EfinixClassicUICharSettings = nil
    DB.loadedFromFile = false
    DB.Load()
    DB.Flush()
end
