--[[
    Project Humain : Dynamic_NPC_Overhaul
    NPC_ObservationLearning.lua

    Apprentissage asynchrone par observation:
    - PNJ observe joueur construire/cultiver/crafter
    - Gagne bonus discret en skill (pas de XP bar)
    - Amelioration progressive et invisible
    - Systeme immersif de transmission de connaissance
]]


local NPC_ObservationLearning = {
    observationRange = 12, -- Distance en cases pour observer
    observationTickInterval = 2, -- Check toutes les 2 sec
    skillBonusPerObservation = 0.5, -- Points de skill gagnes par observation
    lastObservationCheck = {},
    
    -- Mapping actions ? skills observables
    observableActions = {
        carpentry = {
            keywords = {"nail", "wood", "plank", "frame", "wall", "roof"},
            skillName = "carpentry",
            bonusMultiplier = 1.2
        },
        farming = {
            keywords = {"plant", "seed", "harvest", "cultivate", "soil"},
            skillName = "farming",
            bonusMultiplier = 1.0
        },
        cooking = {
            keywords = {"cook", "recipe", "prepare", "heat", "ingredient"},
            skillName = "cooking",
            bonusMultiplier = 0.9
        },
        crafting = {
            keywords = {"craft", "make", "assemble", "build"},
            skillName = "crafting",
            bonusMultiplier = 1.1
        },
        medical = {
            keywords = {"bandage", "stitch", "medicine", "treat", "heal"},
            skillName = "medical",
            bonusMultiplier = 1.3
        },
        mechanics = {
            keywords = {"engine", "vehicle", "repair", "machine", "part"},
            skillName = "mechanics",
            bonusMultiplier = 1.25
        },
        fishing = {
            keywords = {"fish", "hook", "line", "rod", "water"},
            skillName = "fishing",
            bonusMultiplier = 1.0
        }
    }
}

local hasTuningProfiles, NPCTuningProfiles = pcall(require, "NPCTuningProfiles")
if not hasTuningProfiles then
    NPCTuningProfiles = nil
end

local function tuningFactor(key, defaultValue)
    if NPCTuningProfiles and NPCTuningProfiles.getFactor then
        local ok, value = pcall(function()
            return NPCTuningProfiles:getFactor(key, defaultValue or 1)
        end)
        if ok and type(value) == "number" then
            return value
        end
    end
    return defaultValue or 1
end

-- ==============================================================================
-- DETECTION ACTIONS OBSERVABLES
-- ==============================================================================

local function detectActionFromContext(playerActionContext)
    -- Detecte quelle action le joueur effectue
    -- playerActionContext = {animation, itemInHand, targetObject, location}
    
    if not playerActionContext then
        return nil
    end

    local anim = playerActionContext.animation or ""
    local item = playerActionContext.itemInHand or ""
    local target = playerActionContext.targetObject or ""
    local context = playerActionContext.context or ""

    -- Simple keyword matching
    for skillType, config in pairs(NPC_ObservationLearning.observableActions) do
        for _, keyword in ipairs(config.keywords) do
            if string.find(string.lower(anim .. item .. target .. context), 
                          string.lower(keyword)) then
                return skillType
            end
        end
    end

    return nil
end

local function getDistanceBetween(pos1, pos2)
    -- Distance simple 3D
    if not pos1 or not pos2 then
        return 999
    end
    
    local dx = (pos1.x or 0) - (pos2.x or 0)
    local dy = (pos1.y or 0) - (pos2.y or 0)
    local dz = (pos1.z or 0) - (pos2.z or 0)
    
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

-- ==============================================================================
-- APPRENTISSAGE BONUS
-- ==============================================================================

function NPC_ObservationLearning:awardObservationBonus(npcData, skillType, multiplier)
    -- Donne bonus discret au PNJ observant
    if not npcData or not skillType then
        return
    end

    -- Initialise observation log si absent
    if not npcData.observationLog then
        npcData.observationLog = {}
    end

    -- Enregistre observation
    table.insert(npcData.observationLog, {
        skill = skillType,
        timestamp = os.time(),
        multiplier = multiplier
    })

    -- Garde max 100 dernieres observations
    if #npcData.observationLog > 100 then
        table.remove(npcData.observationLog, 1)
    end

    -- Applique bonus discret au skill (pas de bar visible)
    local learningMult = math.max(0.2, tuningFactor("learningRateMult", 1))
    local skillBonus = NPC_ObservationLearning.skillBonusPerObservation * (multiplier or 1.0) * learningMult
    local currentLevel = tonumber(npcData.skills and npcData.skills[skillType] or 0)
    
    npcData.skills = npcData.skills or {}
    npcData.skills[skillType] = currentLevel + skillBonus

    -- Log serveur (admin peut voir)
    print(string.format(
        "[ObservationLearning] PNJ a observe %s: +%.1f xp ? level %.1f",
        skillType, skillBonus, npcData.skills[skillType]
    ))
end

-- ==============================================================================
-- TICK-BASED OBSERVATION CHECK
-- ==============================================================================

function NPC_ObservationLearning:checkNearbyPlayerActions(npcId, npcData, allPlayers)
    -- Appele depuis NPC_NetworkServer tick
    -- Cherche si un joueur fait action observable a proximite
    
    if not npcId or not npcData or not allPlayers or #allPlayers == 0 then
        return
    end

    local now = os.time()
    local tickRateMult = math.max(0.2, tuningFactor("observationTickRateMult", 1))
    local observationInterval = math.max(1, math.floor(self.observationTickInterval / tickRateMult))
    local observationRange = NPC_ObservationLearning.observationRange * math.max(0.4, tuningFactor("observationRangeMult", 1))
    local lastCheck = self.lastObservationCheck[npcId] or (now - observationInterval)

    if (now - lastCheck) < observationInterval then
        return -- Pas encore time pour check
    end

    self.lastObservationCheck[npcId] = now

    local npcPos = { x = npcData.x, y = npcData.y, z = npcData.z }

    -- Parcourt tous les joueurs
    for _, player in ipairs(allPlayers) do
        if player then
            -- Check distance
            local playerPos = {
                x = player.x or 0,
                y = player.y or 0,
                z = player.z or 0
            }
            local distance = getDistanceBetween(npcPos, playerPos)

            if distance <= observationRange then
                -- Check si joueur fait action observable
                local actionContext = {
                    animation = player.currentAnimation or "",
                    itemInHand = player.currentItemType or "",
                    targetObject = player.currentTarget or "",
                    context = player.currentActivity or ""
                }

                local skillType = detectActionFromContext(actionContext)

                if skillType then
                    -- Joueur effectue action observable!
                    local config = NPC_ObservationLearning.observableActions[skillType]
                    self:awardObservationBonus(npcData, skillType, config.bonusMultiplier)
                end
            end
        end
    end
end

-- ==============================================================================
-- QUERY: Obtenir stats apprentissage PNJ
-- ==============================================================================

function NPC_ObservationLearning:getSkillSummary(npcData)
    -- Retourne resume skills pour UI (optionnel)
    if not npcData or not npcData.skills then
        return "Aucun apprentissage observe"
    end

    local summary = {}
    for skill, level in pairs(npcData.skills) do
        if level and level > 0 then
            table.insert(summary, 
                string.format("%s: %.1f", skill, level))
        end
    end

    if #summary == 0 then
        return "Aucun apprentissage observe"
    end

    return table.concat(summary, " | ")
end

function NPC_ObservationLearning:getMostRecentObservations(npcData, count)
    -- Retourne dernieres observations (pour debug/admin)
    count = count or 5

    if not npcData or not npcData.observationLog or #npcData.observationLog == 0 then
        return {}
    end

    local recent = {}
    local startIdx = math.max(1, #npcData.observationLog - count + 1)

    for i = startIdx, #npcData.observationLog do
        table.insert(recent, npcData.observationLog[i])
    end

    return recent
end

-- ==============================================================================
-- FALLBACK DIALOGUE: Integration
-- ==============================================================================

function NPC_ObservationLearning:buildLearningPrompt(npcData)
    -- Retourne prompt suffix pour dialogue si PNJ a apprentissage notable
    
    if not npcData or not npcData.observationLog then
        return ""
    end

    local observationCount = #npcData.observationLog
    if observationCount == 0 then
        return ""
    end

    -- Determine skill dominant
    local skillCounts = {}
    for _, obs in ipairs(npcData.observationLog) do
        local skill = obs.skill or "unknown"
        skillCounts[skill] = (skillCounts[skill] or 0) + 1
    end

    local dominantSkill = "construction"
    local maxCount = 0
    for skill, count in pairs(skillCounts) do
        if count > maxCount then
            maxCount = count
            dominantSkill = skill
        end
    end

    local prompt = string.format(
        "\n[KNOWLEDGE: Vous avez observe et appris %s (observation count: %d). " ..
        "Vous etes plus interesse/confident dans les discussions liees a %s.]",
        dominantSkill,
        observationCount,
        dominantSkill
    )

    return prompt
end

return NPC_ObservationLearning
