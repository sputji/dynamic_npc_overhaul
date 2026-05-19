--[[
    Project Humain : Dynamic_NPC_Overhaul
    NPC_BiteManagement.lua

    Gestion du dilemme de la morsure cachee:
    - Detection morsure cachee
    - Generation signes de compromission (toux, isolement)
    - Systeme d'inspection medicale forcee
    - Tension dramatique multijoueur
]]


local NPC_BiteManagement = {
    coughInterval = 30, -- Check toutes les 30 sec
    coughProbability = 0.15, -- 15% chance par check si hidden bite
    isolationThreshold = 5, -- Distance en cases si trop angoisse
    isolationAnxietyThreshold = 60, -- Seuil d'anxiete (0-100)
    lastCoughCheck = {}
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

local function getOnlinePlayersSafe()
    local out = {}
    if type(getOnlinePlayers) == "function" then
        local ok, players = pcall(function()
            return getOnlinePlayers()
        end)
        if ok and players and players.size then
            for i = 0, players:size() - 1 do
                out[#out + 1] = players:get(i)
            end
        elseif ok and type(players) == "table" then
            for i = 1, #players do
                out[#out + 1] = players[i]
            end
        end
    end
    return out
end

local function broadcastNpcFx(npcId, fxType, npcData)
    if not sendServerCommand then
        return
    end

    local payload = {
        npcId = npcId,
        fxType = fxType,
        x = npcData and (npcData.x or 0) or 0,
        y = npcData and (npcData.y or 0) or 0,
        z = npcData and (npcData.z or 0) or 0
    }

    local players = getOnlinePlayersSafe()
    for i = 1, #players do
        local p = players[i]
        if p then
            sendServerCommand(p, "PH_NPC_NETWORK", "NPCFx", payload)
        end
    end
end

-- ==============================================================================
-- DETECTION SIGNES DE MORSURE CACHEE
-- ==============================================================================

local function shouldCoughNow(npcData)
    -- Determine si le PNJ devrait tousser
    if not npcData or not npcData.health then
        return false
    end

    local isBitten = npcData.health.isBitten == true
    local isBittenHidden = (npcData.health.isBittenHidden == true) or (npcData.health.isHidingBite == true)
    
    if not (isBitten and isBittenHidden) then
        return false -- Pas mordu ou pas cachant
    end

    -- Si infection progresse ? plus chance de tousser
    local infection = tonumber(npcData.health.infection or 0)
    local cough_prob = NPC_BiteManagement.coughProbability * math.max(0.25, tuningFactor("biteVisibilityMult", 1))
    
    if infection > 40 then
        cough_prob = cough_prob * 2 -- Double si infection avancee
    end

    return math.random() < cough_prob
end

local function shouldIsolateSelf(npcData)
    -- Determine si le PNJ se cache du a l'angoisse de la morsure
    if not npcData or not npcData.health then
        return false
    end

    local isBittenHidden = (npcData.health.isBittenHidden == true) or (npcData.health.isHidingBite == true)
    local morale = tonumber(npcData.morale or 50)
    local anxiety = 100 - morale
    
    if not isBittenHidden then
        return false
    end

    -- Plus l'angoisse monte, plus isolation probable
    local threshold = (tonumber(NPC_BiteManagement.isolationAnxietyThreshold) or 60) / math.max(0.25, tuningFactor("biteVisibilityMult", 1))
    return anxiety > threshold -- Seuil dynamique selon profil
end

-- ==============================================================================
-- EMISSION SIGNES
-- ==============================================================================

function NPC_BiteManagement:emitCoughSign(npcId, npcData)
    -- Genere evenement toux visible
    if not npcId or not npcData then
        return
    end

    -- Log serveur
    print(string.format("[BiteSign] PNJ %s tousse (morsure cachee detectee!)", npcId))

    -- Envoi event visible aux clients (animation + son)
    broadcastNpcFx(npcId, "npc_cough", npcData)

    if Events and Events.OnBroadcast then
        Events.OnBroadcast:trigger({
            eventType = "NPCCough",
            npcId = npcId,
            x = npcData.x or 0,
            y = npcData.y or 0,
            z = npcData.z or 0
        })
    end
end

function NPC_BiteManagement:emitIsolationSign(npcId, npcData)
    -- Genere comportement d'isolement (s'eloigne des joueurs)
    if not npcId or not npcData then
        return
    end

    print(string.format("[BiteSign] PNJ %s s'isole (angoisse morsure)", npcId))

    -- Modifie pathfinding temporairement: cherche endroit seul
    npcData._isolationTicks = (npcData._isolationTicks or 0) + 1
    
    if npcData._isolationTicks > 10 then
        npcData._isolationMode = false -- Reset apres 10 ticks
        npcData._isolationTicks = 0
    else
        npcData._isolationMode = true
    end
end

function NPC_BiteManagement:triggerMedicalInspection(npcId, npcData, inspectorPlayer)
    -- Inspection medicale forcee detecte la morsure cachee
    if not npcId or not npcData or not inspectorPlayer then
        return false
    end

    if not (npcData.health and npcData.health.isBittenHidden) then
        return false -- Pas de morsure cachee a detecter
    end

    -- Revele la morsure
    print(string.format(
        "[MedicalInspection] Joueur %s a decouvert morsure cachee du PNJ %s!",
        inspectorPlayer, npcId
    ))

    -- Record dans memory (traumatisme d'etre decouvert)
    if npcData.memory then
        table.insert(npcData.memory, {
            tick = os.time(),
            event = "discovered_hidden_bite",
            actor = inspectorPlayer,
            impact = "severe_distrust"
        })
    end

    -- Revele la morsure
    npcData.health.isBittenHidden = false
    npcData.health.isBitten = true

    -- Mood impact: honte + depression
    npcData.morale = math.max(0, (tonumber(npcData.morale) or 50) - 30)

    -- Envoi event a tous les clients
    if Events and Events.OnBroadcast then
        Events.OnBroadcast:trigger({
            eventType = "BiteTruthRevealed",
            npcId = npcId,
            inspectorPlayer = inspectorPlayer
        })
    end

    return true
end

-- ==============================================================================
-- TICK-BASED CHECKS
-- ==============================================================================

function NPC_BiteManagement:updateNPCBiteStates(npcId, npcData)
    -- Appele par NPC_NetworkServer chaque tick serveur
    if not npcId or not npcData then
        return
    end

    local now = os.time()
    local interval = math.max(4, math.floor(self.coughInterval / math.max(0.2, tuningFactor("biteSignIntervalMult", 1))))
    local lastCheck = self.lastCoughCheck[npcId] or (now - interval)

    if (now - lastCheck) < interval then
        return -- Pas encore time pour check
    end

    self.lastCoughCheck[npcId] = now

    -- Check toux
    if shouldCoughNow(npcData) then
        self:emitCoughSign(npcId, npcData)
    end

    -- Check isolement
    if shouldIsolateSelf(npcData) then
        self:emitIsolationSign(npcId, npcData)
    end
end

-- ==============================================================================
-- DIALOGUE INTEGRATION: Ton anxieux si morsure cachee
-- ==============================================================================

function NPC_BiteManagement:buildBiteAnxietyPrompt(npcData)
    -- Retourne prompt suffix pour systeme dialogue si morsure cachee
    if not npcData or not npcData.health or not npcData.health.isBittenHidden then
        return ""
    end

    local infection = tonumber(npcData.health.infection or 0)
    local anxiety = 100 - (tonumber(npcData.morale) or 50)

    local prompt = "\n[HIDDEN: Vous cachez une morsure infectieuse. "
    
    if infection > 60 then
        prompt = prompt .. "Vous avez tres peur. "
    end
    
    if anxiety > 70 then
        prompt = prompt .. "Chaque interaction vous terrifies. "
    end
    
    prompt = prompt .. "Soyez distrait, nerveux, breve. Evitez le contact.]"
    
    return prompt
end

-- ==============================================================================
-- INSPECTION COMMAND: Permet joueur inspecter medical
-- ==============================================================================

function NPC_BiteManagement:requestMedicalInspection(npcId, inspectorId)
    -- Appele quand joueur demande inspection medicale
    -- Exemple: right-click ? "Inspecter..." ? appelle ca
    
    local okHooks, NPCInteractionHooks = pcall(require, "NPCInteractionHooks")
    if not okHooks or not NPCInteractionHooks then
        return false
    end

    local npcData = NPCInteractionHooks:getNPCData(npcId)
    if not npcData then
        return false
    end

    -- Effectue inspection
    local inspectionResult = self:triggerMedicalInspection(npcId, npcData, inspectorId)
    
    return inspectionResult
end

return NPC_BiteManagement
