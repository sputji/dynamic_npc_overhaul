--[[
    Project Humain : Dynamic NPC Overhaul — B42
    client/00_Init.lua

    Point d'entrée client.
    - Initialise les registres de PNJ côté client (liste des IDs connus)
    - Câble les réponses réseau serveur → handlers client
]]

if not isClient() then return end

local Log        = PHNPC.getModule("NPC_Logger")
local Dispatcher = PHNPC.getModule("NPC_NetworkDispatcher")

-- Registre client des PNJ connus (données légères pour UI)
PHNPC.clientNPCs = PHNPC.clientNPCs or {}   -- { [npcId] = { name, professionId, ... } }

-- ============================================================
-- Réception des événements serveur → client
-- ============================================================

--- Serveur notifie le spawn d'un PNJ
Dispatcher.on("npc_spawn", function(data)
    if not data or not data.id then return end
    PHNPC.clientNPCs[data.id] = data
    Log.debug("CLIENT", "PNJ spawn reçu", { id = data.id, name = data.fullName })
end)

--- Serveur notifie le despawn d'un PNJ
Dispatcher.on("npc_despawn", function(data)
    if not data or not data.id then return end
    PHNPC.clientNPCs[data.id] = nil
    Log.debug("CLIENT", "PNJ despawn reçu", { id = data.id })
end)

--- Réponse de dialogue d'un PNJ
Dispatcher.on("npc_talk_reply", function(data)
    if not data then return end
    local Bubbles = PHNPC.getModule("NPC_SpeechBubbles")
    if Bubbles then
        Bubbles.show(data.npcId, data.name, data.message)
    end
    local ChatUI = PHNPC.getModule("OllamaChatUI")
    if ChatUI and ChatUI.isOpen() then
        ChatUI.addMessage(data.name, data.message)
    end
end)

--- Le PNJ tousse (morsure cachée)
Dispatcher.on("npc_cough", function(data)
    local Bubbles = PHNPC.getModule("NPC_SpeechBubbles")
    if Bubbles then
        Bubbles.show(data.npcId, data.name, "*tousse*", "cough")
    end
end)

--- Le PNJ s'est transformé
Dispatcher.on("npc_turned", function(data)
    if not data then return end
    PHNPC.clientNPCs[data.npcId] = nil
    -- Notification HUD (TODO : NPC_UI.showNotification)
    Log.warn("CLIENT", "PNJ transformé !", { id = data.npcId, name = data.name })
end)

--- Commerce : ouverture de la fenêtre
Dispatcher.on("npc_trade_open", function(data)
    local TradeWindow = PHNPC.getModule("NPC_TradeWindow")
    if TradeWindow then TradeWindow.open(data) end
end)

Dispatcher.on("npc_trade_result", function(data)
    local TradeWindow = PHNPC.getModule("NPC_TradeWindow")
    if TradeWindow then TradeWindow.onResult(data) end
end)

Log.ok("CLIENT", "Init client PHNPC terminée.")
