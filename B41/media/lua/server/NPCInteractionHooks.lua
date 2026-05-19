--[[
    Project Humain : Dynamic_NPC_Overhaul
    NPCInteractionHooks.lua

    Hooks explicites PNJ/joueur pour transactions et interactions sociales.
    Ces hooks permettent de nourrir la memoire de maniere fiable via commandes serveur.
]]


local hasSpawner, NPCSpawner = pcall(require, "NPCSpawner")
if not hasSpawner then
    NPCSpawner = nil
end

local hasMemory, NPCMemory = pcall(require, "NPCMemory")
if not hasMemory then
    NPCMemory = nil
end

local hasFactionMgr, NPCFactionManager = pcall(require, "NPCFactionManager")
if not hasFactionMgr then
    NPCFactionManager = nil
end

local hasMemoryRuntime, NPCMemoryRuntime = pcall(require, "NPCMemoryRuntime")
if not hasMemoryRuntime then
    NPCMemoryRuntime = nil
end

local hasNetServer, NPC_NetworkServer = pcall(require, "NPC_NetworkServer")
if not hasNetServer then
    NPC_NetworkServer = nil
end

local hasEnvironmentHooks, NPCEnvironmentHooks = pcall(require, "NPCEnvironmentHooks")
if not hasEnvironmentHooks then
    NPCEnvironmentHooks = nil
end

local hasQuestRuntime, NPCQuestRuntime = pcall(require, "NPCQuestRuntime")
if not hasQuestRuntime then
    NPCQuestRuntime = nil
end

local hasTuningProfiles, NPCTuningProfiles = pcall(require, "NPCTuningProfiles")
if not hasTuningProfiles then
    NPCTuningProfiles = nil
end

local hasLogger, PHNPC_Logger = pcall(require, "PHNPC_Logger")
if not hasLogger then
    PHNPC_Logger = _G.PHNPC_Logger
end

local NPCInteractionHooks = {
    module = "PH_NPC_INTERACT",
    interactionCommand = "MemoryEvent",
    intelCommand = "RequestIntel",
    tradeCommand = "TradeEvent",
    orderCommand = "OrderAction",
    adminCommand = "AdminAction",
    snapshotCommand = "RequestNpcSnapshot",
    ollamaCommand = "OllamaRequest",
    quoteCooldownSec = 6,
    quoteCooldownByKey = {},
    tradeLocks = {},
    tradeLockTTLTicks = 12
}

local function clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

local function isAdminPlayer(player)
    if not player then
        return false
    end

    if player.isAccessLevel and player:getAccessLevel() then
        local level = tostring(player:getAccessLevel()):lower()
        if level == "admin" or level == "moderator" or level == "gm" then
            return true
        end
    end

    if player.isAdmin and player:isAdmin() then
        return true
    end

    return false
end

local function applyPlayerSocialRelief(player, amount)
    if not player then
        return
    end

    local gain = math.max(0.2, tonumber(amount) or 1)

    if player.getStats then
        local okStats, stats = pcall(function()
            return player:getStats()
        end)
        if okStats and stats then
            if stats.getStress and stats.setStress then
                local stress = tonumber(stats:getStress()) or 0
                pcall(function()
                    stats:setStress(math.max(0, stress - (0.004 * gain)))
                end)
            end
            if stats.getBoredom and stats.setBoredom then
                local boredom = tonumber(stats:getBoredom()) or 0
                pcall(function()
                    stats:setBoredom(math.max(0, boredom - (0.12 * gain)))
                end)
            end
        end
    end

    if player.getBodyDamage then
        local okBody, body = pcall(function()
            return player:getBodyDamage()
        end)
        if okBody and body and body.getUnhappynessLevel and body.setUnhappynessLevel then
            local unh = tonumber(body:getUnhappynessLevel()) or 0
            pcall(function()
                body:setUnhappynessLevel(math.max(0, unh - (0.18 * gain)))
            end)
        end
    end
end

local function registerSocialContactForNPC(npcData, actorType, actorId, mode, tick, intensity)
    if not NPCMemory or not NPCMemory.RegisterDialogueContact or not npcData then
        return
    end
    NPCMemory.RegisterDialogueContact(npcData, actorType, actorId, {
        tick = tick or 0,
        mode = mode or "dialogue",
        intensity = intensity or 1
    })
end

local function resolveTradeTick(args)
    if type(args) == "table" and tonumber(args.tick) then
        return tonumber(args.tick)
    end
    if NPCFactionManager and NPCFactionManager.tickCounter then
        return tonumber(NPCFactionManager.tickCounter) or 0
    end
    return (os and os.time and os.time()) or 0
end

function NPCInteractionHooks:collectTradeLockKeys(sourceType, sourceId, targetType, targetId)
    local keys = {}
    if sourceType == "npc" and sourceId then
        keys[#keys + 1] = "npc:" .. tostring(sourceId)
    end
    if targetType == "npc" and targetId then
        keys[#keys + 1] = "npc:" .. tostring(targetId)
    end
    table.sort(keys)
    return keys
end

function NPCInteractionHooks:tryAcquireTradeLocks(lockKeys, ownerKey, currentTick)
    if type(lockKeys) ~= "table" or #lockKeys == 0 then
        return true, nil
    end

    for key, lock in pairs(self.tradeLocks) do
        if type(lock) ~= "table" or (tonumber(lock.expiresTick) or 0) < currentTick then
            self.tradeLocks[key] = nil
        end
    end

    local ttl = math.max(1, tonumber(self.tradeLockTTLTicks) or 12)
    local expiresTick = currentTick + ttl

    for i = 1, #lockKeys do
        local key = lockKeys[i]
        local lock = self.tradeLocks[key]
        if lock and (tonumber(lock.expiresTick) or 0) >= currentTick and lock.owner ~= ownerKey then
            return false, key
        end
    end

    for i = 1, #lockKeys do
        local key = lockKeys[i]
        self.tradeLocks[key] = {
            owner = ownerKey,
            expiresTick = expiresTick
        }
    end

    return true, nil
end

function NPCInteractionHooks:getNPCData(npcId)
    if not NPCSpawner or type(NPCSpawner.activeNPCs) ~= "table" then
        return nil
    end

    local entry = NPCSpawner.activeNPCs[npcId]
    if not entry then
        return nil, nil
    end

    return entry.data, entry
end

function NPCInteractionHooks:buildNpcSnapshot(npcId, playerId)
    local npcData, entry = self:getNPCData(npcId)
    if not npcData then
        return nil
    end

    if NPCMemory and NPCMemory.EnsureMemory then
        NPCMemory.EnsureMemory(npcData)
    end

    local md = entry and entry.entity and entry.entity.getModData and entry.entity:getModData() or nil
    local fsm = md and md.PH_FSM or nil
    local disposition = nil
    if NPCMemory and playerId then
        disposition = NPCMemory.GetDispositionTowardPlayer(npcData, playerId)
    end

    local factionId = (fsm and fsm.factionId) or (NPCFactionManager and NPCFactionManager.getFactionOfNPC and NPCFactionManager:getFactionOfNPC(npcId))
    local environmentMetrics = nil
    if NPCEnvironmentHooks and NPCEnvironmentHooks.getAdminMetrics then
        environmentMetrics = NPCEnvironmentHooks:getAdminMetrics(npcId)
    end
    local memory = npcData.memory or {}
    local profession = NPCMemory and NPCMemory.GetProfessionProfile and NPCMemory.GetProfessionProfile(npcData) or (npcData.profession or nil)

    local mood = "Neutre"
    if disposition then
        if disposition.isFeared then
            mood = "Effraye"
        elseif disposition.isDangerous or disposition.isHostile then
            mood = "Hostile"
        elseif disposition.isTrusted then
            mood = "Amical"
        end
    end

    return {
        npcId = npcId,
        displayName = npcData.displayName or npcData.name or npcId,
        mood = mood,
        factionId = factionId,
        state = fsm and fsm.state or nil,
        activeOrder = fsm and fsm.activeOrder or nil,
        socialRole = fsm and fsm.socialRole or nil,
        survivalScore = fsm and fsm.survivalScore or nil,
        infectionStatus = fsm and fsm.infectionStatus or nil,
        infectionProgress = fsm and fsm.infectionProgress or nil,
        relation = disposition,
        stats = npcData.stats,
        health = npcData.health,
        personality = npcData.traits and npcData.traits.personality or nil,
        inventory = npcData.inventory,
        profession = profession,
        lastTacticalProfile = npcData.lastTacticalProfile or nil,
        environmentMetrics = environmentMetrics,
        socialState = memory.social,
        psychologyState = memory.psychology,
        weatherState = memory.environment,
        expeditionState = memory.expedition,
        runtimePenalties = npcData.runtimePenalties,
        localizedInjuries = npcData.health and npcData.health.localizedInjuries or nil,
        gameplayProfile = NPCTuningProfiles and NPCTuningProfiles.getActiveProfileName and NPCTuningProfiles:getActiveProfileName() or "realistic"
    }
end

function NPCInteractionHooks:sendActionResult(player, npcId, ok, actionType, message, extra)
    if not player or not sendServerCommand then
        return
    end

    local playerId = player.getUsername and player:getUsername() or nil
    local snapshot = self:buildNpcSnapshot(npcId, playerId)
    local payload = {
        ok = ok == true,
        actionType = actionType,
        npcId = npcId,
        message = message,
        snapshot = snapshot
    }

    if type(extra) == "table" then
        for k, v in pairs(extra) do
            payload[k] = v
        end
    end

    sendServerCommand(player, self.module, "ActionResult", payload)
end

function NPCInteractionHooks:markExplicitPriority(targetNpcId, actorType, actorId, actionType, args)
    if NPCMemoryRuntime and NPCMemoryRuntime.markExplicitInteraction then
        NPCMemoryRuntime:markExplicitInteraction(targetNpcId, actorType, actorId, actionType, args and args.tick)
    end
end

function NPCInteractionHooks:recordOutgoingNPCAction(sourceNpcId, targetType, targetId, actionType, args)
    local sourceData = self:getNPCData(sourceNpcId)
    if not sourceData or not NPCMemory then
        return
    end

    NPCMemory.RegisterOutgoingActorAction(sourceData, targetType, targetId, actionType, {
        tick = args and args.tick or 0,
        value = args and args.value or nil,
        itemType = args and args.itemType or nil,
        reason = args and args.reason or nil,
        hostilityType = args and args.hostilityType or nil,
        payload = args
    })
end

function NPCInteractionHooks:recordActorImpactOnNPC(actorType, actorId, targetNpcId, actionType, args)
    if not NPCMemory then
        return false
    end

    local targetData = self:getNPCData(targetNpcId)
    if not targetData then
        return false
    end

    NPCMemory.RegisterExplicitActorTransaction(targetData, actorType, actorId, actionType, {
        tick = args and args.tick or 0,
        value = args and args.value or nil,
        itemType = args and args.itemType or nil,
        reason = args and args.reason or nil,
        zombieCount = args and args.zombieCount or nil,
        strengthScore = args and args.strengthScore or nil,
        hostilityType = args and args.hostilityType or nil
    })

    self:markExplicitPriority(targetNpcId, actorType, actorId, actionType, args)

    if actorType == "npc" then
        self:recordOutgoingNPCAction(actorId, "npc", targetNpcId, actionType, args)
    end

    return true
end

function NPCInteractionHooks:recordDirectedExchange(sourceType, sourceId, targetType, targetId, exchange)
    if not NPCMemory then
        return false
    end

    if targetType == "npc" then
        local targetData = self:getNPCData(targetId)
        if targetData then
            NPCMemory.RegisterExplicitExchange(targetData, sourceType, sourceId, exchange)
            self:markExplicitPriority(targetId, sourceType, sourceId, exchange and exchange.mode or "exchange", exchange)
        end
    end

    if sourceType == "npc" then
        local sourceData = self:getNPCData(sourceId)
        if sourceData then
            NPCMemory.RegisterExchange(sourceData, targetType, targetId, exchange)
            self:recordOutgoingNPCAction(sourceId, targetType, targetId, exchange and exchange.mode or "exchange", exchange)
        end
    end

    return true
end

function NPCInteractionHooks:removeItemsFromPlayer(player, itemType, quantity)
    if not player or not itemType or quantity <= 0 then
        return false, 0
    end

    local inv = player.getInventory and player:getInventory() or nil
    if not inv or not inv.getItems then
        return false, 0
    end

    local items = inv:getItems()
    if not items or not items.size then
        return false, 0
    end

    local matches = {}
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it and it.getFullType and it:getFullType() == itemType then
            matches[#matches + 1] = it
        end
    end

    if #matches < quantity then
        return false, #matches
    end

    local removed = 0
    for i = 1, quantity do
        local it = matches[i]
        if it then
            local ok = pcall(function()
                inv:Remove(it)
            end)
            if ok then
                removed = removed + 1
            end
        end
    end

    return removed == quantity, removed
end

function NPCInteractionHooks:addItemToNPCInventory(npcData, itemType, quantity)
    npcData.inventory = npcData.inventory or { items = {}, currentWeight = 0, maxWeight = 14 }
    npcData.inventory.items = npcData.inventory.items or {}

    local remaining = math.max(1, tonumber(quantity) or 1)
    for i = 1, #npcData.inventory.items do
        local it = npcData.inventory.items[i]
        if it and it.type == itemType then
            it.quantity = (it.quantity or 0) + remaining
            npcData.inventory.currentWeight = math.max(0, (tonumber(npcData.inventory.currentWeight) or 0) + remaining)
            return
        end
    end

    npcData.inventory.items[#npcData.inventory.items + 1] = {
        type = itemType,
        quantity = remaining,
        condition = 100
    }
    npcData.inventory.currentWeight = (tonumber(npcData.inventory.currentWeight) or 0) + remaining
end

function NPCInteractionHooks:removeItemFromNPCInventory(npcData, itemType, quantity)
    if not npcData or not itemType or quantity <= 0 then
        return false, 0
    end

    npcData.inventory = npcData.inventory or { items = {}, currentWeight = 0, maxWeight = 14 }
    npcData.inventory.items = npcData.inventory.items or {}

    local remaining = math.max(1, tonumber(quantity) or 1)
    local removed = 0
    local i = 1
    while i <= #npcData.inventory.items and remaining > 0 do
        local item = npcData.inventory.items[i]
        if item and item.type == itemType and (item.quantity or 0) > 0 then
            local take = math.min(remaining, tonumber(item.quantity) or 0)
            item.quantity = math.max(0, (tonumber(item.quantity) or 0) - take)
            remaining = remaining - take
            removed = removed + take
            npcData.inventory.currentWeight = math.max(0, (tonumber(npcData.inventory.currentWeight) or 0) - take)
            if item.quantity <= 0 then
                table.remove(npcData.inventory.items, i)
            else
                i = i + 1
            end
        else
            i = i + 1
        end
    end

    return removed == math.max(1, tonumber(quantity) or 1), removed
end

function NPCInteractionHooks:resolveOnlinePlayerByUsername(username)
    if not username then
        return nil
    end

    if type(getOnlinePlayers) == "function" then
        local ok, players = pcall(getOnlinePlayers)
        if ok and type(players) == "table" then
            for i = 1, #players do
                local candidate = players[i]
                if candidate and candidate.getUsername then
                    local okName, candidateName = pcall(function()
                        return candidate:getUsername()
                    end)
                    if okName and tostring(candidateName) == tostring(username) then
                        return candidate
                    end
                end
            end
        end
    end

    if type(getPlayerByUsername) == "function" then
        local ok, candidate = pcall(getPlayerByUsername, tostring(username))
        if ok then
            return candidate
        end
    end

    return nil
end

function NPCInteractionHooks:addItemToPlayerInventory(player, itemType, quantity)
    if not player or not itemType or quantity <= 0 then
        return false, 0
    end

    local inv = player.getInventory and player:getInventory() or nil
    if not inv then
        return false, 0
    end

    local qty = math.max(1, tonumber(quantity) or 1)
    local added = 0
    for i = 1, qty do
        local ok = pcall(function()
            if inv.AddItem then
                inv:AddItem(itemType)
            elseif inv.AddItems then
                inv:AddItems(itemType, 1)
            end
        end)
        if ok then
            added = added + 1
        end
    end

    return added == qty, added
end

function NPCInteractionHooks:getNPCCash(npcData)
    npcData.economy = npcData.economy or { cash = 0 }
    npcData.economy.cash = math.max(0, tonumber(npcData.economy.cash) or 0)
    return npcData.economy.cash
end

function NPCInteractionHooks:addNPCCash(npcData, amount)
    if not npcData then
        return 0
    end

    npcData.economy = npcData.economy or { cash = 0 }
    local current = math.max(0, tonumber(npcData.economy.cash) or 0)
    local delta = math.max(0, math.floor(tonumber(amount) or 0))
    npcData.economy.cash = current + delta
    return npcData.economy.cash
end

function NPCInteractionHooks:spendNPCCash(npcData, amount)
    if not npcData then
        return false, 0
    end

    npcData.economy = npcData.economy or { cash = 0 }
    local current = math.max(0, tonumber(npcData.economy.cash) or 0)
    local delta = math.max(0, math.floor(tonumber(amount) or 0))
    if current < delta then
        return false, current
    end

    npcData.economy.cash = current - delta
    return true, npcData.economy.cash
end

function NPCInteractionHooks:countPlayerCurrencyItems(player)
    if not player or not player.getInventory then
        return 0, nil
    end

    local inv = player:getInventory()
    if not inv or not inv.getItems then
        return 0, nil
    end

    local items = inv:getItems()
    if not items or not items.size then
        return 0, nil
    end

    local total = 0
    local currencyType = nil
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item and item.getFullType then
            local fullType = item:getFullType()
            for j = 1, #NPCMemory.currencyItemTypes do
                local knownType = NPCMemory.currencyItemTypes[j]
                if fullType == knownType then
                    total = total + 1
                    currencyType = currencyType or fullType
                    break
                end
            end
        end
    end

    return total, currencyType
end

function NPCInteractionHooks:collectPlayerCurrencyPayment(player, amount)
    if not player or amount <= 0 then
        return false, 0, nil
    end

    local remaining = math.max(1, math.floor(tonumber(amount) or 0))
    local inv = player.getInventory and player:getInventory() or nil
    if not inv or not inv.getItems then
        return false, 0, nil
    end

    local items = inv:getItems()
    if not items or not items.size then
        return false, 0, nil
    end

    local removed = 0
    local removedType = nil
    for i = 0, items:size() - 1 do
        if remaining <= 0 then
            break
        end

        local item = items:get(i)
        if item and item.getFullType then
            local fullType = item:getFullType()
            local isCurrency = false
            for j = 1, #NPCMemory.currencyItemTypes do
                if fullType == NPCMemory.currencyItemTypes[j] then
                    isCurrency = true
                    break
                end
            end

            if isCurrency then
                local ok = pcall(function()
                    inv:Remove(item)
                end)
                if ok then
                    removed = removed + 1
                    removedType = removedType or fullType
                    remaining = remaining - 1
                end
            end
        end
    end

    return removed >= math.max(1, math.floor(tonumber(amount) or 0)), removed, removedType
end

function NPCInteractionHooks:consumeNPCServicePayment(npcData, player, quote)
    if not quote or not npcData then
        return false, "Devis manquant"
    end

    local cost = math.max(1, tonumber(quote.cost) or 1)
    local mode = tostring(quote.mode or "trade")

    if mode == "free" then
        return true, 0
    end

    local paidByCash = false
    local currencyCount = 0
    if player then
        currencyCount = self:countPlayerCurrencyItems(player)
        if currencyCount >= cost then
            local removedOk = self:collectPlayerCurrencyPayment(player, cost)
            if removedOk then
                paidByCash = true
                self:addNPCCash(npcData, cost)
            end
        end
    end

    if paidByCash then
        return true, cost
    end

    local requested = quote.requests or {}
    local requestItem = requested[1] and requested[1].category or quote.category or "general_goods"
    if player and requestItem then
        local removedOk, removedCount = self:removeItemsFromPlayer(player, requestItem, cost)
        if removedOk then
            self:addNPCCash(npcData, math.max(1, math.floor(cost * 0.6)))
            return true, removedCount
        end
    end

    return false, 0
end

function NPCInteractionHooks:canNPCReceiveItem(npcData, itemType, quantity)
    if not npcData then
        return false, "PNJ invalide"
    end

    npcData.inventory = npcData.inventory or { items = {}, currentWeight = 0, maxWeight = 14 }
    npcData.inventory.items = npcData.inventory.items or {}

    local qty = math.max(1, tonumber(quantity) or 1)
    local currentWeight = math.max(0, tonumber(npcData.inventory.currentWeight) or 0)
    local maxWeight = math.max(1, tonumber(npcData.inventory.maxWeight) or 14)

    if (currentWeight + qty) > maxWeight then
        return false, "Capacite PNJ insuffisante"
    end

    return true, nil
end

function NPCInteractionHooks:handleMemoryEvent(player, args)
    if not NPCMemory or type(args) ~= "table" then
        return false
    end

    local sourceType = args.sourceType or "player"
    local sourceId = args.sourceId
    local targetType = args.targetType or "npc"
    local targetId = args.targetId or args.npcId

    if sourceType == "player" then
        sourceId = (player and player.getUsername and player:getUsername()) or args.playerId
    end

    if not sourceId or not targetId then
        return false
    end

    if targetType == "npc" then
        local ok = self:recordActorImpactOnNPC(sourceType, sourceId, targetId, args.actionType, args)
        self:sendActionResult(player, targetId, ok, "MemoryEvent", ok and "Interaction enregistree" or "Interaction refusee")
        return ok
    end

    if sourceType == "npc" then
        self:recordOutgoingNPCAction(sourceId, targetType, targetId, args.actionType, args)
        return true
    end

    return false
end

function NPCInteractionHooks:handleTradeEvent(player, args)
    if not NPCMemory or type(args) ~= "table" then
        return false
    end

    local sourceType = args.sourceType or "player"
    local sourceId = args.sourceId
    local targetType = args.targetType or "npc"
    local targetId = args.targetId or args.npcId

    if sourceType == "player" then
        sourceId = (player and player.getUsername and player:getUsername()) or args.playerId
    end

    if not sourceId or not targetId then
        return false
    end

    local tradeTick = resolveTradeTick(args)
    local ownerKey = tostring(sourceType or "?") .. ":" .. tostring(sourceId or "?") .. "->" .. tostring(targetType or "?") .. ":" .. tostring(targetId or "?") .. "@" .. tostring(tradeTick)
    local lockKeys = self:collectTradeLockKeys(sourceType, sourceId, targetType, targetId)
    local acquired, blockedKey = self:tryAcquireTradeLocks(lockKeys, ownerKey, tradeTick)
    if not acquired then
        local lockNpcId = tostring(blockedKey or "")
        lockNpcId = lockNpcId:gsub("^npc:", "")
        self:sendActionResult(player, lockNpcId ~= "" and lockNpcId or targetId, false, "TradeEvent", "Transaction en cours, reessayez dans un instant")
        return false
    end

    local qty = math.max(1, tonumber(args.quantity) or 1)
    local itemType = args.itemType
    local strictCapacity = args.strictCapacity ~= false
    local sourcePlayer = nil
    local targetPlayer = nil

    if sourceType == "player" then
        sourcePlayer = player or self:resolveOnlinePlayerByUsername(sourceId)
    end

    if targetType == "player" then
        targetPlayer = self:resolveOnlinePlayerByUsername(targetId)
    end

    local notificationPlayer = player or targetPlayer or sourcePlayer
    local sourceNpcData = sourceType == "npc" and self:getNPCData(sourceId) or nil
    local targetNpcData = targetType == "npc" and self:getNPCData(targetId) or nil
    local tradeQuote = nil

    if NPCMemory and args and (args.mode == "buy" or args.mode == "sell" or args.mode == "trade") then
        local quoteContext = {
            tick = args.tick or 0,
            baseId = args.baseId,
            basePrice = args.price or args.value or 10,
            clanNeed = args.clanNeed,
            personalNeed = args.personalNeed
        }
        if sourceType == "npc" and sourceNpcData then
            tradeQuote = NPCMemory.BuildTradeOffer(sourceNpcData, targetType, targetId, quoteContext)
        elseif targetType == "npc" and targetNpcData then
            tradeQuote = NPCMemory.BuildTradeOffer(targetNpcData, sourceType, sourceId, quoteContext)
        end
    end

    if sourceType == "player" and targetType == "npc" and args.mode == "gift" then
        if not sourcePlayer then
            self:sendActionResult(player, targetId, false, "TradeEvent", "Joueur invalide")
            return false
        end

        if not itemType then
            self:sendActionResult(player, targetId, false, "TradeEvent", "Objet manquant")
            return false
        end

        local removedOk, removedCount = self:removeItemsFromPlayer(sourcePlayer, itemType, qty)
        if not removedOk then
            self:sendActionResult(notificationPlayer, targetId, false, "TradeEvent", "Quantite insuffisante: " .. tostring(removedCount) .. "/" .. tostring(qty))
            return false
        end

        if targetNpcData then
            if strictCapacity then
                local canReceive, reason = self:canNPCReceiveItem(targetNpcData, itemType, qty)
                if not canReceive then
                    local inv = sourcePlayer.getInventory and sourcePlayer:getInventory() or nil
                    if inv and inv.AddItems then
                        pcall(function()
                            inv:AddItems(itemType, qty)
                        end)
                    end
                    self:sendActionResult(notificationPlayer, targetId, false, "TradeEvent", reason or "Capacite insuffisante")
                    return false
                end
            end
            self:addItemToNPCInventory(targetNpcData, itemType, qty)
        elseif targetPlayer then
            local addedOk = self:addItemToPlayerInventory(targetPlayer, itemType, qty)
            if not addedOk then
                local inv = sourcePlayer.getInventory and sourcePlayer:getInventory() or nil
                if inv and inv.AddItems then
                    pcall(function()
                        inv:AddItems(itemType, qty)
                    end)
                end
                self:sendActionResult(notificationPlayer, targetId, false, "TradeEvent", "Inventaire joueur indisponible")
                return false
            end
        end

        if NPCQuestRuntime and NPCQuestRuntime.onGiftSuccess then
            NPCQuestRuntime:onGiftSuccess(sourcePlayer or player, qty)
        end
    end

    if sourceType == "player" and targetType == "npc" and (args.mode == "buy" or args.mode == "purchase") and targetNpcData then
        if not itemType then
            self:sendActionResult(notificationPlayer, targetId, false, "TradeEvent", "Objet demande manquant")
            return false
        end

        local quote = tradeQuote or NPCMemory.BuildTradeOffer(targetNpcData, "player", sourceId, {
            tick = args.tick or 0,
            basePrice = args.price or 10,
            baseId = args.baseId,
            clanNeed = args.clanNeed,
            personalNeed = args.personalNeed
        })
        local cost = math.max(1, tonumber((quote and quote.price) or args.price or args.value or qty) or qty)
        local removedCash, removedCount, currencyType = self:collectPlayerCurrencyPayment(sourcePlayer, cost)
        if not removedCash then
            self:sendActionResult(notificationPlayer, targetId, false, "TradeEvent", "Paiement insuffisant")
            return false
        end

        self:addNPCCash(targetNpcData, cost)
        local removedOk, removedFromNpc = self:removeItemFromNPCInventory(targetNpcData, itemType, qty)
        if not removedOk then
            if currencyType then
                self:addItemToPlayerInventory(sourcePlayer, currencyType, removedCount)
            end
            self:spendNPCCash(targetNpcData, cost)
            self:sendActionResult(notificationPlayer, targetId, false, "TradeEvent", "Stock PNJ insuffisant")
            return false
        end

        self:addItemToPlayerInventory(sourcePlayer, itemType, removedFromNpc)
    end

    if sourceType == "npc" and itemType then
        local sellMode = args.mode == "sell" or args.mode == "merchant" or args.mode == "broker" or args.mode == "trade"
        local cost = math.max(1, tonumber(args.price or args.value or qty) or qty)
        local removedOk, removedCount = self:removeItemFromNPCInventory(sourceNpcData, itemType, qty)
        if not removedOk then
            self:sendActionResult(notificationPlayer, targetId, false, "TradeEvent", "Stock PNJ insuffisant: " .. tostring(removedCount) .. "/" .. tostring(qty))
            return false
        end

        if sellMode and targetPlayer and not args.prepaid then
            local removedCash, removedPaid, currencyType = self:collectPlayerCurrencyPayment(targetPlayer, cost)
            if not removedCash then
                self:addItemToNPCInventory(sourceNpcData, itemType, qty)
                self:sendActionResult(notificationPlayer, targetId, false, "TradeEvent", "Paiement insuffisant")
                return false
            end
            self:addNPCCash(sourceNpcData, cost)
        end

        if targetNpcData then
            if strictCapacity then
                local canReceive, reason = self:canNPCReceiveItem(targetNpcData, itemType, qty)
                if not canReceive then
                    self:addItemToNPCInventory(sourceNpcData, itemType, qty)
                    self:sendActionResult(notificationPlayer, targetId, false, "TradeEvent", reason or "Capacite insuffisante")
                    return false
                end
            end
            self:addItemToNPCInventory(targetNpcData, itemType, qty)
        elseif targetPlayer then
            local addedOk = self:addItemToPlayerInventory(targetPlayer, itemType, qty)
            if not addedOk then
                self:addItemToNPCInventory(sourceNpcData, itemType, qty)
                self:sendActionResult(notificationPlayer, targetId, false, "TradeEvent", "Transfert vers joueur impossible")
                return false
            end
        end
    end

    local ok = self:recordDirectedExchange(sourceType, sourceId, targetType, targetId, {
        tick = args.tick or 0,
        mode = args.mode,
        value = args.value,
        price = args.price,
        itemType = itemType,
        quantity = qty,
        requested = args.requested,
        quote = tradeQuote
    })

    if ok then
        local socialTick = args.tick or tradeTick
        if sourceNpcData then
            registerSocialContactForNPC(sourceNpcData, targetType, targetId, "trade", socialTick, 0.65)
        end
        if targetNpcData then
            registerSocialContactForNPC(targetNpcData, sourceType, sourceId, "trade", socialTick, 0.65)
        end

        local socialPlayer = sourcePlayer or targetPlayer or player
        if socialPlayer then
            applyPlayerSocialRelief(socialPlayer, 0.8)
        end
    end

    if targetType == "npc" then
        self:sendActionResult(notificationPlayer, targetId, ok, "TradeEvent", ok and "Echange enregistre" or "Echec de l'echange")
    end

    if ok and sourceType == "player" and NPCQuestRuntime and NPCQuestRuntime.onTradeSuccess then
        NPCQuestRuntime:onTradeSuccess(sourcePlayer or player, args.mode)
        NPCQuestRuntime:sendJournal(sourcePlayer or player, "trade_event")
    end

    return ok
end

function NPCInteractionHooks:handleIntelRequest(player, args)
    if not NPCFactionManager or type(args) ~= "table" then
        return false
    end

    local npcId = args.npcId
    local playerId = (player and player.getUsername and player:getUsername()) or args.playerId
    if not npcId or not playerId then
        return false
    end

    local intel = NPCFactionManager:OfferIntelToPlayer(npcId, playerId)
    local npcData = self:getNPCData(npcId)
    if sendServerCommand then
        sendServerCommand(player, self.module, "IntelResponse", {
            npcId = npcId,
            intel = intel
        })
    end

    if npcData and intel ~= nil then
        registerSocialContactForNPC(npcData, "player", playerId, "dialogue", NPCFactionManager and NPCFactionManager.tickCounter or 0, 1.0)
    end
    applyPlayerSocialRelief(player, intel and 1.0 or 0.45)

    self:sendActionResult(player, npcId, intel ~= nil, "RequestIntel", intel and "Infos partagees" or "Le PNJ refuse de partager")

    if intel ~= nil and NPCQuestRuntime and NPCQuestRuntime.onIntelSuccess then
        NPCQuestRuntime:onIntelSuccess(player, npcId)
        NPCQuestRuntime:sendJournal(player, "intel")
    end

    return intel ~= nil
end

function NPCInteractionHooks:handleSnapshotRequest(player, args)
    if type(args) ~= "table" or not player then
        return false
    end

    local npcId = args.npcId
    if not npcId then
        return false
    end

    local playerId = player.getUsername and player:getUsername() or nil
    local snapshot = self:buildNpcSnapshot(npcId, playerId)
    if sendServerCommand then
        sendServerCommand(player, self.module, "NpcSnapshot", {
            npcId = npcId,
            snapshot = snapshot
        })
    end

    return snapshot ~= nil
end

function NPCInteractionHooks:isPlayerAlliedWithNPC(playerId, npcId)
    if not NPCFactionManager or not playerId or not npcId then
        return false
    end

    local pf = NPCFactionManager:getFactionOfPlayer(playerId)
    local nf = NPCFactionManager:getFactionOfNPC(npcId)
    if not pf or not nf then
        return false
    end

    local relation = NPCFactionManager:getRelation(pf, nf)
    return relation == NPCFactionManager.relation.ALLY
end

function NPCInteractionHooks:handleOrderAction(player, args)
    if not NPCFactionManager or type(args) ~= "table" then
        return false
    end

    local npcId = args.npcId
    local orderType = args.orderType
    local targetNpcData, targetEntry = self:getNPCData(npcId)
    if not npcId or not orderType or not targetNpcData then
        return false
    end

    local playerId = (player and player.getUsername and player:getUsername()) or args.playerId
    local allowed = isAdminPlayer(player) or self:isPlayerAlliedWithNPC(playerId, npcId)
    if not allowed then
        return false
    end

    local params = args.params or {}
    local mappedOrderType = orderType
    local serviceQuote = nil

    if NPCMemory and targetNpcData and targetNpcData.profession then
        local serviceType = tostring(args.serviceType or orderType or "trade")
        serviceQuote = NPCMemory.BuildServiceQuote(targetNpcData, {
            serviceType = serviceType,
            orderType = orderType,
            counterpartType = "player",
            counterpartId = playerId,
            baseId = params.baseId,
            clanNeed = params.clanNeed,
            personalNeed = params.personalNeed
        })
    end

    local serviceOrders = {
        build = true,
        cook = true,
        scavenge = true,
        study = true,
        guard = true,
        trade = true
    }

    if serviceQuote and serviceOrders[mappedOrderType] then
        local paid, amountPaidOrReason = self:consumeNPCServicePayment(targetNpcData, player, serviceQuote)
        if not paid then
            self:sendActionResult(player, npcId, false, "OrderAction", amountPaidOrReason ~= 0 and tostring(amountPaidOrReason) or ("Paiement requis: " .. tostring(serviceQuote.cost)))
            return false
        end
        params.serviceQuote = serviceQuote
        params.pricePaid = amountPaidOrReason
    end

    if orderType == "tactical_keep_distance" then
        mappedOrderType = "follow"
        params.followPlayerId = playerId
        params.desiredDistance = math.max(4, tonumber(params.desiredDistance) or 7)
        params.maxDistance = math.max(params.desiredDistance + 4, tonumber(params.maxDistance) or 12)
    elseif orderType == "tactical_cover" then
        mappedOrderType = "defend"
        params.coverPlayerId = playerId
        params.coverRadius = math.max(3, tonumber(params.coverRadius) or 6)
    elseif orderType == "tactical_loot_target" then
        mappedOrderType = "scavenge"
        params.targetItemHint = tostring(params.targetItemHint or "")
    elseif orderType == "tactical_preset_defensive_escort" then
        mappedOrderType = "defend"
        params.coverPlayerId = playerId
        params.coverRadius = 9
        params.aggressiveCover = false
        params.escortMode = true
    elseif orderType == "tactical_preset_discreet_loot" then
        mappedOrderType = "scavenge"
        params.targetItemHint = tostring(params.targetItemHint or "food")
        params.stealthScavenge = true
        params.riskyThreshold = 25
    elseif orderType == "tactical_preset_aggressive_cover" then
        mappedOrderType = "defend"
        params.coverPlayerId = playerId
        params.coverRadius = 4
        params.aggressiveCover = true
        params.engageThreshold = 15
    end
    
    if npcId and targetEntry and (orderType:find("preset") or orderType:find("tactical")) then
        local targetData = self:getNPCData(npcId)
        if targetData then
            targetData.lastTacticalProfile = orderType
        end
    end

    if targetEntry and targetEntry.entity then
        params.center = params.center or {
            x = targetEntry.entity:getX(),
            y = targetEntry.entity:getY(),
            z = math.floor(targetEntry.entity:getZ())
        }
    end
    params.automatic = false
    params.expiresTick = params.expiresTick or (NPCFactionManager.tickCounter + 240)

    local ok = NPCFactionManager:issueOrder("player", playerId or "unknown", { npcId }, mappedOrderType, params)
    self:sendActionResult(player, npcId, ok, "OrderAction", ok and "Ordre envoye" or "Ordre refuse")
    return ok
end

function NPCInteractionHooks:handleAdminAction(player, args)
    if type(args) ~= "table" or not isAdminPlayer(player) then
        return false
    end

    local action = args.action
    if action == "setGameplayProfile" and NPCTuningProfiles and NPCTuningProfiles.setActiveProfile then
        local desired = tostring(args.profile or args.value or "")
        local okSet, active = NPCTuningProfiles:setActiveProfile(desired)
        self:sendActionResult(player, args.npcId, okSet, "AdminAction", okSet and ("Profil gameplay actif: " .. tostring(active)) or ("Profil inconnu: " .. desired))
        return okSet
    end

    if action == "getGameplayProfile" and NPCTuningProfiles and NPCTuningProfiles.getActiveProfileName then
        local active = NPCTuningProfiles:getActiveProfileName()
        self:sendActionResult(player, args.npcId, true, "AdminAction", "Profil gameplay actif: " .. tostring(active))
        return true
    end

    if action == "listGameplayProfiles" and NPCTuningProfiles and NPCTuningProfiles.listProfiles then
        local list = NPCTuningProfiles:listProfiles() or {}
        local names = {}
        for i = 1, #list do
            names[#names + 1] = tostring(list[i].id)
        end
        self:sendActionResult(player, args.npcId, true, "AdminAction", "Profils disponibles: " .. table.concat(names, ", "))
        return true
    end

    local npcId = args.npcId
    local npcData = self:getNPCData(npcId)
    if not npcData or not action then
        return false
    end

    if action == "setStat" and npcData.stats and args.statName ~= nil and args.value ~= nil then
        local v = tonumber(args.value) or 0
        npcData.stats[args.statName] = math.max(0, math.min(100, v))
        self:sendActionResult(player, npcId, true, "AdminAction", "Stat modifiee")
        return true
    end

    if action == "setBehavior" then
        npcData.traits = npcData.traits or {}
        npcData.traits.personality = npcData.traits.personality or {}
        local p = npcData.traits.personality
        if args.preset == "friendly" then
            p.brutality = 10
            p.opportunism = 20
            p.socialDrive = 80
            p.loneWolf = 20
        elseif args.preset == "hostile" then
            p.brutality = 85
            p.opportunism = 75
            p.socialDrive = 25
            p.loneWolf = 65
        elseif args.preset == "survivor" then
            p.brutality = 45
            p.opportunism = 55
            p.socialDrive = 45
            p.loneWolf = 55
        end
        self:sendActionResult(player, npcId, true, "AdminAction", "Comportement mis a jour")
        return true
    end

    if action == "setPersonality" and npcData.traits and npcData.traits.personality then
        local p = npcData.traits.personality
        if args.socialDrive ~= nil then
            p.socialDrive = clamp(tonumber(args.socialDrive) or p.socialDrive or 50, 0, 100)
        end
        if args.loneWolf ~= nil then
            p.loneWolf = clamp(tonumber(args.loneWolf) or p.loneWolf or 50, 0, 100)
        end
        if args.adaptability ~= nil then
            p.adaptability = clamp(tonumber(args.adaptability) or p.adaptability or 50, 0, 100)
        end
        if args.brutality ~= nil then
            p.brutality = clamp(tonumber(args.brutality) or p.brutality or 50, 0, 100)
        end
        if args.opportunism ~= nil then
            p.opportunism = clamp(tonumber(args.opportunism) or p.opportunism or 50, 0, 100)
        end
        self:sendActionResult(player, npcId, true, "AdminAction", "Personnalite ajustee")
        return true
    end

    if action == "addItem" and args.itemType then
        npcData.inventory = npcData.inventory or { items = {}, currentWeight = 0, maxWeight = 14 }
        npcData.inventory.items = npcData.inventory.items or {}
        npcData.inventory.items[#npcData.inventory.items + 1] = {
            type = tostring(args.itemType),
            quantity = math.max(1, tonumber(args.quantity) or 1),
            condition = math.max(1, math.min(100, tonumber(args.condition) or 100))
        }
        npcData.inventory.currentWeight = (npcData.inventory.currentWeight or #npcData.inventory.items) + 1
        self:sendActionResult(player, npcId, true, "AdminAction", "Objet ajoute")
        return true
    end

    if action == "clearInventory" then
        npcData.inventory = npcData.inventory or {}
        npcData.inventory.items = {}
        npcData.inventory.currentWeight = 0
        self:sendActionResult(player, npcId, true, "AdminAction", "Inventaire vide")
        return true
    end

    if action == "heal" then
        npcData.health = npcData.health or {}
        npcData.health.current = 100
        npcData.health.pain = 0
        npcData.health.fatigue = 0
        npcData.health.isBitten = false
        npcData.health.isHidingBite = false
        if NPC_NetworkServer and type(NPC_NetworkServer.broadcastNPCFx) == "function" then
            NPC_NetworkServer:broadcastNPCFx(npcId, "npc_medical", npcData)
        end
        self:sendActionResult(player, npcId, true, "AdminAction", "PNJ soigne")
        return true
    end

    if action == "toggleBitten" then
        npcData.health = npcData.health or {}
        npcData.health.isBitten = not (npcData.health.isBitten == true)
        npcData.health.isHidingBite = npcData.health.isBitten == true
        self:sendActionResult(player, npcId, true, "AdminAction", "Etat morsure inverse")
        return true
    end

    self:sendActionResult(player, npcId, false, "AdminAction", "Action admin inconnue")

    return false
end

function NPCInteractionHooks:RecordNPCToNPC(sourceNpcId, targetNpcId, actionType, args)
    return self:recordActorImpactOnNPC("npc", sourceNpcId, targetNpcId, actionType, args or {})
end

function NPCInteractionHooks:RegisterNPCToNPCExchange(sourceNpcId, targetNpcId, exchange)
    return self:recordDirectedExchange("npc", sourceNpcId, "npc", targetNpcId, exchange or {})
end

function NPCInteractionHooks:handleOllamaRequest(player, args)
    if not player or not args then
        return false
    end

    local npcId = args.npcId
    local userMessage = args.userMessage or ""
    local playerLanguage = args.playerLanguage
    
    if not npcId or #userMessage == 0 then
        return false
    end

    local npcData = self:getNPCData(npcId)
    if not npcData then
        -- En mode SOLO, les NPCs sont spawnes cote CLIENT (NPCSpawner_SOLO.lua).
        -- Le serveur n'a pas leur donnees dans NPCSpawner.activeNPCs.
        -- Solution: utiliser OllamaBridge sans contexte NPC (npcData=nil = fallback generique).
        local okOllama, OllamaBridge = pcall(require, "OllamaBridge")
        if not okOllama or not OllamaBridge then
            self:sendOllamaResponse(player, npcId, "Je n'ai rien a vous dire.", false)
            return true
        end
        local function onFallbackComplete(response)
            self:sendOllamaResponse(player, npcId, response, false)
        end
        OllamaBridge:generateDialogue(nil, npcId, userMessage, onFallbackComplete)
        return true
    end

    if playerLanguage and #tostring(playerLanguage) > 0 then
        npcData._dialogueLanguage = tostring(playerLanguage)
    end

    local playerId = (player and player.getUsername and player:getUsername()) or args.playerId
    registerSocialContactForNPC(npcData, "player", playerId or "unknown", "dialogue", NPCFactionManager and NPCFactionManager.tickCounter or 0, 1.15)
    applyPlayerSocialRelief(player, 1.2)

    local okOllama, OllamaBridge = pcall(require, "OllamaBridge")
    if not okOllama or not OllamaBridge then
        self:sendOllamaResponse(player, npcId, "Ollama non disponible", true)
        return false
    end

    local function onOllamaComplete(response)
        self:sendOllamaResponse(player, npcId, response, false)
    end

    OllamaBridge:generateDialogue(npcData, npcId, userMessage, onOllamaComplete)
    return true
end

function NPCInteractionHooks:sendOllamaResponse(player, npcId, response, isError)
    if not player or not sendServerCommand then
        return
    end

    sendServerCommand(player, self.module, "OllamaResponse", {
        npcId = npcId,
        response = response,
        isError = isError == true
    })
end

function NPCInteractionHooks:sendBusinessQuoteResponse(player, npcId, quote, request)
    if not player or not sendServerCommand then
        return
    end

    sendServerCommand(player, self.module, "BusinessQuoteResponse", {
        npcId = npcId,
        quote = quote,
        request = request,
        ok = quote ~= nil
    })
end

function NPCInteractionHooks:isQuoteCooldownReady(playerId, npcId)
    local cooldown = math.max(1, math.floor(tonumber(self.quoteCooldownSec) or 6))
    local key = tostring(playerId or "unknown") .. "|" .. tostring(npcId or "unknown")
    local now = (os and os.time and os.time()) or 0
    local last = tonumber(self.quoteCooldownByKey[key] or 0) or 0
    if last > 0 and (now - last) < cooldown then
        return false, key, cooldown - (now - last)
    end
    self.quoteCooldownByKey[key] = now
    return true, key, 0
end

function NPCInteractionHooks:handleBusinessQuoteRequest(player, args)
    if type(args) ~= "table" then
        return false
    end

    local npcId = args.npcId
    local serviceType = tostring(args.serviceType or args.orderType or "trade"):lower()
    local playerId = (player and player.getUsername and player:getUsername()) or args.playerId

    if PHNPC_Logger and PHNPC_Logger.info then
        PHNPC_Logger:info("NPCInteractionHooks", "handleBusinessQuoteRequest", "Incoming business quote request", {
            requestId = args.requestId,
            npcId = npcId,
            player = playerId,
            serviceType = serviceType,
            itemType = args.itemType,
            quantity = args.quantity
        })
    end

    local npcData = self:getNPCData(npcId)
    if not npcId or not npcData then
        self:sendBusinessQuoteResponse(player, npcId, nil, args)
        if PHNPC_Logger and PHNPC_Logger.warn then
            PHNPC_Logger:warn("NPCInteractionHooks", "handleBusinessQuoteRequest", "Quote request rejected: NPC not found", {
                requestId = args.requestId,
                npcId = npcId,
                player = playerId
            })
        end
        return false
    end

    local ready, _, waitSec = self:isQuoteCooldownReady(playerId, npcId)
    if not ready then
        self:sendBusinessQuoteResponse(player, npcId, nil, args)
        self:sendActionResult(player, npcId, false, "BusinessQuote", "Attendez " .. tostring(waitSec) .. "s avant un nouveau devis")
        if PHNPC_Logger and PHNPC_Logger.warn then
            PHNPC_Logger:warn("NPCInteractionHooks", "handleBusinessQuoteRequest", "Quote request rejected: cooldown", {
                requestId = args.requestId,
                npcId = npcId,
                player = playerId,
                waitSec = waitSec
            })
        end
        return false
    end

    local eligibility = NPCMemory and NPCMemory.CheckBusinessEligibility and NPCMemory.CheckBusinessEligibility(npcData, {
        serviceType = serviceType,
        orderType = args.orderType,
        itemType = args.itemType,
        quantity = args.quantity,
        marketCategory = args.marketCategory,
        targetHint = args.targetHint,
        buildSiteId = args.buildSiteId,
        baseId = args.baseId,
        clanNeed = args.clanNeed,
        personalNeed = args.personalNeed
    }) or nil

    if eligibility and eligibility.allowed ~= true then
        self:sendBusinessQuoteResponse(player, npcId, nil, args)
        local reasonMap = {
            sans_metier = "Ce PNJ n'a pas de metier.",
            metier_non_debloque = "Metier non debloque: niveau max requis.",
            metier_non_compatible = "Ce service ne correspond pas au metier du PNJ.",
            choix_autonome_refus = "Le PNJ refuse pour le moment de faire ce metier."
        }
        self:sendActionResult(player, npcId, false, "BusinessQuote", reasonMap[eligibility.reason] or "Service indisponible", { requestId = args.requestId })
        if PHNPC_Logger and PHNPC_Logger.warn then
            PHNPC_Logger:warn("NPCInteractionHooks", "handleBusinessQuoteRequest", "Quote request rejected: eligibility", {
                requestId = args.requestId,
                npcId = npcId,
                player = playerId,
                reason = eligibility.reason,
                role = eligibility.role,
                level = eligibility.level,
                maxLevel = eligibility.maxLevel,
                willingness = eligibility.willingness
            })
        end
        return false
    end

    local marketState = nil
    if NPCFactionManager and NPCFactionManager.BuildLocalMarketState then
        marketState = NPCFactionManager:BuildLocalMarketState(npcId)
    end

    local quote = NPCMemory and NPCMemory.BuildServiceQuote and NPCMemory.BuildServiceQuote(npcData, {
        serviceType = serviceType,
        orderType = args.orderType,
        itemType = args.itemType,
        quantity = args.quantity,
        marketCategory = args.marketCategory,
        targetHint = args.targetHint,
        buildSiteId = args.buildSiteId,
        baseId = args.baseId,
        price = args.price,
        marketState = marketState,
        counterpartType = "player",
        counterpartId = playerId,
        clanNeed = args.clanNeed,
        personalNeed = args.personalNeed
    }) or nil

    self:sendBusinessQuoteResponse(player, npcId, quote, args)
    if PHNPC_Logger and PHNPC_Logger.log then
        local level = quote and "OK" or "WARN"
        PHNPC_Logger:log(level, "NPCInteractionHooks", "handleBusinessQuoteRequest", quote and "Quote created" or "Quote unavailable", {
            requestId = args.requestId,
            npcId = npcId,
            player = playerId,
            serviceType = serviceType,
            hasQuote = quote ~= nil,
            totalCost = quote and quote.cost or nil
        })
    end
    return quote ~= nil
end

function NPCInteractionHooks:handleBusinessOrderRequest(player, args)
    if type(args) ~= "table" then
        return false
    end

    local npcId = args.npcId
    local npcData = self:getNPCData(npcId)
    local playerId = (player and player.getUsername and player:getUsername()) or args.playerId

    if PHNPC_Logger and PHNPC_Logger.info then
        PHNPC_Logger:info("NPCInteractionHooks", "handleBusinessOrderRequest", "Incoming business order request", {
            requestId = args.requestId,
            npcId = npcId,
            player = playerId,
            serviceType = args.serviceType,
            itemType = args.itemType,
            quantity = args.quantity
        })
    end

    if not npcId or not npcData then
        self:sendActionResult(player, npcId, false, "BusinessOrder", "PNJ introuvable", { requestId = args.requestId })
        if PHNPC_Logger and PHNPC_Logger.warn then
            PHNPC_Logger:warn("NPCInteractionHooks", "handleBusinessOrderRequest", "Order request rejected: NPC not found", {
                requestId = args.requestId,
                npcId = npcId,
                player = playerId
            })
        end
        return false
    end

    local serviceType = tostring(args.serviceType or args.orderType or "trade"):lower()
    local eligibility = NPCMemory and NPCMemory.CheckBusinessEligibility and NPCMemory.CheckBusinessEligibility(npcData, {
        serviceType = serviceType,
        orderType = args.orderType,
        itemType = args.itemType,
        quantity = args.quantity,
        marketCategory = args.marketCategory,
        targetHint = args.targetHint,
        buildSiteId = args.buildSiteId,
        baseId = args.baseId,
        clanNeed = args.clanNeed,
        personalNeed = args.personalNeed
    }) or nil

    if eligibility and eligibility.allowed ~= true then
        local reasonMap = {
            sans_metier = "Ce PNJ n'a pas de metier.",
            metier_non_debloque = "Metier non debloque: niveau max requis.",
            metier_non_compatible = "Ce service ne correspond pas au metier du PNJ.",
            choix_autonome_refus = "Le PNJ refuse pour le moment de faire ce metier."
        }
        self:sendActionResult(player, npcId, false, "BusinessOrder", reasonMap[eligibility.reason] or "Service indisponible", { requestId = args.requestId })
        return false
    end

    local marketState = nil
    if NPCFactionManager and NPCFactionManager.BuildLocalMarketState then
        marketState = NPCFactionManager:BuildLocalMarketState(npcId)
    end

    local quote = NPCMemory and NPCMemory.BuildServiceQuote and NPCMemory.BuildServiceQuote(npcData, {
        serviceType = serviceType,
        orderType = args.orderType,
        itemType = args.itemType,
        quantity = args.quantity,
        marketCategory = args.marketCategory,
        targetHint = args.targetHint,
        buildSiteId = args.buildSiteId,
        baseId = args.baseId,
        price = args.price,
        marketState = marketState,
        counterpartType = "player",
        counterpartId = playerId,
        clanNeed = args.clanNeed,
        personalNeed = args.personalNeed
    }) or nil

    if not quote then
        self:sendActionResult(player, npcId, false, "BusinessOrder", "Devis indisponible", { requestId = args.requestId })
        if PHNPC_Logger and PHNPC_Logger.warn then
            PHNPC_Logger:warn("NPCInteractionHooks", "handleBusinessOrderRequest", "Order request rejected: quote unavailable", {
                requestId = args.requestId,
                npcId = npcId,
                player = playerId,
                serviceType = serviceType
            })
        end
        return false
    end

    local ok = false
    local params = {
        automatic = false,
        baseId = args.baseId,
        buildSiteId = args.buildSiteId,
        targetHint = args.targetHint,
        itemType = args.itemType,
        quantity = args.quantity,
        serviceType = serviceType,
        businessQuote = quote,
        deliveryToPlayerId = playerId,
        pricePaid = nil,
        expiresTick = (NPCFactionManager and NPCFactionManager.tickCounter or 0) + 260
    }

    if serviceType == "build" then
        local paid, paidAmount = self:consumeNPCServicePayment(npcData, player, quote)
        if not paid then
            self:sendActionResult(player, npcId, false, "BusinessOrder", "Paiement requis: " .. tostring(quote.cost), { requestId = args.requestId })
            return false
        end
        local base = nil
        if NPCFactionManager and NPCFactionManager.getBaseOfNPC then
            base = select(1, NPCFactionManager:getBaseOfNPC(npcId))
        end
        if base and NPCFactionManager and NPCFactionManager.reserveBuildSiteForNPC then
            local site = NPCFactionManager:reserveBuildSiteForNPC(base, npcId)
            if site then
                params.buildSiteId = site.id
                params.center = { x = site.x, y = site.y, z = site.z }
            else
                params.center = base.center
            end
            params.baseId = base.id
        end
        params.businessService = "build"
        params.productionPlan = quote.productionPlan
        params.pricePaid = paidAmount
        ok = NPCFactionManager and NPCFactionManager:issueOrder("player", playerId or "unknown", { npcId }, NPCFactionManager.orderType.BUILD, params) or false
    elseif serviceType == "craft" then
        local paid, paidAmount = self:consumeNPCServicePayment(npcData, player, quote)
        if not paid then
            self:sendActionResult(player, npcId, false, "BusinessOrder", "Paiement requis: " .. tostring(quote.cost), { requestId = args.requestId })
            return false
        end
        params.businessService = "craft"
        params.productionPlan = quote.productionPlan
        params.pricePaid = paidAmount
        ok = NPCFactionManager and NPCFactionManager:issueOrder("player", playerId or "unknown", { npcId }, NPCFactionManager.orderType.STUDY, params) or false
    elseif serviceType == "buy" or serviceType == "trade" then
        if not args.itemType then
            self:sendActionResult(player, npcId, false, "BusinessOrder", "Objet requis", { requestId = args.requestId })
            return false
        end
        ok = self:handleTradeEvent(player, {
            sourceType = "npc",
            sourceId = npcId,
            targetType = "player",
            targetId = playerId,
            mode = "sell",
            itemType = args.itemType,
            quantity = math.max(1, tonumber(args.quantity) or 1),
            price = quote.cost,
            value = quote.cost,
            requested = args.targetHint,
            prepaid = false,
            tick = NPCFactionManager and NPCFactionManager.tickCounter or 0
        })
    else
        local paid, paidAmount = self:consumeNPCServicePayment(npcData, player, quote)
        if not paid then
            self:sendActionResult(player, npcId, false, "BusinessOrder", "Paiement requis: " .. tostring(quote.cost), { requestId = args.requestId })
            return false
        end
        params.businessService = serviceType
        params.pricePaid = paidAmount
        ok = NPCFactionManager and NPCFactionManager:issueOrder("player", playerId or "unknown", { npcId }, NPCFactionManager.orderType.STUDY, params) or false
    end

    self:sendActionResult(player, npcId, ok, "BusinessOrder", ok and "Commande metier validee" or "Commande metier refusee", { requestId = args.requestId })

    if ok and NPCQuestRuntime and NPCQuestRuntime.onTradeSuccess then
        NPCQuestRuntime:onTradeSuccess(player, serviceType)
        NPCQuestRuntime:sendJournal(player, "business_order")
    end

    return ok
end

function NPCInteractionHooks:onClientCommand(module, command, player, args)
    if module ~= self.module then
        return
    end

    if command == self.interactionCommand then
        self:handleMemoryEvent(player, args)
    elseif command == self.tradeCommand then
        self:handleTradeEvent(player, args)
    elseif command == self.intelCommand then
        self:handleIntelRequest(player, args)
    elseif command == self.orderCommand then
        self:handleOrderAction(player, args)
    elseif command == self.adminCommand then
        self:handleAdminAction(player, args)
    elseif command == self.snapshotCommand then
        self:handleSnapshotRequest(player, args)
    elseif command == "BusinessQuoteRequest" then
        self:handleBusinessQuoteRequest(player, args)
    elseif command == "BusinessOrderRequest" then
        self:handleBusinessOrderRequest(player, args)
    elseif command == "QuestJournalRequest" then
        if NPCQuestRuntime and NPCQuestRuntime.sendJournal then
            NPCQuestRuntime:sendJournal(player, "manual_request")
        end
    elseif command == "QuestResetRequest" then
        if NPCQuestRuntime and NPCQuestRuntime.reset then
            local ok = NPCQuestRuntime:reset(player)
            if ok then
                NPCQuestRuntime:sendJournal(player, "reset")
            end
            self:sendActionResult(player, nil, ok, "Quest", ok and "Journal quetes reinitialise" or "Echec reset quetes")
        end
    elseif command == self.ollamaCommand then
        self:handleOllamaRequest(player, args)
    end
end

function NPCInteractionHooks:start()
    if Events and Events.OnClientCommand then
        Events.OnClientCommand.Add(function(module, command, player, args)
            NPCInteractionHooks:onClientCommand(module, command, player, args)
        end)
    end
end

NPCInteractionHooks:start()

return NPCInteractionHooks
