--[[
    Project Humain : Dynamic_NPC_Overhaul
    NPCDataModel.lua

    Classe de base pour les PNJ dynamiques (solo et multi) sur Project Zomboid v41.78.19.
    Conception orientee objet (table + metatable) pour offrir une base extensible.
]]

local NPCDataModel = {}
NPCDataModel.__index = NPCDataModel


-- Version correcte pour Project Zomboid
if type(LuaEventManager) == "table" and type(LuaEventManager.AddEvent) == "function" then
    if not Events.OnRealtimeEvent then
        LuaEventManager.AddEvent("OnRealtimeEvent")
    end
end

local _idCounter = 0
local _insert = table.insert

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for k, v in pairs(value) do
        copy[k] = deepCopy(v)
    end
    return copy
end

local function clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

local function randInt(minValue, maxValue)
    -- ZombRand est prefere en environnement PZ; fallback sur math.random en dehors du jeu.
    if type(ZombRand) == "function" then
        return minValue + ZombRand((maxValue - minValue) + 1)
    end
    return math.random(minValue, maxValue)
end

local function chance(percent)
    return randInt(1, 100) <= percent
end

local function pickRandom(list)
    return list[randInt(1, #list)]
end

local firstNames = {
    "Alex", "Mathis", "Lucas", "Hugo", "Leo", "Nathan", "Noah", "Tom",
    "Enzo", "Jules", "Emma", "Lea", "Chloe", "Sarah", "Nina", "Camille",
    "Sofia", "Manon", "Laura", "Eva"
}

local lastNames = {
    "Martin", "Bernard", "Dubois", "Thomas", "Robert", "Richard", "Petit", "Durand",
    "Leroy", "Moreau", "Simon", "Laurent", "Michel", "Garcia", "Roux", "Fournier",
    "Girard", "Andre", "Mercier", "Faure"
}

local function buildIdentity(seedData)
    local firstName = tostring(seedData.firstName or seedData.forename or pickRandom(firstNames))
    local lastName = tostring(seedData.lastName or seedData.surname or pickRandom(lastNames))
    local fullName = (firstName .. " " .. lastName)
    if not fullName or #fullName == 0 then
        fullName = firstName .. " " .. lastName
    end
    return {
        firstName = firstName,
        lastName = lastName,
        fullName = fullName
    }
end

local professionCatalog = {
    none = {
        label = "Sans metier",
        produces = {},
        buys = {},
        sells = {},
        tradeMode = "none"
    },
    merchant = {
        label = "Marchand",
        produces = { "general_goods", "materials" },
        buys = { "food", "water", "medicine", "tools", "materials", "weapons", "crafts" },
        sells = { "general_goods", "materials", "tools" },
        tradeMode = "broker"
    },
    cook = {
        label = "Cuisinier",
        produces = { "food" },
        buys = { "food", "water", "fuel", "seasoning" },
        sells = { "food" },
        tradeMode = "barter"
    },
    artisan = {
        label = "Artisan",
        produces = { "tools", "materials", "crafts" },
        buys = { "materials", "tools", "food", "water" },
        sells = { "tools", "materials", "crafts" },
        tradeMode = "barter"
    },
    medic = {
        label = "Medecin",
        produces = { "medicine" },
        buys = { "medicine", "cloth", "alcohol", "food", "water" },
        sells = { "medicine" },
        tradeMode = "barter"
    },
    scavenger = {
        label = "Ratisseur",
        produces = { "mixed_supplies" },
        buys = { "tools", "food", "water", "materials" },
        sells = { "mixed_supplies" },
        tradeMode = "barter"
    },
    guard = {
        label = "Garde",
        produces = { "protection" },
        buys = { "weapons", "ammo", "food", "water" },
        sells = { "service" },
        tradeMode = "barter"
    },
    survivor = {
        label = "Survivant",
        produces = { "mixed_supplies" },
        buys = { "food", "water", "tools" },
        sells = { "mixed_supplies" },
        tradeMode = "barter"
    }
}

local function normalizeProfessionRole(role)
    local value = tostring(role or "survivor"):lower()
    if professionCatalog[value] then
        return value
    end
    return "none"
end

local function shouldAssignProfession(seedData, stats, traits)
    if type(seedData.profession) == "table" or seedData.professionRole ~= nil then
        return true
    end

    -- Tous les PNJ ne doivent pas avoir un metier.
    local socialDrive = traits and traits.personality and traits.personality.socialDrive or 50
    local intelligence = stats and stats.intelligence or 50
    local craftSkill = stats and stats.craftSkill or 0
    local chanceToHaveProfession = 35

    if intelligence >= 60 then chanceToHaveProfession = chanceToHaveProfession + 10 end
    if craftSkill >= 55 then chanceToHaveProfession = chanceToHaveProfession + 10 end
    if socialDrive >= 70 then chanceToHaveProfession = chanceToHaveProfession + 5 end

    chanceToHaveProfession = clamp(chanceToHaveProfession, 20, 75)
    return chance(chanceToHaveProfession)
end

local function inferProfessionRole(seedData, stats, traits)
    if not shouldAssignProfession(seedData, stats, traits) then
        return "none"
    end

    if type(seedData.profession) == "table" and seedData.profession.role then
        return normalizeProfessionRole(seedData.profession.role)
    end

    if seedData.professionRole then
        return normalizeProfessionRole(seedData.professionRole)
    end

    local personality = traits and traits.personality or {}
    local socialDrive = personality.socialDrive or 50
    local opportunism = personality.opportunism or 50
    local craftSkill = stats.craftSkill or 0
    local intelligence = stats.intelligence or 0
    local strength = stats.strength or 0
    local courage = stats.courage or 0

    if socialDrive >= 70 and opportunism >= 60 and intelligence >= 45 then
        return "merchant"
    end

    if craftSkill >= 70 and intelligence >= 60 then
        return "artisan"
    end

    if intelligence >= 65 and craftSkill >= 40 then
        return "cook"
    end

    if intelligence >= 60 and craftSkill >= 35 and (seedData.healthCurrent or 100) >= 70 then
        return "medic"
    end

    if strength >= 65 and courage >= 55 then
        return "guard"
    end

    if opportunism >= 55 and socialDrive <= 55 then
        return "scavenger"
    end

    return "survivor"
end

local function buildProfession(seedData, stats, traits)
    local role = inferProfessionRole(seedData, stats, traits)
    local catalog = professionCatalog[role] or professionCatalog.survivor
    local source = "generated"
    local level = randInt(1, 5)
    local strategy = seedData.professionStrategy or "balanced"

    if type(seedData.profession) == "table" then
        local provided = seedData.profession
        source = provided.source or source
        level = clamp(provided.level or level, 1, 10)
        strategy = provided.strategy or provided.mode or strategy
    else
        level = clamp(seedData.professionLevel or level, 1, 10)
        if seedData.professionSource then
            source = tostring(seedData.professionSource)
        end
    end

    local hasProfession = role ~= "none"
    local maxLevel = 10
    local unlocked = hasProfession and level >= maxLevel

    return {
        role = role,
        label = catalog.label,
        level = level,
        maxLevel = maxLevel,
        unlocked = unlocked,
        hasProfession = hasProfession,
        source = source,
        strategy = tostring(strategy or "balanced"),
        tradeMode = catalog.tradeMode,
        produces = deepCopy(catalog.produces),
        buys = deepCopy(catalog.buys),
        sells = deepCopy(catalog.sells),
        requests = deepCopy(catalog.buys),
        isMerchant = role == "merchant",
        canChange = seedData.professionLocked ~= true,
        changedCount = clamp(seedData.professionChangedCount or 0, 0, 99)
    }
end

local function buildStarterEconomy(seedData)
    local cash = tonumber(seedData.cash or seedData.money or 0) or 0
    local savings = tonumber(seedData.savings or 0) or 0
    return {
        cash = math.max(0, math.floor(cash)),
        savings = math.max(0, math.floor(savings)),
        reservedForClan = math.max(0, math.floor(tonumber(seedData.reservedForClan or 0) or 0)),
        budgetMode = seedData.budgetMode or "balanced",
        lastPriceTrend = seedData.lastPriceTrend or "neutral",
        marketBias = clamp(seedData.marketBias or 0, -100, 100),
        priceMemory = seedData.priceMemory or {},
        requests = seedData.economyRequests or {},
        supportClanFirst = seedData.supportClanFirst == true,
        soloPriority = seedData.soloPriority == true
    }
end

local function generateUniqueId()
    _idCounter = _idCounter + 1

    local timestamp = 0
    if os and os.time then
        timestamp = os.time()
    end

    return string.format("npc_%d_%d_%d", timestamp, _idCounter, randInt(1000, 9999))
end

function NPCDataModel.getCourageLabel(courage)
    if courage <= 20 then
        return "lache"
    elseif courage <= 40 then
        return "prudent"
    elseif courage <= 65 then
        return "equilibre"
    elseif courage <= 85 then
        return "audacieux"
    end
    return "heroique"
end

local function buildStarterInventory()
    local inventory = {
        maxWeight = randInt(8, 14),
        currentWeight = 0,
        items = {}
    }

    local lootPool = {
        "Base.WaterBottleEmpty",
        "Base.Bandage",
        "Base.Crisps",
        "Base.CannedSardines",
        "Base.Hammer",
        "Base.Screwdriver",
        "Base.Sheet",
        "Base.KitchenKnife",
        "Base.Lighter"
    }

    -- 55% chance de demarrer presque nu (0 item); sinon 1 a 3 objets de base.
    local itemCount = 0
    if not chance(55) then
        itemCount = randInt(1, 3)
    end

    for i = 1, itemCount do
        local item = lootPool[randInt(1, #lootPool)]
        _insert(inventory.items, {
            type = item,
            condition = randInt(35, 100),
            quantity = 1
        })
    end

    inventory.currentWeight = #inventory.items
    return inventory
end

function NPCDataModel.new(seedData)
    local self = setmetatable({}, NPCDataModel)
    self:initialize(seedData)
    return self
end

function NPCDataModel:initialize(seedData)
    seedData = seedData or {}

    self.id = seedData.id or generateUniqueId()

    local identity = buildIdentity(seedData)
    self.firstName = identity.firstName
    self.lastName = identity.lastName
    self.name = identity.fullName
    self.displayName = identity.fullName

    -- Stats evolutives (0-100), modifiables ensuite via la logique de simulation.
    self.stats = {
        hunger = clamp(seedData.hunger or randInt(20, 70), 0, 100),
        thirst = clamp(seedData.thirst or randInt(20, 70), 0, 100),
        courage = clamp(seedData.courage or randInt(10, 90), 0, 100),
        intelligence = clamp(seedData.intelligence or randInt(25, 85), 0, 100),
        strength = clamp(seedData.strength or randInt(20, 90), 0, 100),
        craftSkill = clamp(seedData.craftSkill or randInt(0, 60), 0, 100),
        sociability = clamp(seedData.sociability or randInt(25, 80), 0, 100)
    }

    self.health = {
        current = clamp(seedData.healthCurrent or randInt(70, 100), 0, 100),
        max = clamp(seedData.healthMax or 100, 1, 100),
        isBitten = seedData.isBitten == true,
        isHidingBite = seedData.isHidingBite == true,
        pain = clamp(seedData.pain or randInt(0, 35), 0, 100),
        fatigue = clamp(seedData.fatigue or randInt(10, 60), 0, 100),
        localizedInjuries = deepCopy(seedData.localizedInjuries or {
            head = 0,
            torso = 0,
            arm_l = 0,
            arm_r = 0,
            hand_l = 0,
            hand_r = 0,
            leg_l = 0,
            leg_r = 0,
            foot_l = 0,
            foot_r = 0
        })
    }

    self.inventory = seedData.inventory or buildStarterInventory()
    self.economy = seedData.economy or buildStarterEconomy(seedData)

    -- Memoire sociale/tactique du PNJ.
    self.memory = {
        reputationByPlayer = seedData.reputationByPlayer or {}, -- ex: ["playerUsername"] = -100..100
        dangerousZones = seedData.dangerousZones or {},         -- ex: { "Rosewood_Police", "Muldraugh_Warehouse" }
        trustedNPCs = seedData.trustedNPCs or {},               -- ids PNJ consideres fiables
        knownLootSpots = seedData.knownLootSpots or {},         -- zones connues pour ressources
        recentEvents = seedData.recentEvents or {}              -- journal compact d'evenements
    }

    self.traits = {
        courageLabel = NPCDataModel.getCourageLabel(self.stats.courage),
        personality = {
            socialDrive = clamp(seedData.socialDrive or randInt(15, 90), 0, 100),
            loneWolf = clamp(seedData.loneWolf or randInt(10, 90), 0, 100),
            adaptability = clamp(seedData.adaptability or randInt(20, 90), 0, 100),
            brutality = clamp(seedData.brutality or randInt(5, 80), 0, 100),
            opportunism = clamp(seedData.opportunism or randInt(10, 90), 0, 100)
        }
    }

    self.profession = buildProfession(seedData, self.stats, self.traits)
end

function NPCDataModel:updateCourageLabel()
    self.traits.courageLabel = NPCDataModel.getCourageLabel(self.stats.courage)
end

function NPCDataModel:adjustStat(statName, delta)
    local current = self.stats[statName]
    if current == nil then
        return false
    end

    self.stats[statName] = clamp(current + delta, 0, 100)
    if statName == "courage" then
        self:updateCourageLabel()
    end
    return true
end

function NPCDataModel:isBiteSecretActive()
    return self.health.isBitten and self.health.isHidingBite
end

function NPCDataModel:toTable()
    return {
        schemaVersion = 1,
        id = self.id,
        firstName = self.firstName,
        lastName = self.lastName,
        name = self.name,
        displayName = self.displayName,
        stats = deepCopy(self.stats),
        health = deepCopy(self.health),
        inventory = deepCopy(self.inventory),
        economy = deepCopy(self.economy),
        memory = deepCopy(self.memory),
        traits = deepCopy(self.traits),
        profession = deepCopy(self.profession)
    }
end

function NPCDataModel:serialize()
    local snapshot = self:toTable()

    -- PZ fournit souvent JSON.encode; sinon on retourne la table brute.
    if JSON and type(JSON.encode) == "function" then
        return JSON.encode(snapshot)
    end

    return snapshot
end

function NPCDataModel:fromTable(data)
    if type(data) ~= "table" then
        return false, "invalid_table"
    end

    self.id = data.id or self.id or generateUniqueId()
    self.firstName = tostring(data.firstName or data.forename or self.firstName or "Alex")
    self.lastName = tostring(data.lastName or data.surname or self.lastName or "Martin")
    self.name = tostring(data.name or data.displayName or (self.firstName .. " " .. self.lastName))
    self.displayName = tostring(data.displayName or self.name)

    local stats = data.stats or {}
    self.stats = {
        hunger = clamp(stats.hunger or 0, 0, 100),
        thirst = clamp(stats.thirst or 0, 0, 100),
        courage = clamp(stats.courage or 0, 0, 100),
        intelligence = clamp(stats.intelligence or 0, 0, 100),
        strength = clamp(stats.strength or 0, 0, 100),
        craftSkill = clamp(stats.craftSkill or 0, 0, 100)
    }

    local health = data.health or {}
    self.health = {
        current = clamp(health.current or 100, 0, 100),
        max = clamp(health.max or 100, 1, 100),
        isBitten = health.isBitten == true,
        isHidingBite = health.isHidingBite == true,
        pain = clamp(health.pain or 0, 0, 100),
        fatigue = clamp(health.fatigue or 0, 0, 100)
    }

    self.inventory = deepCopy(data.inventory or {
        maxWeight = 10,
        currentWeight = 0,
        items = {}
    })

    self.economy = deepCopy(data.economy or buildStarterEconomy(data))

    local memory = data.memory or {}
    self.memory = {
        reputationByPlayer = deepCopy(memory.reputationByPlayer or {}),
        dangerousZones = deepCopy(memory.dangerousZones or {}),
        trustedNPCs = deepCopy(memory.trustedNPCs or {}),
        knownLootSpots = deepCopy(memory.knownLootSpots or {}),
        recentEvents = deepCopy(memory.recentEvents or {})
    }

    self.traits = deepCopy(data.traits or {})
    self:updateCourageLabel()

    self.profession = buildProfession(data, self.stats, self.traits)

    return true
end

function NPCDataModel.deserialize(payload)
    local parsed = payload

    if type(payload) == "string" then
        if JSON and type(JSON.decode) == "function" then
            parsed = JSON.decode(payload)
        else
            return nil, "json_decode_unavailable"
        end
    end

    if type(parsed) ~= "table" then
        return nil, "invalid_payload"
    end

    local npc = NPCDataModel.new({
        id = parsed.id
    })

    local ok, err = npc:fromTable(parsed)
    if not ok then
        return nil, err
    end

    return npc
end

return NPCDataModel
