--[[
    Project Humain : Dynamic NPC Overhaul — B42
    server/NPC_ObservationLearning.lua

    Apprentissage passif : les PNJ proches du joueur gagnent de l'XP
    en observant ses actions (cuisine, construction, soin, ...).
]]

if not isServer() then return end

local Log      = PHNPC.getModule("NPC_Logger")
local Config   = PHNPC.getModule("NPC_Config")
local SpawnMgr = PHNPC.getModule("NPC_SpawnManager")

local NPC_ObservationLearning = {
    _started    = false,
    _tickTimer  = 0,
}

-- Mapping événement PZ → compétence PHNPC observée
local ACTION_SKILL_MAP = {
    Cooking     = "Cooking",
    Carpentry   = "Carpentry",
    Doctor      = "Doctor",
    Aiming      = "Aiming",
    Mechanics   = "Mechanics",
    Farming     = "Farming",
    Foraging    = "Foraging",
}

-- ============================================================
-- Observation d'une action joueur
-- ============================================================

local function observePlayerAction(player, skillName)
    local cfg     = Config.get()
    local range   = cfg.ObservationRange or 12
    local active  = SpawnMgr and SpawnMgr.getActive() or {}

    for _, npc in pairs(active) do
        local iso = npc.isoObject
        if iso then
            local dx = iso:getX() - player:getX()
            local dy = iso:getY() - player:getY()
            if (dx * dx + dy * dy) <= (range * range) then
                npc:addObservationXP(skillName, 1)
                Log.trace("NPC_ObservationLearning", "XP observé",
                    { npc = npc.id, skill = skillName, total = npc.observedSkills[skillName] or 0 })
            end
        end
    end
end

-- ============================================================
-- Hook sur les actions joueur (B42 : OnPlayerAttackFinished / OnCooked / etc.)
-- ============================================================

-- Cuisine
Events.OnCooked.Add(function(foodItem)
    local player = getSpecificPlayer and getSpecificPlayer(0)
    if player then observePlayerAction(player, "Cooking") end
end)

-- Construction
Events.OnObjectAdded.Add(function(obj)
    if not obj then return end
    -- Vérifier si c'est une construction de charpenterie
    local player = getSpecificPlayer and getSpecificPlayer(0)
    if player then observePlayerAction(player, "Carpentry") end
end)

-- Soins (OnCharacterHeal si disponible en B42)
Events.OnPlayerUpdate.Add(function(player)
    -- Heuristique légère : on observe toutes les N ticks
    NPC_ObservationLearning._tickTimer = NPC_ObservationLearning._tickTimer + 1
    if NPC_ObservationLearning._tickTimer < 600 then return end  -- ~20s
    NPC_ObservationLearning._tickTimer = 0

    -- Vérifier si le joueur fait une action de soin (bandage actif)
    local ok, bandaged = pcall(function()
        return player:isBeingTreated and player:isBeingTreated()
    end)
    if ok and bandaged then
        observePlayerAction(player, "Doctor")
    end
end)

-- ============================================================
-- API
-- ============================================================

function NPC_ObservationLearning.start()
    if NPC_ObservationLearning._started then return end
    NPC_ObservationLearning._started = true
    Log.ok("NPC_ObservationLearning", "Observation learning démarré.")
end

PHNPC.registerModule("NPC_ObservationLearning", NPC_ObservationLearning)
return NPC_ObservationLearning
