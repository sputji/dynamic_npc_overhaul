--[[
    Project Humain : Dynamic NPC Overhaul — B42
    server/NPC_BiteManagement.lua

    Système de morsure cachée :
    - Le PNJ tousse à intervalles aléatoires
    - L'anxiété monte progressivement
    - À 100% de trauma → le PNJ tourne zombie (événement)
]]

if not isServer() then return end

local Log      = PHNPC.getModule("NPC_Logger")
local Config   = PHNPC.getModule("NPC_Config")
local SpawnMgr = PHNPC.getModule("NPC_SpawnManager")
local Dispatcher = PHNPC.getModule("NPC_NetworkDispatcher")

local NPC_BiteManagement = {
    _started  = false,
    _timers   = {},   -- { [npcId] = secondsUntilCough }
}

-- ============================================================
-- Logique interne
-- ============================================================

local function processBitten(npcId, data, cfg)
    -- Décroissance morale / montée anxiété
    data:setNeed("morale", -(0.5))
    data.trauma = PHNPC.clamp(data.trauma + 0.3, 0, 100)

    -- Toux aléatoire
    local timer = NPC_BiteManagement._timers[npcId] or 0
    timer = timer - 1
    if timer <= 0 then
        local prob = cfg.BiteCoughProbabilityPercent or 15
        if PHNPC.randInt(1, 100) <= prob then
            Dispatcher.send("all", "npc_cough", { npcId = npcId, name = data.fullName })
            Log.debug("NPC_BiteManagement", "PNJ tousse", { id = npcId })
        end
        timer = cfg.BiteCoughIntervalSec or 30
    end
    NPC_BiteManagement._timers[npcId] = timer

    -- Seuil critique : transformation
    if data.trauma >= 100 then
        Log.warn("NPC_BiteManagement", "PNJ transformé en zombie !", { id = npcId })
        Dispatcher.send("all", "npc_turned", { npcId = npcId, name = data.fullName })
        -- TODO : remplacer l'IsoPlayer par un IsoZombie natif B42
        local iso = data.isoObject
        if iso then iso:removeFromWorld() end
        SpawnMgr.getActive()[npcId] = nil
        PHNPC.getModule("NPC_Brain").unregister(npcId)
    end
end

-- ============================================================
-- Boucle (toutes les 10 secondes)
-- ============================================================

local _tenSecTimer = 0

local function onTick()
    _tenSecTimer = _tenSecTimer + 1
    if _tenSecTimer < 300 then return end   -- ~10 s @ 30fps
    _tenSecTimer = 0

    local cfg     = Config.get()
    local active  = SpawnMgr and SpawnMgr.getActive() or {}

    for npcId, data in pairs(active) do
        if data.bitten then
            local ok, err = pcall(processBitten, npcId, data, cfg)
            if not ok and Log then
                Log.error("NPC_BiteManagement", "Erreur traitement morsure", { id = npcId, err = tostring(err) })
            end
        end
    end
end

-- ============================================================
-- API publique
-- ============================================================

--- Marque un PNJ comme mordu.
-- @param npcId  string
function NPC_BiteManagement.bite(npcId)
    local active = SpawnMgr and SpawnMgr.getActive() or {}
    local data   = active[npcId]
    if not data then return end
    data.bitten   = true
    data.biteTime = getTimestampMs and getTimestampMs() or 0
    Log.warn("NPC_BiteManagement", "PNJ mordu !", { id = npcId })
    -- Notifier les clients (bulle anxiété, animation)
    Dispatcher.send("all", "npc_bitten", { npcId = npcId })
end

function NPC_BiteManagement.start()
    if NPC_BiteManagement._started then return end
    Events.OnTick.Add(onTick)
    NPC_BiteManagement._started = true
    Log.ok("NPC_BiteManagement", "Bite management démarré.")
end

PHNPC.registerModule("NPC_BiteManagement", NPC_BiteManagement)
return NPC_BiteManagement
