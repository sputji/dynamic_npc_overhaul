--[[
    PHNPC_Core.lua  v0.0.9b  (shared)
    Etat global + constantes + stats par metier
    Project Humain : Dynamic NPC Overhaul
    Pattern: NPC_Helper_Mod GCCore.lua
    v0.0.9b : FOLLOW_STOP_DISTANCE 3->2, FOLLOW_DISTANCE 8->6,
              REPEL_DISTANCE ajoute pour anti-sticking joueur
]]

PHNPC = PHNPC or {}
PHNPC.allNPCs   = PHNPC.allNPCs or {}   -- [npcRef] = true  (tous les NPCs actifs)
PHNPC.recruited = PHNPC.recruited or {}  -- [npcRef] = true  (recrutes : following ou staying)

-- ============================================================
-- CONFIG IA
-- ============================================================
PHNPC.FOLLOW_DISTANCE      = 6    -- tiles : redemarrer le suivi si le joueur est plus loin que ca
PHNPC.FOLLOW_STOP_DISTANCE = 2    -- tiles : s'arreter a cette distance du joueur (pas sur sa case)
PHNPC.FOLLOW_TARGET_DIST   = 2.5  -- tiles : point cible du pathfind (STOP + 0.5 buffer)
PHNPC.REPEL_DISTANCE       = 1.5  -- tiles : seuil en-dessous duquel on repousse le NPC
PHNPC.FOLLOW_TICK_RATE  = 20   -- ticks entre deux appels pathToLocationF
PHNPC.INTERACTION_DIST  = 3    -- tiles : rayon clic droit pour interagir

-- ============================================================
-- COMBAT IA (GCCombatAI.lua pattern NPC_Helper_Mod)
-- ============================================================
PHNPC.COMBAT_RANGE       = 8    -- tiles : rayon detection zombie pour combat auto
PHNPC.COMBAT_ATTACK_RANGE = 1.5 -- tiles : distance d'attaque melee
PHNPC.COMBAT_TICK_RATE   = 30   -- ticks entre evaluations combat
PHNPC.FLEE_HP_RATIO      = 0.30 -- ratio HP pour declencher la fuite (30%)
PHNPC.FLEE_DISTANCE      = 15   -- tiles : distance cible de fuite depuis le danger
PHNPC.BARK_TICK_RATE     = 500  -- ticks entre barks auto (~8 sec a 60fps)

-- ============================================================
-- SANTE
-- ============================================================
PHNPC.MAX_HEALTH = 100         -- PV par defaut si outfit inconnu

-- ============================================================
-- STATS PAR METIER
-- speed     : multiplicateur de vitesse (setSpeedMod)
-- strength  : force (0-10), influence les degats infliges (futur)
-- health    : points de vie max
-- maxWeight : poids max inventaire (kg)
-- items     : items donnes au spawn
-- ============================================================
PHNPC.OUTFIT_STATS = {
    Farmer  = {
        speed     = 0.75,
        strength  = 7,
        health    = 90,
        maxWeight = 15.0,
        items     = { "Base.Shovel", "Base.Trowel" },
    },
    Police  = {
        speed     = 0.85,
        strength  = 8,
        health    = 110,
        maxWeight = 20.0,
        items     = { "Base.PoliceBaton", "Base.HandTorch" },
    },
    Fireman = {
        speed     = 0.80,
        strength  = 9,
        health    = 120,
        maxWeight = 25.0,
        items     = { "Base.Axe" },
    },
    Doctor  = {
        speed     = 0.78,
        strength  = 6,
        health    = 100,
        maxWeight = 15.0,
        items     = { "Base.BandageDirty", "Base.Painkillers" },
    },
    Ranger  = {
        speed     = 0.90,
        strength  = 7,
        health    = 105,
        maxWeight = 18.0,
        items     = { "Base.HuntingKnife", "Base.HandTorch" },
    },
    Chef    = {
        speed     = 0.75,
        strength  = 6,
        health    = 90,
        maxWeight = 15.0,
        items     = { "Base.KitchenKnife", "Base.CanOpener" },
    },
    Survivor = {
        speed     = 0.80,
        strength  = 7,
        health    = 100,
        maxWeight = 18.0,
        items     = { "Base.Crowbar" },
    },
}

-- ============================================================
-- OUTFITS DISPONIBLES AU SPAWN
-- ============================================================
PHNPC.OUTFITS = {
    "Farmer", "Police", "Fireman", "Doctor",
    "Ranger", "Chef", "Survivor",
}

-- ============================================================
-- NOMS ALEATOIRES
-- ============================================================
PHNPC.NAMES_M = {
    "Marc", "Thomas", "Pierre", "Jean", "Luc",
    "Paul", "Alain", "Denis", "Francois", "Michel",
}
PHNPC.NAMES_F = {
    "Marie", "Sophie", "Claire", "Anne", "Julie",
    "Laura", "Emma", "Chloe", "Sarah", "Lucie",
}

function PHNPC.getRandomName(isFemale)
    local list = isFemale and PHNPC.NAMES_F or PHNPC.NAMES_M
    return list[ZombRand(#list) + 1]
end

-- ============================================================
-- HELPERS GLOBAUX
-- ============================================================

-- Renvoie true si ce zombie est un de nos NPCs
function PHNPC.isNPC(zombie)
    if not zombie then return false end
    return PHNPC.allNPCs[zombie] == true
end

-- Renvoie les stats de l'outfit (avec fallback Survivor)
function PHNPC.getOutfitStats(outfit)
    return PHNPC.OUTFIT_STATS[outfit] or PHNPC.OUTFIT_STATS["Survivor"]
end

print("[PHNPC] Core v0.0.9a loaded")
