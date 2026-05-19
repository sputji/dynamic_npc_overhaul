--[[
    Project Humain : Dynamic NPC Overhaul — B42
    server/AdminCommands.lua

    Commandes admin via /phnpc <sous-commande> [args...].
    Disponibles uniquement pour les joueurs avec droits admin.

    Commandes :
      /phnpc list            — liste les PNJ actifs
      /phnpc spawn           — force un spawn au joueur
      /phnpc kill <id>       — supprime un PNJ
      /phnpc bite <id>       — marque un PNJ comme mordu (test)
      /phnpc debug           — bascule le mode debug
      /phnpc reload          — recharge la config
]]

if not isServer() then return end

local Log      = PHNPC.getModule("NPC_Logger")
local SpawnMgr = PHNPC.getModule("NPC_SpawnManager")
local BiteMgr  = PHNPC.getModule("NPC_BiteManagement")
local Config   = PHNPC.getModule("NPC_Config")

-- ============================================================
-- Helper : vérification admin
-- ============================================================

local function isAdmin(player)
    return player and (player:isAccessLevel("Admin") or player:isAccessLevel("Moderator"))
end

local function reply(player, msg)
    if player and player.Say then
        player:Say("[PHNPC] " .. msg)
    else
        print("[PHNPC][Admin] " .. msg)
    end
end

-- ============================================================
-- Handlers des sous-commandes
-- ============================================================

local COMMANDS = {}

COMMANDS["list"] = function(player, args)
    local active = SpawnMgr and SpawnMgr.getActive() or {}
    local count  = 0
    for id, data in pairs(active) do
        count = count + 1
        reply(player, string.format("[%d] %s (%s) HP=%d état=%s",
            count, data.fullName, data.professionId, data.health, data.fsmState))
    end
    if count == 0 then reply(player, "Aucun PNJ actif.") end
end

COMMANDS["spawn"] = function(player, args)
    local SpawnManager = PHNPC.getModule("NPC_SpawnManager")
    if SpawnManager then
        -- Forcer un spawn via la fonction interne (exposée pour debug)
        local ok, err = pcall(function()
            -- appeler spawnNearPlayer directement via event simulé
            Events.EveryOneMinute.Trigger()
        end)
        reply(player, ok and "Spawn forcé." or ("Erreur : " .. tostring(err)))
    end
end

COMMANDS["kill"] = function(player, args)
    local npcId = args[1]
    if not npcId then reply(player, "Usage : /phnpc kill <id>") return end
    local active = SpawnMgr and SpawnMgr.getActive() or {}
    local data   = active[npcId]
    if not data then reply(player, "PNJ introuvable : " .. npcId) return end
    if data.isoObject then data.isoObject:removeFromWorld() end
    active[npcId] = nil
    PHNPC.getModule("NPC_Brain").unregister(npcId)
    reply(player, "PNJ supprimé : " .. npcId)
end

COMMANDS["bite"] = function(player, args)
    local npcId = args[1]
    if not npcId then reply(player, "Usage : /phnpc bite <id>") return end
    if BiteMgr then
        BiteMgr.bite(npcId)
        reply(player, "PNJ mordu (test) : " .. npcId)
    end
end

COMMANDS["debug"] = function(player, args)
    local logger = PHNPC.getModule("NPC_Logger")
    if logger then
        logger.enabled = not logger.enabled
        reply(player, "Debug " .. (logger.enabled and "ON" or "OFF"))
    end
end

COMMANDS["reload"] = function(player, args)
    Config.invalidate()
    reply(player, "Configuration rechargée.")
end

-- ============================================================
-- Hook sur la commande /phnpc
-- ============================================================

Events.OnServerCommand.Add(function(modId, cmd, data)
    -- géré par le Dispatcher, mais on intercepte aussi les commandes chat
end)

-- Hook commande chat (B42 : OnCommandEntered sur serveur)
local function onPlayerCommand(command, player)
    if not command then return end
    if not command:match("^/phnpc") then return end
    if not isAdmin(player) then
        reply(player, "Accès refusé (admin requis).")
        return
    end

    local parts  = {}
    for word in command:gmatch("%S+") do parts[#parts + 1] = word end
    local sub    = parts[2] or "list"
    local args   = {}
    for i = 3, #parts do args[#args + 1] = parts[i] end

    local handler = COMMANDS[sub]
    if handler then
        local ok, err = pcall(handler, player, args)
        if not ok then
            Log.error("AdminCommands", "Erreur commande /" .. sub, { err = tostring(err) })
            reply(player, "Erreur : " .. tostring(err))
        end
    else
        reply(player, "Commande inconnue. Disponibles : list, spawn, kill, bite, debug, reload")
    end
end

Events.OnServerStarted.Add(function()
    Events.OnCommandEntered.Add(onPlayerCommand)
    Log.ok("AdminCommands", "Commandes /phnpc enregistrées.")
end)
