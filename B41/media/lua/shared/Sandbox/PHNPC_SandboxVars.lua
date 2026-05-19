--[[
    Dynamic NPC Overhaul - Custom Sandbox values
    FR: Valeurs Sandbox personnalisees du mod.
    EN: Custom sandbox values for the mod.
]]

SandboxVars = SandboxVars or {}
SandboxVars.PHNPC = SandboxVars.PHNPC or {
    -- Theme 1: Global & Profiles
    ActiveProfile = "realistic",

    -- Theme 2: Network & Performance
    NetworkSyncIntervalTenths = 5, -- 0.5s
    FSMEntriesLimit = 10,
    FSMRange = 40,
    MaxActiveNPCs = 12,
    PerPlayerBudget = 4,
    SpawnRadius = 32,
    DespawnRadius = 48,
    SpawnAttemptsPerCycle = 6,
    AllowZombieFallback = true,

    -- Theme 3: Dialogue AI (Ollama)
    EnableOllama = true,
    OllamaApiUrl = "http://localhost:11434",
    OllamaModel = "neural-chat",
    OllamaTimeoutMs = 8000,
    OllamaCacheSize = 50,

    -- Theme 4: Bite Management
    BiteCoughIntervalSec = 30,
    BiteCoughProbabilityPercent = 15,
    BiteIsolationAnxietyThreshold = 60,

    -- Theme 5: Observation Learning
    ObservationRange = 12,
    ObservationIntervalSec = 2,

    -- Theme 6: Survival & Economy
    DisableNeedsDecay = false,
    ServiceBasePriceMultiplierTenths = 10, -- 1.0x
    ServiceMarginMultiplierTenths = 10, -- 1.0x
    MarketVolatilityMultiplierTenths = 10, -- 1.0x
    MarketAggressivenessMultiplierTenths = 10, -- 1.0x
    QuoteCooldownSec = 6
}

return SandboxVars.PHNPC
