--[[
    Project Humain : Dynamic_NPC_Overhaul
    NPCTuningProfiles.lua

    Profils gameplay globaux pour calibrer l'ensemble du mod:
    - realistic (par defaut)
    - hardcore
    - narrative
]]

local NPCTuningProfiles = {
    defaultProfile = "realistic",
    storeKey = "PHNPC_TUNING",
    profiles = {
        realistic = {
            label = "Survie realiste",
            npcResistanceMult = 1.0,
            needsDecayMult = 1.0,
            fabricationSpeedMult = 1.0,
            recoveryRateMult = 1.0,
            learningRateMult = 1.0,
            economyPriceMult = 1.0,
            economyVolatilityMult = 1.0,
            socialGainMult = 1.0,
            socialDecayMult = 1.0,
            traumaGainMult = 1.0,
            traumaDecayMult = 1.0,
            rageDecayMult = 1.0,
            traumaThreatSensitivityMult = 1.0,
            freezeChanceMult = 1.0,
            freezeDurationMult = 1.0,
            weatherExposureMult = 1.0,
            weatherRecoveryMult = 1.0,
            weatherDiseaseImpactMult = 1.0,
            injuryPenaltyMult = 1.0,
            infectionProgressMult = 1.0,
            infectionLeaveThresholdMult = 1.0,
            infectionAttackThresholdMult = 1.0,
            biteVisibilityMult = 1.0,
            biteSignIntervalMult = 1.0,
            expeditionDistanceThresholdMult = 1.0,
            expeditionReturnChanceMult = 1.0,
            expeditionDurationMult = 1.0,
            expeditionLootMult = 1.0,
            observationRangeMult = 1.0,
            observationTickRateMult = 1.0
        },
        hardcore = {
            label = "Hardcore",
            npcResistanceMult = 0.85,
            needsDecayMult = 1.25,
            fabricationSpeedMult = 0.78,
            recoveryRateMult = 0.8,
            learningRateMult = 0.72,
            economyPriceMult = 1.2,
            economyVolatilityMult = 1.25,
            socialGainMult = 0.82,
            socialDecayMult = 1.2,
            traumaGainMult = 1.22,
            traumaDecayMult = 0.82,
            rageDecayMult = 0.86,
            traumaThreatSensitivityMult = 1.12,
            freezeChanceMult = 1.2,
            freezeDurationMult = 1.18,
            weatherExposureMult = 1.25,
            weatherRecoveryMult = 0.82,
            weatherDiseaseImpactMult = 1.25,
            injuryPenaltyMult = 1.25,
            infectionProgressMult = 1.35,
            infectionLeaveThresholdMult = 0.9,
            infectionAttackThresholdMult = 0.9,
            biteVisibilityMult = 1.28,
            biteSignIntervalMult = 0.8,
            expeditionDistanceThresholdMult = 1.15,
            expeditionReturnChanceMult = 0.78,
            expeditionDurationMult = 1.28,
            expeditionLootMult = 0.78,
            observationRangeMult = 0.9,
            observationTickRateMult = 0.85
        },
        narrative = {
            label = "Narratif",
            npcResistanceMult = 1.15,
            needsDecayMult = 0.9,
            fabricationSpeedMult = 1.22,
            recoveryRateMult = 1.18,
            learningRateMult = 1.35,
            economyPriceMult = 0.9,
            economyVolatilityMult = 0.85,
            socialGainMult = 1.35,
            socialDecayMult = 0.8,
            traumaGainMult = 0.85,
            traumaDecayMult = 1.22,
            rageDecayMult = 1.18,
            traumaThreatSensitivityMult = 0.9,
            freezeChanceMult = 0.8,
            freezeDurationMult = 0.85,
            weatherExposureMult = 0.85,
            weatherRecoveryMult = 1.22,
            weatherDiseaseImpactMult = 0.8,
            injuryPenaltyMult = 0.85,
            infectionProgressMult = 0.85,
            infectionLeaveThresholdMult = 1.1,
            infectionAttackThresholdMult = 1.12,
            biteVisibilityMult = 0.82,
            biteSignIntervalMult = 1.25,
            expeditionDistanceThresholdMult = 0.9,
            expeditionReturnChanceMult = 1.2,
            expeditionDurationMult = 0.85,
            expeditionLootMult = 1.25,
            observationRangeMult = 1.1,
            observationTickRateMult = 1.25
        },
        ultra_hardcore = {
            label = "Ultra-Hardcore",
            npcResistanceMult = 0.72,
            needsDecayMult = 1.45,
            fabricationSpeedMult = 0.62,
            recoveryRateMult = 0.62,
            learningRateMult = 0.58,
            economyPriceMult = 1.35,
            economyVolatilityMult = 1.38,
            socialGainMult = 0.68,
            socialDecayMult = 1.35,
            traumaGainMult = 1.4,
            traumaDecayMult = 0.7,
            rageDecayMult = 0.72,
            traumaThreatSensitivityMult = 1.2,
            freezeChanceMult = 1.35,
            freezeDurationMult = 1.25,
            weatherExposureMult = 1.45,
            weatherRecoveryMult = 0.68,
            weatherDiseaseImpactMult = 1.45,
            injuryPenaltyMult = 1.42,
            infectionProgressMult = 1.55,
            infectionLeaveThresholdMult = 0.82,
            infectionAttackThresholdMult = 0.82,
            biteVisibilityMult = 1.4,
            biteSignIntervalMult = 0.65,
            expeditionDistanceThresholdMult = 1.25,
            expeditionReturnChanceMult = 0.62,
            expeditionDurationMult = 1.42,
            expeditionLootMult = 0.62,
            observationRangeMult = 0.82,
            observationTickRateMult = 0.75
        },
        rp_soft = {
            label = "RP Soft",
            npcResistanceMult = 1.22,
            needsDecayMult = 0.82,
            fabricationSpeedMult = 1.35,
            recoveryRateMult = 1.32,
            learningRateMult = 1.5,
            economyPriceMult = 0.84,
            economyVolatilityMult = 0.74,
            socialGainMult = 1.55,
            socialDecayMult = 0.68,
            traumaGainMult = 0.72,
            traumaDecayMult = 1.35,
            rageDecayMult = 1.28,
            traumaThreatSensitivityMult = 0.82,
            freezeChanceMult = 0.68,
            freezeDurationMult = 0.72,
            weatherExposureMult = 0.74,
            weatherRecoveryMult = 1.35,
            weatherDiseaseImpactMult = 0.7,
            injuryPenaltyMult = 0.72,
            infectionProgressMult = 0.72,
            infectionLeaveThresholdMult = 1.18,
            infectionAttackThresholdMult = 1.22,
            biteVisibilityMult = 0.72,
            biteSignIntervalMult = 1.4,
            expeditionDistanceThresholdMult = 0.82,
            expeditionReturnChanceMult = 1.35,
            expeditionDurationMult = 0.74,
            expeditionLootMult = 1.4,
            observationRangeMult = 1.18,
            observationTickRateMult = 1.4
        }
    }
}

local function getStore()
    if ModData and ModData.getOrCreate then
        return ModData.getOrCreate(NPCTuningProfiles.storeKey)
    end

    _G = _G or {}
    _G[NPCTuningProfiles.storeKey] = _G[NPCTuningProfiles.storeKey] or {}
    return _G[NPCTuningProfiles.storeKey]
end

local function resolveProfileName(name)
    local normalized = tostring(name or ""):lower()
    if NPCTuningProfiles.profiles[normalized] then
        return normalized
    end
    return nil
end

function NPCTuningProfiles:getActiveProfileName()
    local store = getStore()
    local desired = resolveProfileName(store and store.activeProfile)
    if desired then
        return desired
    end
    return self.defaultProfile
end

function NPCTuningProfiles:getActiveProfile()
    local name = self:getActiveProfileName()
    return self.profiles[name] or self.profiles[self.defaultProfile]
end

function NPCTuningProfiles:getFactor(key, defaultValue)
    local profile = self:getActiveProfile()
    local value = profile and profile[key]
    if type(value) ~= "number" then
        return defaultValue or 1
    end
    return value
end

function NPCTuningProfiles:setActiveProfile(name)
    local resolved = resolveProfileName(name)
    if not resolved then
        return false, self:getActiveProfileName()
    end

    local store = getStore()
    store.activeProfile = resolved
    return true, resolved
end

function NPCTuningProfiles:listProfiles()
    local out = {}
    for key, value in pairs(self.profiles) do
        out[#out + 1] = {
            id = key,
            label = value.label or key
        }
    end
    table.sort(out, function(a, b)
        return tostring(a.id) < tostring(b.id)
    end)
    return out
end

return NPCTuningProfiles
