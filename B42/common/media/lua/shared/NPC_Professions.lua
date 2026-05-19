--[[
    Project Humain : Dynamic NPC Overhaul — B42
    shared/NPC_Professions.lua

    Définition des 5 métiers : Marchand, Cuisinier, Artisan, Médecin, Explorateur.
    Chaque profession expose :
      - label        : nom affiché
      - produces     : catégories de produits créés
      - buys / sells : catégories échangées
      - tradeMode    : "barter" | "broker" | "gift"
      - fsm_priorities : ordre des états FSM préférés
      - outfitHints  : noms d'outfit B42 (SurvivorFactory)
      - skillBonuses : { [pzSkillName] = xpBonus }
]]

local NPC_Professions = {}

-- ============================================================
-- Catalogue
-- ============================================================
NPC_Professions.catalog = {

    merchant = {
        label      = "Marchand",
        produces   = { "general_goods", "materials" },
        buys       = { "food", "water", "medicine", "tools", "materials", "weapons", "crafts" },
        sells      = { "general_goods", "materials", "tools" },
        tradeMode  = "broker",
        fsm_priorities = { "trade", "wander", "guard", "defend" },
        outfitHints    = { "Business_M", "Business_F" },
        skillBonuses   = { Farming = 2, Carpentry = 1 },
    },

    cook = {
        label      = "Cuisinier",
        produces   = { "food" },
        buys       = { "food", "water", "fuel", "seasoning" },
        sells      = { "food" },
        tradeMode  = "barter",
        fsm_priorities = { "work", "trade", "wander", "defend" },
        outfitHints    = { "Chef_M", "Chef_F", "Civilian_M", "Civilian_F" },
        skillBonuses   = { Cooking = 5, Farming = 2 },
    },

    artisan = {
        label      = "Artisan",
        produces   = { "tools", "materials", "crafts" },
        buys       = { "materials", "tools", "food", "water" },
        sells      = { "tools", "materials", "crafts" },
        tradeMode  = "barter",
        fsm_priorities = { "work", "wander", "trade", "defend" },
        outfitHints    = { "Carpenter_M", "Carpenter_F", "Worker_M", "Worker_F" },
        skillBonuses   = { Carpentry = 5, MetalWelding = 3, Mechanics = 2 },
    },

    medic = {
        label      = "Médecin",
        produces   = { "medicine" },
        buys       = { "medicine", "cloth", "alcohol", "food", "water" },
        sells      = { "medicine" },
        tradeMode  = "barter",
        fsm_priorities = { "work", "guard", "defend", "wander" },
        outfitHints    = { "Doctor_M", "Doctor_F" },
        skillBonuses   = { Doctor = 5, FirstAid = 3 },
    },

    explorer = {
        label      = "Explorateur",
        produces   = { "loot", "information" },
        buys       = { "food", "water", "weapons", "ammo", "tools" },
        sells      = { "loot", "weapons", "ammo" },
        tradeMode  = "barter",
        fsm_priorities = { "wander", "defend", "work", "trade" },
        outfitHints    = { "Hunter_M", "Hunter_F", "Military_M", "Military_F" },
        skillBonuses   = { Aiming = 3, Nimble = 3, Sneaking = 2, Trapping = 2 },
    },
}

-- ============================================================
-- API
-- ============================================================

--- Retourne la définition d'une profession (ou nil).
function NPC_Professions.get(id)
    return NPC_Professions.catalog[id]
end

--- Liste de tous les IDs de professions.
function NPC_Professions.ids()
    local t = {}
    for k in pairs(NPC_Professions.catalog) do t[#t + 1] = k end
    return t
end

--- Profession aléatoire.
function NPC_Professions.random()
    local ids = NPC_Professions.ids()
    return ids[PHNPC.randInt(1, #ids)]
end

--- Retourne un nom d'outfit compatible B42 depuis les hints d'une profession.
-- Utilise dressInNamedOutfit(outfitName) sur le SurvivorDesc.
function NPC_Professions.getOutfit(profId, isFemale)
    local prof = NPC_Professions.catalog[profId]
    if not prof then return isFemale and "Civilian_F" or "Civilian_M" end
    local hints = prof.outfitHints or {}
    -- Filtrer par genre si possible
    local filtered = {}
    local suffix   = isFemale and "_F" or "_M"
    for _, h in ipairs(hints) do
        if h:sub(-2) == suffix then filtered[#filtered + 1] = h end
    end
    if #filtered > 0 then return filtered[PHNPC.randInt(1, #filtered)] end
    if #hints    > 0 then return hints[PHNPC.randInt(1, #hints)] end
    return isFemale and "Civilian_F" or "Civilian_M"
end

PHNPC.registerModule("NPC_Professions", NPC_Professions)
return NPC_Professions
