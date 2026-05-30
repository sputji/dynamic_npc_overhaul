--[[
    PHNPC_Main.lua  v0.0.16  (client)
    Point d'entree principal et coordinateur d'initialisation du mod.
    Responsable du demarrage ordonne des modules et de la registration
    des evenements racines.

    Ordre de chargement garanti par PZ :
      shared/  => PHNPC_Core.lua, PHNPC_Stats.lua
      client/  => tous les autres modules (alphabetique par defaut PZ)

    Ce fichier est charge EN DERNIER (prefixe PHNPC_Main > les autres
    car "M" > la plupart des autres lettres en tri ASCII) et initialise
    les sous-systemes dans l'ordre correct.

    v0.0.16 :
      - Point d'entree unifie
      - Hook OnGameStart centralise
      - Verification de sante des modules au demarrage
      - Exposition de PHNPC.VERSION pour les autres modules
]]

-- ============================================================
-- VERSION GLOBALE
-- ============================================================
PHNPC = PHNPC or {}
PHNPC.VERSION = "0.0.16"

-- ============================================================
-- VERIFICATION DE SANTE DES MODULES (au demarrage)
-- Verifie que toutes les fonctions critiques sont bien presentes.
-- ============================================================
local function checkModuleHealth()
    local errors = {}

    -- Modules shared
    if not PHNPC.initStats   then errors[#errors+1] = "PHNPC_Stats.lua manquant (initStats)" end
    if not PHNPC.initInventory then errors[#errors+1] = "PHNPC_Stats.lua manquant (initInventory)" end

    -- Modules client
    if not PHNPC.convertToNPC    then errors[#errors+1] = "PHNPC_Convert.lua manquant" end
    if not PHNPC.startFollowing  then errors[#errors+1] = "PHNPC_Actions.lua manquant" end
    if not PHNPC.npcCombatStep   then errors[#errors+1] = "PHNPC_Combat.lua manquant" end
    if not PHNPC.openNPCInventory then errors[#errors+1] = "PHNPC_Inventory.lua manquant" end
    if not PHNPC.autoEquipBestOutfit then errors[#errors+1] = "PHNPC_Outfits.lua manquant" end
    if not PHNPC.findFreeSquareNear then errors[#errors+1] = "PHNPC_Pathfinding.lua manquant" end

    if #errors > 0 then
        for _, e in ipairs(errors) do
            PHNPC.Log.error("Main", e)
        end
    else
        PHNPC.Log.info("Main", "Tous les modules v" .. PHNPC.VERSION .. " charges et valides.")
    end
end

-- ============================================================
-- REINITIALISATION DES REGISTRES A CHAQUE NOUVELLE PARTIE
-- Centralise ici pour eviter les doublons dans chaque module
-- ============================================================
local function onGameStart()
    -- Tables principales
    PHNPC.allNPCs       = {}
    PHNPC.recruited     = {}
    PHNPC._combatTimers = {}
    PHNPC._barkTimers   = {}

    -- Reinitialiser l'inventaire ouvert (Inventory.lua)
    PHNPC._openInventoryNPC = nil

    -- Reinitialiser les timers de pathfinding (Pathfinding.lua)
    PHNPC._pathTimers = {}

    PHNPC.Log.info("Main", "Registres reinitialises pour la nouvelle partie.")
    checkModuleHealth()
end

Events.OnGameStart.Add(onGameStart)

-- ============================================================
-- HOOK ONCONNECTED (mode serveur)
-- ============================================================
Events.OnConnected.Add(function()
    PHNPC.Log.info("Main", "Connexion serveur detectee — reinitialisation des registres.")
    onGameStart()
end)

print("[PHNPC] Main v0.0.18 loaded")
