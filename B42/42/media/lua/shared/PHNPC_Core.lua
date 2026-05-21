--[[
    PHNPC_Core.lua  v0.1  (shared)
    Etat global - Project Humain : Dynamic NPC Overhaul
    Pattern: NPC_Helper_Mod GCCore.lua
]]

PHNPC = PHNPC or {}
PHNPC.allNPCs   = PHNPC.allNPCs or {}   -- [npcRef] = true  (tous les NPCs actifs)
PHNPC.recruited = PHNPC.recruited or {}  -- [npcRef] = true  (recrutes : following ou staying)

-- Config IA
PHNPC.FOLLOW_DISTANCE   = 3    -- tiles : distance min avant d'arreter le suivi
PHNPC.FOLLOW_TICK_RATE  = 20   -- ticks entre deux appels pathToCharacter
PHNPC.INTERACTION_DIST  = 3    -- tiles : rayon clic droit pour interagir

-- Outfits disponibles au spawn
PHNPC.OUTFITS = {
    "Farmer", "Police", "Fireman", "Doctor",
    "Ranger", "Chef", "Survivor",
}

-- Noms aleatoires
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

-- Renvoie true si ce zombie est un de nos NPCs
function PHNPC.isNPC(zombie)
    if not zombie then return false end
    return PHNPC.allNPCs[zombie] == true
end

print("[PHNPC] Core v0.1 loaded")
