--[[
    Project Humain : Dynamic NPC Overhaul — B42
    server/00_Init.lua

    Point d'entrée serveur.
    Charge et initialise tous les sous-systèmes serveur.
]]

if not isServer() then return end

local Log = PHNPC.getModule("NPC_Logger")
Log.info("SERVER", "Initialisation du serveur PHNPC...")

-- Les modules serveur s'enregistrent via leurs propres fichiers.
-- Ce fichier câble les événements de démarrage.

local function onServerStart()
    local SpawnMgr = PHNPC.getModule("NPC_SpawnManager")
    if SpawnMgr then SpawnMgr.start() end

    local BiteMgr = PHNPC.getModule("NPC_BiteManagement")
    if BiteMgr then BiteMgr.start() end

    local ObsLearning = PHNPC.getModule("NPC_ObservationLearning")
    if ObsLearning then ObsLearning.start() end

    Log.ok("SERVER", "Tous les sous-systèmes démarrés.")
end

Events.OnGameStart.Add(onServerStart)
