--[[
    Dynamic NPC Overhaul - Mod Options integration (Build 41)
    FR: Cree une page de gestion complete quand Mod Options est disponible.
    EN: Builds a full management page when Mod Options is available.
]]

local okConfig, PHNPC_ConfigManager = pcall(require, "PHNPC_ConfigManager")
if not okConfig then
    PHNPC_ConfigManager = _G.PHNPC_ConfigManager
end

if not PHNPC_ConfigManager then
    return
end

local function hasModOptions()
    return ModOptions and ModOptions.getInstance
end

local runtimeLogState = {
    pathLogged = false
}

local function logModOptionsPath(pathLabel)
    if runtimeLogState.pathLogged then
        return
    end
    runtimeLogState.pathLogged = true
    print("[PHNPC Config] Mod Options path: " .. tostring(pathLabel))
end

local function buildV144Descriptor(cfg)
    return {
        mod_id = "PHNPC",
        mod_shortname = "Dynamic NPC Overhaul",
        mod_fullname = "Dynamic NPC Overhaul",
        options_data = {
            activeProfile = {
                name = "Theme 1 - Profil actif",
                default = cfg.activeProfile,
                values = { "realistic", "hardcore", "narrative", "ultra_hardcore", "rp_soft" }
            },
            networkSyncInterval = {
                name = "Theme 2 - Intervalle sync reseau (s)",
                default = cfg.networkSyncInterval,
                min = 0.1,
                max = 2.0,
                step = 0.1
            },
            fsmEntriesLimit = {
                name = "Theme 2 - Limite entrees FSM",
                default = cfg.fsmEntriesLimit,
                min = 5,
                max = 15,
                step = 1
            },
            fsmRange = {
                name = "Theme 2 - Portee FSM",
                default = cfg.fsmRange,
                min = 20,
                max = 60,
                step = 1
            },
            maxActiveNPCs = {
                name = "Theme 2 - NPC actifs max",
                default = cfg.maxActiveNPCs,
                min = 4,
                max = 48,
                step = 1
            },
            perPlayerBudget = {
                name = "Theme 2 - Budget NPC par joueur",
                default = cfg.perPlayerBudget,
                min = 1,
                max = 16,
                step = 1
            },
            spawnRadius = {
                name = "Theme 2 - Rayon de spawn",
                default = cfg.spawnRadius,
                min = 18,
                max = 80,
                step = 1
            },
            despawnRadius = {
                name = "Theme 2 - Rayon de despawn",
                default = cfg.despawnRadius,
                min = 24,
                max = 120,
                step = 1
            },
            spawnAttemptsPerCycle = {
                name = "Theme 2 - Tentatives de spawn / cycle",
                default = cfg.spawnAttemptsPerCycle,
                min = 2,
                max = 20,
                step = 1
            },
            allowZombieFallback = {
                name = "Theme 2 - Autoriser fallback zombie",
                default = cfg.allowZombieFallback,
                type = "tickbox"
            },
            enableOllama = {
                name = "Theme 3 - Activer IA Ollama",
                default = cfg.enableOllama,
                type = "tickbox"
            },
            ollamaApiUrl = {
                name = "Theme 3 - URL API",
                default = cfg.ollamaApiUrl,
                type = "textentry"
            },
            ollamaModel = {
                name = "Theme 3 - Modele",
                default = cfg.ollamaModel,
                type = "textentry"
            },
            ollamaTimeoutMs = {
                name = "Theme 3 - Timeout requete (ms)",
                default = cfg.ollamaTimeoutMs,
                min = 2000,
                max = 15000,
                step = 100
            },
            ollamaCacheSize = {
                name = "Theme 3 - Taille cache",
                default = cfg.ollamaCacheSize,
                min = 10,
                max = 100,
                step = 1
            },
            biteCoughIntervalSec = {
                name = "Theme 4 - Intervalle verification toux (s)",
                default = cfg.biteCoughIntervalSec,
                min = 10,
                max = 60,
                step = 1
            },
            biteCoughProbabilityPercent = {
                name = "Theme 4 - Probabilite de toux cachee (%)",
                default = math.floor((cfg.biteCoughProbability or 0.15) * 100),
                min = 0,
                max = 100,
                step = 1
            },
            biteIsolationAnxietyThreshold = {
                name = "Theme 4 - Seuil isolement anxiete",
                default = cfg.biteIsolationAnxietyThreshold,
                min = 0,
                max = 100,
                step = 1
            },
            observationRange = {
                name = "Theme 5 - Portee observation",
                default = cfg.observationRange,
                min = 5,
                max = 20,
                step = 1
            },
            observationIntervalSec = {
                name = "Theme 5 - Intervalle verification (s)",
                default = cfg.observationIntervalSec,
                min = 1,
                max = 10,
                step = 1
            },
            disableNeedsDecay = {
                name = "Theme 6 - Desactiver degradation faim/soif",
                default = cfg.disableNeedsDecay,
                type = "tickbox"
            },
            serviceBasePriceMultiplier = {
                name = "Theme 6 - Multiplicateur prix services",
                default = cfg.serviceBasePriceMultiplier,
                min = 0.1,
                max = 5.0,
                step = 0.1
            },
            serviceMarginMultiplier = {
                name = "Theme 6 - Marge commerciale globale",
                default = cfg.serviceMarginMultiplier,
                min = 0.5,
                max = 3.0,
                step = 0.1
            },
            marketVolatilityMultiplier = {
                name = "Theme 6 - Volatilite du marche",
                default = cfg.marketVolatilityMultiplier,
                min = 0.25,
                max = 2.0,
                step = 0.05
            },
            marketAggressivenessMultiplier = {
                name = "Theme 6 - Agressivite des prix",
                default = cfg.marketAggressivenessMultiplier,
                min = 0.5,
                max = 2.0,
                step = 0.05
            },
            quoteCooldownSec = {
                name = "Theme 6 - Cooldown devis (s)",
                default = cfg.quoteCooldownSec,
                min = 1,
                max = 60,
                step = 1
            }
        }
    }
end

local function getPage()
    if not hasModOptions() then
        return nil
    end

    local cfg = PHNPC_ConfigManager:get()
    local descriptor = buildV144Descriptor(cfg)

    -- Mod Options (Build 41) v1.4.4 accepte couramment un descriptor options_data.
    local ok, page = pcall(function()
        return ModOptions:getInstance(descriptor)
    end)
    if ok and page then
        logModOptionsPath("descriptor_v1_4_4_colon")
        return page
    end

    ok, page = pcall(function()
        return ModOptions.getInstance(descriptor)
    end)
    if ok and page then
        logModOptionsPath("descriptor_v1_4_4_dot")
        return page
    end

    ok, page = pcall(function()
        return ModOptions:getInstance("PHNPC", "Dynamic NPC Overhaul")
    end)
    if ok and page then
        logModOptionsPath("fallback_legacy_colon")
        return page
    end

    ok, page = pcall(function()
        return ModOptions.getInstance("PHNPC", "Dynamic NPC Overhaul")
    end)
    if ok and page then
        logModOptionsPath("fallback_legacy_dot")
        return page
    end

    logModOptionsPath("not_available_or_failed")
    return nil
end

local function addOption(page, methodNames, ...)
    if not page then
        return nil
    end
    for i = 1, #methodNames do
        local fn = page[methodNames[i]]
        if type(fn) == "function" then
            local ok, control = pcall(fn, page, ...)
            if ok then
                return control
            end
        end
    end
    return nil
end

local function readControlValue(control, fallback)
    if not control then
        return fallback
    end
    if type(control.getValue) == "function" then
        local ok, value = pcall(function()
            return control:getValue()
        end)
        if ok then
            return value
        end
    end
    if control.value ~= nil then
        return control.value
    end
    return fallback
end

local function bindOption(control, key, fallback, transform)
    if not control then
        return
    end

    local function pushValue()
        local value = readControlValue(control, fallback)
        if transform then
            value = transform(value)
        end
        PHNPC_ConfigManager:setModOptionValue(key, value)
        PHNPC_ConfigManager:applyToRuntime(true)
    end

    if type(control.setOnChange) == "function" then
        pcall(function()
            control:setOnChange(pushValue)
        end)
    end

    if type(control.onChange) == "function" then
        local prev = control.onChange
        control.onChange = function(...)
            pcall(prev, ...)
            pushValue()
        end
    end

    pushValue()
end

local function registerPage()
    if not hasModOptions() then
        return
    end

    local page = getPage()
    if not page then
        return
    end

    PHNPC_ConfigManager.hasModOptionsPage = true

    local cfg = PHNPC_ConfigManager:get()

    -- Theme 1: Global & Profiles
    addOption(page, {"addTitle", "addLabel"}, "Theme 1 - Global & Profils")
    local profile = addOption(page, {"addComboBox", "addCombo"}, "activeProfile", "Profil actif", {
        "realistic", "hardcore", "narrative", "ultra_hardcore", "rp_soft"
    }, cfg.activeProfile)
    bindOption(profile, "activeProfile", cfg.activeProfile, function(v)
        return tostring(v or cfg.activeProfile)
    end)

    -- Theme 2: Network & Performance
    addOption(page, {"addTitle", "addLabel"}, "Theme 2 - Reseau & Performance")
    local sync = addOption(page, {"addSlider"}, "networkSyncInterval", "Intervalle sync reseau (s)", 0.1, 2.0, cfg.networkSyncInterval, 0.1)
    bindOption(sync, "networkSyncInterval", cfg.networkSyncInterval, tonumber)

    local fsmLimit = addOption(page, {"addSlider"}, "fsmEntriesLimit", "Limite entrees FSM", 5, 15, cfg.fsmEntriesLimit, 1)
    bindOption(fsmLimit, "fsmEntriesLimit", cfg.fsmEntriesLimit, tonumber)

    local fsmRange = addOption(page, {"addSlider"}, "fsmRange", "Portee FSM", 20, 60, cfg.fsmRange, 1)
    bindOption(fsmRange, "fsmRange", cfg.fsmRange, tonumber)

    local maxActiveNPCs = addOption(page, {"addSlider"}, "maxActiveNPCs", "NPC actifs max", 4, 48, cfg.maxActiveNPCs, 1)
    bindOption(maxActiveNPCs, "maxActiveNPCs", cfg.maxActiveNPCs, tonumber)

    local perPlayerBudget = addOption(page, {"addSlider"}, "perPlayerBudget", "Budget NPC par joueur", 1, 16, cfg.perPlayerBudget, 1)
    bindOption(perPlayerBudget, "perPlayerBudget", cfg.perPlayerBudget, tonumber)

    local spawnRadius = addOption(page, {"addSlider"}, "spawnRadius", "Rayon de spawn", 18, 80, cfg.spawnRadius, 1)
    bindOption(spawnRadius, "spawnRadius", cfg.spawnRadius, tonumber)

    local despawnRadius = addOption(page, {"addSlider"}, "despawnRadius", "Rayon de despawn", 24, 120, cfg.despawnRadius, 1)
    bindOption(despawnRadius, "despawnRadius", cfg.despawnRadius, tonumber)

    local spawnAttempts = addOption(page, {"addSlider"}, "spawnAttemptsPerCycle", "Tentatives de spawn / cycle", 2, 20, cfg.spawnAttemptsPerCycle, 1)
    bindOption(spawnAttempts, "spawnAttemptsPerCycle", cfg.spawnAttemptsPerCycle, tonumber)

    local fallbackZombie = addOption(page, {"addTickBox", "addBoolean"}, "allowZombieFallback", "Autoriser fallback zombie", cfg.allowZombieFallback)
    bindOption(fallbackZombie, "allowZombieFallback", cfg.allowZombieFallback)

    -- Theme 3: Dialogue AI (Ollama)
    addOption(page, {"addTitle", "addLabel"}, "Theme 3 - IA de Dialogue (Ollama)")
    local ollamaEnable = addOption(page, {"addTickBox", "addBoolean"}, "enableOllama", "Activer IA Ollama", cfg.enableOllama)
    bindOption(ollamaEnable, "enableOllama", cfg.enableOllama)

    local ollamaUrl = addOption(page, {"addTextEntry", "addTextBox", "addString"}, "ollamaApiUrl", "URL API", cfg.ollamaApiUrl)
    bindOption(ollamaUrl, "ollamaApiUrl", cfg.ollamaApiUrl, tostring)

    local ollamaModel = addOption(page, {"addTextEntry", "addTextBox", "addString"}, "ollamaModel", "Modele", cfg.ollamaModel)
    bindOption(ollamaModel, "ollamaModel", cfg.ollamaModel, tostring)

    local ollamaTimeout = addOption(page, {"addSlider"}, "ollamaTimeoutMs", "Timeout requete (ms)", 2000, 15000, cfg.ollamaTimeoutMs, 100)
    bindOption(ollamaTimeout, "ollamaTimeoutMs", cfg.ollamaTimeoutMs, tonumber)

    local ollamaCache = addOption(page, {"addSlider"}, "ollamaCacheSize", "Taille cache", 10, 100, cfg.ollamaCacheSize, 1)
    bindOption(ollamaCache, "ollamaCacheSize", cfg.ollamaCacheSize, tonumber)

    -- Theme 4: Bite Management
    addOption(page, {"addTitle", "addLabel"}, "Theme 4 - Gestion de l'Infection")
    local biteInterval = addOption(page, {"addSlider"}, "biteCoughIntervalSec", "Intervalle verification toux (s)", 10, 60, cfg.biteCoughIntervalSec, 1)
    bindOption(biteInterval, "biteCoughIntervalSec", cfg.biteCoughIntervalSec, tonumber)

    local biteProb = addOption(page, {"addSlider"}, "biteCoughProbabilityPercent", "Probabilite de toux (%)", 0, 100, math.floor((cfg.biteCoughProbability or 0.15) * 100), 1)
    bindOption(biteProb, "biteCoughProbability", cfg.biteCoughProbability, function(v)
        return (tonumber(v) or 15) / 100
    end)

    local biteIsolation = addOption(page, {"addSlider"}, "biteIsolationAnxietyThreshold", "Seuil isolement anxiete", 0, 100, cfg.biteIsolationAnxietyThreshold, 1)
    bindOption(biteIsolation, "biteIsolationAnxietyThreshold", cfg.biteIsolationAnxietyThreshold, tonumber)

    -- Theme 5: Observation Learning
    addOption(page, {"addTitle", "addLabel"}, "Theme 5 - Apprentissage Passif")
    local obsRange = addOption(page, {"addSlider"}, "observationRange", "Portee observation", 5, 20, cfg.observationRange, 1)
    bindOption(obsRange, "observationRange", cfg.observationRange, tonumber)

    local obsInterval = addOption(page, {"addSlider"}, "observationIntervalSec", "Intervalle verification (s)", 1, 10, cfg.observationIntervalSec, 1)
    bindOption(obsInterval, "observationIntervalSec", cfg.observationIntervalSec, tonumber)

    -- Theme 6: Survival & Economy
    addOption(page, {"addTitle", "addLabel"}, "Theme 6 - Survie & Economie")
    local disableNeeds = addOption(page, {"addTickBox", "addBoolean"}, "disableNeedsDecay", "Desactiver degradation faim/soif", cfg.disableNeedsDecay)
    bindOption(disableNeeds, "disableNeedsDecay", cfg.disableNeedsDecay)

    local priceMult = addOption(page, {"addSlider"}, "serviceBasePriceMultiplier", "Multiplicateur prix services", 0.1, 5.0, cfg.serviceBasePriceMultiplier, 0.1)
    bindOption(priceMult, "serviceBasePriceMultiplier", cfg.serviceBasePriceMultiplier, tonumber)

    local marginMult = addOption(page, {"addSlider"}, "serviceMarginMultiplier", "Marge commerciale globale", 0.5, 3.0, cfg.serviceMarginMultiplier, 0.1)
    bindOption(marginMult, "serviceMarginMultiplier", cfg.serviceMarginMultiplier, tonumber)

    local volatilityMult = addOption(page, {"addSlider"}, "marketVolatilityMultiplier", "Volatilite du marche", 0.25, 2.0, cfg.marketVolatilityMultiplier, 0.05)
    bindOption(volatilityMult, "marketVolatilityMultiplier", cfg.marketVolatilityMultiplier, tonumber)

    local aggressivenessMult = addOption(page, {"addSlider"}, "marketAggressivenessMultiplier", "Agressivite des prix", 0.5, 2.0, cfg.marketAggressivenessMultiplier, 0.05)
    bindOption(aggressivenessMult, "marketAggressivenessMultiplier", cfg.marketAggressivenessMultiplier, tonumber)

    local quoteCooldown = addOption(page, {"addSlider"}, "quoteCooldownSec", "Cooldown devis (s)", 1, 60, cfg.quoteCooldownSec, 1)
    bindOption(quoteCooldown, "quoteCooldownSec", cfg.quoteCooldownSec, tonumber)

    if type(page.apply) == "function" then
        local prevApply = page.apply
        page.apply = function(...)
            local ok = pcall(prevApply, ...)
            PHNPC_ConfigManager:applyToRuntime(true)
            return ok
        end
    end

    PHNPC_ConfigManager:applyToRuntime(true)
end

if Events and Events.OnGameStart then
    Events.OnGameStart.Add(function()
        -- pcall : registerPage appelle setModOptionValue etc. qui peuvent echouer
        -- si PHNPC_ConfigManager n'est pas encore pret au moment de OnGameStart
        local ok, err = pcall(registerPage)
        if not ok then
            print("[PHNPC Config] registerPage failed: " .. tostring(err))
        end
    end)
else
    local ok, err = pcall(registerPage)
    if not ok then
        print("[PHNPC Config] registerPage failed: " .. tostring(err))
    end
end
