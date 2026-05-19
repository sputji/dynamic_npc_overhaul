--[[
    Project Humain : Dynamic NPC Overhaul — B42
    client/NPC_InteractionClient.lua

    Gestion des interactions joueur ↔ PNJ :
    - Menu clic-droit sur un PNJ (contexte "Parler", "Commercer", "Examiner")
    - Envoi des commandes au serveur via Dispatcher
]]

if not isClient() then return end

local Log        = PHNPC.getModule("NPC_Logger")
local Dispatcher = PHNPC.getModule("NPC_NetworkDispatcher")

-- ============================================================
-- Détection du PNJ sous le curseur / en contexte
-- ============================================================

--- Retourne l'ID PHNPC d'un IsoObject si c'est un PNJ géré.
local function getPHNPCId(isoObj)
    if not isoObj then return nil end
    local ok, npcId = pcall(function()
        local md = isoObj:getModData()
        return md and md.PHNPC_id
    end)
    return ok and npcId or nil
end

local function getNPCData(npcId)
    return PHNPC.clientNPCs and PHNPC.clientNPCs[npcId]
end

-- ============================================================
-- Menu contextuel clic-droit (B42)
-- ============================================================

local function onFillWorldContextMenu(playerIndex, context, worldObjects, test)
    if test then return true end

    for _, obj in ipairs(worldObjects) do
        local npcId = getPHNPCId(obj)
        if npcId then
            local data   = getNPCData(npcId)
            local name   = data and data.fullName or "PNJ"
            local player = getSpecificPlayer(playerIndex)

            -- Option : Parler
            context:addOption("Parler à " .. name, obj, function()
                local ChatUI = PHNPC.getModule("OllamaChatUI")
                if ChatUI then
                    ChatUI.open(npcId, name, player)
                else
                    -- Dialogue rapide sans UI complète
                    Dispatcher.send("server", "npc_talk", { npcId = npcId, message = "Bonjour" })
                end
            end)

            -- Option : Commercer (seulement si profession marchande)
            local profId = data and data.professionId
            if profId == "merchant" or profId == "cook" or profId == "artisan" then
                context:addOption("Commercer avec " .. name, obj, function()
                    Dispatcher.send("server", "npc_trade_request", { npcId = npcId })
                end)
            end

            -- Option : Examiner
            context:addOption("Examiner " .. name, obj, function()
                local NPCUI = PHNPC.getModule("NPC_UI")
                if NPCUI then NPCUI.showInfo(npcId) end
            end)

            break  -- Un seul PNJ par contexte
        end
    end
end

Events.OnPreFillWorldObjectContextMenu.Add(onFillWorldContextMenu)

Log.ok("NPC_InteractionClient", "Menu contextuel PNJ enregistré.")
