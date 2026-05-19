--[[
    Dynamic NPC Overhaul - Unified Configuration Manager
    FR: Priorite des sources -> Mod Options (solo client) > Sandbox > difficulte native.
    EN: Source priority -> Mod Options (solo client) > Sandbox > native game difficulty.
]]

local PHNPC_ConfigManager = {
    MOD_ID = "PHNPC",
    SANDBOX_SECTION = "PHNPC",
    cachedConfig = nil,
    modOptionsState = {},
    hasModOptionsPage = false,
    defaults = {
        activeProfile = "realistic",

        networkSyncInterval = 0.5,
        fsmEntriesLimit = 10,
        fsmRange = 40,
        maxActiveNPCs = 12,
        perPlayerBudget = 4,
        spawnRadius = 32,
        despawnRadius = 48,
        spawnAttemptsPerCycle = 6,
        allowZombieFallback = true,

        enableOllama = true,
        ollamaApiUrl = "http://localhost:11434",
        ollamaModel = "neural-chat",
        ollamaTimeoutMs = 8000,
        ollamaCacheSize = 50,

        biteCoughIntervalSec = 30,
        biteCoughProbability = 0.15,
        biteIsolationAnxietyThreshold = 60,

        observationRange = 12,
        observationIntervalSec = 2,

        disableNeedsDecay = false,
        serviceBasePriceMultiplier = 1.0,
        serviceMarginMultiplier = 1.0,
        marketVolatilityMultiplier = 1.0,
        marketAggressivenessMultiplier = 1.0,
        quoteCooldownSec = 6,

        configSource = "defaults"
    }
}


local validProfiles = {
    realistic = true,
    hardcore = true,
    narrative = true,
    ultra_hardcore = true,
    rp_soft = true
}

local function isTrue(v)
    return v == true or v == 1 or v == "1" or v == "true"
end

local function clampNumber(v, minValue, maxValue, fallback)
    local n = tonumber(v)
    if not n then
        return fallback
    end
    if n < minValue then
        return minValue
    end
    if n > maxValue then
        return maxValue
    end
    return n
end

local function normalizeProfile(v)
    local p = tostring(v or ""):lower()
    if validProfiles[p] then
        return p
    end
    return PHNPC_ConfigManager.defaults.activeProfile
end

local function isServerAuthority()
    if type(isServer) == "function" then
        return isServer() == true
    end
    return false
end

local function getSandboxSection()
    local vars = rawget(_G, "SandboxVars")
    if type(vars) ~= "table" then
        return nil
    end
    local section = vars[PHNPC_ConfigManager.SANDBOX_SECTION]
    if type(section) == "table" then
        return section
    end
    return nil
end

local function mapNativeDifficultyToProfile()
    local mode = ""

    local core = getCore and getCore() or nil
    if core and core.getGameMode then
        local ok, gameMode = pcall(function()
            return core:getGameMode()
        end)
        if ok and gameMode then
            mode = tostring(gameMode):lower()
        end
    end

    if mode == "apocalypse" then
        return "hardcore"
    end
    if mode == "survival" or mode == "survivor" then
        return "realistic"
    end
    if mode == "builder" then
        return "rp_soft"
    end

    return PHNPC_ConfigManager.defaults.activeProfile
end

function PHNPC_ConfigManager:setModOptionValue(key, value)
    self.modOptionsState[key] = value
end

function PHNPC_ConfigManager:getModOptionValue(key)
    return self.modOptionsState[key]
end

local function buildConfigFromSandbox(section)
    local d = PHNPC_ConfigManager.defaults
    section = section or {}

    return {
        activeProfile = normalizeProfile(section.ActiveProfile),

        networkSyncInterval = clampNumber((section.NetworkSyncIntervalTenths or 5) / 10, 0.1, 2.0, d.networkSyncInterval),
        fsmEntriesLimit = math.floor(clampNumber(section.FSMEntriesLimit, 5, 15, d.fsmEntriesLimit)),
        fsmRange = math.floor(clampNumber(section.FSMRange, 20, 60, d.fsmRange)),
        maxActiveNPCs = math.floor(clampNumber(section.MaxActiveNPCs, 4, 48, d.maxActiveNPCs)),
        perPlayerBudget = math.floor(clampNumber(section.PerPlayerBudget, 1, 16, d.perPlayerBudget)),
        spawnRadius = math.floor(clampNumber(section.SpawnRadius, 18, 80, d.spawnRadius)),
        despawnRadius = math.floor(clampNumber(section.DespawnRadius, 24, 120, d.despawnRadius)),
        spawnAttemptsPerCycle = math.floor(clampNumber(section.SpawnAttemptsPerCycle, 2, 20, d.spawnAttemptsPerCycle)),
        allowZombieFallback = isTrue(section.AllowZombieFallback),

        enableOllama = isTrue(section.EnableOllama),
        ollamaApiUrl = tostring(section.OllamaApiUrl or d.ollamaApiUrl),
        ollamaModel = tostring(section.OllamaModel or d.ollamaModel),
        ollamaTimeoutMs = math.floor(clampNumber(section.OllamaTimeoutMs, 2000, 15000, d.ollamaTimeoutMs)),
        ollamaCacheSize = math.floor(clampNumber(section.OllamaCacheSize, 10, 100, d.ollamaCacheSize)),

        biteCoughIntervalSec = math.floor(clampNumber(section.BiteCoughIntervalSec, 10, 60, d.biteCoughIntervalSec)),
        biteCoughProbability = clampNumber((section.BiteCoughProbabilityPercent or 15) / 100, 0, 1, d.biteCoughProbability),
        biteIsolationAnxietyThreshold = math.floor(clampNumber(section.BiteIsolationAnxietyThreshold, 0, 100, d.biteIsolationAnxietyThreshold)),

        observationRange = math.floor(clampNumber(section.ObservationRange, 5, 20, d.observationRange)),
        observationIntervalSec = math.floor(clampNumber(section.ObservationIntervalSec, 1, 10, d.observationIntervalSec)),

        disableNeedsDecay = isTrue(section.DisableNeedsDecay),
        serviceBasePriceMultiplier = clampNumber((section.ServiceBasePriceMultiplierTenths or 10) / 10, 0.1, 5.0, d.serviceBasePriceMultiplier),
        serviceMarginMultiplier = clampNumber((section.ServiceMarginMultiplierTenths or 10) / 10, 0.5, 3.0, d.serviceMarginMultiplier),
        marketVolatilityMultiplier = clampNumber((section.MarketVolatilityMultiplierTenths or 10) / 10, 0.25, 2.0, d.marketVolatilityMultiplier),
        marketAggressivenessMultiplier = clampNumber((section.MarketAggressivenessMultiplierTenths or 10) / 10, 0.5, 2.0, d.marketAggressivenessMultiplier),
        quoteCooldownSec = math.floor(clampNumber(section.QuoteCooldownSec, 1, 60, d.quoteCooldownSec)),

        configSource = "sandbox"
    }
end

local function buildConfigFromModOptions(base)
    local c = {}
    for k, v in pairs(base) do
        c[k] = v
    end

    local getOpt = function(name)
        return PHNPC_ConfigManager:getModOptionValue(name)
    end

    c.activeProfile = normalizeProfile(getOpt("activeProfile") or c.activeProfile)
    c.networkSyncInterval = clampNumber(getOpt("networkSyncInterval") or c.networkSyncInterval, 0.1, 2.0, c.networkSyncInterval)
    c.fsmEntriesLimit = math.floor(clampNumber(getOpt("fsmEntriesLimit") or c.fsmEntriesLimit, 5, 15, c.fsmEntriesLimit))
    c.fsmRange = math.floor(clampNumber(getOpt("fsmRange") or c.fsmRange, 20, 60, c.fsmRange))
    c.maxActiveNPCs = math.floor(clampNumber(getOpt("maxActiveNPCs") or c.maxActiveNPCs, 4, 48, c.maxActiveNPCs))
    c.perPlayerBudget = math.floor(clampNumber(getOpt("perPlayerBudget") or c.perPlayerBudget, 1, 16, c.perPlayerBudget))
    c.spawnRadius = math.floor(clampNumber(getOpt("spawnRadius") or c.spawnRadius, 18, 80, c.spawnRadius))
    c.despawnRadius = math.floor(clampNumber(getOpt("despawnRadius") or c.despawnRadius, 24, 120, c.despawnRadius))
    c.spawnAttemptsPerCycle = math.floor(clampNumber(getOpt("spawnAttemptsPerCycle") or c.spawnAttemptsPerCycle, 2, 20, c.spawnAttemptsPerCycle))

    local vFallback = getOpt("allowZombieFallback")
    if vFallback ~= nil then
        c.allowZombieFallback = isTrue(vFallback)
    end

    local vEnable = getOpt("enableOllama")
    if vEnable ~= nil then
        c.enableOllama = isTrue(vEnable)
    end

    c.ollamaApiUrl = tostring(getOpt("ollamaApiUrl") or c.ollamaApiUrl)
    c.ollamaModel = tostring(getOpt("ollamaModel") or c.ollamaModel)
    c.ollamaTimeoutMs = math.floor(clampNumber(getOpt("ollamaTimeoutMs") or c.ollamaTimeoutMs, 2000, 15000, c.ollamaTimeoutMs))
    c.ollamaCacheSize = math.floor(clampNumber(getOpt("ollamaCacheSize") or c.ollamaCacheSize, 10, 100, c.ollamaCacheSize))

    c.biteCoughIntervalSec = math.floor(clampNumber(getOpt("biteCoughIntervalSec") or c.biteCoughIntervalSec, 10, 60, c.biteCoughIntervalSec))
    c.biteCoughProbability = clampNumber(getOpt("biteCoughProbability") or c.biteCoughProbability, 0, 1, c.biteCoughProbability)
    c.biteIsolationAnxietyThreshold = math.floor(clampNumber(getOpt("biteIsolationAnxietyThreshold") or c.biteIsolationAnxietyThreshold, 0, 100, c.biteIsolationAnxietyThreshold))

    c.observationRange = math.floor(clampNumber(getOpt("observationRange") or c.observationRange, 5, 20, c.observationRange))
    c.observationIntervalSec = math.floor(clampNumber(getOpt("observationIntervalSec") or c.observationIntervalSec, 1, 10, c.observationIntervalSec))

    local vNeeds = getOpt("disableNeedsDecay")
    if vNeeds ~= nil then
        c.disableNeedsDecay = isTrue(vNeeds)
    end

    c.serviceBasePriceMultiplier = clampNumber(getOpt("serviceBasePriceMultiplier") or c.serviceBasePriceMultiplier, 0.1, 5.0, c.serviceBasePriceMultiplier)
    c.serviceMarginMultiplier = clampNumber(getOpt("serviceMarginMultiplier") or c.serviceMarginMultiplier, 0.5, 3.0, c.serviceMarginMultiplier)
    c.marketVolatilityMultiplier = clampNumber(getOpt("marketVolatilityMultiplier") or c.marketVolatilityMultiplier, 0.25, 2.0, c.marketVolatilityMultiplier)
    c.marketAggressivenessMultiplier = clampNumber(getOpt("marketAggressivenessMultiplier") or c.marketAggressivenessMultiplier, 0.5, 2.0, c.marketAggressivenessMultiplier)
    c.quoteCooldownSec = math.floor(clampNumber(getOpt("quoteCooldownSec") or c.quoteCooldownSec, 1, 60, c.quoteCooldownSec))
    c.configSource = "mod_options"

    return c
end

function PHNPC_ConfigManager:resolve()
    local ok, result = pcall(function()
        local d = self.defaults
        local config = {}
        for k, v in pairs(d) do
            config[k] = v
        end

        local sandboxSection = getSandboxSection()
        local hasSandbox = type(sandboxSection) == "table"

        if hasSandbox then
            config = buildConfigFromSandbox(sandboxSection)
        else
            config.activeProfile = mapNativeDifficultyToProfile()
            config.configSource = "native_difficulty"
        end

        -- Server authority: never trust client Mod Options for gameplay logic.
        if not isServerAuthority() and self.hasModOptionsPage and next(self.modOptionsState) ~= nil then
            config = buildConfigFromModOptions(config)
        end

        self.cachedConfig = config
        return config
    end)
    if ok and type(result) == "table" then
        return result
    end
    self.cachedConfig = self.cachedConfig or self.defaults
    return self.cachedConfig
end

function PHNPC_ConfigManager:get()
    if type(self.resolve) ~= "function" then
        self.cachedConfig = self.cachedConfig or self.defaults
        return self.cachedConfig
    end
    if not self.cachedConfig then
        return self:resolve()
    end
    return self.cachedConfig
end

local function safeRequire(name)
    local ok, ref = pcall(require, name)
    if ok then
        return ref
    end
    return nil
end

function PHNPC_ConfigManager:applyToRuntime(forceResolve)
    local resolver = type(self.resolve) == "function" and self.resolve or PHNPC_ConfigManager.resolve
    local cfg = nil
    if forceResolve and type(resolver) == "function" then
        cfg = resolver(self)
    else
        cfg = self:get()
    end
    cfg = cfg or self.defaults
    local serverRuntime = type(isServer) == "function" and isServer() == true

    local NPCTuningProfiles = safeRequire("NPCTuningProfiles")
    if NPCTuningProfiles and NPCTuningProfiles.setActiveProfile then
        pcall(function()
            NPCTuningProfiles:setActiveProfile(cfg.activeProfile)
        end)
    end

    if serverRuntime then
        local NPC_NetworkServer = safeRequire("NPC_NetworkServer")
        if NPC_NetworkServer then
            NPC_NetworkServer.syncInterval = cfg.networkSyncInterval
        end

        local NPCSpawner = safeRequire("NPCSpawner")
        if NPCSpawner then
            NPCSpawner.replicationFSMRange = cfg.fsmRange
            NPCSpawner.replicationMaxFSMPerPlayer = cfg.fsmEntriesLimit
            NPCSpawner.maxActiveNPCs = cfg.maxActiveNPCs
            NPCSpawner.perPlayerBudget = cfg.perPlayerBudget
            NPCSpawner.spawnRadius = cfg.spawnRadius
            NPCSpawner.despawnRadius = math.max(cfg.spawnRadius + 8, cfg.despawnRadius)
            NPCSpawner.spawnAttemptsPerCycle = cfg.spawnAttemptsPerCycle
            NPCSpawner.allowZombieFallback = cfg.allowZombieFallback
        end
    end

    local NPCDebugReplication = rawget(_G, "PHNPCDebugReplication")
    if type(NPCDebugReplication) == "table" then
        NPCDebugReplication.fsmRange = cfg.fsmRange
        NPCDebugReplication.fsmLimit = cfg.fsmEntriesLimit
    end

    if serverRuntime then
        local OllamaBridge = safeRequire("OllamaBridge")
        if OllamaBridge then
            OllamaBridge.enabled = cfg.enableOllama
            OllamaBridge.baseUrl = cfg.ollamaApiUrl
            OllamaBridge.model = cfg.ollamaModel
            OllamaBridge.timeout = cfg.ollamaTimeoutMs
            OllamaBridge.maxCacheSize = cfg.ollamaCacheSize
        end

        local NPC_BiteManagement = safeRequire("NPC_BiteManagement")
        if NPC_BiteManagement then
            NPC_BiteManagement.coughInterval = cfg.biteCoughIntervalSec
            NPC_BiteManagement.coughProbability = cfg.biteCoughProbability
            NPC_BiteManagement.isolationAnxietyThreshold = cfg.biteIsolationAnxietyThreshold
        end

        local NPC_ObservationLearning = safeRequire("NPC_ObservationLearning")
        if NPC_ObservationLearning then
            NPC_ObservationLearning.observationRange = cfg.observationRange
            NPC_ObservationLearning.observationTickInterval = cfg.observationIntervalSec
        end

        local NPCBrain = safeRequire("NPCBrain")
        if NPCBrain then
            NPCBrain.disableNeedsDecay = cfg.disableNeedsDecay
            NPCBrain.zombieVisionRange = math.max(10, math.min(18, math.floor(cfg.spawnRadius * 0.4)))
        end

        local NPCMemory = safeRequire("NPCMemory")
        if NPCMemory then
            NPCMemory.globalServicePriceMultiplier = cfg.serviceBasePriceMultiplier
            NPCMemory.globalServiceMarginMultiplier = cfg.serviceMarginMultiplier
            NPCMemory.globalMarketVolatilityMultiplier = cfg.marketVolatilityMultiplier
            NPCMemory.globalMarketAggressivenessMultiplier = cfg.marketAggressivenessMultiplier
        end

        local NPCInteractionHooks = safeRequire("NPCInteractionHooks")
        if NPCInteractionHooks then
            NPCInteractionHooks.quoteCooldownSec = cfg.quoteCooldownSec
        end
    end

    return cfg
end

function PHNPC_ConfigManager:start()
    if Events and Events.OnGameBoot then
        Events.OnGameBoot.Add(function()
            -- isServerAuthority() n'existe pas en Build 41 ; utiliser fallback nil-safe
            local serverAuth = type(isServerAuthority) == "function" and isServerAuthority() or false
            if not serverAuth then
                PHNPC_ConfigManager:applyToRuntime(true)
            end
        end)
    end

    if Events and Events.OnGameStart then
        Events.OnGameStart.Add(function()
            -- isServerAuthority() n'existe pas en Build 41 ; utiliser fallback nil-safe
            local serverAuth = type(isServerAuthority) == "function" and isServerAuthority() or false
            if not serverAuth then
                PHNPC_ConfigManager:applyToRuntime(true)
            end
        end)
    end

    if Events and Events.OnServerStarted then
        Events.OnServerStarted.Add(function()
            PHNPC_ConfigManager:applyToRuntime(true)
        end)
    end
end

PHNPC_ConfigManager:start()

_G.PHNPC_ConfigManager = PHNPC_ConfigManager

return PHNPC_ConfigManager
