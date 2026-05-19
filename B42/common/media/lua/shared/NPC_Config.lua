--[[
    Project Humain : Dynamic NPC Overhaul — B42
    shared/NPC_Config.lua

    Lit les SandboxVars.PHNPC injectés par sandbox-options.txt.
    Fournit des valeurs par défaut si les vars sandbox sont absentes.
    Priorité : SandboxVars > defaults.
]]

local Log = PHNPC.getModule("NPC_Logger")

-- ============================================================
-- Valeurs par défaut (miroir de sandbox-options.txt)
-- ============================================================
local DEFAULTS = {
    -- Général  (ActiveProfile = entier 1-5, correspond à sandbox-options.txt type=integer)
    ActiveProfile                    = 2,
    DebugMode                        = false,

    -- Spawn & performance
    MaxActiveNPCs                    = 12,
    PerPlayerBudget                  = 4,
    SpawnRadius                      = 32,
    DespawnRadius                    = 48,
    FSMRange                         = 40,
    FSMEntriesLimit                  = 10,
    SpawnAttemptsPerCycle            = 6,
    NetworkSyncIntervalTenths        = 5,   -- ×0.1 = 0.5 s

    -- Ollama
    EnableOllama                     = false,
    OllamaApiUrl                     = "http://localhost:11434",
    OllamaModel                      = "neural-chat",
    OllamaTimeoutMs                  = 8000,
    OllamaCacheSize                  = 50,

    -- Morsures
    BiteCoughIntervalSec             = 30,
    BiteCoughProbabilityPercent      = 15,
    BiteIsolationAnxietyThreshold    = 60,

    -- Apprentissage passif
    ObservationRange                 = 12,
    ObservationIntervalSec           = 2,

    -- Économie
    DisableNeedsDecay                = false,
    ServiceBasePriceMultiplierTenths = 10,  -- ×0.1 = 1.0
    ServiceMarginMultiplierTenths    = 10,
    MarketVolatilityMultiplierTenths = 10,
    QuoteCooldownSec                 = 6,
}

local VALID_PROFILES = { realistic=true, hardcore=true, narrative=true,
                          ultra_hardcore=true, rp_soft=true }

-- ============================================================
-- Module
-- ============================================================
local NPC_Config = {
    _cache = nil,
}

local function getSandbox()
    local vars = rawget(_G, "SandboxVars")
    if type(vars) == "table" and type(vars.PHNPC) == "table" then
        return vars.PHNPC
    end
    return nil
end

local function readNumber(sb, key, lo, hi, fallback)
    local v = tonumber(sb and sb[key])
    if not v then return fallback end
    return PHNPC.clamp(v, lo, hi)
end

local function readBool(sb, key, fallback)
    local v = sb and sb[key]
    if v == nil then return fallback end
    return v == true or v == 1 or v == "1" or v == "true"
end

local function readProfile(sb)
    local p = tostring((sb and sb.ActiveProfile) or ""):lower()
    return VALID_PROFILES[p] and p or DEFAULTS.ActiveProfile
end

--- Construit (ou retourne en cache) la configuration active.
function NPC_Config.get()
    if NPC_Config._cache then return NPC_Config._cache end

    local sb  = getSandbox()
    local cfg = PHNPC.deepCopy(DEFAULTS)

    cfg.ActiveProfile                    = readProfile(sb)
    cfg.DebugMode                        = readBool(sb,   "DebugMode",                        DEFAULTS.DebugMode)
    cfg.MaxActiveNPCs                    = readNumber(sb, "MaxActiveNPCs",                    1,  40,    DEFAULTS.MaxActiveNPCs)
    cfg.PerPlayerBudget                  = readNumber(sb, "PerPlayerBudget",                  1,  10,    DEFAULTS.PerPlayerBudget)
    cfg.SpawnRadius                      = readNumber(sb, "SpawnRadius",                      10, 80,    DEFAULTS.SpawnRadius)
    cfg.DespawnRadius                    = readNumber(sb, "DespawnRadius",                    20, 120,   DEFAULTS.DespawnRadius)
    cfg.FSMRange                         = readNumber(sb, "FSMRange",                         10, 80,    DEFAULTS.FSMRange)
    cfg.NetworkSyncIntervalTenths        = readNumber(sb, "NetworkSyncIntervalTenths",        1,  20,    DEFAULTS.NetworkSyncIntervalTenths)
    cfg.EnableOllama                     = readBool(sb,   "EnableOllama",                     DEFAULTS.EnableOllama)
    cfg.OllamaModel                      = (sb and type(sb.OllamaModel) == "string" and #sb.OllamaModel > 0 and sb.OllamaModel) or DEFAULTS.OllamaModel
    cfg.OllamaTimeoutMs                  = readNumber(sb, "OllamaTimeoutMs",                  1000, 30000, DEFAULTS.OllamaTimeoutMs)
    cfg.OllamaCacheSize                  = readNumber(sb, "OllamaCacheSize",                  0,  200,   DEFAULTS.OllamaCacheSize)
    cfg.BiteCoughIntervalSec             = readNumber(sb, "BiteCoughIntervalSec",             10, 120,   DEFAULTS.BiteCoughIntervalSec)
    cfg.BiteCoughProbabilityPercent      = readNumber(sb, "BiteCoughProbabilityPercent",      1,  100,   DEFAULTS.BiteCoughProbabilityPercent)
    cfg.ObservationRange                 = readNumber(sb, "ObservationRange",                 4,  30,    DEFAULTS.ObservationRange)
    cfg.ObservationIntervalSec           = readNumber(sb, "ObservationIntervalSec",           1,  10,    DEFAULTS.ObservationIntervalSec)
    cfg.DisableNeedsDecay                = readBool(sb,   "DisableNeedsDecay",                DEFAULTS.DisableNeedsDecay)
    cfg.ServiceBasePriceMultiplierTenths = readNumber(sb, "ServiceBasePriceMultiplierTenths", 1,  50,    DEFAULTS.ServiceBasePriceMultiplierTenths)

    -- Dérivés calculés
    cfg.NetworkSyncInterval = cfg.NetworkSyncIntervalTenths * 0.1
    cfg.ServiceBasePriceMultiplier = cfg.ServiceBasePriceMultiplierTenths * 0.1

    if Log then Log.debug("NPC_Config", "Configuration chargée", { source = sb and "SandboxVars" or "defaults", profile = cfg.ActiveProfile }) end

    NPC_Config._cache = cfg
    return cfg
end

--- Invalide le cache (à appeler si les sandbox vars changent).
function NPC_Config.invalidate()
    NPC_Config._cache = nil
end

PHNPC.registerModule("NPC_Config", NPC_Config)
return NPC_Config
