local _, ns = ...

-- Combat lockdown queue. Anything that touches a protected frame goes
-- through Combat:Run(fn); it executes immediately out of combat and is
-- deferred to PLAYER_REGEN_ENABLED otherwise. Functions are keyed so a
-- job queued twice runs once.
local Combat = {}
ns.Combat = Combat

local queue = {}
local order = {}

function Combat.Queue(key, fn)
    if not queue[key] then
        table.insert(order, key)
    end
    queue[key] = fn
end

function Combat.Run(key, fn)
    if InCombatLockdown() then
        Combat.Queue(key, fn)
        return false
    end
    local ok, err = xpcall(fn, geterrorhandler())
    if not ok then
        ns.Log("Combat", "%s failed: %s", key, tostring(err))
    end
    return true
end

local function flush()
    if InCombatLockdown() then
        return
    end
    local pending = order
    local jobs = queue
    order = {}
    queue = {}
    for _, key in ipairs(pending) do
        local fn = jobs[key]
        if fn then
            local ok, err = xpcall(fn, geterrorhandler())
            if not ok then
                ns.Log("Combat", "%s failed: %s", key, tostring(err))
            end
        end
    end
end

ns.RegisterEvent("PLAYER_REGEN_ENABLED", Combat, flush)

function Combat.Pending()
    return #order
end
