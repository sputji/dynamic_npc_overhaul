--[[
    Project Humain : Dynamic NPC Overhaul — B42
    client/NPC_InteractionClient.lua

    Menu de clic droit sur une entité PNJ PHNPC :
      "Parler à [Nom du PNJ]" → log via NPC_Logger (stub dialogue)

    Scan de getZombieList() pour détecter les PNJs PHNPC à portée.
    La portée d'interaction est plus large que le rayon de conversion :
    on peut parler à un PNJ à 3 cases même si OnZombieUpdate ne tourne
    pas encore (zone chargée).
]]

local PHNPC_InteractionClient = {}

-- Distance maximale d'interaction (en cases)
local INTERACT_DIST = 3.0

-- ============================================================
-- Hook menu clic droit
-- ============================================================

local function onFillContextMenu(playerIndex, context, worldObjects, test)
    if test then return end

    local player = getSpecificPlayer(playerIndex)
    if not player then return end

    local cell = player:getCell()
    if not cell then return end

    local zombieList = cell:getZombieList()
    if not zombieList or zombieList:size() == 0 then return end

    local px, py = player:getX(), player:getY()

    for i = 0, zombieList:size() - 1 do
        local zombie = zombieList:get(i)
        if zombie then
            -- Lecture ModData protégée
            local mdOk, md = pcall(function() return zombie:getModData() end)
            if mdOk and md and md.PHNPC_IsNPC then
                -- Calcul de distance
                local distOk, dist = pcall(function()
                    local dx = zombie:getX() - px
                    local dy = zombie:getY() - py
                    return math.sqrt(dx * dx + dy * dy)
                end)

                if distOk and dist <= INTERACT_DIST then
                    local npcName = md.PHNPC_FullName or "PNJ Inconnu"
                    context:addOption(
                        "Parler à " .. npcName,
                        zombie,
                        PHNPC_InteractionClient.onTalkClicked,
                        player
                    )
                end
            end
        end
    end
end

-- ============================================================
-- Callback "Parler"
-- Stub : branche NPC_Dialogue + NPC_Brain ici lors de la Phase 3.
-- ============================================================

function PHNPC_InteractionClient.onTalkClicked(zombie, player)
    local Log = PHNPC.getModule("NPC_Logger")
    if not Log then return end

    -- Récupérer les données depuis le registre actif (DataModel en mémoire)
    local npcData = PHNPC._activeNPCs[zombie]

    local name       = (npcData and npcData.fullName)     or "PNJ Inconnu"
    local profession = (npcData and npcData.professionId) or "inconnu"
    local health     = (npcData and npcData.health)       or 100

    Log.info("InteractionClient", "Interaction Parler déclenchée", {
        npc        = name,
        profession = profession,
        health     = health,
        pX         = math.floor(player:getX()),
        pY         = math.floor(player:getY()),
    })

    -- Feedback console (sera remplacé par une bulle de dialogue / UI)
    print(string.format(
        '[PHNPC] %s vous regarde... "..." (dialogue non implémenté — Phase 3)',
        name
    ))
end

-- ============================================================
-- Enregistrement
-- ============================================================

Events.OnPreFillWorldObjectContextMenu.Add(onFillContextMenu)

PHNPC.registerModule("PHNPC_InteractionClient", PHNPC_InteractionClient)
return PHNPC_InteractionClient
