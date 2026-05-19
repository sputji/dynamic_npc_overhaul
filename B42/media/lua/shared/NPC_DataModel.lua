--[[
    Project Humain : Dynamic NPC Overhaul — B42
    shared/NPC_DataModel.lua

    Modèle de données d'un PNJ dynamique.
    Utilise IsoPlayer (B42) avec setNPC(true) + SurvivorFactory pour le descripteur.
    Pattern OO via métatable.
]]

local Log = PHNPC.getModule("NPC_Logger")

-- ============================================================
-- Catalogues
-- ============================================================
local PROFESSION_IDS = { "merchant", "cook", "artisan", "medic", "explorer" }

-- Noms de fallback si SurvivorFactory n'est pas disponible
local FIRST_NAMES = {
    "Alex","Mathis","Lucas","Hugo","Léo","Nathan","Noah","Tom",
    "Enzo","Jules","Emma","Léa","Chloé","Sarah","Nina","Camille",
    "Sofia","Manon","Laura","Eva",
}
local LAST_NAMES = {
    "Martin","Bernard","Dubois","Thomas","Robert","Richard","Petit","Durand",
    "Leroy","Moreau","Simon","Laurent","Michel","Garcia","Roux","Fournier",
}

-- ============================================================
-- Classe NPCDataModel
-- ============================================================
local NPCDataModel = {}
NPCDataModel.__index = NPCDataModel

local _idCounter = 0

--- Crée une nouvelle instance PNJ.
-- @param overrides table?  Champs optionnels à surcharger.
-- @return NPCDataModel
function NPCDataModel.new(overrides)
    _idCounter = _idCounter + 1

    local isFemale = PHNPC.randInt(0, 1) == 1

    -- Noms via SurvivorFactory (B42) ou fallback
    local firstName, lastName
    if type(SurvivorFactory) == "table" and type(SurvivorFactory.getRandomForename) == "function" then
        firstName = SurvivorFactory.getRandomForename(isFemale) or FIRST_NAMES[PHNPC.randInt(1, #FIRST_NAMES)]
        lastName  = SurvivorFactory.getRandomSurname()          or LAST_NAMES[PHNPC.randInt(1, #LAST_NAMES)]
    else
        firstName = FIRST_NAMES[PHNPC.randInt(1, #FIRST_NAMES)]
        lastName  = LAST_NAMES[PHNPC.randInt(1, #LAST_NAMES)]
    end

    local self = setmetatable({}, NPCDataModel)

    -- Identité
    self.id        = "PHNPC_" .. _idCounter .. "_" .. tostring(getTimestampMs and getTimestampMs() or os.clock())
    self.firstName = firstName
    self.lastName  = lastName
    self.fullName  = firstName .. " " .. lastName
    self.isFemale  = isFemale

    -- Profession (aléatoire si non fournie)
    self.professionId = PROFESSION_IDS[PHNPC.randInt(1, #PROFESSION_IDS)]

    -- Besoins (0–100)
    self.hunger    = PHNPC.randInt(20, 60)
    self.thirst    = PHNPC.randInt(20, 60)
    self.fatigue   = PHNPC.randInt(10, 40)
    self.morale    = PHNPC.randInt(50, 80)
    self.stress    = 0

    -- État santé
    self.health    = 100
    self.bitten    = false
    self.biteTime  = nil   -- timestamp de morsure

    -- Psychologie / Trauma
    self.trauma    = 0     -- 0–100 : déclenche PTSD (gel/rage)
    self.ptsdState = nil   -- nil / "freeze" / "rage"

    -- IA & FSM
    self.fsmState       = "idle"   -- idle / wander / work / trade / defend / flee / guard
    self.fsmTarget      = nil      -- position ou entité cible
    self.lastFsmTick    = 0
    self.stuckTicks     = 0

    -- Apprentissage passif
    self.observedSkills = {}   -- { [skillName] = xp accumulé }

    -- Commerce
    self.inventory      = {}   -- { [itemType] = qty }
    self.gold           = PHNPC.randInt(5, 30)

    -- Référence à l'objet IsoPlayer (nil avant le spawn)
    self.isoObject = nil

    -- Appliquer les surcharges
    if type(overrides) == "table" then
        for k, v in pairs(overrides) do self[k] = v end
    end

    return self
end

-- ============================================================
-- Méthodes
-- ============================================================

--- Vérifie si le PNJ est vivant et non infecté critiquement.
function NPCDataModel:isAlive()
    return self.health > 0 and not (self.bitten and self.trauma >= 100)
end

--- Met à jour un besoin avec clamp automatique.
function NPCDataModel:setNeed(need, delta)
    local v = (self[need] or 0) + delta
    self[need] = PHNPC.clamp(v, 0, 100)
end

--- Décroissance naturelle des besoins (appelée par le serveur).
-- @param dtSec  number  Secondes écoulées depuis le dernier tick
function NPCDataModel:decayNeeds(dtSec)
    local cfg = PHNPC.getModule("NPC_Config") and PHNPC.getModule("NPC_Config").get() or {}
    if cfg.DisableNeedsDecay then return end
    self:setNeed("hunger",  -(dtSec * 0.05))
    self:setNeed("thirst",  -(dtSec * 0.08))
    self:setNeed("fatigue",  (dtSec * 0.03))
end

--- Ajoute de l'XP d'observation pour une compétence.
function NPCDataModel:addObservationXP(skillName, amount)
    self.observedSkills[skillName] = (self.observedSkills[skillName] or 0) + (amount or 1)
end

--- Sérialise pour transmitModData / sauvegarde.
function NPCDataModel:serialize()
    return {
        id           = self.id,
        firstName    = self.firstName,
        lastName     = self.lastName,
        isFemale     = self.isFemale,
        professionId = self.professionId,
        hunger       = self.hunger,
        thirst       = self.thirst,
        fatigue      = self.fatigue,
        morale       = self.morale,
        stress       = self.stress,
        health       = self.health,
        bitten       = self.bitten,
        biteTime     = self.biteTime,
        trauma       = self.trauma,
        ptsdState    = self.ptsdState,
        fsmState     = self.fsmState,
        observedSkills = self.observedSkills,
        inventory    = self.inventory,
        gold         = self.gold,
    }
end

--- Restaure depuis une table sérialisée.
-- @param data  table
function NPCDataModel.deserialize(data)
    local inst = setmetatable({}, NPCDataModel)
    for k, v in pairs(data) do inst[k] = v end
    inst.isoObject = nil   -- jamais persisté
    return inst
end

PHNPC.registerModule("NPC_DataModel", NPCDataModel)
return NPCDataModel
