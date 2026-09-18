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

-- On this client the saved file is not always in place when ADDON_LOADED
-- fires for us. Load reads whatever the global holds; Adopt is called again
-- on the later login events and switches to the game's table if it showed
-- up (or got replaced) in the meantime. DB.seen records the event that first
-- saw a saved table, for /fcui status.
DB.seen = {} -- event -> "file" | "none" | "ours"

function DB.Adopt(event)
    local saved = ForeverClassicUIDB
    if type(saved) ~= "table" then
        DB.seen[event] = "none"
        return false
    end
    if saved == ns.db then
        DB.seen[event] = "ours"
        return false
    end
    DB.seen[event] = "file"
    DB.Load()
    DB.loadedAt = event
    return true
end

function DB.Load()
    -- remembered for /fcui status: did the game hand us a saved file at all
    DB.loadedFromFile = type(ForeverClassicUIDB) == "table"
    if type(ForeverClassicUIDB) ~= "table" then
        ForeverClassicUIDB = {}
    end
    local db = ForeverClassicUIDB
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
    ForeverClassicUIDB = {}
    DB.Load()
end
