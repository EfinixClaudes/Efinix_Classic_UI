local _, ns = ...

local DB = {}
ns.DB = DB

local DEFAULTS = {
    version = 4,
    scale = 1,
    darkMode = false, -- frame art tinted dark grey (addon option)
    microMenuRow = true, -- all menus in one micro menu row; the bar art grows to fit
    darkContrastPrevious = nil, -- questTextContrast cvar before dark mode set it to 4
    modules = {
        ActionBars = true,
        UnitFrames = true,
        PartyFrames = true,
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
        Talents = true,
        QuestWatch = true,
        Gather = true,
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
    -- Gather: which recorded node kinds the world map shows
    gather = { showMining = true, showHerbs = true },
    -- QuestWatch: folded zone headers, zone name -> true
    questWatch = { collapsed = {} },
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

-- Forever (build 69913) writes SavedVariables files but loads a file back
-- only when every value in it is a string: any boolean, number or nested
-- table anywhere in the file makes the whole file come back empty (nine
-- probe builds on 2026-09-18, see docs/CLIENT_FACTS.md). So the settings are
-- stored as ONE STRING: { data = "<encoded>", build, written }, nothing else
-- may ever be put into the saved globals. Encode/Decode below is a flat
-- "path=value" format for plain tables (string/number keys, string/number/
-- boolean values), no Lua parsing needed. ns.db is always a private table;
-- the globals only hold the encoded copy, refreshed by DB.Flush after every
-- settings change and at logout.
-- DB.seen records what each event found, for /fcui status.
DB.seen = {} -- event -> "file" | "none" | "legacy"

-- "~XX" escapes: no "%" in the saved text (a percent sign is the one
-- character we have not seen come back from this client's loader)
local function escape(text)
    return (tostring(text):gsub("[^%w]", function(c)
        return ("~%02X"):format(c:byte())
    end))
end

local function unescape(text)
    return (text:gsub("~(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end
DB.Escape = escape
DB.Unescape = unescape

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

-- Only what differs from DEFAULTS is written (copyDefaults fills the rest at
-- load), which keeps the saved text short.
local function encodeInto(out, tbl, defaults, prefix, depth)
    if depth > 8 then
        return
    end
    for key, value in pairs(tbl) do
        local keyKind, valueKind = type(key), type(value)
        if keyKind == "string" or keyKind == "number" then
            local path = prefix .. encodeKey(key)
            local default = type(defaults) == "table" and defaults[key] or nil
            if valueKind == "table" then
                if next(value) == nil then
                    if type(default) == "table" and next(default) ~= nil then
                        out[#out + 1] = path .. "=t" -- emptied on purpose
                    end
                else
                    encodeInto(out, value, default, path .. ".", depth + 1)
                end
            elseif valueKind == "string" or valueKind == "number" or valueKind == "boolean" then
                if value ~= default then
                    out[#out + 1] = path .. "=" .. encodeValue(value)
                end
            end
        end
    end
end

function DB.Encode(tbl)
    local out = {}
    encodeInto(out, tbl, DEFAULTS, "", 0)
    -- the schema version is always written, or the migrations would run again on load
    out[#out + 1] = "sversion=n" .. tostring(tonumber(tbl.version) or DEFAULTS.version)
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

-- Three stores receive the encoded text: a registered cvar (came back in
-- every probe on this client, account-wide), the per-character and the
-- account-wide saved variable (the saved files come back only sometimes).
-- At login the cvar wins, then the per-character copy, then the account copy.
local CVAR = "EfinixClassicUISettings"

-- Every store is registered here, at ADDON_LOADED. The settings cvar, which
-- is registered this early, came back after full client restarts although no
-- WTF file on disk holds it; the bank and gather blobs, registered later at
-- PLAYER_LOGIN, did not. So all blob cvars are registered at the same point.
local BLOB_KEYS = { "Bank", "Gather" }
local registerBlobCVar -- defined with the blob store below

function DB.RegisterCVar()
    if C_CVar and C_CVar.RegisterCVar and C_CVar.GetCVar and C_CVar.GetCVar(CVAR) == nil then
        pcall(C_CVar.RegisterCVar, CVAR, "")
    end
    for _, key in ipairs(BLOB_KEYS) do
        registerBlobCVar(key)
    end
end

local function cvarTable()
    local value = C_CVar and C_CVar.GetCVar and C_CVar.GetCVar(CVAR)
    if type(value) ~= "string" or value == "" then
        return nil
    end
    -- "HH:MM:SS|build|data"
    local written, build, data = value:match("^([^|]*)|([^|]*)|(.*)$")
    if not data then
        return nil
    end
    return { data = data, written = written, build = build }
end

local function savedTable()
    local cvar = cvarTable()
    if cvar then
        return cvar, "cvar"
    end
    local char = EfinixClassicUICharSettings
    if type(char) == "table" and (type(char.data) == "string" or type(char.modules) == "table") then
        return char, "character"
    end
    local account = EfinixClassicUIAccountSettings
    if type(account) == "table" and type(account.data) == "string" then
        return account, "account"
    end
    return nil
end

---------------------------------------------------------------------------
-- Extra stores for bulkier data (the bank snapshot): one registered cvar
-- "EfinixClassicUI<key>" each, plus a copy inside the per-character saved
-- table under "blob_<key>". The cvar wins at load, as with the settings.
---------------------------------------------------------------------------
local blobs = {} -- key -> text | false (looked up, nothing stored)

local function blobCVar(key)
    return "EfinixClassicUI" .. key
end

registerBlobCVar = function(key)
    if C_CVar and C_CVar.RegisterCVar and C_CVar.GetCVar and C_CVar.GetCVar(blobCVar(key)) == nil then
        pcall(C_CVar.RegisterCVar, blobCVar(key), "")
    end
end

-- For /fcui status: where each blob currently is and how long it is.
function DB.BlobReport()
    local parts = {}
    for _, key in ipairs(BLOB_KEYS) do
        local cvarValue = C_CVar and C_CVar.GetCVar and C_CVar.GetCVar(blobCVar(key))
        local char = EfinixClassicUICharSettings
        local saved = type(char) == "table" and char["blob_" .. key]
        parts[#parts + 1] = ("%s: cvar %s, saved %s"):format(
            key,
            type(cvarValue) == "string" and (#cvarValue .. " chars") or "none",
            type(saved) == "string" and (#saved .. " chars") or "none"
        )
    end
    return table.concat(parts, "; ")
end

function DB.GetBlob(key)
    if blobs[key] == nil then
        local value
        if C_CVar and C_CVar.GetCVar then
            registerBlobCVar(key)
            value = C_CVar.GetCVar(blobCVar(key))
        end
        if type(value) ~= "string" or value == "" then
            local char = EfinixClassicUICharSettings
            value = type(char) == "table" and char["blob_" .. key] or nil
        end
        blobs[key] = type(value) == "string" and value ~= "" and value or false
    end
    return blobs[key] or nil
end

function DB.SetBlob(key, text)
    blobs[key] = text
    if C_CVar and C_CVar.SetCVar then
        registerBlobCVar(key)
        pcall(C_CVar.SetCVar, blobCVar(key), text)
    end
    DB.Flush()
end

-- Carry blob copies into a fresh saved table: what this session set, else
-- what the previous table held.
local function copyBlobs(previous, stamp)
    if type(previous) == "table" then
        for field, value in pairs(previous) do
            if type(field) == "string" and field:sub(1, 5) == "blob_" and type(value) == "string" then
                stamp[field] = value
            end
        end
    end
    for key, text in pairs(blobs) do
        if text then
            stamp["blob_" .. key] = text
        end
    end
end

-- Read the saved global if it holds settings we have not taken yet.
function DB.Adopt(event)
    local saved = savedTable()
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
    ns.db.logins = tonumber(ns.db.logins) or 0
    local data = DB.Encode(ns.db)
    local stamp = { data = data, build = tostring(ns.BUILD), written = date("%H:%M:%S") }
    copyBlobs(EfinixClassicUICharSettings, stamp)
    EfinixClassicUICharSettings = stamp
    EfinixClassicUIAccountSettings = { data = data, build = stamp.build, written = stamp.written }
    if C_CVar and C_CVar.SetCVar then
        DB.RegisterCVar()
        pcall(C_CVar.SetCVar, CVAR, stamp.written .. "|" .. stamp.build .. "|" .. data)
    end
    DB.flushed = #data
end

function DB.Load()
    local saved, source = savedTable()
    local db
    if type(saved) == "table" and type(saved.data) == "string" then
        db = DB.Decode(saved.data)
        DB.loadedFromFile = true
        DB.loadedSource = source
        DB.loadedWritten = tostring(saved.written)
    elseif type(saved) == "table" and type(saved.modules) == "table" then
        db = saved -- a table from an earlier build, taken as is
        DB.loadedFromFile = true
        DB.loadedSource = source
    else
        db = {}
        DB.loadedFromFile = false
    end
    db.logins = (tonumber(db.logins) or 0) + 1
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
    EfinixClassicUIAccountSettings = nil
    if C_CVar and C_CVar.SetCVar and C_CVar.GetCVar and C_CVar.GetCVar(CVAR) ~= nil then
        pcall(C_CVar.SetCVar, CVAR, "")
    end
    DB.loadedFromFile = false
    DB.Load()
    DB.Flush()
end
