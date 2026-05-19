if not isServer() then return {} end

--[[
    NPCSpawner_SOLO.lua
    Dynamic NPC Overhaul v2.1 - SOLO MODE ONLY
    
    VERSION: SOLO-ONLY (simplified, no network replication)
    PURPOSE: Handle NPC spawn/despawn in single-player games
    
    Features:
    - NPC spawn near player
    - NPC despawn when far
    - Dormancy management
    - NO network sync (single-player only)
    - NO admin commands/replication
]]


local hasModel, NPCDataModel = pcall(require, "NPCDataModel")
local hasConfigManager, PHNPC_ConfigManager = pcall(require, "PHNPC_ConfigManager")
local hasLogger, PHNPC_Logger = pcall(require, "PHNPC_Logger")

if not hasModel then NPCDataModel = nil end
if not hasConfigManager then PHNPC_ConfigManager = _G.PHNPC_ConfigManager end
if not hasLogger then PHNPC_Logger = _G.PHNPC_Logger end

local STATE_KEY = "PH_DynamicNPC_Overhaul_State"
local CHUNK_SIZE = 10

local NPCSpawner_SOLO = {
    activeNPCs = {},
    dormantNPCs = {},
    activeChunkPool = {},
    activeChunkList = {},
    maxActiveNPCs = 12,
    perPlayerBudget = 4,
    maxSpawnsPerCycle = 6,
    spawnRadius = 32,
    despawnRadius = 48,
    minSpawnDistance = 14,
    spawnAttemptsPerCycle = 6,
    tickCounter = 0,
    updateEveryTicks = 150,
    saveEveryTicks = 1800,
    dormantTTLticks = 21600,
    maxDormantRecords = 2000,
    forcedOutfit = nil,
    markerColor = { r = 0.15, g = 1.00, b = 0.20, a = 1.00 },
    lastSpawnFailureReason = "none",
    lastSpawnFailureTick = 0,
    fallbackIdCounter = 0,
    loadedPersistence = false
}

local maleHair = { "Bald", "BuzzCut", "Messy", "Short", "SidePart" }
local femaleHair = { "Bob", "Long", "PonyTail", "Messy", "Short" }
local skinTones = {
    { r = 0.96, g = 0.82, b = 0.70 }, { r = 0.86, g = 0.67, b = 0.52 },
    { r = 0.74, g = 0.55, b = 0.40 }, { r = 0.56, g = 0.40, b = 0.30 },
    { r = 0.42, g = 0.30, b = 0.22 }
}

-- ============================================================================
-- CORE UTILITY FUNCTIONS
-- ============================================================================

local function randInt(minValue, maxValue)
    if type(ZombRand) == "function" then
        return minValue + ZombRand((maxValue - minValue) + 1)
    end
    return math.random(minValue, maxValue)
end

local function pickRandom(list)
    return list[randInt(1, #list)]
end

local function deepCopy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = deepCopy(v) end
    return out
end

local function nextFallbackNpcId(spawner)
    spawner.fallbackIdCounter = (tonumber(spawner.fallbackIdCounter) or 0) + 1
    return string.format("npc_fallback_%d_%d", tonumber(spawner.tickCounter) or 0, spawner.fallbackIdCounter)
end

local function createNpcDataForSpawn(spawner)
    if NPCDataModel and type(NPCDataModel.new) == "function" then
        local ok, npc = pcall(function() return NPCDataModel.new() end)
        if ok and type(npc) == "table" then
            if not npc.id or tostring(npc.id) == "" then npc.id = nextFallbackNpcId(spawner) end
            return npc
        end
    end
    return { id = nextFallbackNpcId(spawner) }
end

local function toChunkCoord(value) return math.floor(value / CHUNK_SIZE) end
local function chunkKey(cx, cy, z) return tostring(cx) .. ":" .. tostring(cy) .. ":" .. tostring(z) end

local function splitChunkKey(key)
    local cx, cy, z = string.match(key, "([^:]+):([^:]+):([^:]+)")
    if not cx then return nil, nil, nil end
    return tonumber(cx), tonumber(cy), tonumber(z)
end

local function getPersistenceRoot()
    local world = getWorld and getWorld() or nil
    if world and world.getModData then
        local md = world:getModData()
        md[STATE_KEY] = md[STATE_KEY] or { version = 1, npcs = {} }
        return md[STATE_KEY]
    end
    if ModData and ModData.getOrCreate then
        local md = ModData.getOrCreate(STATE_KEY)
        md.version = md.version or 1
        md.npcs = md.npcs or {}
        return md
    end
    return nil
end

local function sqDistance2D(x1, y1, x2, y2)
    local dx = x1 - x2
    local dy = y1 - y2
    return math.sqrt(dx * dx + dy * dy)
end

local function isSquareValidForSpawn(square)
    if not square then return false end
    if square.isSolid and square:isSolid() then return false end
    if square.getRoom and square:getRoom() ~= nil then return false end
    if square.getMovingObjects then
        local moving = square:getMovingObjects()
        if moving and moving.size and moving:size() > 0 then return false end
    end
    return true
end

local function isSquareValidForIndoorSpawn(square)
    if not square then return false end
    if square.isSolid and square:isSolid() then return false end
    if not (square.getRoom and square:getRoom() ~= nil) then return false end
    if square.getMovingObjects then
        local moving = square:getMovingObjects()
        if moving and moving.size and moving:size() > 0 then return false end
    end
    return true
end

local function nearestPlayerDistance(players, x, y)
    local nearest = 999999
    for i = 1, #players do
        local p = players[i]
        local d = sqDistance2D(p:getX(), p:getY(), x, y)
        if d < nearest then nearest = d end
    end
    return nearest
end

local function nearestPlayerDistance3D(players, x, y, z)
    local nearest = 999999
    for i = 1, #players do
        local p = players[i]
        if p and p.getX and p.getY and p.getZ then
            if math.floor(p:getZ()) == z then
                local d = sqDistance2D(p:getX(), p:getY(), x, y)
                if d < nearest then nearest = d end
            end
        end
    end
    return nearest
end

-- ============================================================================
-- SOLO NPC VISUAL SETUP (IsoPlayer uniquement)
-- ============================================================================

-- Build 41: dressInNamedOutfit() ne fonctionne PAS sur les IsoPlayer NPC.
-- Pattern correct (confirme par NotAlone, BravensNPCFramework):
--   1. SurvivorFactory.CreateSurvivor() pour le descriptor
--   2. IsoPlayer.new() avec ce descriptor
--   3. Apres creation: inv:AddItem() + npc:setWornItem() pour chaque piece de vetement

-- Tables de vetements par body location (Male/Female)
local clothingMale = {
    Tshirt        = { "Base.Tshirt_WhiteBlack", "Base.Tshirt_Blue", "Base.Tshirt_Grey" },
    Shirt         = { "Base.Shirt_Blue", "Base.Shirt_Green", "Base.Shirt_White" },
    Jumper        = { "Base.Jumper_Brown", "Base.Jumper_Grey" },
    Pants         = { "Base.Jeans_Blue", "Base.Jeans_DarkBlue", "Base.Trousers_Black" },
    Shoes         = { "Base.Shoes_Black", "Base.Shoes_Brown", "Base.BootsWinter" },
    Hat           = { "Base.Cap_White", "Base.Cap_Red" },
    Socks         = { "Base.Socks_White", "Base.Socks_Black" },
}
local clothingFemale = {
    Tshirt        = { "Base.Tshirt_WhiteBlack", "Base.Tshirt_Pink", "Base.Tshirt_Grey" },
    Shirt         = { "Base.Shirt_Blue", "Base.Shirt_White" },
    Jumper        = { "Base.Jumper_Brown", "Base.Jumper_Grey" },
    Pants         = { "Base.Jeans_Blue", "Base.Jeans_DarkBlue" },
    Shoes         = { "Base.Shoes_Black", "Base.Shoes_Brown" },
    Hat           = { "Base.Cap_White" },
    Socks         = { "Base.Socks_White", "Base.Socks_Black" },
}

local function applyClothingToNPC(npc, isFemale)
    local inv = npc and npc.getInventory and npc:getInventory()
    if not inv then return end
    local clothes = isFemale and clothingFemale or clothingMale
    for bodyLocation, items in pairs(clothes) do
        if #items > 0 then
            local fullType = items[randInt(1, #items)]
            local ok, item = pcall(function() return inv:AddItem(fullType) end)
            if ok and item and npc.setWornItem then
                pcall(function() npc:setWornItem(bodyLocation, item) end)
            end
        end
    end
end

local function createIsoPlayerDescriptor(isFemale)
    if not SurvivorFactory or not SurvivorType or not SurvivorFactory.CreateSurvivor then return nil end
    local sType = SurvivorType.Neutral or SurvivorType.FriendlyArmed or SurvivorType.Aggressive
    if not sType then return nil end
    local ok, descriptor = pcall(function() return SurvivorFactory.CreateSurvivor(sType, isFemale == true) end)
    if not ok or not descriptor then return nil end
    return descriptor
end

local function applyIsoPlayerVisual(npc, isFemale, npcData)
    if not npc then return end
    if npc.setNPC then pcall(function() npc:setNPC(true) end) end
    if npc.setSceneCulled then pcall(function() npc:setSceneCulled(false) end) end
    if npc.setInvisible then pcall(function() npc:setInvisible(false) end) end
    if npc.setGodMod then pcall(function() npc:setGodMod(false) end) end
    if npc.setCanBeZombie then pcall(function() npc:setCanBeZombie(false) end) end
    if npc.setBlockMovement then pcall(function() npc:setBlockMovement(false) end) end

    -- Habiller via inv:AddItem() + setWornItem() - la seule methode fonctionnelle en B41 sur IsoPlayer NPC
    applyClothingToNPC(npc, isFemale)

    if npcData and npcData.name and npc.setDisplayName then pcall(function() npc:setDisplayName(tostring(npcData.name)) end) end
end

local function createIsoPlayerProxy(square, npcData, isFemale)
    if not square or not IsoPlayer or not IsoPlayer.new or not getWorld then return nil end
    local world = getWorld()
    if not world or not world.getCell then return nil end
    local descriptor = createIsoPlayerDescriptor(isFemale)
    if not descriptor then return nil end

    local ok, npc = pcall(function()
        return IsoPlayer.new(world:getCell(), descriptor, square:getX(), square:getY(), square:getZ())
    end)
    if not ok or not npc then return nil end

    -- Build 41: IsoPlayer.new() enregistre le NPC dans le monde automatiquement.
    -- Appeler addToWorld() en plus cause une double-inscription (bugs visuels / pathfinding).
    -- Ne PAS appeler addToWorld() en Build 41.

    applyIsoPlayerVisual(npc, isFemale, npcData)

    if npc.getModData then
        local md = npc:getModData()
        md.PH_IsDynamicNPC = true
        md.PH_NPCId = npcData.id
    end
    return npc
end

-- ============================================================================
-- SOLO SPAWN LOGIC
-- ============================================================================

local function findSpawnSquareNearPlayer(player, radius, minDistance, attempts)
    local cell = getCell and getCell() or nil
    if not cell then return nil end
    local px, py, pz = math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())
    for _ = 1, attempts do
        local x = px + randInt(-radius, radius)
        local y = py + randInt(-radius, radius)
        local square = cell:getGridSquare(x, y, pz)
        if isSquareValidForSpawn(square) then
            if sqDistance2D(px, py, x, y) >= minDistance then return square end
        end
    end
    return nil
end

local function findIndoorSpawnSquareNearPlayer(player, radius, minDistance, attempts)
    local cell = getCell and getCell() or nil
    if not cell then return nil end
    local px, py, pz = math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())
    for _ = 1, attempts do
        local x = px + randInt(-radius, radius)
        local y = py + randInt(-radius, radius)
        local square = cell:getGridSquare(x, y, pz)
        if isSquareValidForIndoorSpawn(square) then
            if sqDistance2D(px, py, x, y) >= minDistance then return square end
        end
    end
    return nil
end

local function findSpawnSquareInChunk(cx, cy, z, players, minDistance, attempts)
    local cell = getCell and getCell() or nil
    if not cell then return nil end
    local baseX, baseY = cx * CHUNK_SIZE, cy * CHUNK_SIZE
    for _ = 1, attempts do
        local x = baseX + randInt(0, CHUNK_SIZE - 1)
        local y = baseY + randInt(0, CHUNK_SIZE - 1)
        local square = cell:getGridSquare(x, y, z)
        if isSquareValidForSpawn(square) then
            local nearest = nearestPlayerDistance3D(players, x, y, z)
            if nearest >= minDistance and nearest <= (NPCSpawner_SOLO.spawnRadius + 10) then return square end
        end
    end
    return nil
end

local function findIndoorSpawnSquareInChunk(cx, cy, z, players, minDistance, attempts)
    local cell = getCell and getCell() or nil
    if not cell then return nil end
    local baseX, baseY = cx * CHUNK_SIZE, cy * CHUNK_SIZE
    for _ = 1, attempts do
        local x = baseX + randInt(0, CHUNK_SIZE - 1)
        local y = baseY + randInt(0, CHUNK_SIZE - 1)
        local square = cell:getGridSquare(x, y, z)
        if isSquareValidForIndoorSpawn(square) then
            local nearest = nearestPlayerDistance3D(players, x, y, z)
            if nearest >= minDistance and nearest <= (NPCSpawner_SOLO.spawnRadius + 10) then return square end
        end
    end
    return nil
end

-- ============================================================================
-- SOLO MODE: CLASS METHODS
-- ============================================================================

function NPCSpawner_SOLO:create3DHumanProxy(square, npcData)
    if not square then return nil end
    local isFemale = randInt(0, 1) == 1
    local npc = createIsoPlayerProxy(square, npcData, isFemale)
    if npc then
        self.lastSpawnFailureReason = "none"
        self.lastSpawnFailureTick = self.tickCounter
        return npc
    end
    self.lastSpawnFailureReason = "iso_player_spawn_failed"
    self.lastSpawnFailureTick = self.tickCounter
    return nil
end

function NPCSpawner_SOLO:isChunkActiveByPos(x, y, z)
    local cx = toChunkCoord(x)
    local cy = toChunkCoord(y)
    return self.activeChunkPool[chunkKey(cx, cy, z)] == true
end

function NPCSpawner_SOLO:rebuildActiveChunkPool(players)
    self.activeChunkPool = {}
    self.activeChunkList = {}
    local radiusInChunks = math.max(1, math.ceil(self.spawnRadius / CHUNK_SIZE))

    for i = 1, #players do
        local p = players[i]
        if p and p.getX and p.getY and p.getZ then
            local pcx = toChunkCoord(p:getX())
            local pcy = toChunkCoord(p:getY())
            local pz = math.floor(p:getZ())

            for dx = -radiusInChunks, radiusInChunks do
                for dy = -radiusInChunks, radiusInChunks do
                    if (dx * dx + dy * dy) <= (radiusInChunks * radiusInChunks) then
                        local cx = pcx + dx
                        local cy = pcy + dy
                        local key = chunkKey(cx, cy, pz)
                        if not self.activeChunkPool[key] then
                            self.activeChunkPool[key] = true
                            self.activeChunkList[#self.activeChunkList + 1] = key
                        end
                    end
                end
            end
        end
    end
end

function NPCSpawner_SOLO:buildRecordFromEntry(entry)
    local ex, ey, ez = entry.x, entry.y, entry.z
    if entry.entity then
        ex = entry.entity.getX and entry.entity:getX() or ex
        ey = entry.entity.getY and entry.entity:getY() or ey
        ez = entry.entity.getZ and math.floor(entry.entity:getZ()) or ez
    end

    local snapshot = nil
    if entry.data and entry.data.toTable then
        snapshot = entry.data:toTable()
    elseif entry.data then
        snapshot = deepCopy(entry.data)
    end

    return {
        id = entry.id,
        x = math.floor(ex or 0),
        y = math.floor(ey or 0),
        z = math.floor(ez or 0),
        snapshot = snapshot,
        savedAtTick = self.tickCounter,
        dormantSinceTick = self.tickCounter
    }
end

function NPCSpawner_SOLO:pruneDormantByTTL()
    local removed = 0
    local nowTick = self.tickCounter

    for npcId, record in pairs(self.dormantNPCs) do
        if type(record) ~= "table" then
            self.dormantNPCs[npcId] = nil
            removed = removed + 1
        else
            local since = record.dormantSinceTick or record.savedAtTick or nowTick
            if (nowTick - since) > self.dormantTTLticks then
                self.dormantNPCs[npcId] = nil
                removed = removed + 1
            end
        end
    end

    local count = 0
    for _ in pairs(self.dormantNPCs) do count = count + 1 end
    if count <= self.maxDormantRecords then return removed end

    local sortable = {}
    for npcId, record in pairs(self.dormantNPCs) do
        sortable[#sortable + 1] = { id = npcId, tick = (record and (record.dormantSinceTick or record.savedAtTick)) or 0 }
    end
    table.sort(sortable, function(a, b) return a.tick < b.tick end)

    local overflow = count - self.maxDormantRecords
    for i = 1, overflow do
        local item = sortable[i]
        if item then
            self.dormantNPCs[item.id] = nil
            removed = removed + 1
        end
    end
    return removed
end

function NPCSpawner_SOLO:saveState()
    self:pruneDormantByTTL()
    local root = getPersistenceRoot()
    if not root then return false end
    local merged = {}
    for npcId, record in pairs(self.dormantNPCs) do merged[npcId] = deepCopy(record) end
    for npcId, entry in pairs(self.activeNPCs) do merged[npcId] = self:buildRecordFromEntry(entry) end

    root.version = 1
    root.npcs = merged
    root.savedAtTick = self.tickCounter
    root.savedAtUnix = (os and os.time and os.time()) or 0
    if ModData and ModData.transmit then
        pcall(function() ModData.transmit(STATE_KEY) end)
    end
    return true
end

function NPCSpawner_SOLO:loadState()
    local root = getPersistenceRoot()
    self.dormantNPCs = {}
    if not root or type(root.npcs) ~= "table" then
        self.loadedPersistence = true
        return
    end

    for npcId, record in pairs(root.npcs) do
        if type(record) == "table" then
            self.dormantNPCs[npcId] = {
                id = record.id or npcId,
                x = math.floor(record.x or 0),
                y = math.floor(record.y or 0),
                z = math.floor(record.z or 0),
                snapshot = deepCopy(record.snapshot),
                savedAtTick = record.savedAtTick or 0,
                dormantSinceTick = record.dormantSinceTick or record.savedAtTick or 0
            }
        end
    end

    self:pruneDormantByTTL()
    self.loadedPersistence = true
end

function NPCSpawner_SOLO:createModelFromRecord(record)
    local snapshot = record and record.snapshot or nil
    if NPCDataModel and snapshot then
        if NPCDataModel.deserialize then
            local npc, err = NPCDataModel.deserialize(snapshot)
            if npc then return npc end
            if err == "json_decode_unavailable" and type(snapshot) == "table" then
                local fallback = NPCDataModel.new({ id = record.id })
                fallback:fromTable(snapshot)
                return fallback
            end
        end
        if NPCDataModel.new and type(snapshot) == "table" then
            local fallback = NPCDataModel.new({ id = record.id })
            if fallback.fromTable then fallback:fromTable(snapshot) end
            return fallback
        end
    end
    return { id = record.id }
end

function NPCSpawner_SOLO:spawnFromRecord(record, players)
    if not record then return nil end
    local cell = getCell and getCell() or nil
    if not cell then return nil end

    local square = cell:getGridSquare(record.x, record.y, record.z)
    if not isSquareValidForSpawn(square) then
        local cx, cy = toChunkCoord(record.x), toChunkCoord(record.y)
        square = findIndoorSpawnSquareInChunk(cx, cy, record.z, players, self.minSpawnDistance, self.spawnAttemptsPerCycle)
            or findSpawnSquareInChunk(cx, cy, record.z, players, self.minSpawnDistance, self.spawnAttemptsPerCycle)
    end

    if not square then
        self.lastSpawnFailureReason = "no_valid_spawn_square"
        self.lastSpawnFailureTick = self.tickCounter
        return nil
    end

    local npcData = self:createModelFromRecord(record)
    local entity = self:create3DHumanProxy(square, npcData)
    if not entity then
        if self.lastSpawnFailureReason == "none" then
            self.lastSpawnFailureReason = "create_proxy_failed"
            self.lastSpawnFailureTick = self.tickCounter
        end
        return nil
    end

    self.activeNPCs[npcData.id] = {
        id = npcData.id, data = npcData, entity = entity,
        x = square:getX(), y = square:getY(), z = square:getZ(),
        spawnedAtTick = self.tickCounter
    }
    self.dormantNPCs[record.id] = nil
    return npcData.id
end

function NPCSpawner_SOLO:spawnFromChunkPool(players)
    if #self.activeChunkList == 0 then return nil end
    local chunk = self.activeChunkList[randInt(1, #self.activeChunkList)]
    local cx, cy, z = splitChunkKey(chunk)
    if not cx then return nil end

    local square = findIndoorSpawnSquareInChunk(cx, cy, z, players, self.minSpawnDistance, self.spawnAttemptsPerCycle)
        or findSpawnSquareInChunk(cx, cy, z, players, self.minSpawnDistance, self.spawnAttemptsPerCycle)
    if not square then return nil end

    local npcData = createNpcDataForSpawn(self)
    local entity = self:create3DHumanProxy(square, npcData)
    if not entity then return nil end

    self.activeNPCs[npcData.id] = {
        id = npcData.id, data = npcData, entity = entity,
        x = square:getX(), y = square:getY(), z = square:getZ(),
        spawnedAtTick = self.tickCounter
    }
    return npcData.id
end

function NPCSpawner_SOLO:spawnOneNearPlayer(player)
    if not player then return nil end
    local square = findIndoorSpawnSquareNearPlayer(player, self.spawnRadius, self.minSpawnDistance, self.spawnAttemptsPerCycle * 2)
        or findSpawnSquareNearPlayer(player, self.spawnRadius, self.minSpawnDistance, self.spawnAttemptsPerCycle)

    if not square then return nil end
    local npcData = createNpcDataForSpawn(self)
    local entity = self:create3DHumanProxy(square, npcData)
    if not entity then return nil end

    self.activeNPCs[npcData.id] = {
        id = npcData.id, data = npcData, entity = entity,
        x = square:getX(), y = square:getY(), z = square:getZ(),
        spawnedAtTick = self.tickCounter
    }
    return npcData.id
end

function NPCSpawner_SOLO:despawnNPC(npcId)
    local entry = self.activeNPCs[npcId]
    if not entry then return false end
    local entity = entry.entity
    if entity then
        if entity.removeFromWorld then pcall(function() entity:removeFromWorld() end) end
        if entity.removeFromSquare then pcall(function() entity:removeFromSquare() end) end
    end
    if entry.data then
        local record = self:buildRecordFromEntry(entry)
        record.dormantSinceTick = self.tickCounter
        self.dormantNPCs[npcId] = record
    end
    self.activeNPCs[npcId] = nil
    return true
end

function NPCSpawner_SOLO:despawnFarFromPlayers(players)
    local removeIds = {}
    for npcId, entry in pairs(self.activeNPCs) do
        local entity = entry.entity
        if not entity then
            removeIds[#removeIds + 1] = npcId
        else
            local ex = entity.getX and entity:getX() or entry.x
            local ey = entity.getY and entity:getY() or entry.y
            local ez = entity.getZ and math.floor(entity:getZ()) or entry.z
            local nearest = nearestPlayerDistance(players, ex, ey)
            local chunkIsActive = self:isChunkActiveByPos(ex, ey, ez)
            if nearest > self.despawnRadius or not chunkIsActive then
                removeIds[#removeIds + 1] = npcId
            end
        end
    end
    for i = 1, #removeIds do self:despawnNPC(removeIds[i]) end
end

function NPCSpawner_SOLO:spawnBudgeted(players)
    local active = self:getActiveCount()
    local hardBudget = self.maxActiveNPCs
    local targetByPlayers = math.min(hardBudget, #players * self.perPlayerBudget)

    if active >= targetByPlayers then return end

    local slots = math.min(targetByPlayers - active, self.maxSpawnsPerCycle)
    for _ = 1, slots do
        local revived = nil
        for npcId, record in pairs(self.dormantNPCs) do
            if self:isChunkActiveByPos(record.x, record.y, record.z) then
                revived = self:spawnFromRecord(record, players)
                if revived then break else self.dormantNPCs[npcId] = nil end
            end
        end
        if not revived then
            local okId = self:spawnFromChunkPool(players)
            if not okId then
                local p = players[randInt(1, #players)]
                okId = self:spawnOneNearPlayer(p)
            end
            if not okId then break end
        end
    end
end

function NPCSpawner_SOLO:getActiveCount()
    local count = 0
    for _ in pairs(self.activeNPCs) do count = count + 1 end
    return count
end

function NPCSpawner_SOLO:getDormantCount()
    local count = 0
    for _ in pairs(self.dormantNPCs) do count = count + 1 end
    return count
end

function NPCSpawner_SOLO:clearAllNPCs()
    local removed = 0
    local activeIds = {}
    for npcId in pairs(self.activeNPCs) do activeIds[#activeIds + 1] = npcId end
    for i = 1, #activeIds do if self:despawnNPC(activeIds[i]) then removed = removed + 1 end end

    local dormantBefore = self:getDormantCount()
    self.dormantNPCs = {}
    self:saveState()
    return removed, dormantBefore
end

-- ============================================================================
-- SOLO UPDATE LOOP (SIMPLIFIED - NO NETWORK SYNC, NO ADMIN COMMANDS)
-- ============================================================================

function NPCSpawner_SOLO:update()
    self.tickCounter = self.tickCounter + 1

    if not self.loadedPersistence then
        self:loadState()
    end

    if (self.tickCounter % self.updateEveryTicks) ~= 0 then
        if (self.tickCounter % self.saveEveryTicks) == 0 then self:saveState() end
        return
    end

    -- SOLO: Single player, no need to fetch online players
    local players = {}
    local player = getPlayer and getPlayer(0) or nil
    if player then
        players[1] = player
    else
        if (self.tickCounter % self.saveEveryTicks) == 0 then self:saveState() end
        return
    end

    self:rebuildActiveChunkPool(players)
    self:despawnFarFromPlayers(players)
    self:pruneDormantByTTL()
    self:spawnBudgeted(players)

    -- SOLO: NO transmitModData (no network sync needed)

    if (self.tickCounter % self.saveEveryTicks) == 0 then
        self:saveState()
    end
end

-- ============================================================================
-- SOLO BOOTSTRAP
-- ============================================================================

function NPCSpawner_SOLO:start()
    if Events and Events.OnServerStarted then
        Events.OnServerStarted.Add(function()
            NPCSpawner_SOLO:loadState()
            if PHNPC_ConfigManager and PHNPC_ConfigManager.applyToRuntime then
                PHNPC_ConfigManager:applyToRuntime(true)
            end
        end)
    end
    if Events and Events.OnSave then Events.OnSave.Add(function() NPCSpawner_SOLO:saveState() end) end
    if Events and Events.OnPostSave then Events.OnPostSave.Add(function() NPCSpawner_SOLO:saveState() end) end
    if Events and Events.OnTick then Events.OnTick.Add(function() NPCSpawner_SOLO:update() end) end
end

NPCSpawner_SOLO:start()

return NPCSpawner_SOLO

