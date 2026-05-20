-- Project Humain: Dynamic NPC Overhaul - B42
-- server/NPC_SpawnManager.lua v2.0
-- Receives PHNPC_RequestSpawn from client, generates NPC data,
-- broadcasts PHNPC_DoSpawn to all clients.
-- SOLO: NPC_NetworkDispatcher routes calls directly (no real network).
-- MULTI: server authority over NPC identity; all clients receive DoSpawn.
-- NO BOM. ASCII only.

local Dispatcher = PHNPC.getModule("NPC_NetworkDispatcher")

if not Dispatcher then
    print("[PHNPC] NPC_SpawnManager: NPC_NetworkDispatcher not found, spawn manager disabled.")
    return
end

-- ============================================================
-- FALLBACK NAMES (if SurvivorFactory not available server-side)
-- ============================================================

local FNAMES_M = { "Bob", "Tom", "Alex", "Lucas", "Noah", "Sam", "Chris", "Jack" }
local FNAMES_F = { "Kate", "Emma", "Lea", "Sara", "Nina", "Rose", "Mia",  "Amy"  }
local LNAMES   = { "Martin", "Smith", "Brown", "Durand", "Roux", "Davis", "Clark", "Young" }

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
-- PHNPC_RequestSpawn handler (runs on server or directly in solo)
-- ============================================================

Dispatcher.on("PHNPC_RequestSpawn", function(data, fromPlayer)
    if not data then return end

    local x = tonumber(data.x) or 0
    local y = tonumber(data.y) or 0
    local z = tonumber(data.z) or 0

    -- Server-authoritative identity generation
    local isFemale = (ZombRand(2) == 1)
    local forename, surname = randomName(isFemale)

    -- Unique NPC ID (timestamp-based)
    local ts = tostring(getTimestampMs and getTimestampMs() or os.time())
    local npcId = "PHNPC_" .. forename .. "_" .. surname .. "_" .. ts

    -- Broadcast to all clients so every connected player sees the same NPC
    Dispatcher.send("all", "PHNPC_DoSpawn", {
        id       = npcId,
        forename = forename,
        surname  = surname,
        isFemale = isFemale,
        x        = x,
        y        = y,
        z        = z,
    })

    print("[PHNPC] SpawnManager: dispatched "
        .. forename .. " " .. surname
        .. " @ " .. x .. "," .. y)
end)

print("[PHNPC] NPC_SpawnManager v2.0 loaded")