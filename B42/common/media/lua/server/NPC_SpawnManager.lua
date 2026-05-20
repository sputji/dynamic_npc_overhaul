-- Project Humain: Dynamic NPC Overhaul - B42
-- server/NPC_SpawnManager.lua v3.0
-- Server authority: NPC identity + behavioral target sync at 10Hz.
-- SOLO: NPC_NetworkDispatcher routes directly (same VM, no real network).
-- MULTI: server tracks NPC states; broadcasts PHNPC_SyncTarget to all clients.
-- NO BOM. ASCII only.

local Dispatcher = PHNPC.getModule("NPC_NetworkDispatcher")

if not Dispatcher then
    print("[PHNPC] NPC_SpawnManager: NPC_NetworkDispatcher not found, disabled.")
    return
end

-- ============================================================
-- FALLBACK NAMES
-- ============================================================

local FNAMES_M = { "Bob", "Tom", "Alex", "Lucas", "Noah", "Sam", "Chris", "Jack", "Matt", "Ryan" }
local FNAMES_F = { "Kate", "Emma", "Lea", "Sara", "Nina", "Rose", "Mia",  "Amy",  "Zoe",  "Lily" }
local LNAMES   = { "Martin", "Smith", "Brown", "Durand", "Roux", "Davis", "Clark", "Young", "Baker", "Reed" }

local function randomName(isFemale)
    local forename, surname
    if type(SurvivorFactory) == "table" then
        local ok1, fn = pcall(function() return SurvivorFactory.getRandomForename(isFemale) end)
        local ok2, sn = pcall(function() return SurvivorFactory.getRandomSurname() end)
        forename = (ok1 and fn) or nil
        surname  = (ok2 and sn) or nil
    end
    if not forename then
        local pool = isFemale and FNAMES_F or FNAMES_M
        forename = pool[ZombRand(#pool) + 1]
    end
    if not surname then
        surname = LNAMES[ZombRand(#LNAMES) + 1]
    end
    return forename, surname
end

-- ============================================================
-- SERVER NPC REGISTRY
-- Tracks behavioral state for server-side authority computation.
-- [npcId] = { id, x, y, z, followMode, wander_tx, wander_ty, wander_age }
-- ============================================================

local _serverNPCs = {}

-- ============================================================
-- PLAYER LIST HELPER (pattern from Bandits)
-- Returns only non-NPC players (filters out our IsoPlayer NPCs).
-- ============================================================

local function getRealPlayers()
    local gamemode = "Survival"
    pcall(function() gamemode = getWorld():getGameMode() end)
    local pList
    if gamemode == "Multiplayer" then
        pList = getOnlinePlayers and getOnlinePlayers()
    else
        pList = IsoPlayer.getPlayers()
    end
    if not pList then return {} end
    local result = {}
    for i = 0, pList:size() - 1 do
        local p = pList:get(i)
        if p then
            local ok, npcFlag = pcall(function() return p:isNPC() end)
            if not (ok and npcFlag) then
                result[#result + 1] = p
            end
        end
    end
    return result
end

-- ============================================================
-- PHNPC_RequestSpawn handler
-- ============================================================

Dispatcher.on("PHNPC_RequestSpawn", function(data, fromPlayer)
    if not data then return end

    local x = tonumber(data.x) or 0
    local y = tonumber(data.y) or 0
    local z = tonumber(data.z) or 0

    local isFemale = (ZombRand(2) == 1)
    local forename, surname = randomName(isFemale)

    local ts    = tostring(getTimestampMs and getTimestampMs() or os.time())
    local npcId = "PHNPC_" .. forename .. "_" .. surname .. "_" .. ts

    -- Register server-side state
    _serverNPCs[npcId] = {
        id         = npcId,
        x          = x, y = y, z = z,
        followMode = true,
        wander_tx  = x, wander_ty = y,
        wander_age = 999,   -- generate new wander target on first wander tick
    }

    Dispatcher.send("all", "PHNPC_DoSpawn", {
        id = npcId, forename = forename, surname = surname,
        isFemale = isFemale, x = x, y = y, z = z,
    })

    print("[PHNPC] SpawnManager: dispatched "
        .. forename .. " " .. surname .. " @ " .. x .. "," .. y)
end)

-- ============================================================
-- PHNPC_SetFollowMode handler (client informs server of mode change)
-- ============================================================

Dispatcher.on("PHNPC_SetFollowMode", function(data)
    if not data or not data.id then return end
    local ns = _serverNPCs[data.id]
    if ns then
        ns.followMode = data.followMode
        if not data.followMode then
            ns.wander_age = 999     -- trigger new wander target immediately
        end
        print("[PHNPC] SpawnManager: " .. data.id
            .. " followMode=" .. tostring(data.followMode))
    end
end)

-- ============================================================
-- PHNPC_RemoveNPC handler (client signals NPC is dead / removed)
-- ============================================================

Dispatcher.on("PHNPC_RemoveNPC", function(data)
    if data and data.id then
        _serverNPCs[data.id] = nil
        print("[PHNPC] SpawnManager: removed server state for " .. data.id)
    end
end)

-- ============================================================
-- SERVER AUTHORITY TICK
-- Every SYNC_EVERY ticks (~10Hz): compute NPC destination and
-- broadcast PHNPC_SyncTarget to all clients.
-- Clients use this target for pathToLocation() instead of
-- computing locally, which eliminates multiplayer position desync.
-- ============================================================

local _serverTick = 0
local SYNC_EVERY  = 6   -- 10Hz at 60fps, ~3Hz at 20fps server

Events.OnTick.Add(function()
    _serverTick = _serverTick + 1
    if _serverTick % SYNC_EVERY ~= 0 then return end
    -- next() is nil in Kahlua; use pairs early-exit instead
    local _hasNPCs = false
    for _ in pairs(_serverNPCs) do _hasNPCs = true; break end
    if not _hasNPCs then return end

    local players = getRealPlayers()

    for id, ns in pairs(_serverNPCs) do
        local tx, ty, tz = ns.x, ns.y, ns.z

        if ns.followMode and #players > 0 then
            -- Find nearest real player
            local best, bestDistSq = players[1], math.huge
            for _, p in ipairs(players) do
                local dx = p:getX() - ns.x
                local dy = p:getY() - ns.y
                local d2 = dx * dx + dy * dy
                if d2 < bestDistSq then
                    best, bestDistSq = p, d2
                end
            end
            tx = best:getX()
            ty = best:getY()
            tz = best:getZ()
            -- Advance server position estimate toward target
            local dx, dy = tx - ns.x, ty - ns.y
            local dist   = math.sqrt(dx * dx + dy * dy)
            if dist > 1.5 then
                local spd = 1.5 * (SYNC_EVERY / 60)
                ns.x = ns.x + (dx / dist) * math.min(spd, dist)
                ns.y = ns.y + (dy / dist) * math.min(spd, dist)
            end

        else
            -- Wander mode: generate new target when arrived or on start
            ns.wander_age = ns.wander_age + SYNC_EVERY
            if ns.wander_age > 300 then
                ns.wander_tx  = ns.x + ZombRand(16) - 8
                ns.wander_ty  = ns.y + ZombRand(16) - 8
                ns.wander_age = 0
            end
            tx = ns.wander_tx
            ty = ns.wander_ty
            tz = ns.z
            -- Advance server position estimate toward wander target
            local dx, dy = tx - ns.x, ty - ns.y
            local dist   = math.sqrt(dx * dx + dy * dy)
            if dist > 0.5 then
                local spd = 0.8 * (SYNC_EVERY / 60)
                ns.x = ns.x + (dx / dist) * math.min(spd, dist)
                ns.y = ns.y + (dy / dist) * math.min(spd, dist)
            else
                ns.wander_age = 999     -- arrived, generate new target next cycle
            end
        end

        -- Broadcast destination to all clients
        Dispatcher.send("all", "PHNPC_SyncTarget", { id = id, tx = tx, ty = ty, tz = tz })
    end
end)

print("[PHNPC] NPC_SpawnManager v3.0 loaded")