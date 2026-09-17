local _, ns = ...

local DB = {}
ns.DB = DB

local DEFAULTS = {
    version = 2,
    scale = 1,
    modules = {
        ActionBars = true,
        UnitFrames = true,
        CastBar = true,
        Bags = true,
    },
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
}

function DB.Load()
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
    return db
end

function DB.Reset()
    ForeverClassicUIDB = {}
    DB.Load()
end
