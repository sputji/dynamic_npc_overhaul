-- Project Humain: Dynamic NPC Overhaul - B42
-- shared/PHNPC_Stats.lua
-- Noms genres, profils de stats par outfit, generation aleatoire.
-- NO BOM. ASCII only.

PHNPC = PHNPC or {}

-- ============================================================
-- NOMS GENRES
-- ============================================================
PHNPC.NAMES_MALE = {
    "Ethan", "Marcus", "Nathan", "Jake", "Tyler", "Derek", "Logan",
    "Cole", "Hunter", "Zach", "Brett", "Dean", "Travis", "Kyle",
    "Ryan", "Aaron", "Sean", "Adam", "Joel", "Luke",
}

PHNPC.NAMES_FEMALE = {
    "Sarah", "Emma", "Maya", "Chloe", "Lily", "Grace", "Hannah",
    "Rachel", "Amber", "Tara", "Leah", "Kayla", "Brooke", "Megan",
    "Claire", "Jade", "Holly", "Kate", "Molly", "Paige",
}

-- ============================================================
-- PROFILS DE STATS PAR OUTFIT
-- Chaque profil definit les ranges min/max pour chaque stat.
-- Courage  : resistance a la peur des zombies (0-100)
-- Force    : degats en melee, capacite a transporter (0-100)
-- Melee    : competence corps a corps (0-100)
-- Tir      : competence armes a feu (0-100)
-- Endurance: resistance a la fatigue, vitesse de deplacement (0-100)
-- ============================================================
PHNPC.STAT_PROFILES = {
    Police   = { courage={60,95}, force={50,80}, melee={55,85}, tir={60,90}, endurance={55,80} },
    Fireman  = { courage={70,100},force={65,95}, melee={60,90}, tir={30,60}, endurance={70,95} },
    Doctor   = { courage={35,65}, force={30,55}, melee={25,50}, tir={30,60}, endurance={40,65} },
    Ranger   = { courage={55,85}, force={50,80}, melee={45,75}, tir={65,95}, endurance={60,85} },
    Chef     = { courage={30,60}, force={40,70}, melee={35,65}, tir={20,50}, endurance={35,60} },
    Farmer   = { courage={40,70}, force={55,85}, melee={40,70}, tir={40,70}, endurance={50,75} },
    Survivor = { courage={45,75}, force={40,70}, melee={40,70}, tir={35,65}, endurance={45,70} },
}

-- Profil par defaut si outfit inconnu
local DEFAULT_PROFILE = { courage={30,70}, force={30,70}, melee={30,70}, tir={30,70}, endurance={30,70} }

-- ============================================================
-- GENERATION D'UN NOMBRE ALEATOIRE DANS UN RANGE
-- ============================================================
local function randRange(min, max)
    return min + ZombRand(max - min + 1)
end

-- ============================================================
-- GENERER UN NOM GENRE
-- ============================================================
function PHNPC.generateName(isFemale)
    local pool = isFemale and PHNPC.NAMES_FEMALE or PHNPC.NAMES_MALE
    return pool[ZombRand(#pool) + 1]
end

-- ============================================================
-- GENERER LES STATS POUR UN OUTFIT DONNE
-- ============================================================
function PHNPC.generateStats(outfit)
    local profile = PHNPC.STAT_PROFILES[outfit] or DEFAULT_PROFILE
    return {
        courage   = randRange(profile.courage[1],   profile.courage[2]),
        force     = randRange(profile.force[1],      profile.force[2]),
        melee     = randRange(profile.melee[1],      profile.melee[2]),
        tir       = randRange(profile.tir[1],        profile.tir[2]),
        endurance = randRange(profile.endurance[1],  profile.endurance[2]),
    }
end

-- ============================================================
-- DESCRIPTION TEXTUELLE DES STATS (pour le menu)
-- ============================================================
function PHNPC.statsToString(stats)
    if not stats then return "(stats inconnues)" end
    local function bar(v)
        if v >= 80 then return "Excellent" end
        if v >= 60 then return "Bon" end
        if v >= 40 then return "Moyen" end
        return "Faible"
    end
    return string.format(
        "Courage:%s Force:%s Melee:%s Tir:%s Endurance:%s",
        bar(stats.courage), bar(stats.force),
        bar(stats.melee), bar(stats.tir), bar(stats.endurance)
    )
end

-- ============================================================
-- SEUILS DE COMPORTEMENT
-- ============================================================
PHNPC.FEAR_COURAGE_THRESHOLD = 50   -- En-dessous: le NPC peut fuir les zombies
PHNPC.FEAR_ZOMBIE_DIST       = 10   -- Tiles: distance a partir de laquelle le NPC detecte les zombies
PHNPC.FIGHT_COURAGE_THRESHOLD = 40  -- Au-dessus ET zombie proche: le NPC peut attaquer

print("[PHNPC] Stats module loaded (B42)")
