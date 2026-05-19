--[[
    Project Humain : Dynamic_NPC_Overhaul
    NPCMemoryRuntime.lua

    Runtime serveur de perception sociale.
    Convertit des evenements de gameplay proches en signaux memoire:
    - aide/don probable
    - vol probable
    - aide en combat contre zombies
    - demonstration de force du joueur
]]

local hasSpawner, NPCSpawner = pcall(require, "NPCSpawner")
if not hasSpawner then
    NPCSpawner = nil
end

local hasMemory, NPCMemory = pcall(require, "NPCMemory")
if not hasMemory then
    NPCMemory = nil
end

local NPCMemoryRuntime = {
    tickCounter = 0,
    updateEveryTicks = 20,
    cachedZombieList = nil,
    playerObserveRange = 10,
    combatObserveRange = 12,
    inventoryObserveRange = 4,
    explicitPriorityTicks = 90,
    recentExplicit = {},
    snapshots = {}
}

local function actorKey(actorType, actorId)
    return tostring(actorType or "unknown") .. ":" .. tostring(actorId)
end

local function explicitClass(actionType)
    if actionType == "gift" or actionType == "help" or actionType == "theft" or actionType == "stole" or actionType == "free" then
        return "inventory"
    end
    if actionType == "combat_help" then
        return "combat"
    end
    if actionType == "strength" then
        return "strength"
    end
    if actionType == "hostile" or actionType == "assault" or actionType == "threat" or actionType == "insult" then
        return "hostility"
    end
    return tostring(actionType or "unknown")
end

local function sqDistance2D(x1, y1, x2, y2)
    local dx = x1 - x2
    local dy = y1 - y2
    return math.sqrt(dx * dx + dy * dy)
end

local function getOnlinePlayerList()
    local players = {}

    if type(getOnlinePlayers) == "function" then
        local online = getOnlinePlayers()
        if online and online.size then
            for i = 0, online:size() - 1 do
                players[#players + 1] = online:get(i)
            end
            return players
        end
    end

    if type(getNumActivePlayers) == "function" and type(getSpecificPlayer) == "function" then
        for i = 0, getNumActivePlayers() - 1 do
            local p = getSpecificPlayer(i)
            if p then
                players[#players + 1] = p
            end
        end
    end

    return players
end

local function getEntityPos(entity, fallback)
    local fx = fallback and fallback.x or 0
    local fy = fallback and fallback.y or 0
    local fz = fallback and fallback.z or 0

    if not entity then
        return fx, fy, fz
    end

    local x = (entity.getX and entity:getX()) or fx
    local y = (entity.getY and entity:getY()) or fy
    local z = (entity.getZ and math.floor(entity:getZ())) or fz
    return x, y, z
end

local function countZombiePressureAround(zombies, x, y, z, radius)
    if not zombies or not zombies.size then
        return 0
    end

    local count = 0
    for i = 0, zombies:size() - 1 do
        local zombie = zombies:get(i)
        if zombie and zombie.getX and zombie.getY and zombie.getZ then
            if math.floor(zombie:getZ()) == math.floor(z) then
                local d = sqDistance2D(x, y, zombie:getX(), zombie:getY())
                if d <= radius then
                    count = count + 1
                end
            end
        end
    end

    return count
end

local function getInventoryUnits(npcData)
    local inventory = npcData and npcData.inventory
    local items = inventory and inventory.items
    if type(items) ~= "table" then
        return 0
    end

    local count = 0
    for i = 1, #items do
        local item = items[i]
        count = count + (item and item.quantity or 1)
    end
    return count
end

function NPCMemoryRuntime:getObservedPlayersNearNPC(npcEntry)
    local players = getOnlinePlayerList()
    local ex, ey, ez = getEntityPos(npcEntry.entity, npcEntry)
    local observed = {}

    for i = 1, #players do
        local player = players[i]
        if player and player.getX and player.getY and player.getZ then
            if math.floor(player:getZ()) == math.floor(ez) then
                local d = sqDistance2D(ex, ey, player:getX(), player:getY())
                if d <= self.playerObserveRange then
                    observed[#observed + 1] = {
                        player = player,
                        id = (player.getUsername and player:getUsername()) or tostring(i),
                        distance = d
                    }
                end
            end
        end
    end

    table.sort(observed, function(a, b)
        return a.distance < b.distance
    end)
    return observed
end

function NPCMemoryRuntime:markExplicitInteraction(targetNpcId, actorType, actorId, actionType, tick)
    local npcKey = tostring(targetNpcId)
    local aKey = actorKey(actorType, actorId)
    self.recentExplicit[npcKey] = self.recentExplicit[npcKey] or {}
    self.recentExplicit[npcKey][aKey] = self.recentExplicit[npcKey][aKey] or {}
    self.recentExplicit[npcKey][aKey][explicitClass(actionType)] = tick or self.tickCounter
end

function NPCMemoryRuntime:hasRecentExplicit(targetNpcId, actorType, actorId, className)
    local npcBucket = self.recentExplicit[tostring(targetNpcId)]
    if not npcBucket then
        return false
    end

    local actorBucket = npcBucket[actorKey(actorType, actorId)]
    if not actorBucket then
        return false
    end

    local seenTick = actorBucket[className]
    if not seenTick then
        return false
    end

    return (self.tickCounter - seenTick) <= self.explicitPriorityTicks
end

function NPCMemoryRuntime:observePlayerStrength(npcData, observed, zombiePressure)
    if not NPCMemory or not observed then
        return
    end

    local player = observed.player
    local strengthScore = 10
    if player.getPerkLevel and Perks then
        local ok, score = pcall(function()
            return player:getPerkLevel(Perks.Strength)
        end)
        if ok and score then
            strengthScore = strengthScore + (tonumber(score) or 0) * 8
        end
    end

    if zombiePressure >= 3 then
        strengthScore = strengthScore + 20
    end

    NPCMemory.RecordPlayerStrengthObservation(npcData, observed.id, {
        strengthScore = strengthScore,
        tick = self.tickCounter
    })
end

function NPCMemoryRuntime:observeCombatHelp(npcId, npcData, snapshot, currentPressure, observed)
    if not NPCMemory or not observed then
        return
    end

    if self:hasRecentExplicit(npcId, "player", observed.id, "combat") then
        return
    end

    local prevPressure = snapshot and snapshot.zombiePressure or 0
    local fsmState = snapshot and snapshot.fsmState or nil
    local underThreat = fsmState == "Combat" or fsmState == "Flee" or prevPressure >= 2

    if underThreat and prevPressure >= 2 and currentPressure < prevPressure then
        NPCMemory.RecordPlayerCombatHelp(npcData, observed.id, {
            tick = self.tickCounter,
            value = math.min(28, (prevPressure - currentPressure) * 10),
            zombieCount = prevPressure
        })
    end
end

function NPCMemoryRuntime:observeInventoryDelta(npcId, npcData, snapshot, currentUnits, observed)
    if not NPCMemory or not observed then
        return
    end

    if self:hasRecentExplicit(npcId, "player", observed.id, "inventory") then
        return
    end

    local prevUnits = snapshot and snapshot.inventoryUnits or currentUnits
    local delta = currentUnits - prevUnits
    if delta == 0 then
        return
    end

    local state = snapshot and snapshot.fsmState or ""
    local consuming = (state == "Survive") or (state == "Combat")

    if delta > 0 then
        NPCMemory.RecordPlayerHelp(npcData, observed.id, {
            tick = self.tickCounter,
            value = math.min(20, delta * 8),
            reason = "gift_or_supply"
        })
    elseif delta < 0 and not consuming then
        NPCMemory.RecordPlayerTheft(npcData, observed.id, {
            tick = self.tickCounter,
            value = math.min(24, math.abs(delta) * 8),
            itemType = "unknown_taken"
        })
    end
end

function NPCMemoryRuntime:observeOne(npcId, npcEntry)
    local npcData = npcEntry and npcEntry.data
    if not npcData or not NPCMemory then
        return
    end

    local observedPlayers = self:getObservedPlayersNearNPC(npcEntry)
    local primary = observedPlayers[1]

    local ex, ey, ez = getEntityPos(npcEntry.entity, npcEntry)
    local currentPressure = countZombiePressureAround(self.cachedZombieList, ex, ey, ez, self.combatObserveRange)
    local currentUnits = getInventoryUnits(npcData)
    local md = npcEntry.entity and npcEntry.entity.getModData and npcEntry.entity:getModData() or nil
    local fsmState = md and md.PH_FSM and md.PH_FSM.state or nil

    local snapshot = self.snapshots[npcId] or {}

    if primary and primary.distance <= self.playerObserveRange then
        self:observePlayerStrength(npcData, primary, currentPressure)
        self:observeCombatHelp(npcId, npcData, snapshot, currentPressure, primary)
        if primary.distance <= self.inventoryObserveRange then
            self:observeInventoryDelta(npcId, npcData, snapshot, currentUnits, primary)
        end
    end

    self.snapshots[npcId] = {
        inventoryUnits = currentUnits,
        zombiePressure = currentPressure,
        fsmState = fsmState,
        tick = self.tickCounter
    }
end

function NPCMemoryRuntime:cleanupSnapshots(activeNPCs)
    for npcId in pairs(self.snapshots) do
        if not activeNPCs[npcId] then
            self.snapshots[npcId] = nil
        end
    end

    for npcId in pairs(self.recentExplicit) do
        if not activeNPCs[npcId] then
            self.recentExplicit[npcId] = nil
        end
    end
end

function NPCMemoryRuntime:update()
    self.tickCounter = self.tickCounter + 1
    if (self.tickCounter % self.updateEveryTicks) ~= 0 then
        return
    end

    if not NPCSpawner or type(NPCSpawner.activeNPCs) ~= "table" or not NPCMemory then
        return
    end

    local cell = getCell and getCell() or nil
    self.cachedZombieList = (cell and cell.getZombieList and cell:getZombieList()) or nil

    self:cleanupSnapshots(NPCSpawner.activeNPCs)

    for npcId, entry in pairs(NPCSpawner.activeNPCs) do
        self:observeOne(npcId, entry)
    end
end

function NPCMemoryRuntime:start()
    if Events and Events.OnTick then
        Events.OnTick.Add(function()
            NPCMemoryRuntime:update()
        end)
    end
end

NPCMemoryRuntime:start()

return NPCMemoryRuntime
