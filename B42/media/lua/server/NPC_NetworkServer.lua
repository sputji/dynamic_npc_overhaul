--[[
    Project Humain : Dynamic NPC Overhaul — B42
    server/NPC_NetworkServer.lua

    Traitement des commandes reçues des clients.
    Toutes les commandes passent par NPC_NetworkDispatcher.on().
]]

if not isServer() then return end

local Log        = PHNPC.getModule("NPC_Logger")
local Dispatcher = PHNPC.getModule("NPC_NetworkDispatcher")
local SpawnMgr   = PHNPC.getModule("NPC_SpawnManager")
local Dialogue   = PHNPC.getModule("NPC_Dialogue")
local OllamaBridge = PHNPC.getModule("OllamaBridge")

-- ============================================================
-- Handlers de commandes client → serveur
-- ============================================================

--- Le client demande à parler à un PNJ.
Dispatcher.on("npc_talk", function(data, player)
    if not data or not data.npcId then return end
    local npc = SpawnMgr and SpawnMgr.getById(data.npcId)
    if not npc then return end

    local cfg      = PHNPC.getModule("NPC_Config").get()
    local playerMsg = data.message or ""

    -- Tenter Ollama, sinon fallback dialogue
    local function sendReply(reply)
        Dispatcher.send("client", "npc_talk_reply", {
            npcId   = data.npcId,
            message = reply,
            name    = npc.fullName,
        }, player)
    end

    if cfg.EnableOllama and OllamaBridge then
        OllamaBridge.ask(npc, playerMsg, function(reply, err)
            if err or not reply then
                sendReply(Dialogue.ollamaFallback(npc, playerMsg))
            else
                sendReply(reply)
            end
        end)
    else
        sendReply(Dialogue.ollamaFallback(npc, playerMsg))
    end
end)

--- Le client demande l'inventaire d'un PNJ (commerce).
Dispatcher.on("npc_trade_request", function(data, player)
    if not data or not data.npcId then return end
    local npc = SpawnMgr and SpawnMgr.getById(data.npcId)
    if not npc then return end

    Dispatcher.send("client", "npc_trade_open", {
        npcId     = data.npcId,
        name      = npc.fullName,
        inventory = npc.inventory,
        gold      = npc.gold,
    }, player)
end)

--- Le client confirme un échange.
Dispatcher.on("npc_trade_confirm", function(data, player)
    if not data or not data.npcId then return end
    local npc = SpawnMgr and SpawnMgr.getById(data.npcId)
    if not npc then return end

    -- TODO : validation serveur de l'échange (items, gold, quantités)
    Log.debug("NPC_NetworkServer", "Échange confirmé", { npcId = data.npcId, player = player and player:getUsername() or "?" })
    Dispatcher.send("client", "npc_trade_result", { success = true, npcId = data.npcId }, player)
end)

Log.ok("NPC_NetworkServer", "Handlers réseau serveur enregistrés.")
