--[[
    Project Humain : Dynamic NPC Overhaul — B42
    shared/NPC_FactionManager.lua

    Gestion des factions et des relations PNJ ↔ Joueur ↔ PNJ.
    Chaque PNJ appartient à une faction.
    Les factions ont des relations entre elles (alliées / neutres / hostiles).
]]

local NPC_FactionManager = {
    _factions  = {},   -- { [id] = { label, relations={[otherId]=value} } }
    _npcFaction = {},  -- { [npcId] = factionId }
}

-- ============================================================
-- Définitions de factions par défaut
-- ============================================================
local DEFAULT_FACTIONS = {
    survivors = {
        label     = "Survivants",
        color     = { r = 0.2, g = 0.8, b = 0.2 },
        relations = { survivors = 60, traders = 50, bandits = -50, unknown = 0 },
    },
    traders = {
        label     = "Marchands",
        color     = { r = 0.9, g = 0.8, b = 0.1 },
        relations = { survivors = 50, traders = 70, bandits = -30, unknown = 20 },
    },
    bandits = {
        label     = "Bandits",
        color     = { r = 0.9, g = 0.2, b = 0.2 },
        relations = { survivors = -50, traders = -30, bandits = 80, unknown = -20 },
    },
    unknown = {
        label     = "Inconnu",
        color     = { r = 0.5, g = 0.5, b = 0.5 },
        relations = { survivors = 0, traders = 20, bandits = -20, unknown = 30 },
    },
}

-- ============================================================
-- Initialisation
-- ============================================================

function NPC_FactionManager.init()
    for id, def in pairs(DEFAULT_FACTIONS) do
        NPC_FactionManager._factions[id] = {
            label     = def.label,
            color     = def.color,
            relations = PHNPC.deepCopy(def.relations),
        }
    end
end

-- ============================================================
-- API factions
-- ============================================================

--- Assigne un PNJ à une faction.
function NPC_FactionManager.assign(npcId, factionId)
    NPC_FactionManager._npcFaction[npcId] = factionId
end

--- Retourne la faction d'un PNJ (ou "unknown").
function NPC_FactionManager.getFaction(npcId)
    return NPC_FactionManager._npcFaction[npcId] or "unknown"
end

--- Retourne la relation entre deux factions (-100 / +100).
function NPC_FactionManager.getRelation(factionA, factionB)
    local f = NPC_FactionManager._factions[factionA]
    if not f then return 0 end
    return f.relations[factionB] or 0
end

--- Modifie la relation entre deux factions.
function NPC_FactionManager.adjustRelation(factionA, factionB, delta)
    local f = NPC_FactionManager._factions[factionA]
    if not f then return end
    local v = (f.relations[factionB] or 0) + delta
    f.relations[factionB] = PHNPC.clamp(v, -100, 100)
end

--- Retourne la relation entre un PNJ et un autre PNJ.
function NPC_FactionManager.npcRelation(npcIdA, npcIdB)
    local fA = NPC_FactionManager.getFaction(npcIdA)
    local fB = NPC_FactionManager.getFaction(npcIdB)
    return NPC_FactionManager.getRelation(fA, fB)
end

--- Liste toutes les factions.
function NPC_FactionManager.list()
    local out = {}
    for id, f in pairs(NPC_FactionManager._factions) do
        out[#out + 1] = { id = id, label = f.label, color = f.color }
    end
    return out
end

-- Initialisation automatique au chargement
NPC_FactionManager.init()

PHNPC.registerModule("NPC_FactionManager", NPC_FactionManager)
return NPC_FactionManager
