--[[
    Project Humain : Dynamic NPC Overhaul — B42
    client/NPC_SpawnDebug.lua

    Menu de debug (clic droit sur le sol ou n'importe quel objet monde) :
      "PHNPC Debug : Spawner un PNJ"

    Visible uniquement si le joueur est admin ou si le mode debug PZ est actif.

    Flux solo   : client → sendServerCommand → Events.OnClientCommand (même Lua) → spawn
    Flux multi  : client → réseau → serveur → spawn → PHNPC_SpawnConfirm → client

    Le spawn réel de l'entité est toujours exécuté côté serveur
    (server/NPC_SpawnManager.lua).  La conversion visuelle et l'attachement
    du DataModel sont gérés par client/NPC_FollowTick.lua via OnZombieUpdate.
]]

local PHNPC_SpawnDebug = {}

-- ============================================================
-- Helpers
-- ============================================================

--- Retourne true si le joueur est autorisé à utiliser le menu de debug.
local function isAdminOrDebug(player)
    local ok, result = pcall(function()
        return player:isAccessLevel("admin") or getDebug()
    end)
    return ok and (result == true)
end

-- ============================================================
-- Hook menu clic droit
-- ============================================================

local function onFillContextMenu(playerIndex, context, worldObjects, test)
    if test then return end

    local player = getSpecificPlayer(playerIndex)
    if not player then return end
    if not isAdminOrDebug(player) then return end

    -- Toujours présent pour un admin, quelle que soit la cible du clic.
    context:addOption(
        "PHNPC Debug : Spawner un PNJ",
        player,
        PHNPC_SpawnDebug.requestSpawn
    )
end

-- ============================================================
-- Demande de spawn (client → serveur)
-- ============================================================

--- Envoyé au serveur pour déclencher le spawn réel de l'entité.
-- En solo, Events.OnClientCommand est traité dans le même état Lua
-- (pas de réseau), donc l'appel est synchrone.
function PHNPC_SpawnDebug.requestSpawn(player)
    local Log = PHNPC.getModule("NPC_Logger")
    if Log then
        Log.info("SpawnDebug", "Demande de spawn envoyée au serveur",
            { x = math.floor(player:getX()), y = math.floor(player:getY()) })
    end

    -- Le serveur cherchera lui-même une case libre autour de ces coordonnées.
    sendServerCommand(PHNPC.MOD_ID, "PHNPC_SpawnRequest", {
        x = player:getX(),
        y = player:getY(),
        z = player:getZ(),
    })
end

-- ============================================================
-- Enregistrement
-- ============================================================

Events.OnPreFillWorldObjectContextMenu.Add(onFillContextMenu)

PHNPC.registerModule("PHNPC_SpawnDebug", PHNPC_SpawnDebug)
return PHNPC_SpawnDebug
