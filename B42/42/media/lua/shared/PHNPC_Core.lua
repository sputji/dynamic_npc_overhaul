--[[
    PHNPC_Core.lua  v0.0.9d  (shared)
    Etat global + constantes + stats par metier
    Project Humain : Dynamic NPC Overhaul
    Pattern: NPC_Helper_Mod GCCore.lua
    v0.0.9d : ajout PHNPC.Log minimal (etendu par PHNPC_Log.lua),
              nouvelles constantes comportement (STAY_RADIUS, etc.),
              suppression FOLLOW_TARGET_DIST (offset causait la rotation)
    v0.0.9c : suppression REPEL_DISTANCE, ajout DANGER constants
]]

PHNPC = PHNPC or {}
PHNPC.allNPCs   = PHNPC.allNPCs or {}   -- [npcRef] = true  (tous les NPCs actifs)
PHNPC.recruited = PHNPC.recruited or {}  -- [npcRef] = true  (recrutes)

-- ============================================================
-- LOGGING MINIMAL (etendu par client/PHNPC_Log.lua)
-- Disponible des le chargement de Core (shared, premier fichier charge)
-- ============================================================
PHNPC.Log = {
    LEVEL = 0,  -- 0=DEBUG 1=INFO 2=WARN 3=ERROR (remplace par PHNPC_Log.lua)
    debug = function(m, s) print("[PHNPC][DBG]["..tostring(m).."] "..tostring(s)) end,
    info  = function(m, s) print("[PHNPC][INF]["..tostring(m).."] "..tostring(s)) end,
    warn  = function(m, s) print("[PHNPC][WRN]["..tostring(m).."] "..tostring(s)) end,
    error = function(m, s) print("[PHNPC][ERR]["..tostring(m).."] "..tostring(s)) end,
    npc   = function(n, l, s)
        local nm = "?"
        pcall(function() nm = n:getModData().PHNPC_Name or "NPC" end)
        print("[PHNPC]["..tostring(l or "INF").."][NPC:"..nm.."] "..tostring(s))
    end,
    npcState = function(_) end,  -- stub, active par PHNPC_Log.lua
}

-- ============================================================
-- CONFIG IA
-- ============================================================
PHNPC.FOLLOW_DISTANCE      = 6    -- tiles : redemarrer le suivi si joueur plus loin que ca
PHNPC.FOLLOW_STOP_DISTANCE = 2    -- tiles : s'arreter a cette distance du joueur
PHNPC.FOLLOW_MOVE_THRESHOLD = 2   -- tiles : seuil de deplacement joueur pour recalculer pathfind
PHNPC.FOLLOW_TICK_RATE     = 20   -- ticks entre deux recalculs pathfind (si joueur bouge)
PHNPC.INTERACTION_DIST     = 3    -- tiles : rayon clic droit pour interagir

-- ============================================================
-- COMPORTEMENT ZONE (staying / free / shelter)
-- ============================================================
PHNPC.STAY_RADIUS          = 5    -- tiles : rayon de la zone "Reste ici" / arrivee "Va la-bas"
PHNPC.PATROL_RADIUS        = 3    -- tiles : rayon d'exploration libre dans la zone
PHNPC.FREE_WANDER_DIST     = 10   -- tiles : distance max d'errance en etat "free"
PHNPC.ZONE_PATROL_TICKS    = 200  -- ticks entre deux mouvements de patrouille dans la zone

-- ============================================================
-- COMBAT IA (GCCombatAI.lua pattern NPC_Helper_Mod)
-- ============================================================
PHNPC.COMBAT_RANGE        = 8    -- tiles : rayon detection zombie pour combat auto
PHNPC.COMBAT_ATTACK_RANGE = 1.5  -- tiles : distance d'attaque melee
PHNPC.COMBAT_TICK_RATE    = 30   -- ticks entre evaluations combat
PHNPC.FLEE_HP_RATIO       = 0.30 -- ratio HP pour declencher la fuite (30%)
PHNPC.FLEE_DISTANCE       = 15   -- tiles : distance cible de fuite
PHNPC.FLEE_ESCAPE_TRIES   = 8    -- nombre de directions testees pour trouver une fuite libre
PHNPC.BARK_TICK_RATE      = 500  -- ticks entre barks auto (~8 sec a 60fps)

-- ============================================================
-- DANGER : sons NPC + agro zombies (PHNPC_Danger.lua)
-- ============================================================
PHNPC.AGGRO_RANGE       = 10   -- tiles : rayon dans lequel les zombies peuvent cibler le NPC
PHNPC.NOISE_RADIUS      = 12   -- tiles : rayon du bruit (bark/attaque) qui attire les zombies
PHNPC.DANGER_TICK_RATE  = 80   -- ticks entre chaque scan d'agro zombies

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
        speed     = 0.62,
        strength  = 7,
        health    = 90,
        maxWeight = 15.0,
        items     = { "Base.Shovel", "Base.Trowel" },
    },
    Police  = {
        speed     = 0.70,
        strength  = 8,
        health    = 110,
        maxWeight = 20.0,
        -- v0.0.9f : essai Base.PoliceBaton puis Base.NightStick (nom variable selon build B42)
        items     = { {"Base.PoliceBaton", "Base.NightStick"}, "Base.HandTorch" },
    },
    Fireman = {
        speed     = 0.68,
        strength  = 9,
        health    = 120,
        maxWeight = 25.0,
        items     = { "Base.Axe" },
    },
    Doctor  = {
        speed     = 0.62,
        strength  = 6,
        health    = 100,
        maxWeight = 15.0,
        items     = { "Base.BandageDirty", "Base.Painkillers" },
    },
    Ranger  = {
        speed     = 0.75,
        strength  = 7,
        health    = 105,
        maxWeight = 18.0,
        items     = { "Base.HuntingKnife", "Base.HandTorch" },
    },
    Chef    = {
        speed     = 0.62,
        strength  = 6,
        health    = 90,
        maxWeight = 15.0,
        items     = { "Base.KitchenKnife", "Base.CanOpener" },
    },
    Survivor = {
        speed     = 0.65,
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
-- NOMS ALEATOIRES (v0.0.9f : Prenom + Nom de famille complets)
-- ============================================================
PHNPC.NAMES_M = {
    "Marc Dupont",    "Thomas Martin",  "Pierre Bernard", "Jean Durand",
    "Luc Moreau",     "Paul Lambert",   "Alain Simon",    "Denis Leroy",
    "Francois Garcia","Michel Roux",    "David Legrand",  "Stephane Henry",
    "Laurent Petit",  "Nicolas Blanc",  "Patrick Renard", "Bruno Girard",
}
PHNPC.NAMES_F = {
    "Marie Dupont",   "Sophie Leclerc", "Claire Fontaine","Anne Renard",
    "Julie Vidal",    "Laura Bonnet",   "Emma Richard",   "Chloe Morin",
    "Sarah Lambert",  "Lucie Girard",   "Isabelle Perrin","Valerie Picard",
    "Cecile Rousseau","Nathalie Faure", "Sandrine Michel","Christine Roy",
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
