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
            -- Détection robuste cross-VM (B42 : ModData inaccessible entre VMs)
            -- Méthode 1 : registre _activeNPCs (populé par attachDataModel côté client)
            local isNPC = PHNPC._activeNPCs ~= nil and PHNPC._activeNPCs[zombie] ~= nil
            -- Méthode 2 : variable Java setVariable/getVariableBoolean (cross-VM safe)
            if not isNPC then
                pcall(function()
                    isNPC = zombie:getVariableBoolean("PHNPC_IsNPC") == true
                end)
            end

            if isNPC then
                -- Calcul de distance
                local distOk, dist = pcall(function()
                    local dx = zombie:getX() - px
                    local dy = zombie:getY() - py
                    return math.sqrt(dx * dx + dy * dy)
                end)

                if distOk and dist <= INTERACT_DIST then
                    local npcData = PHNPC._activeNPCs and PHNPC._activeNPCs[zombie]
                    local npcName = (npcData and npcData.fullName) or "Survivant"
                    context:addOption(
                        "Parler à " .. npcName,
                        zombie,
                        PHNPC_InteractionClient.onTalkClicked,
                        player
                    )                    -- Option de suivi / autonomie
                    local isFollowing = npcData and npcData.followMode or false
                    local followLabel = isFollowing
                        and ("\u25A0 Rester ici  \u2014 " .. npcName)
                        or  ("\u25B6 Suivre moi \u2014 " .. npcName)
                    context:addOption(
                        followLabel,
                        zombie,
                        PHNPC_InteractionClient.onFollowToggle,
                        player
                    )                end
            end
        end
    end
end

-- ============================================================
-- Callback "Parler"
-- Stub : branche NPC_Dialogue + NPC_Brain ici lors de la Phase 3.
-- ============================================================

function PHNPC_InteractionClient.onTalkClicked(zombie, player)
    local Log    = PHNPC.getModule("NPC_Logger")
    local npcData = PHNPC._activeNPCs and PHNPC._activeNPCs[zombie]
    local name    = (npcData and npcData.fullName) or "PNJ Inconnu"

    if Log then
        Log.info("InteractionClient", "Dialogue ouvert", {
            npc = name,
            pX  = math.floor(player:getX()),
            pY  = math.floor(player:getY()),
        })
    end

    -- Ouvrir la fenêtre de dialogue (Phase 3)
    local DialogueWindow = PHNPC.getModule("NPC_DialogueWindow")
    if DialogueWindow then
        DialogueWindow.open(npcData or { fullName = name }, zombie)
    else
        -- Fallback texte si la fenêtre n'est pas chargée
        local Dlg  = PHNPC.getModule("NPC_Dialogue")
        local line = Dlg and Dlg.get("greeting", { name = name }) or "..."
        print(string.format('[PHNPC] %s : "%s"', name, line))
    end
end

-- ============================================================
-- Callback "Suivre moi" / "Rester ici"
-- Bascule le mode de suivi du NPC.
-- ============================================================

function PHNPC_InteractionClient.onFollowToggle(zombie, player)
    local npcData = PHNPC._activeNPCs and PHNPC._activeNPCs[zombie]
    if not npcData then return end

    npcData.followMode = not npcData.followMode

    local mode = npcData.followMode and "suivi" or "autonome"
    local Log  = PHNPC.getModule("NPC_Logger")
    if Log then
        Log.info("InteractionClient", "Mode NPC bascul\u00e9",
            { npc = npcData.fullName, mode = mode })
    end
    print(string.format("[PHNPC] %s \u2192 mode %s", npcData.fullName or "NPC", mode))

    -- Feedback vocal : ligne de dialogue adapt\u00e9e au mode choisi
    local Bubble = PHNPC.getModule("NPC_SpeechBubble")
    local Dlg    = PHNPC.getModule("NPC_Dialogue")
    if Bubble and Dlg then
        local ctx  = npcData.followMode and "greeting" or "idle"
        local line = Dlg.get(ctx, { name = npcData.firstName or "?" })
        pcall(function() Bubble.show(npcData, zombie, line) end)
    end
end

-- ============================================================
-- Enregistrement
-- ============================================================

Events.OnPreFillWorldObjectContextMenu.Add(onFillContextMenu)

PHNPC.registerModule("PHNPC_InteractionClient", PHNPC_InteractionClient)
return PHNPC_InteractionClient
