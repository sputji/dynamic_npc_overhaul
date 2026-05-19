--[[
    Project Humain : Dynamic_NPC_Overhaul
    NPCMemory.lua

    Memoire sociale et dramatique des PNJ.
    - Historique aide/vol/force du joueur
    - Partage d'informations entre PNJ
    - Transmission conditionnelle d'infos aux joueurs
    - Echanges gratuits, troc, contreparties et demandes d'aide
    - Gestion de l'infection cachee (eloignement discret / attaque)
]]

local NPCMemory = {
    maxRecentEvents = 24,
    maxTradeLedger = 28,
    maxRequestLedger = 22,
    maxSharedIntelPerActor = 10,
    maxActorProfiles = 72,
    maxActorRumors = 72,
    maxDangerousZones = 64,
    maxKnownLootSpots = 64,
    maxTrustedNPCs = 96,
    maxReputationByActor = 96,
    infectionProgressPerTick = 0.35,
    bittenLeaveThreshold = 72,
    bittenAttackThreshold = 100,
    socialDecayPerTick = 0.028,
    socialGainDialogue = 2.7,
    socialGainTrade = 1.6,
    traumaDecayPerTick = 0.02,
    rageDecayPerTick = 0.03,
    traumaThreatTrigger = 62,
    traumaFreezeThreshold = 52,
    rageThreatTrigger = 48,
    rageActivationThreshold = 38,
    expeditionReturnBaseChance = 28,
    expeditionSurvivalFactor = 0.38,
    expeditionDistancePenalty = 1.65,
    expeditionMinReturnChance = 8,
    expeditionMaxReturnChance = 92,
    expeditionDurationJitterMin = 120,
    expeditionDurationJitterMax = 320,
    weatherWetGain = 1.6,
    weatherWetDry = 1.2,
    weatherColdGain = 1.4,
    weatherColdRecover = 0.9,
    globalServicePriceMultiplier = 1.0,
    globalServiceMarginMultiplier = 1.0,
    globalMarketVolatilityMultiplier = 1.0,
    globalMarketAggressivenessMultiplier = 1.0
}

local hasTuningProfiles, NPCTuningProfiles = pcall(require, "NPCTuningProfiles")
if not hasTuningProfiles then
    NPCTuningProfiles = nil
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
    if type(ZombRand) == "function" then
        return minValue + ZombRand((maxValue - minValue) + 1)
    end
    return math.random(minValue, maxValue)
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

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end

    local out = {}
    for k, v in pairs(value) do
        out[k] = deepCopy(v)
    end
    return out
end

local function nowTick(context)
    if type(context) == "table" and context.tick then
        return context.tick
    end
    return 0
end

local function normalizeId(actor)
    if type(actor) == "string" then
        return actor
    end

    if type(actor) == "table" then
        if actor.id then
            return tostring(actor.id)
        end
        if actor.getUsername then
            local ok, username = pcall(function()
                return actor:getUsername()
            end)
            if ok and username then
                return tostring(username)
            end
        end
        if actor.username then
            return tostring(actor.username)
        end
    end

    return tostring(actor)
end

local localizedPartKeys = {
    "head",
    "torso",
    "arm_l",
    "arm_r",
    "hand_l",
    "hand_r",
    "leg_l",
    "leg_r",
    "foot_l",
    "foot_r"
}

local function ensureLocalizedInjuries(npcData)
    npcData.health = npcData.health or {}
    local injuries = npcData.health.localizedInjuries
    if type(injuries) ~= "table" then
        injuries = {}
        npcData.health.localizedInjuries = injuries
    end

    for i = 1, #localizedPartKeys do
        local key = localizedPartKeys[i]
        injuries[key] = clamp(tonumber(injuries[key]) or 0, 0, 100)
    end

    return injuries
end

local function normalizeActorKey(actorType, actorId)
    local kind = tostring(actorType or "unknown")
    return kind .. ":" .. normalizeId(actorId)
end

local function pruneTableHead(tbl, maxCount)
    if type(tbl) ~= "table" then
        return
    end
    while #tbl > maxCount do
        table.remove(tbl, 1)
    end
end

local function countMapEntries(tbl)
    local count = 0
    if type(tbl) ~= "table" then
        return count
    end
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

local function pruneMapByLastTick(tbl, maxEntries)
    if type(tbl) ~= "table" then
        return
    end

    local count = countMapEntries(tbl)
    if count <= maxEntries then
        return
    end

    local entries = {}
    for key, value in pairs(tbl) do
        entries[#entries + 1] = {
            key = key,
            tick = tonumber(value and (value.lastInteractionTick or value.lastActionTick or value.lastTradeTick or value.lastSeenTick or value.lastTick or value.lastUpdateTick or value.sharedTick or value.tick)) or 0
        }
    end

    table.sort(entries, function(a, b)
        return a.tick < b.tick
    end)

    local toDelete = count - maxEntries
    for i = 1, toDelete do
        local item = entries[i]
        if item and item.key ~= nil then
            tbl[item.key] = nil
        end
    end
end

local function pruneBooleanMapByKey(tbl, maxEntries)
    if type(tbl) ~= "table" then
        return
    end

    local count = countMapEntries(tbl)
    if count <= maxEntries then
        return
    end

    local keys = {}
    for key in pairs(tbl) do
        keys[#keys + 1] = tostring(key)
    end
    table.sort(keys)

    local toDelete = count - maxEntries
    for i = 1, toDelete do
        tbl[keys[i]] = nil
    end
end

local professionCatalog = {
    none = {
        label = "Sans metier",
        buys = {},
        sells = {},
        produces = {},
        tradeMode = "none"
    },
    merchant = {
        label = "Marchand",
        buys = { "food", "water", "medicine", "tools", "materials", "weapons", "crafts" },
        sells = { "general_goods", "materials", "tools" },
        produces = { "general_goods", "materials" },
        tradeMode = "broker"
    },
    cook = {
        label = "Cuisinier",
        buys = { "food", "water", "fuel", "seasoning" },
        sells = { "food" },
        produces = { "food" },
        tradeMode = "barter"
    },
    artisan = {
        label = "Artisan",
        buys = { "materials", "tools", "food", "water" },
        sells = { "tools", "materials", "crafts" },
        produces = { "tools", "materials", "crafts" },
        tradeMode = "barter"
    },
    medic = {
        label = "Medecin",
        buys = { "medicine", "cloth", "alcohol", "food", "water" },
        sells = { "medicine" },
        produces = { "medicine" },
        tradeMode = "barter"
    },
    scavenger = {
        label = "Ratisseur",
        buys = { "tools", "food", "water", "materials" },
        sells = { "mixed_supplies" },
        produces = { "mixed_supplies" },
        tradeMode = "barter"
    },
    guard = {
        label = "Garde",
        buys = { "weapons", "ammo", "food", "water" },
        sells = { "service" },
        produces = { "protection" },
        tradeMode = "barter"
    },
    survivor = {
        label = "Survivant",
        buys = { "food", "water", "tools" },
        sells = { "mixed_supplies" },
        produces = { "mixed_supplies" },
        tradeMode = "barter"
    }
}

local serviceCatalog = {
    cook = { baseCost = 18, category = "food", label = "Cuisine" },
    build = { baseCost = 32, category = "materials", label = "Construction" },
    craft = { baseCost = 26, category = "crafts", label = "Fabrication" },
    buy = { baseCost = 12, category = "general_goods", label = "Achat" },
    scavenge = { baseCost = 24, category = "tools", label = "Exploration" },
    study = { baseCost = 14, category = "crafts", label = "Apprentissage" },
    guard = { baseCost = 20, category = "service", label = "Protection" },
    trade = { baseCost = 10, category = "general_goods", label = "Commerce" }
}

local currencyItemTypes = {
    "Base.Money",
    "Base.MoneyBundle",
    "Base.DollarBill",
    "Base.Dollars"
}

NPCMemory.currencyItemTypes = currencyItemTypes

local categoryDefaultItems = {
    food = "Base.CannedSardines",
    water = "Base.WaterBottleFull",
    medicine = "Base.Bandage",
    tools = "Base.Screwdriver",
    materials = "Base.Sheet",
    crafts = "Base.Book",
    weapons = "Base.KitchenKnife",
    ammo = "Base.Bullets9mm",
    general_goods = "Base.Battery",
    service = "Base.RippedSheets"
}

local productionRecipes = {
    craft = {
        workUnits = 6,
        ingredients = {
            materials = 2,
            tools = 1
        },
        resultByCategory = {
            food = { itemType = categoryDefaultItems.food, quantity = 1 },
            water = { itemType = categoryDefaultItems.water, quantity = 1 },
            medicine = { itemType = categoryDefaultItems.medicine, quantity = 1 },
            tools = { itemType = categoryDefaultItems.tools, quantity = 1 },
            materials = { itemType = categoryDefaultItems.materials, quantity = 2 },
            crafts = { itemType = categoryDefaultItems.crafts, quantity = 1 },
            weapons = { itemType = categoryDefaultItems.weapons, quantity = 1 },
            general_goods = { itemType = categoryDefaultItems.general_goods, quantity = 1 }
        }
    },
    build = {
        workUnits = 8,
        ingredients = {
            materials = 3,
            tools = 1
        },
        resultByCategory = {
            materials = { itemType = categoryDefaultItems.materials, quantity = 3 },
            general_goods = { itemType = categoryDefaultItems.materials, quantity = 2 }
        }
    },
    buy = {
        workUnits = 1,
        ingredients = {},
        resultByCategory = {
            food = { itemType = categoryDefaultItems.food, quantity = 1 },
            water = { itemType = categoryDefaultItems.water, quantity = 1 },
            medicine = { itemType = categoryDefaultItems.medicine, quantity = 1 },
            tools = { itemType = categoryDefaultItems.tools, quantity = 1 },
            materials = { itemType = categoryDefaultItems.materials, quantity = 1 },
            crafts = { itemType = categoryDefaultItems.crafts, quantity = 1 },
            weapons = { itemType = categoryDefaultItems.weapons, quantity = 1 },
            ammo = { itemType = categoryDefaultItems.ammo, quantity = 1 },
            general_goods = { itemType = categoryDefaultItems.general_goods, quantity = 1 }
        }
    }
}

local function containsText(text, needle)
    return tostring(text or ""):lower():find(needle, 1, true) ~= nil
end

local function classifyItemType(itemType)
    local value = tostring(itemType or ""):lower()
    if value == "" then
        return "general_goods"
    end

    if containsText(value, "water") or containsText(value, "bottle") or containsText(value, "juice") or containsText(value, "soda") or containsText(value, "pop") then
        return "water"
    end
    if containsText(value, "canned") or containsText(value, "food") or containsText(value, "crisps") or containsText(value, "beans") or containsText(value, "soup") or containsText(value, "sardines") or containsText(value, "tuna") or containsText(value, "bread") or containsText(value, "meat") or containsText(value, "fruit") then
        return "food"
    end
    if containsText(value, "bandage") or containsText(value, "pill") or containsText(value, "alcohol") or containsText(value, "disinfect") or containsText(value, "firstaid") or containsText(value, "medical") or containsText(value, "antibiotic") then
        return "medicine"
    end
    if containsText(value, "hammer") or containsText(value, "screwdriver") or containsText(value, "saw") or containsText(value, "wrench") or containsText(value, "trowel") or containsText(value, "axe") or containsText(value, "knife") or containsText(value, "tool") then
        return "tools"
    end
    if containsText(value, "sheet") or containsText(value, "nail") or containsText(value, "plank") or containsText(value, "rope") or containsText(value, "duct") or containsText(value, "glue") or containsText(value, "wood") then
        return "materials"
    end
    if containsText(value, "ammo") or containsText(value, "bullet") or containsText(value, "shell") then
        return "ammo"
    end
    if containsText(value, "weapon") or containsText(value, "gun") or containsText(value, "pistol") or containsText(value, "rifle") or containsText(value, "bat") or containsText(value, "axe") then
        return "weapons"
    end
    if containsText(value, "thread") or containsText(value, "needle") or containsText(value, "book") or containsText(value, "magazine") or containsText(value, "recipe") then
        return "crafts"
    end

    return "general_goods"
end

local function categoryMatchesItem(itemType, category)
    local cat = tostring(category or "general_goods"):lower()
    if cat == "general_goods" then
        return true
    end
    return classifyItemType(itemType) == cat
end

local function resolveMarketCategory(request, profession)
    if type(request) ~= "table" then
        return profession and profession.role or "general_goods"
    end

    local explicit = request.marketCategory or request.category
    if explicit then
        return tostring(explicit)
    end

    local serviceType = tostring(request.serviceType or request.orderType or request.mode or profession and profession.role or "trade"):lower()
    if serviceType == "build" then
        return "materials"
    elseif serviceType == "craft" then
        return "crafts"
    elseif serviceType == "buy" or serviceType == "trade" then
        if request.itemType then
            return classifyItemType(request.itemType)
        end
        return "general_goods"
    elseif serviceType == "cook" then
        return "food"
    elseif serviceType == "guard" then
        return "service"
    elseif serviceType == "scavenge" then
        return "tools"
    elseif serviceType == "study" then
        return "crafts"
    end

    return profession and (profession.sells and profession.sells[1]) or "general_goods"
end

local function normalizeRecipeCategory(value)
    local category = tostring(value or "general_goods"):lower()
    if categoryDefaultItems[category] then
        return category
    end
    return "general_goods"
end

local function pickDefaultResultItem(category)
    local normalized = normalizeRecipeCategory(category)
    return categoryDefaultItems[normalized] or categoryDefaultItems.general_goods, normalized
end

local function getInventoryItems(npcData)
    local inventory = npcData and npcData.inventory or nil
    local items = inventory and inventory.items or nil
    if type(items) ~= "table" then
        return nil
    end
    return items
end

local function removeInventoryByCategory(npcData, category, quantity)
    local items = getInventoryItems(npcData)
    if type(items) ~= "table" then
        return false, 0
    end

    local wanted = math.max(1, tonumber(quantity) or 1)
    local removed = 0
    local i = 1
    while i <= #items and removed < wanted do
        local item = items[i]
        if item and item.type and (item.quantity or 0) > 0 then
            local itemCategory = classifyItemType(item.type)
            if category == itemCategory or category == "general_goods" then
                local have = math.max(0, tonumber(item.quantity) or 0)
                local take = math.min(wanted - removed, have)
                item.quantity = have - take
                removed = removed + take
                if item.quantity <= 0 then
                    table.remove(items, i)
                else
                    i = i + 1
                end
            else
                i = i + 1
            end
        else
            i = i + 1
        end
    end

    if removed > 0 and npcData.inventory then
        npcData.inventory.currentWeight = math.max(0, (tonumber(npcData.inventory.currentWeight) or 0) - removed)
    end

    return removed >= wanted, removed
end

local function addInventoryItem(npcData, itemType, quantity)
    if not npcData then
        return false
    end
    npcData.inventory = npcData.inventory or { items = {}, currentWeight = 0, maxWeight = 14 }
    npcData.inventory.items = npcData.inventory.items or {}

    local qty = math.max(1, tonumber(quantity) or 1)
    for i = 1, #npcData.inventory.items do
        local it = npcData.inventory.items[i]
        if it and it.type == itemType then
            it.quantity = (tonumber(it.quantity) or 0) + qty
            npcData.inventory.currentWeight = (tonumber(npcData.inventory.currentWeight) or 0) + qty
            return true
        end
    end

    npcData.inventory.items[#npcData.inventory.items + 1] = {
        type = itemType,
        quantity = qty,
        condition = 100
    }
    npcData.inventory.currentWeight = (tonumber(npcData.inventory.currentWeight) or 0) + qty
    return true
end

function NPCMemory.ResolveProductionPlan(npcData, request)
    request = request or {}
    local serviceType = tostring(request.serviceType or request.orderType or "craft"):lower()
    local recipe = productionRecipes[serviceType] or productionRecipes.craft
    local marketCategory = normalizeRecipeCategory(request.marketCategory or request.category or request.itemCategory or request.itemType or "general_goods")
    local resultItemType, resultCategory = pickDefaultResultItem(marketCategory)

    if request.itemType and tostring(request.itemType) ~= "" then
        local requestedItem = tostring(request.itemType)
        if requestedItem:find("Base.", 1, true) then
            resultItemType = requestedItem
        end
    end

    local quantity = math.max(1, tonumber(request.quantity) or 1)
    local ingredients = {}
    for category, count in pairs(recipe.ingredients or {}) do
        ingredients[#ingredients + 1] = {
            category = category,
            quantity = math.max(1, math.floor((count or 1) * math.max(1, math.ceil(quantity / 2))))
        }
    end

    local baseWorkUnits = math.max(1, math.floor((recipe.workUnits or 4) * math.max(1, quantity)))
    local fabricationSpeed = math.max(0.2, tuningFactor("fabricationSpeedMult", 1))

    return {
        serviceType = serviceType,
        marketCategory = marketCategory,
        result = {
            itemType = resultItemType,
            category = resultCategory,
            quantity = quantity
        },
        ingredients = ingredients,
        workUnits = math.max(1, math.floor(baseWorkUnits / fabricationSpeed)),
        deliveryTarget = request.deliveryTarget or request.counterpartType or "player",
        deliveryToPlayerId = request.deliveryToPlayerId or request.counterpartId,
        notes = request.targetHint or request.baseId or ""
    }
end

function NPCMemory.ConsumeProductionIngredients(npcData, plan)
    if not npcData or not plan then
        return false, "invalid_plan"
    end

    local missing = {}
    for i = 1, #(plan.ingredients or {}) do
        local ingredient = plan.ingredients[i]
        local ok, removed = removeInventoryByCategory(npcData, ingredient.category, ingredient.quantity)
        if not ok then
            missing[#missing + 1] = {
                category = ingredient.category,
                quantity = ingredient.quantity,
                removed = removed or 0
            }
        end
    end

    if #missing > 0 then
        return false, missing
    end

    return true, nil
end

function NPCMemory.CompleteProductionPlan(npcData, plan)
    if not npcData or not plan or not plan.result then
        return false
    end

    addInventoryItem(npcData, plan.result.itemType or categoryDefaultItems.general_goods, plan.result.quantity or 1)
    NPCMemory.PushRecentEvent(npcData, "production_complete", {
        serviceType = plan.serviceType,
        resultItemType = plan.result.itemType,
        resultQuantity = plan.result.quantity,
        marketCategory = plan.marketCategory,
        tick = nowTick(npcData)
    })

    return true, plan.result
end

local function resolveProfession(npcData)
    local profession = npcData and npcData.profession or nil
    local role = "none"

    if type(profession) == "table" then
        role = tostring(profession.role or profession.type or role):lower()
    elseif type(profession) == "string" then
        role = tostring(profession):lower()
    end

    if not professionCatalog[role] then
        role = "none"
    end

    local catalog = professionCatalog[role]
    local level = 1
    local maxLevel = 10
    local source = "generated"

    if type(profession) == "table" then
        level = clamp(tonumber(profession.level) or 1, 1, 10)
        maxLevel = clamp(tonumber(profession.maxLevel) or 10, 1, 10)
        source = profession.source or source
    end

    local hasProfession = role ~= "none"
    local unlocked = hasProfession and level >= maxLevel

    return {
        role = role,
        label = (type(profession) == "table" and profession.label) or catalog.label,
        level = level,
        maxLevel = maxLevel,
        unlocked = unlocked,
        hasProfession = hasProfession,
        source = source,
        tradeMode = (type(profession) == "table" and profession.tradeMode) or catalog.tradeMode,
        buys = deepCopy((type(profession) == "table" and profession.buys) or catalog.buys),
        sells = deepCopy((type(profession) == "table" and profession.sells) or catalog.sells),
        produces = deepCopy((type(profession) == "table" and profession.produces) or catalog.produces),
        isMerchant = role == "merchant"
    }
end

function NPCMemory.GetProfessionProfile(npcData)
    return resolveProfession(npcData)
end

local function normalizeStrategyName(strategy)
    local value = tostring(strategy or "balanced"):lower()
    if value == "solo" or value == "self" then
        return "self"
    end
    if value == "clan" or value == "group" or value == "community" then
        return "clan"
    end
    if value == "both" or value == "hybrid" or value == "balanced" then
        return "both"
    end
    return "balanced"
end

local function replaceProfessionRole(npcData, newRole, reason)
    local profession = NPCMemory.GetProfessionProfile(npcData)
    local role = tostring(newRole or profession.role or "none"):lower()
    local catalog = professionCatalog[role] or professionCatalog.none

    npcData.profession = npcData.profession or {}
    npcData.profession.role = role
    npcData.profession.label = catalog.label
    npcData.profession.tradeMode = catalog.tradeMode
    npcData.profession.buys = deepCopy(catalog.buys)
    npcData.profession.sells = deepCopy(catalog.sells)
    npcData.profession.produces = deepCopy(catalog.produces)
    npcData.profession.requests = deepCopy(catalog.buys)
    npcData.profession.isMerchant = role == "merchant"
    npcData.profession.hasProfession = role ~= "none"
    npcData.profession.maxLevel = clamp(tonumber(npcData.profession.maxLevel) or 10, 1, 10)
    npcData.profession.unlocked = npcData.profession.hasProfession and (clamp(tonumber(npcData.profession.level) or 1, 1, 10) >= npcData.profession.maxLevel)
    npcData.profession.changedCount = clamp((tonumber(npcData.profession.changedCount) or 0) + 1, 0, 99)
    npcData.profession.lastChangeReason = reason or npcData.profession.lastChangeReason or "adaptation"
    return npcData.profession
end

local function buildBusinessEligibility(npcData, profession, serviceType, demandProfile)
    local st = tostring(serviceType or "trade"):lower()
    local role = tostring(profession and profession.role or "none")
    local hasProfession = profession and profession.hasProfession == true
    local unlocked = profession and profession.unlocked == true
    local allowedByRole = false
    local reason = nil

    if not hasProfession then
        reason = "sans_metier"
    elseif not unlocked then
        reason = "metier_non_debloque"
    end

    if not reason then
        if st == "buy" or st == "trade" then
            allowedByRole = role == "merchant"
        elseif st == "craft" then
            allowedByRole = (role == "artisan" or role == "cook" or role == "scavenger")
        elseif st == "build" then
            allowedByRole = (role == "artisan" or role == "guard")
        elseif st == "cook" then
            allowedByRole = role == "cook"
        elseif st == "guard" then
            allowedByRole = role == "guard"
        elseif st == "scavenge" then
            allowedByRole = role == "scavenger"
        elseif st == "study" then
            allowedByRole = (role == "artisan" or role == "medic" or role == "cook")
        else
            allowedByRole = false
        end

        if not allowedByRole then
            reason = "metier_non_compatible"
        end
    end

    local willingness = 0
    local accepts = false
    if not reason then
        local personality = npcData and npcData.traits and npcData.traits.personality or {}
        local socialDrive = tonumber(personality.socialDrive or 50) or 50
        local adaptability = tonumber(personality.adaptability or 50) or 50
        local brutality = tonumber(personality.brutality or 50) or 50
        local personalNeed = tonumber(demandProfile and demandProfile.personalNeed or 0) or 0
        local clanNeed = tonumber(demandProfile and demandProfile.clanNeed or 0) or 0
        local urgency = math.max(personalNeed, clanNeed)

        willingness = 32 + math.floor((profession.level or 1) * 3) + math.floor((socialDrive + adaptability) * 0.22) - math.floor(brutality * 0.08) + math.floor(urgency * 0.25)
        willingness = clamp(willingness, 20, 95)
        accepts = (randInt(1, 100) <= willingness)
        if not accepts then
            reason = "choix_autonome_refus"
        end
    end

    return {
        allowed = reason == nil,
        reason = reason,
        willingness = willingness,
        role = role,
        level = profession and profession.level or 0,
        maxLevel = profession and profession.maxLevel or 10,
        unlocked = profession and profession.unlocked == true,
        hasProfession = profession and profession.hasProfession == true,
        serviceType = st
    }
end

function NPCMemory.CheckBusinessEligibility(npcData, request)
    request = request or {}
    local profession = NPCMemory.GetProfessionProfile(npcData)
    local demandProfile = NPCMemory.BuildEconomicDemand(npcData, request)
    local serviceType = tostring(request.serviceType or request.orderType or "trade"):lower()
    return buildBusinessEligibility(npcData, profession, serviceType, demandProfile)
end

function NPCMemory.UpdateProfessionStrategy(npcData, context)
    if not npcData then
        return nil
    end

    npcData.profession = npcData.profession or {}
    local profession = NPCMemory.GetProfessionProfile(npcData)
    local economy = npcData.economy or {}
    local personalNeed = math.max(0, tonumber(context and context.personalNeed or 0) or 0)
    local clanNeed = math.max(0, tonumber(context and context.clanNeed or 0) or 0)
    local isInClan = context and context.isInClan == true
    local supportClanFirst = economy.supportClanFirst == true
    local soloPriority = economy.soloPriority == true

    local strategy = profession.strategy or economy.budgetMode or "balanced"
    if soloPriority or not isInClan then
        strategy = "self"
    elseif supportClanFirst and clanNeed > personalNeed then
        strategy = "clan"
    elseif personalNeed > 70 and clanNeed > 70 then
        strategy = "both"
    elseif clanNeed >= personalNeed then
        strategy = "clan"
    else
        strategy = "self"
    end

    profession.strategy = strategy
    npcData.profession.strategy = strategy

    local moodPressure = math.max(personalNeed, clanNeed)
    local mutable = profession.canChange ~= false
    local shouldShift = mutable and moodPressure >= 75 and context and context.allowRoleShift ~= false

    if shouldShift then
        local stats = npcData.stats or {}
        local personality = npcData.traits and npcData.traits.personality or {}
        local socialDrive = personality.socialDrive or 50
        local opportunism = personality.opportunism or 50
        local craftSkill = stats.craftSkill or 0
        local intelligence = stats.intelligence or 0
        local strength = stats.strength or 0
        local courage = stats.courage or 0
        local newRole = profession.role

        if strategy == "clan" and socialDrive >= 55 and opportunism >= 50 then
            newRole = "merchant"
        elseif craftSkill >= 70 and intelligence >= 60 then
            newRole = "artisan"
        elseif intelligence >= 68 and craftSkill >= 40 then
            newRole = "cook"
        elseif intelligence >= 60 and craftSkill >= 35 then
            newRole = "medic"
        elseif strength >= 65 and courage >= 55 then
            newRole = "guard"
        elseif opportunism >= 55 then
            newRole = "scavenger"
        else
            newRole = "survivor"
        end

        if newRole ~= profession.role then
            replaceProfessionRole(npcData, newRole, context and context.reason or "role_shift")
            profession = NPCMemory.GetProfessionProfile(npcData)
        end
    end

    return profession
end

function NPCMemory.BuildEconomicDemand(npcData, context)
    local profession = NPCMemory.GetProfessionProfile(npcData)
    local stats = npcData and npcData.stats or {}
    local health = npcData and npcData.health or {}
    local economy = npcData and npcData.economy or {}
    local demands = {}
    local wants = {}
    local requests = {}
    local personalNeed = 0
    local clanNeed = 0

    local function addDemand(category, priority, reason, source)
        if not category then
            return
        end
        demands[#demands + 1] = {
            category = category,
            priority = priority or 10,
            reason = reason or "general",
            source = source or profession.role
        }
        wants[#wants + 1] = category
    end

    local function addRequest(kind, category, detail, quantity, priority)
        requests[#requests + 1] = {
            kind = kind,
            category = category,
            detail = detail,
            quantity = quantity or 1,
            priority = priority or 10
        }
    end

    for i = 1, #(profession.buys or {}) do
        addDemand(profession.buys[i], 14, "profession_need", profession.role)
    end

    if (stats.hunger or 100) <= 40 then
        addDemand("food", 22, "personal_hunger", "self")
        personalNeed = personalNeed + 22
    end
    if (stats.thirst or 100) <= 40 then
        addDemand("water", 22, "personal_thirst", "self")
        personalNeed = personalNeed + 22
    end
    if (health.pain or 0) >= 35 then
        addDemand("medicine", 18, "wound_care", "self")
        personalNeed = personalNeed + 12
    end

    local clanPressure = tonumber(context and context.clanNeed or 0) or 0
    if context and context.groupNeeds and type(context.groupNeeds) == "table" then
        for key, need in pairs(context.groupNeeds) do
            if need and (need > 0) then
                local category = tostring(key)
                addDemand(category, 10 + math.min(20, math.floor(need)), "clan_need", "clan")
                clanNeed = clanNeed + math.min(30, math.floor(need))
            end
        end
    end

    if profession.role == "merchant" then
        addRequest("stock", "general_goods", "refill_goods", 1, 20)
        addRequest("stock", "materials", "refill_supply", 1, 16)
    elseif profession.role == "artisan" then
        addRequest("produce", "materials", "craft_materials", 1, 18)
        addRequest("produce", "tools", "craft_tools", 1, 18)
    elseif profession.role == "cook" then
        addRequest("produce", "food", "cook_rations", 1, 18)
        addRequest("stock", "water", "get_water", 1, 16)
    elseif profession.role == "medic" then
        addRequest("produce", "medicine", "make_medical_supplies", 1, 18)
    elseif profession.role == "guard" then
        addRequest("service", "weapons", "maintain_defense", 1, 18)
    else
        addRequest("needs", "food", "survival_needs", 1, 12)
    end

    local inventory = npcData and npcData.inventory or nil
    local currentWeight = inventory and tonumber(inventory.currentWeight) or 0
    local maxWeight = inventory and tonumber(inventory.maxWeight) or 1
    if currentWeight >= maxWeight * 0.85 then
        personalNeed = personalNeed + 10
        addRequest("sell", "general_goods", "clear_stock", 1, 15)
    end

    local mode = "self"
    if economy.supportClanFirst == true and clanNeed > personalNeed then
        mode = "clan"
    elseif economy.soloPriority == true and personalNeed >= clanNeed then
        mode = "self"
    elseif personalNeed > 55 and clanNeed > 55 then
        mode = "both"
    elseif clanNeed >= personalNeed and clanNeed > 0 then
        mode = "clan"
    elseif personalNeed > 0 then
        mode = "self"
    end

    return {
        profession = profession,
        demands = demands,
        wants = wants,
        requests = requests,
        personalNeed = personalNeed,
        clanNeed = clanNeed + clanPressure,
        mode = mode,
        strategy = profession.strategy or mode
    }
end

function NPCMemory.CalculatePriceProfile(npcData, counterpartType, counterpartId, context)
    local profession = NPCMemory.GetProfessionProfile(npcData)
    local demandProfile = NPCMemory.BuildEconomicDemand(npcData, context)
    local disposition = nil
    local marketState = context and context.marketState or nil
    local marketCategory = resolveMarketCategory(context, profession)

    if counterpartType and counterpartId then
        disposition = NPCMemory.GetDispositionTowardActor(npcData, counterpartType, counterpartId)
    end

    local demandScore = 0
    local supplyScore = 0
    for i = 1, #demandProfile.demands do
        demandScore = demandScore + (demandProfile.demands[i].priority or 10)
    end
    for i = 1, #profession.sells do
        supplyScore = supplyScore + 10
    end
    supplyScore = supplyScore + math.max(0, (npcData.inventory and #npcData.inventory.items or 0) * 4)

    local delta = demandScore - supplyScore
    local configuredVolatility = math.max(0.25, tonumber(NPCMemory.globalMarketVolatilityMultiplier) or 1.0)
    local marketVolatility = math.max(0.25, tuningFactor("economyVolatilityMult", 1) * configuredVolatility)
    local aggressiveness = math.max(0.5, tonumber(NPCMemory.globalMarketAggressivenessMultiplier) or 1.0)
    local multiplier = 1 + (delta * 0.03 * marketVolatility)

    if marketState then
        local localSupply = tonumber(marketState.localSupply and marketState.localSupply[marketCategory] or 0) or 0
        local localDemand = tonumber(marketState.localDemand and marketState.localDemand[marketCategory] or 0) or 0
        local merchantCount = tonumber(marketState.merchantCount or 0) or 0
        local stockPressure = localDemand - localSupply
        multiplier = multiplier + clamp(stockPressure * 0.025 * marketVolatility, -0.28, 0.42)

        if merchantCount <= 0 then
            multiplier = multiplier + 0.18
        elseif merchantCount >= 3 then
            multiplier = multiplier - 0.08
        end

        local localStockBias = tonumber(marketState.stockBias or 0) or 0
        multiplier = multiplier + clamp(localStockBias * 0.01, -0.16, 0.16)
    end

    if profession.isMerchant then
        multiplier = multiplier + (0.08 * aggressiveness)
    end
    if disposition and disposition.isTrusted then
        multiplier = multiplier - (0.08 / aggressiveness)
    elseif disposition and (disposition.isHostile or disposition.isDangerous) then
        multiplier = multiplier + (0.22 * aggressiveness)
    end
    if context and context.clanNeed then
        multiplier = multiplier + math.min(0.18, math.max(0, tonumber(context.clanNeed) or 0) / 1000)
    end

    multiplier = clamp(multiplier, 0.5, 2.8)

    local state = "neutre"
    if multiplier > 1.08 then
        state = "augmentation"
    elseif multiplier < 0.93 then
        state = "baisse"
    end

    local basePrice = math.max(1, tonumber(context and context.basePrice or 10) or 10)
    local finalPrice = math.max(1, math.floor(basePrice * multiplier))

    return {
        state = state,
        multiplier = multiplier,
        basePrice = basePrice,
        finalPrice = finalPrice,
        marketCategory = marketCategory,
        demandScore = demandScore,
        supplyScore = supplyScore,
        demandProfile = demandProfile,
        disposition = disposition,
        profession = profession
    }
end

function NPCMemory.BuildServiceQuote(npcData, request)
    request = request or {}
    local profession = NPCMemory.GetProfessionProfile(npcData)
    local demandProfile = NPCMemory.BuildEconomicDemand(npcData, request)
    local serviceType = tostring(request.serviceType or request.orderType or "trade"):lower()

    local eligibility = buildBusinessEligibility(npcData, profession, serviceType, demandProfile)
    if not eligibility.allowed then
        return nil
    end

    local catalog = serviceCatalog[serviceType] or serviceCatalog.trade
    local productionPlan = nil
    if serviceType == "craft" or serviceType == "build" then
        productionPlan = NPCMemory.ResolveProductionPlan(npcData, request)
    end
    local priceProfile = NPCMemory.CalculatePriceProfile(npcData, request.counterpartType, request.counterpartId, {
        basePrice = catalog.baseCost,
        clanNeed = demandProfile.clanNeed,
        personalNeed = demandProfile.personalNeed,
        marketState = request.marketState,
        marketCategory = request.marketCategory or catalog.category,
        itemType = request.itemType,
        category = request.marketCategory or catalog.category,
        serviceType = serviceType
    })

    local finalCost = math.max(1, priceProfile.finalPrice)
    if profession.role == serviceType then
        finalCost = math.max(1, math.floor(finalCost * 0.8))
    elseif profession.isMerchant and serviceType == "trade" then
        finalCost = math.max(1, math.floor(finalCost * 1.15))
    end

    finalCost = math.max(1, math.floor(finalCost * math.max(0.25, tuningFactor("economyPriceMult", 1))))
    finalCost = math.max(1, math.floor(finalCost * math.max(0.1, tonumber(NPCMemory.globalServicePriceMultiplier) or 1.0)))
    finalCost = math.max(1, math.floor(finalCost * math.max(0.25, tonumber(NPCMemory.globalServiceMarginMultiplier) or 1.0)))

    return {
        serviceType = serviceType,
        label = catalog.label,
        category = catalog.category,
        baseCost = catalog.baseCost,
        priceState = priceProfile.state,
        priceMultiplier = priceProfile.multiplier,
        marketCategory = priceProfile.marketCategory,
        cost = finalCost,
        demands = demandProfile.demands,
        requests = demandProfile.requests,
        mode = demandProfile.mode,
        strategy = demandProfile.strategy,
        acceptedPaymentTypes = currencyItemTypes,
        requiresPayment = true,
        profession = profession,
        eligibility = eligibility,
        productionPlan = productionPlan
    }
end

function NPCMemory.SelectTradeItems(npcData, categories, limit)
    local inventory = npcData and npcData.inventory
    local items = inventory and inventory.items
    if type(items) ~= "table" then
        return {}
    end

    local wantedCategories = {}
    if type(categories) == "table" then
        wantedCategories = categories
    elseif categories then
        wantedCategories = { categories }
    end

    local maxItems = math.max(1, tonumber(limit) or 3)
    local result = {}
    for index = 1, #items do
        local item = items[index]
        if item and item.type and (item.quantity or 0) > 0 then
            local itemType = tostring(item.type)
            for i = 1, #wantedCategories do
                local category = wantedCategories[i]
                if categoryMatchesItem(itemType, category) then
                    result[#result + 1] = itemType
                    break
                end
            end
            if #result >= maxItems then
                break
            end
        end
    end

    if #result == 0 then
        local fallback, _ = NPCMemory.FindInventoryItem(npcData, function(candidate)
            return candidate and candidate.type and candidate.quantity and candidate.quantity > 0
        end)
        if fallback then
            result[#result + 1] = fallback.type
        end
    end

    return result
end

local function ensureActorProfile(memory, actorType, actorId)
    local key = normalizeActorKey(actorType, actorId)

    if not memory.actorProfiles[key] then
        memory.actorProfiles[key] = {
            actorType = actorType or "unknown",
            actorId = normalizeId(actorId),
            trust = 0,
            fear = 0,
            respect = 0,
            gratitude = 0,
            resentment = 0,
            aggression = 0,
            helpedCount = 0,
            theftCount = 0,
            hostileCount = 0,
            dangerScore = 0,
            strengthScore = 0,
            lastInteractionTick = 0
        }
    end

    return memory.actorProfiles[key], key
end

function NPCMemory.EnsureMemory(npcData)
    npcData.stats = npcData.stats or {}
    if npcData.stats.sociability == nil then
        npcData.stats.sociability = 50
    else
        npcData.stats.sociability = clamp(tonumber(npcData.stats.sociability) or 50, 0, 100)
    end

    npcData.memory = npcData.memory or {}
    local memory = npcData.memory

    memory.reputationByActor = memory.reputationByActor or memory.reputationByPlayer or {}
    memory.reputationByPlayer = memory.reputationByActor
    memory.dangerousZones = memory.dangerousZones or {}
    memory.trustedNPCs = memory.trustedNPCs or {}
    memory.knownLootSpots = memory.knownLootSpots or {}
    memory.recentEvents = memory.recentEvents or {}

    memory.actorProfiles = memory.actorProfiles or memory.playerProfiles or {}
    memory.playerProfiles = memory.actorProfiles
    memory.actorRumors = memory.actorRumors or memory.playerRumors or {}
    memory.playerRumors = memory.actorRumors
    memory.sharedIntelToPlayers = memory.sharedIntelToPlayers or {}
    memory.tradeLedger = memory.tradeLedger or {}
    memory.requestLedger = memory.requestLedger or {}
    memory.outgoingByActor = memory.outgoingByActor or {}
    memory.outgoingRecent = memory.outgoingRecent or {}
    memory.infection = memory.infection or {
        progress = 0,
        intendsToLeave = false,
        berserkTriggered = false,
        lastUpdateTick = 0,
        knownByGroup = false
    }
    memory.social = memory.social or {
        sociability = clamp(tonumber(npcData.stats.sociability) or 50, 0, 100),
        loneliness = 35,
        lastInteractionTick = 0,
        lastDecayTick = 0,
        storiesShared = 0
    }
    memory.psychology = memory.psychology or {
        trauma = 0,
        rage = 0,
        freezeUntilTick = 0,
        lastStressTick = 0,
        lastTraumaTick = 0,
        allyLossCount = 0
    }
    memory.environment = memory.environment or {
        wetness = 0,
        coldStress = 0,
        sickness = 0,
        needsShelter = false,
        needsWarmth = false,
        lastWeatherTick = 0
    }
    memory.expedition = memory.expedition or {
        active = false,
        returnTick = 0,
        startedTick = 0,
        distance = 0,
        willReturn = true,
        lootTier = "none"
    }

    ensureLocalizedInjuries(npcData)

    pruneTableHead(memory.recentEvents, NPCMemory.maxRecentEvents)
    pruneTableHead(memory.outgoingRecent, NPCMemory.maxRecentEvents)
    pruneTableHead(memory.tradeLedger, NPCMemory.maxTradeLedger)
    pruneTableHead(memory.requestLedger, NPCMemory.maxRequestLedger)
    pruneMapByLastTick(memory.actorProfiles, NPCMemory.maxActorProfiles)
    pruneMapByLastTick(memory.outgoingByActor, NPCMemory.maxActorProfiles)
    pruneMapByLastTick(memory.actorRumors, NPCMemory.maxActorRumors)
    pruneMapByLastTick(memory.dangerousZones, NPCMemory.maxDangerousZones)
    pruneMapByLastTick(memory.knownLootSpots, NPCMemory.maxKnownLootSpots)
    pruneMapByLastTick(memory.reputationByActor, NPCMemory.maxReputationByActor)
    pruneBooleanMapByKey(memory.trustedNPCs, NPCMemory.maxTrustedNPCs)

    if type(memory.sharedIntelToPlayers) == "table" then
        for actorId, intelList in pairs(memory.sharedIntelToPlayers) do
            pruneTableHead(intelList, NPCMemory.maxSharedIntelPerActor)
            if type(intelList) == "table" and #intelList == 0 then
                memory.sharedIntelToPlayers[actorId] = nil
            end
        end
    end

    return memory
end

function NPCMemory.RegisterDialogueContact(npcData, actorType, actorId, context)
    local memory = NPCMemory.EnsureMemory(npcData)
    local social = memory.social
    local tick = nowTick(context)
    local mode = tostring(context and context.mode or "dialogue")
    local gain = mode == "trade" and NPCMemory.socialGainTrade or NPCMemory.socialGainDialogue
    gain = gain * math.max(0.25, tuningFactor("socialGainMult", 1))
    if context and context.intensity then
        gain = gain * math.max(0.2, tonumber(context.intensity) or 1)
    end

    social.sociability = clamp((social.sociability or 40) + gain, 0, 100)
    social.loneliness = clamp((social.loneliness or 35) - (gain * 0.85), 0, 100)
    social.lastInteractionTick = tick

    npcData.stats = npcData.stats or {}
    npcData.stats.sociability = clamp(tonumber(npcData.stats.sociability or social.sociability) + (gain * 0.35), 0, 100)

    local profile = NPCMemory.GetActorProfile(npcData, actorType or "player", actorId or "unknown")
    profile.trust = clamp((profile.trust or 0) + math.floor(gain * 0.45), -100, 100)
    profile.respect = clamp((profile.respect or 0) + math.floor(gain * 0.2), -100, 100)
    profile.lastInteractionTick = tick

    local eventType = mode == "trade" and "social_trade_contact" or "social_dialogue_contact"
    NPCMemory.PushRecentEvent(npcData, eventType, {
        tick = tick,
        actorType = actorType,
        actorId = normalizeId(actorId),
        gain = gain,
        sociability = social.sociability,
        loneliness = social.loneliness
    })

    return {
        sociability = social.sociability,
        loneliness = social.loneliness
    }
end

function NPCMemory.UpdateSocialState(npcData, context)
    local memory = NPCMemory.EnsureMemory(npcData)
    local social = memory.social
    local tick = nowTick(context)
    local previousTick = social.lastDecayTick or tick
    local delta = math.max(1, tick - previousTick)
    social.lastDecayTick = tick

    local decay = delta * NPCMemory.socialDecayPerTick * math.max(0.2, tuningFactor("socialDecayMult", 1))
    if (tick - (social.lastInteractionTick or 0)) > 180 then
        social.sociability = clamp((social.sociability or 40) - decay, 0, 100)
        social.loneliness = clamp((social.loneliness or 35) + (decay * 1.4), 0, 100)
    else
        social.loneliness = clamp((social.loneliness or 35) - (decay * 0.35), 0, 100)
    end

    npcData.stats = npcData.stats or {}
    npcData.stats.sociability = clamp(tonumber(npcData.stats.sociability or social.sociability), 0, 100)

    return {
        sociability = social.sociability,
        loneliness = social.loneliness,
        wantsTalk = social.loneliness >= 55
    }
end

function NPCMemory.RecordAllyDevoured(npcData, allyId, context)
    local memory = NPCMemory.EnsureMemory(npcData)
    local psych = memory.psychology
    local tick = nowTick(context)

    psych.allyLossCount = (psych.allyLossCount or 0) + 1
    psych.trauma = clamp((psych.trauma or 0) + 28, 0, 100)
    psych.rage = clamp((psych.rage or 0) + 16, 0, 100)
    psych.lastTraumaTick = tick

    NPCMemory.PushRecentEvent(npcData, "ally_devoured", {
        tick = tick,
        allyId = normalizeId(allyId),
        trauma = psych.trauma,
        rage = psych.rage,
        allyLossCount = psych.allyLossCount
    })

    return {
        trauma = psych.trauma,
        rage = psych.rage,
        allyLossCount = psych.allyLossCount
    }
end

function NPCMemory.UpdatePsychologicalStress(npcData, context)
    local memory = NPCMemory.EnsureMemory(npcData)
    local psych = memory.psychology
    local tick = nowTick(context)
    local previousTick = psych.lastStressTick or tick
    local delta = math.max(1, tick - previousTick)
    psych.lastStressTick = tick

    local threatSensitivity = math.max(0.3, tuningFactor("traumaThreatSensitivityMult", 1))
    local traumaGainMult = math.max(0.2, tuningFactor("traumaGainMult", 1))
    local traumaDecayMult = math.max(0.2, tuningFactor("traumaDecayMult", 1))
    local rageDecayMult = math.max(0.2, tuningFactor("rageDecayMult", 1))
    local threatLevel = clamp((tonumber(context and context.threatLevel) or 0) * threatSensitivity, 0, 100)
    local witnessedLoss = context and context.witnessedLoss == true

    if witnessedLoss then
        psych.trauma = clamp((psych.trauma or 0) + (18 * traumaGainMult), 0, 100)
        psych.rage = clamp((psych.rage or 0) + (10 * traumaGainMult), 0, 100)
    end

    if threatLevel >= (NPCMemory.traumaThreatTrigger or 62) then
        psych.trauma = clamp((psych.trauma or 0) + (0.03 * threatLevel * traumaGainMult), 0, 100)
        psych.rage = clamp((psych.rage or 0) + (0.02 * threatLevel * traumaGainMult), 0, 100)
    else
        psych.trauma = clamp((psych.trauma or 0) - (delta * NPCMemory.traumaDecayPerTick * traumaDecayMult), 0, 100)
        psych.rage = clamp((psych.rage or 0) - (delta * NPCMemory.rageDecayPerTick * rageDecayMult), 0, 100)
    end

    local freezeTriggered = false
    if threatLevel >= (NPCMemory.traumaThreatTrigger or 62) and (psych.trauma or 0) >= (NPCMemory.traumaFreezeThreshold or 52) and (psych.freezeUntilTick or 0) < tick then
        local freezeChance = clamp((((psych.trauma or 0) - 35) + math.floor(threatLevel * 0.35)) * math.max(0.2, tuningFactor("freezeChanceMult", 1)), 0, 95)
        if randInt(1, 100) <= freezeChance then
            local freezeDuration = math.max(8, math.floor(randInt(30, 78) * math.max(0.25, tuningFactor("freezeDurationMult", 1))))
            psych.freezeUntilTick = tick + freezeDuration
            freezeTriggered = true
            NPCMemory.PushRecentEvent(npcData, "trauma_freeze", {
                tick = tick,
                trauma = psych.trauma,
                threatLevel = threatLevel,
                freezeUntilTick = psych.freezeUntilTick
            })
        end
    end

    local rageActive = threatLevel >= (NPCMemory.rageThreatTrigger or 48) and (psych.rage or 0) >= (NPCMemory.rageActivationThreshold or 38)
    if rageActive and randInt(1, 100) <= 18 then
        NPCMemory.PushRecentEvent(npcData, "trauma_rage", {
            tick = tick,
            rage = psych.rage,
            trauma = psych.trauma,
            threatLevel = threatLevel
        })
    end

    return {
        trauma = psych.trauma,
        rage = psych.rage,
        freezeUntilTick = psych.freezeUntilTick or 0,
        freezeTriggered = freezeTriggered,
        isFrozen = (psych.freezeUntilTick or 0) > tick,
        rageActive = rageActive,
        rageBoost = rageActive and math.floor((psych.rage or 0) / 12) or 0
    }
end

function NPCMemory.UpdateWeatherSurvival(npcData, context)
    local memory = NPCMemory.EnsureMemory(npcData)
    local env = memory.environment
    local tick = nowTick(context)
    local weather = context and context.weather or {}
    local temperature = tonumber(weather.temperatureC) or 14
    local isRaining = weather.isRaining == true
    local isSnowing = weather.isSnowing == true
    local hasShelter = weather.hasShelter == true
    local hasWarmClothes = weather.hasWarmClothes == true
    local canLightFire = weather.canLightFire == true
    local delta = math.max(1, tick - (env.lastWeatherTick or tick))
    local exposureMult = math.max(0.2, tuningFactor("weatherExposureMult", 1))
    local recoveryMult = math.max(0.2, tuningFactor("weatherRecoveryMult", 1))
    local diseaseImpactMult = math.max(0.2, tuningFactor("weatherDiseaseImpactMult", 1))
    local resistanceMult = math.max(0.4, tuningFactor("npcResistanceMult", 1))
    env.lastWeatherTick = tick

    if isRaining and not hasShelter then
        env.wetness = clamp((env.wetness or 0) + (NPCMemory.weatherWetGain * delta * exposureMult), 0, 100)
    else
        env.wetness = clamp((env.wetness or 0) - (NPCMemory.weatherWetDry * delta * recoveryMult), 0, 100)
    end

    local severeCold = isSnowing or temperature <= 0
    local underProtected = severeCold and (not hasWarmClothes and not canLightFire)
    if underProtected then
        env.coldStress = clamp((env.coldStress or 0) + (NPCMemory.weatherColdGain * delta * exposureMult), 0, 100)
    else
        env.coldStress = clamp((env.coldStress or 0) - (NPCMemory.weatherColdRecover * delta * recoveryMult), 0, 100)
    end

    if (env.wetness or 0) >= 60 and severeCold then
        env.sickness = clamp((env.sickness or 0) + (0.5 * delta * diseaseImpactMult), 0, 100)
    else
        env.sickness = clamp((env.sickness or 0) - (0.18 * delta * recoveryMult), 0, 100)
    end

    env.needsShelter = (env.wetness or 0) >= 45 and not hasShelter
    env.needsWarmth = (env.coldStress or 0) >= 40 and underProtected

    if (env.sickness or 0) >= 55 then
        npcData.health = npcData.health or {}
        npcData.health.current = clamp((tonumber(npcData.health.current) or 100) - ((0.3 * diseaseImpactMult) / resistanceMult), 0, 100)
        NPCMemory.PushRecentEvent(npcData, "weather_sick", {
            tick = tick,
            wetness = env.wetness,
            coldStress = env.coldStress,
            sickness = env.sickness
        })
    elseif env.needsShelter then
        NPCMemory.PushRecentEvent(npcData, "weather_seek_shelter", {
            tick = tick,
            wetness = env.wetness,
            coldStress = env.coldStress
        })
    elseif env.needsWarmth then
        NPCMemory.PushRecentEvent(npcData, "weather_seek_warmth", {
            tick = tick,
            coldStress = env.coldStress,
            temperatureC = temperature
        })
    end

    return {
        wetness = env.wetness,
        coldStress = env.coldStress,
        sickness = env.sickness,
        needsShelter = env.needsShelter,
        needsWarmth = env.needsWarmth,
        severeCold = severeCold
    }
end

function NPCMemory.ApplyLocalizedInjuryEffects(npcData, context)
    local injuries = ensureLocalizedInjuries(npcData)
    local tick = nowTick(context)

    local legAvg = math.floor(((injuries.leg_l or 0) + (injuries.leg_r or 0) + (injuries.foot_l or 0) + (injuries.foot_r or 0)) / 4)
    local armAvg = math.floor(((injuries.arm_l or 0) + (injuries.arm_r or 0) + (injuries.hand_l or 0) + (injuries.hand_r or 0)) / 4)
    local torso = tonumber(injuries.torso) or 0
    local head = tonumber(injuries.head) or 0
    local injuryPenaltyMult = math.max(0.2, tuningFactor("injuryPenaltyMult", 1))
    local resistanceMult = math.max(0.4, tuningFactor("npcResistanceMult", 1))

    local mobilityPenalty = clamp(math.floor((legAvg * 0.9 + torso * 0.2) * injuryPenaltyMult), 0, 90)
    local aimPenalty = clamp(math.floor((armAvg * 0.7 + head * 0.4) * injuryPenaltyMult), 0, 90)
    local strengthPenalty = clamp(math.floor((torso * 0.4 + armAvg * 0.35) * injuryPenaltyMult), 0, 80)
    local carryPenalty = clamp(math.floor((legAvg * 0.35 + armAvg * 0.25 + torso * 0.45) * injuryPenaltyMult), 0, 75)

    npcData.runtimePenalties = {
        mobility = mobilityPenalty,
        aim = aimPenalty,
        strength = strengthPenalty,
        carry = carryPenalty,
        computedAtTick = tick,
        legCritical = legAvg >= 55,
        armCritical = armAvg >= 55,
        headCritical = head >= 60
    }

    npcData.health = npcData.health or {}
    npcData.health.pain = clamp((tonumber(npcData.health.pain) or 0) + math.floor(((legAvg + armAvg + torso + head) * 0.003 * injuryPenaltyMult) / resistanceMult), 0, 100)

    if npcData.runtimePenalties.legCritical then
        NPCMemory.PushRecentEvent(npcData, "injury_leg_critical", {
            tick = tick,
            severity = legAvg,
            mobilityPenalty = mobilityPenalty
        })
    end

    return npcData.runtimePenalties
end

function NPCMemory.ScheduleExpedition(npcData, context)
    local memory = NPCMemory.EnsureMemory(npcData)
    local expedition = memory.expedition
    local tick = nowTick(context)
    local distance = math.max(1, math.floor(tonumber(context and context.distance) or 10))
    local returnChanceMult = math.max(0.2, tuningFactor("expeditionReturnChanceMult", 1))
    local durationMult = math.max(0.25, tuningFactor("expeditionDurationMult", 1))

    local stats = npcData.stats or {}
    local health = npcData.health or {}
    local injuries = ensureLocalizedInjuries(npcData)
    local injuryBurden = math.floor(((injuries.leg_l or 0) + (injuries.leg_r or 0) + (injuries.torso or 0)) / 3)
    local survivalScore = (tonumber(stats.courage) or 50) + (tonumber(stats.intelligence) or 50) + (tonumber(stats.strength) or 50) + (tonumber(health.current) or 70) - injuryBurden
    local distancePenalty = math.floor(distance * (NPCMemory.expeditionDistancePenalty or 1.65))
    local returnChance = clamp(
        (NPCMemory.expeditionReturnBaseChance or 28) + math.floor(survivalScore * (NPCMemory.expeditionSurvivalFactor or 0.38)) - distancePenalty,
        NPCMemory.expeditionMinReturnChance or 8,
        NPCMemory.expeditionMaxReturnChance or 92
    )
    returnChance = clamp(
        math.floor(returnChance * returnChanceMult),
        NPCMemory.expeditionMinReturnChance or 8,
        NPCMemory.expeditionMaxReturnChance or 92
    )

    local durationFactor = math.max(10, tonumber(context and context.durationFactor) or 18)
    local baseDuration = math.max(60, tonumber(context and context.baseDuration) or 180)
    local jitterMin = NPCMemory.expeditionDurationJitterMin or 120
    local jitterMax = NPCMemory.expeditionDurationJitterMax or 320
    local duration = math.max(10, math.floor((baseDuration + (distance * durationFactor) + randInt(jitterMin, jitterMax)) * durationMult))
    local willReturn = randInt(1, 100) <= returnChance
    local lootTier = "low"
    if distance >= 34 and returnChance >= 52 then
        lootTier = "high"
    elseif distance >= 20 then
        lootTier = "mid"
    end

    expedition.active = true
    expedition.startedTick = tick
    expedition.returnTick = tick + duration
    expedition.distance = distance
    expedition.willReturn = willReturn
    expedition.lootTier = lootTier
    expedition.source = deepCopy(context or {})

    NPCMemory.PushRecentEvent(npcData, "expedition_started", {
        tick = tick,
        distance = distance,
        returnTick = expedition.returnTick,
        returnChance = returnChance,
        willReturn = willReturn,
        lootTier = lootTier
    })

    return deepCopy(expedition)
end

function NPCMemory.ResolveExpedition(snapshot, tick)
    if type(snapshot) ~= "table" then
        return nil
    end

    local memory = snapshot.memory
    local expedition = memory and memory.expedition or nil
    if type(expedition) ~= "table" or expedition.active ~= true then
        return nil
    end

    local now = math.floor(tonumber(tick) or 0)
    if now < (tonumber(expedition.returnTick) or 0) then
        return {
            ready = false,
            active = true
        }
    end

    expedition.active = false
    snapshot.memory = snapshot.memory or {}
    snapshot.memory.expedition = expedition

    local result = {
        ready = true,
        willReturn = expedition.willReturn == true,
        lootTier = tostring(expedition.lootTier or "low"),
        distance = tonumber(expedition.distance) or 0
    }

    if not result.willReturn then
        if snapshot.health then
            snapshot.health.current = clamp((tonumber(snapshot.health.current) or 70) - 100, 0, 100)
        end
        return result
    end

    snapshot.inventory = snapshot.inventory or { items = {}, currentWeight = 0, maxWeight = 14 }
    snapshot.inventory.items = snapshot.inventory.items or {}

    local lootMult = math.max(0.2, tuningFactor("expeditionLootMult", 1))
    local lootCount = result.lootTier == "high" and randInt(3, 6) or (result.lootTier == "mid" and randInt(2, 4) or randInt(1, 3))
    lootCount = math.max(1, math.floor(lootCount * lootMult))
    local lootPool = {
        "Base.CannedSardines",
        "Base.WaterBottleFull",
        "Base.Bandage",
        "Base.Hammer",
        "Base.Sheet",
        "Base.NailsBox",
        "Base.Pills",
        "Base.Battery"
    }

    for i = 1, lootCount do
        snapshot.inventory.items[#snapshot.inventory.items + 1] = {
            type = lootPool[randInt(1, #lootPool)],
            quantity = 1,
            condition = randInt(45, 100)
        }
    end
    snapshot.inventory.currentWeight = (tonumber(snapshot.inventory.currentWeight) or 0) + lootCount

    snapshot.memory.recentEvents = snapshot.memory.recentEvents or {}
    snapshot.memory.recentEvents[#snapshot.memory.recentEvents + 1] = {
        eventType = "expedition_returned",
        tick = now,
        payload = {
            distance = result.distance,
            lootTier = result.lootTier,
            lootCount = lootCount
        }
    }

    return result
end

function NPCMemory.GetOutgoingProfile(npcData, actorType, actorId)
    local memory = NPCMemory.EnsureMemory(npcData)
    local key = normalizeActorKey(actorType, actorId)
    if not memory.outgoingByActor[key] then
        memory.outgoingByActor[key] = {
            actorType = actorType,
            actorId = normalizeId(actorId),
            helped = 0,
            traded = 0,
            threatened = 0,
            assaulted = 0,
            stolen = 0,
            guilt = 0,
            brutality = 0,
            opportunism = 0,
            lastActionTick = 0
        }
    end
    return memory.outgoingByActor[key], key
end

function NPCMemory.RegisterOutgoingActorAction(npcData, actorType, actorId, actionType, context)
    local memory = NPCMemory.EnsureMemory(npcData)
    local profile, actorKey = NPCMemory.GetOutgoingProfile(npcData, actorType, actorId)
    local amount = (context and context.value) or randInt(8, 18)
    local tick = nowTick(context)

    if actionType == "gift" or actionType == "help" or actionType == "trade" then
        profile.helped = profile.helped + (actionType == "trade" and 0 or 1)
        profile.traded = profile.traded + (actionType == "trade" and 1 or 0)
        profile.guilt = clamp(profile.guilt - 2, 0, 100)
    elseif actionType == "theft" or actionType == "stole" then
        profile.stolen = profile.stolen + 1
        profile.brutality = clamp(profile.brutality + math.floor(amount * 0.4), 0, 100)
        profile.opportunism = clamp(profile.opportunism + math.floor(amount * 0.5), 0, 100)
        profile.guilt = clamp(profile.guilt + math.floor(amount * 0.25), 0, 100)
    elseif actionType == "hostile" or actionType == "threat" or actionType == "insult" then
        profile.threatened = profile.threatened + 1
        profile.brutality = clamp(profile.brutality + math.floor(amount * 0.45), 0, 100)
        profile.opportunism = clamp(profile.opportunism + math.floor(amount * 0.25), 0, 100)
        profile.guilt = clamp(profile.guilt + math.floor(amount * 0.18), 0, 100)
    elseif actionType == "assault" then
        profile.assaulted = profile.assaulted + 1
        profile.brutality = clamp(profile.brutality + math.floor(amount * 0.65), 0, 100)
        profile.opportunism = clamp(profile.opportunism + math.floor(amount * 0.25), 0, 100)
        profile.guilt = clamp(profile.guilt + math.floor(amount * 0.35), 0, 100)
    end

    profile.lastActionTick = tick

    memory.outgoingRecent[#memory.outgoingRecent + 1] = {
        actorType = actorType,
        actorId = normalizeId(actorId),
        actorKey = actorKey,
        actionType = actionType,
        value = amount,
        tick = tick,
        payload = deepCopy(context or {})
    }

    while #memory.outgoingRecent > NPCMemory.maxRecentEvents do
        table.remove(memory.outgoingRecent, 1)
    end

    NPCMemory.PushRecentEvent(npcData, "outgoing_action", {
        actorType = actorType,
        actorId = normalizeId(actorId),
        actionType = actionType,
        value = amount,
        tick = tick
    })

    return profile
end

function NPCMemory.PushRecentEvent(npcData, eventType, payload)
    local memory = NPCMemory.EnsureMemory(npcData)
    local recent = memory.recentEvents

    recent[#recent + 1] = {
        eventType = eventType,
        tick = nowTick(payload),
        payload = deepCopy(payload or {})
    }

    while #recent > NPCMemory.maxRecentEvents do
        table.remove(recent, 1)
    end

    pruneTableHead(memory.tradeLedger, NPCMemory.maxTradeLedger)
    pruneTableHead(memory.requestLedger, NPCMemory.maxRequestLedger)
    pruneMapByLastTick(memory.actorProfiles, NPCMemory.maxActorProfiles)
    pruneMapByLastTick(memory.outgoingByActor, NPCMemory.maxActorProfiles)
end

function NPCMemory.GetActorProfile(npcData, actorType, actorId)
    local memory = NPCMemory.EnsureMemory(npcData)
    return ensureActorProfile(memory, actorType, actorId)
end

function NPCMemory.GetPlayerProfile(npcData, playerId)
    return NPCMemory.GetActorProfile(npcData, "player", playerId)
end

function NPCMemory.UpdateActorReputation(npcData, actorType, actorId, delta)
    local memory = NPCMemory.EnsureMemory(npcData)
    local actorKey = normalizeActorKey(actorType, actorId)
    memory.reputationByActor[actorKey] = clamp((memory.reputationByActor[actorKey] or 0) + delta, -100, 100)
    return memory.reputationByActor[actorKey]
end

function NPCMemory.UpdateReputation(npcData, playerId, delta)
    return NPCMemory.UpdateActorReputation(npcData, "player", playerId, delta)
end

function NPCMemory.RecordActorHelp(npcData, actorType, actorId, context)
    local profile, actorKey = NPCMemory.GetActorProfile(npcData, actorType, actorId)
    local amount = (context and context.value) or randInt(8, 18)

    profile.helpedCount = profile.helpedCount + 1
    profile.gratitude = clamp(profile.gratitude + amount, 0, 100)
    profile.trust = clamp(profile.trust + math.floor(amount * 0.7), -100, 100)
    profile.respect = clamp(profile.respect + math.floor(amount * 0.4), -100, 100)
    profile.lastInteractionTick = nowTick(context)

    NPCMemory.UpdateActorReputation(npcData, actorType, actorId, math.floor(amount * 0.8))
    NPCMemory.PushRecentEvent(npcData, "actor_helped", {
        actorType = actorType,
        actorId = normalizeId(actorId),
        actorKey = actorKey,
        reason = context and context.reason,
        value = amount,
        tick = nowTick(context)
    })

    return profile, actorKey
end

function NPCMemory.RecordActorTheft(npcData, actorType, actorId, context)
    local profile, actorKey = NPCMemory.GetActorProfile(npcData, actorType, actorId)
    local amount = (context and context.value) or randInt(12, 26)

    profile.theftCount = profile.theftCount + 1
    profile.resentment = clamp(profile.resentment + amount, 0, 100)
    profile.trust = clamp(profile.trust - math.floor(amount * 0.9), -100, 100)
    profile.fear = clamp(profile.fear + math.floor(amount * 0.35), 0, 100)
    profile.dangerScore = clamp(profile.dangerScore + math.floor(amount * 0.65), 0, 100)
    profile.aggression = clamp(profile.aggression + math.floor(amount * 0.55), 0, 100)
    profile.lastInteractionTick = nowTick(context)

    NPCMemory.UpdateActorReputation(npcData, actorType, actorId, -amount)
    NPCMemory.PushRecentEvent(npcData, "actor_stole", {
        actorType = actorType,
        actorId = normalizeId(actorId),
        actorKey = actorKey,
        itemType = context and context.itemType,
        value = amount,
        tick = nowTick(context)
    })

    return profile, actorKey
end

function NPCMemory.RecordActorAggression(npcData, actorType, actorId, context)
    local profile, actorKey = NPCMemory.GetActorProfile(npcData, actorType, actorId)
    local amount = (context and context.value) or randInt(10, 22)

    profile.hostileCount = profile.hostileCount + 1
    profile.resentment = clamp(profile.resentment + amount, 0, 100)
    profile.trust = clamp(profile.trust - math.floor(amount * 0.8), -100, 100)
    profile.fear = clamp(profile.fear + math.floor(amount * 0.45), 0, 100)
    profile.dangerScore = clamp(profile.dangerScore + math.floor(amount * 0.7), 0, 100)
    profile.aggression = clamp(profile.aggression + amount, 0, 100)
    profile.lastInteractionTick = nowTick(context)

    NPCMemory.UpdateActorReputation(npcData, actorType, actorId, -math.floor(amount * 0.85))
    NPCMemory.PushRecentEvent(npcData, "actor_hostile", {
        actorType = actorType,
        actorId = normalizeId(actorId),
        actorKey = actorKey,
        hostilityType = context and context.hostilityType,
        value = amount,
        tick = nowTick(context)
    })

    return profile, actorKey
end

function NPCMemory.RecordActorStrengthObservation(npcData, actorType, actorId, strengthInfo)
    local profile, actorKey = NPCMemory.GetActorProfile(npcData, actorType, actorId)
    local observedStrength = 0

    if type(strengthInfo) == "table" then
        observedStrength = strengthInfo.strengthScore or strengthInfo.power or 0
    else
        observedStrength = tonumber(strengthInfo) or 0
    end

    observedStrength = clamp(observedStrength, 0, 100)
    profile.strengthScore = observedStrength
    profile.respect = clamp(profile.respect + math.floor(observedStrength * 0.20), -100, 100)
    profile.fear = clamp(profile.fear + math.floor(observedStrength * 0.12), 0, 100)
    profile.dangerScore = clamp(profile.dangerScore + math.floor(observedStrength * 0.10), 0, 100)
    profile.lastInteractionTick = nowTick(strengthInfo)

    NPCMemory.PushRecentEvent(npcData, "actor_strength_seen", {
        actorType = actorType,
        actorId = normalizeId(actorId),
        actorKey = actorKey,
        strengthScore = observedStrength,
        tick = nowTick(strengthInfo)
    })

    return profile, actorKey
end

function NPCMemory.RecordActorCombatHelp(npcData, actorType, actorId, context)
    local profile, actorKey = NPCMemory.GetActorProfile(npcData, actorType, actorId)
    local amount = (context and context.value) or randInt(14, 24)

    profile.gratitude = clamp(profile.gratitude + amount, 0, 100)
    profile.trust = clamp(profile.trust + math.floor(amount * 0.8), -100, 100)
    profile.respect = clamp(profile.respect + math.floor(amount * 0.8), -100, 100)
    profile.fear = clamp(profile.fear - math.floor(amount * 0.2), 0, 100)
    profile.lastInteractionTick = nowTick(context)

    NPCMemory.UpdateActorReputation(npcData, actorType, actorId, amount)
    NPCMemory.PushRecentEvent(npcData, "actor_saved_in_combat", {
        actorType = actorType,
        actorId = normalizeId(actorId),
        actorKey = actorKey,
        zombieCount = context and context.zombieCount,
        tick = nowTick(context)
    })

    return profile, actorKey
end

function NPCMemory.RecordPlayerHelp(npcData, playerId, context)
    local profile, pid = NPCMemory.RecordActorHelp(npcData, "player", playerId, context)
    NPCMemory.PushRecentEvent(npcData, "player_helped", {
        playerId = normalizeId(playerId),
        reason = context and context.reason,
        tick = nowTick(context)
    })
    return profile, pid
end

function NPCMemory.RecordPlayerTheft(npcData, playerId, context)
    local profile, pid = NPCMemory.RecordActorTheft(npcData, "player", playerId, context)
    NPCMemory.PushRecentEvent(npcData, "player_stole", {
        playerId = normalizeId(playerId),
        itemType = context and context.itemType,
        tick = nowTick(context)
    })
    return profile, pid
end

function NPCMemory.RecordPlayerStrengthObservation(npcData, playerId, strengthInfo)
    local profile, pid = NPCMemory.RecordActorStrengthObservation(npcData, "player", playerId, strengthInfo)
    NPCMemory.PushRecentEvent(npcData, "player_strength_seen", {
        playerId = normalizeId(playerId),
        strengthScore = type(strengthInfo) == "table" and strengthInfo.strengthScore or strengthInfo,
        tick = nowTick(strengthInfo)
    })
    return profile, pid
end

function NPCMemory.RecordPlayerCombatHelp(npcData, playerId, context)
    local profile, pid = NPCMemory.RecordActorCombatHelp(npcData, "player", playerId, context)
    NPCMemory.PushRecentEvent(npcData, "player_saved_in_combat", {
        playerId = normalizeId(playerId),
        zombieCount = context and context.zombieCount,
        tick = nowTick(context)
    })
    return profile, pid
end

function NPCMemory.RecordNPCHelp(npcData, npcId, context)
    return NPCMemory.RecordActorHelp(npcData, "npc", npcId, context)
end

function NPCMemory.RecordNPCTheft(npcData, npcId, context)
    return NPCMemory.RecordActorTheft(npcData, "npc", npcId, context)
end

function NPCMemory.RecordNPCHostility(npcData, npcId, context)
    return NPCMemory.RecordActorAggression(npcData, "npc", npcId, context)
end

function NPCMemory.RecordNPCStrengthObservation(npcData, npcId, context)
    return NPCMemory.RecordActorStrengthObservation(npcData, "npc", npcId, context)
end

function NPCMemory.RecordNPCCombatHelp(npcData, npcId, context)
    return NPCMemory.RecordActorCombatHelp(npcData, "npc", npcId, context)
end

function NPCMemory.RegisterExplicitPlayerTransaction(npcData, playerId, actionType, payload)
    return NPCMemory.RegisterExplicitActorTransaction(npcData, "player", playerId, actionType, payload)
end

function NPCMemory.RegisterExplicitActorTransaction(npcData, actorType, actorId, actionType, payload)
    payload = payload or {}

    if actionType == "gift" or actionType == "help" then
        return NPCMemory.RecordActorHelp(npcData, actorType, actorId, payload)
    elseif actionType == "theft" or actionType == "stole" then
        return NPCMemory.RecordActorTheft(npcData, actorType, actorId, payload)
    elseif actionType == "combat_help" then
        return NPCMemory.RecordActorCombatHelp(npcData, actorType, actorId, payload)
    elseif actionType == "strength" then
        return NPCMemory.RecordActorStrengthObservation(npcData, actorType, actorId, payload)
    elseif actionType == "hostile" or actionType == "assault" or actionType == "threat" or actionType == "insult" then
        return NPCMemory.RecordActorAggression(npcData, actorType, actorId, payload)
    end

    NPCMemory.PushRecentEvent(npcData, "actor_transaction_unknown", {
        actorType = actorType,
        actorId = normalizeId(actorId),
        actionType = actionType,
        payload = deepCopy(payload),
        tick = nowTick(payload)
    })
    return nil
end

function NPCMemory.GetDispositionTowardActor(npcData, actorType, actorId)
    local profile = NPCMemory.GetActorProfile(npcData, actorType, actorId)

    return {
        actorType = actorType,
        actorId = normalizeId(actorId),
        trust = profile.trust,
        fear = profile.fear,
        respect = profile.respect,
        gratitude = profile.gratitude,
        resentment = profile.resentment,
        aggression = profile.aggression,
        reputation = npcData.memory.reputationByActor[normalizeActorKey(actorType, actorId)] or 0,
        isTrusted = profile.trust >= 35,
        isFeared = profile.fear >= 45,
        isDangerous = profile.dangerScore >= 50,
        isHostile = profile.aggression >= 45 or profile.resentment >= 45
    }
end

function NPCMemory.GetDispositionTowardPlayer(npcData, playerId)
    return NPCMemory.GetDispositionTowardActor(npcData, "player", playerId)
end

function NPCMemory.GetDispositionTowardNPC(npcData, npcId)
    return NPCMemory.GetDispositionTowardActor(npcData, "npc", npcId)
end

function NPCMemory.ShareMemory(npcA, npcB, context)
    if not npcA or not npcB or npcA == npcB then
        return false
    end

    local memoryA = NPCMemory.EnsureMemory(npcA)
    local memoryB = NPCMemory.EnsureMemory(npcB)
    local shared = {
        players = 0,
        zones = 0,
        lootSpots = 0
    }

    for actorKey, profileA in pairs(memoryA.actorProfiles) do
        local profileB = memoryB.actorProfiles[actorKey] or {}
        memoryB.actorProfiles[actorKey] = profileB
        profileB.trust = clamp(math.floor((profileB.trust + profileA.trust) * 0.5), -100, 100)
        profileB.fear = clamp(math.floor((profileB.fear + profileA.fear) * 0.5), 0, 100)
        profileB.respect = clamp(math.floor((profileB.respect + profileA.respect) * 0.5), -100, 100)
        profileB.gratitude = clamp(math.floor((profileB.gratitude + profileA.gratitude) * 0.5), 0, 100)
        profileB.resentment = clamp(math.floor((profileB.resentment + profileA.resentment) * 0.5), 0, 100)
        profileB.aggression = clamp(math.floor(((profileB.aggression or 0) + (profileA.aggression or 0)) * 0.5), 0, 100)
        profileB.dangerScore = clamp(math.floor((profileB.dangerScore + profileA.dangerScore) * 0.5), 0, 100)
        profileB.strengthScore = math.max(profileB.strengthScore or 0, profileA.strengthScore or 0)
        profileB.actorType = profileA.actorType
        profileB.actorId = profileA.actorId
        profileB.lastInteractionTick = math.max(profileB.lastInteractionTick or 0, nowTick(context))

        memoryB.reputationByActor[actorKey] = clamp(
            math.floor(((memoryB.reputationByActor[actorKey] or 0) + (memoryA.reputationByActor[actorKey] or 0)) * 0.5),
            -100,
            100
        )
        memoryB.actorRumors[actorKey] = {
            sourceNPC = npcA.id,
            actorType = profileA.actorType,
            actorId = profileA.actorId,
            dangerScore = profileA.dangerScore or 0,
            strengthScore = profileA.strengthScore or 0,
            trust = profileA.trust or 0,
            aggression = profileA.aggression or 0,
            sharedTick = nowTick(context)
        }
        shared.players = shared.players + 1
    end

    for zoneId, zone in pairs(memoryA.dangerousZones) do
        if memoryB.dangerousZones[zoneId] == nil then
            memoryB.dangerousZones[zoneId] = deepCopy(zone)
            shared.zones = shared.zones + 1
        end
    end

    for spotId, spot in pairs(memoryA.knownLootSpots) do
        if memoryB.knownLootSpots[spotId] == nil then
            memoryB.knownLootSpots[spotId] = deepCopy(spot)
            shared.lootSpots = shared.lootSpots + 1
        end
    end

    memoryA.trustedNPCs[npcB.id] = true
    memoryB.trustedNPCs[npcA.id] = true

    NPCMemory.PushRecentEvent(npcA, "shared_memory_out", {
        withNpcId = npcB.id,
        shared = shared,
        tick = nowTick(context)
    })
    NPCMemory.PushRecentEvent(npcB, "shared_memory_in", {
        fromNpcId = npcA.id,
        shared = shared,
        tick = nowTick(context)
    })

    return true, shared
end

function NPCMemory.ShouldShareWithPlayer(npcData, playerId)
    local profile = NPCMemory.GetPlayerProfile(npcData, playerId)
    local willingness = profile.trust + profile.gratitude + math.floor(profile.respect * 0.5) - profile.resentment
    return willingness >= 25
end

function NPCMemory.ShouldShareWithActor(npcData, actorType, actorId)
    local profile = NPCMemory.GetActorProfile(npcData, actorType, actorId)
    local willingness = profile.trust + profile.gratitude + math.floor(profile.respect * 0.5) - profile.resentment - math.floor((profile.aggression or 0) * 0.25)
    return willingness >= 25
end

function NPCMemory.BuildIntelForActor(npcData, actorType, actorId)
    if not NPCMemory.ShouldShareWithActor(npcData, actorType, actorId) then
        return nil
    end

    local memory = NPCMemory.EnsureMemory(npcData)
    local intel = {
        dangerousZones = {},
        knownLootSpots = {},
        rumors = {}
    }

    local count = 0
    for zoneId, zone in pairs(memory.dangerousZones) do
        intel.dangerousZones[zoneId] = deepCopy(zone)
        count = count + 1
        if count >= 3 then
            break
        end
    end

    count = 0
    for spotId, spot in pairs(memory.knownLootSpots) do
        intel.knownLootSpots[spotId] = deepCopy(spot)
        count = count + 1
        if count >= 3 then
            break
        end
    end

    count = 0
    local selfKey = normalizeActorKey(actorType, actorId)
    for actorKey, rumor in pairs(memory.actorRumors) do
        if actorKey ~= selfKey then
            intel.rumors[actorKey] = deepCopy(rumor)
            count = count + 1
            if count >= 2 then
                break
            end
        end
    end

    return intel
end

function NPCMemory.BuildIntelForPlayer(npcData, playerId)
    local intel = NPCMemory.BuildIntelForActor(npcData, "player", playerId)
    if not intel then
        return nil
    end

    local memory = NPCMemory.EnsureMemory(npcData)

    memory.sharedIntelToPlayers[normalizeId(playerId)] = {
        lastSharedTick = 0,
        lastIntel = deepCopy(intel)
    }

    return intel
end

function NPCMemory.FindInventoryItem(npcData, predicate)
    local inventory = npcData and npcData.inventory
    local items = inventory and inventory.items
    if type(items) ~= "table" then
        return nil, nil
    end

    for index = 1, #items do
        local item = items[index]
        if predicate(item) then
            return item, index
        end
    end
    return nil, nil
end

function NPCMemory.BuildTradeOffer(npcData, counterpartType, counterpartId, context)
    local memory = NPCMemory.EnsureMemory(npcData)
    local profession = NPCMemory.GetProfessionProfile(npcData)
    local economicDemand = NPCMemory.BuildEconomicDemand(npcData, context)
    local needFood = (npcData.stats and npcData.stats.hunger or 100) <= 35
    local needWater = (npcData.stats and npcData.stats.thirst or 100) <= 35
    local wants = {}
    local offers = {}
    local priceMode = profession.isMerchant and profession.tradeMode or "free"

    if needFood then
        wants[#wants + 1] = "food"
    end
    if needWater then
        wants[#wants + 1] = "water"
    end

    local professionWants = profession.buys or {}
    for i = 1, #professionWants do
        wants[#wants + 1] = professionWants[i]
    end

    for i = 1, #economicDemand.wants do
        wants[#wants + 1] = economicDemand.wants[i]
    end

    local sellCategories = profession.sells or {}
    local professionOffers = NPCMemory.SelectTradeItems(npcData, sellCategories, profession.isMerchant and 4 or 2)
    for i = 1, #professionOffers do
        offers[#offers + 1] = professionOffers[i]
    end

    if #offers == 0 then
        local item = NPCMemory.FindInventoryItem(npcData, function(candidate)
            return candidate and candidate.type and candidate.quantity and candidate.quantity > 0
        end)
        if item then
            offers[#offers + 1] = item.type
        end
    end

    if counterpartType == "player" or counterpartType == "npc" then
        local disposition = NPCMemory.GetDispositionTowardActor(npcData, counterpartType, counterpartId)
        if profession.isMerchant and not disposition.isHostile and not disposition.isDangerous then
            priceMode = profession.tradeMode or "merchant"
        elseif disposition.isTrusted and disposition.gratitude >= 15 then
            priceMode = "free"
        elseif disposition.isDangerous or disposition.isHostile or disposition.resentment >= 20 then
            priceMode = "quest"
        else
            priceMode = #wants > 0 and "barter" or "free"
        end
    else
        priceMode = #wants > 0 and "barter" or "free"
    end

    local priceProfile = NPCMemory.CalculatePriceProfile(npcData, counterpartType, counterpartId, context)

    local request = nil
    if priceMode == "quest" then
        request = {
            type = "help",
            detail = (context and context.baseId) and "help_base" or "help_against_zombies"
        }
    elseif priceMode == "barter" or priceMode == "merchant" or priceMode == "broker" then
        request = {
            type = "item",
            detail = wants[1] or "materials"
        }
    end

    local proposal = {
        counterpartType = counterpartType,
        counterpartId = normalizeId(counterpartId),
        mode = priceMode,
        profession = profession,
        demands = economicDemand.demands,
        requests = economicDemand.requests,
        price = priceProfile.finalPrice,
        priceState = priceProfile.state,
        priceMultiplier = priceProfile.multiplier,
        wants = wants,
        offers = offers,
        request = request
    }

    memory.tradeLedger[#memory.tradeLedger + 1] = {
        tick = nowTick(context),
        proposal = deepCopy(proposal)
    }

    return proposal
end

function NPCMemory.RegisterExchange(npcData, counterpartType, counterpartId, exchange)
    local memory = NPCMemory.EnsureMemory(npcData)
    memory.tradeLedger[#memory.tradeLedger + 1] = {
        tick = nowTick(exchange),
        counterpartType = counterpartType,
        counterpartId = normalizeId(counterpartId),
        exchange = deepCopy(exchange)
    }

    NPCMemory.PushRecentEvent(npcData, "exchange_done", {
        counterpartType = counterpartType,
        counterpartId = normalizeId(counterpartId),
        exchange = deepCopy(exchange),
        tick = nowTick(exchange)
    })
end

function NPCMemory.RegisterExplicitExchange(npcData, counterpartType, counterpartId, exchange)
    NPCMemory.RegisterExchange(npcData, counterpartType, counterpartId, exchange)

    if type(exchange) == "table" then
        if exchange.mode == "free" or exchange.mode == "gift" then
            NPCMemory.RecordActorHelp(npcData, counterpartType, counterpartId, {
                tick = nowTick(exchange),
                value = exchange.value or 10,
                reason = "explicit_exchange_help"
            })
        elseif exchange.mode == "theft" then
            NPCMemory.RecordActorTheft(npcData, counterpartType, counterpartId, {
                tick = nowTick(exchange),
                value = exchange.value or 14,
                itemType = exchange.itemType
            })
        end
    end

    return true
end

function NPCMemory.UpdateInfectionBehavior(npcData, context)
    local memory = NPCMemory.EnsureMemory(npcData)
    local infection = memory.infection
    local tick = nowTick(context)

    if not npcData.health or npcData.health.isBitten ~= true then
        infection.progress = 0
        infection.intendsToLeave = false
        infection.berserkTriggered = false
        infection.lastUpdateTick = tick
        return {
            status = "healthy"
        }
    end

    local deltaTicks = math.max(1, tick - (infection.lastUpdateTick or tick))
    local infectionProgressMult = math.max(0.1, tuningFactor("infectionProgressMult", 1))
    local leaveThreshold = clamp((NPCMemory.bittenLeaveThreshold or 72) * math.max(0.2, tuningFactor("infectionLeaveThresholdMult", 1)), 5, 100)
    local attackThreshold = clamp((NPCMemory.bittenAttackThreshold or 100) * math.max(0.2, tuningFactor("infectionAttackThresholdMult", 1)), 5, 100)
    infection.lastUpdateTick = tick
    infection.progress = clamp(infection.progress + (deltaTicks * NPCMemory.infectionProgressPerTick * infectionProgressMult), 0, 100)

    if npcData.health.isHidingBite and infection.progress >= leaveThreshold and not infection.intendsToLeave then
        infection.intendsToLeave = true
        NPCMemory.PushRecentEvent(npcData, "bitten_leaves_discreetly", {
            tick = tick,
            progress = infection.progress
        })
        return {
            status = "leave_discreetly",
            progress = infection.progress,
            hideBite = true
        }
    end

    if infection.progress >= attackThreshold and not infection.berserkTriggered then
        infection.berserkTriggered = true
        npcData.health.isHidingBite = false
        NPCMemory.PushRecentEvent(npcData, "bitten_turned_aggressive", {
            tick = tick,
            progress = infection.progress
        })
        return {
            status = "sudden_attack",
            progress = infection.progress,
            berserk = true
        }
    end

    return {
        status = "infected",
        progress = infection.progress,
        hideBite = npcData.health.isHidingBite == true,
        intendsToLeave = infection.intendsToLeave == true
    }
end

return NPCMemory