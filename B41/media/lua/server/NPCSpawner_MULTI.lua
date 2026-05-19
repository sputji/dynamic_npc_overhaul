--[[
    NPCSpawner_MULTI.lua
    Dynamic NPC Overhaul v2.1 - MULTIJOUEUR MODE ONLY
    
    VERSION: MULTI-ONLY (full-featured, network replication enabled)
    PURPOSE: Handle NPC spawn/despawn in multiplayer servers with full sync
    
    Features:
    - NPC spawn near players
    - NPC despawn when far
    - Dormancy management
    - FULL network sync (transmitModData)
    - Admin commands & replication
    - Chat command handlers
]]


local hasModel, NPCDataModel = pcall(require, "NPCDataModel")
local hasConfigManager, PHNPC_ConfigManager = pcall(require, "PHNPC_ConfigManager")
local hasLogger, PHNPC_Logger = pcall(require, "PHNPC_Logger")

if not hasModel then NPCDataModel = nil end
if not hasConfigManager then PHNPC_ConfigManager = _G.PHNPC_ConfigManager end
if not hasLogger then PHNPC_Logger = _G.PHNPC_Logger end

local STATE_KEY = "PH_DynamicNPC_Overhaul_State"
local CHUNK_SIZE = 10
local CHAT_PREFIX = "/phnpc"

local NPCSpawner_MULTI = {
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

    -- MULTI-ONLY: Replication settings
    replicationEnabled = true,
    replicationEveryTicks = 300,
    replicationModule = "PH_NPC",
    replicationCommand = "ChunkDebugState",
    replicationAckCommand = "AdminDebugAck",
    replicationAdminCommand = "AdminSetDebug",
    replicationMaxChunksPerPlayer = 48,
    replicationFSMRange = 40,
    replicationMaxFSMPerPlayer = 10,
    debugViewers = {},

    forcedOutfit = nil,
    markerColor = { r = 0.15, g = 1.00, b = 0.20, a = 1.00 },
    lastSpawnFailureReason = "none",
    lastSpawnFailureTick = 0,
    fallbackIdCounter = 0,
    loadedPersistence = false
}

local maleOutfits = { "Survivalist", "Police", "Fireman", "ConstructionWorker", "Farmer", "Tourist" }
local femaleOutfits = { "Nurse", "Survivalist", "Tourist", "OfficeWorker", "Farmer" }
local maleHair = { "Bald", "BuzzCut", "Messy", "Short", "SidePart" }
local femaleHair = { "Bob", "Long", "PonyTail", "Messy", "Short" }

-- Copy ALL utility functions from NPCSpawner.lua (same as SOLO)
-- [For brevity: functions identical to SOLO version - randInt, pickRandom, deepCopy, etc.]

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

local function getOnlinePlayerList()
    local players = {}
    if type(getOnlinePlayers) == "function" then
        local online = getOnlinePlayers()
        if online and online.size then
            for i = 0, online:size() - 1 do players[#players + 1] = online:get(i) end
            return players
        end
    end
    if type(getNumActivePlayers) == "function" and type(getSpecificPlayer) == "function" then
        for i = 0, getNumActivePlayers() - 1 do
            local p = getSpecificPlayer(i)
            if p then players[#players + 1] = p end
        end
    end
    return players
end

local function normalizeBoolOrNil(value)
    if value == nil then return nil end
    return value == true
end

local function normalizeNumberOrNil(value)
    if value == nil then return nil end
    local n = tonumber(value)
    if not n then return nil end
    return math.floor(n)
end

local function isAllowedValue(value, allowed)
    for i = 1, #allowed do if allowed[i] == value then return true end end
    return false
end

local function trim(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function tokenizeLower(line)
    local out = {}
    line = trim(string.lower(line or ""))
    for token in string.gmatch(line, "%S+") do out[#out + 1] = token end
    return out
end

local function extractCommandText(args)
    if type(args) == "string" then return args end
    if type(args) ~= "table" then return nil end
    return args.text or args.message or args.msg or args.command or args.line or args.raw
end

local function sendConsoleResult(player, ok, message)
    if not sendServerCommand then return end
    local payload = { ok = ok == true, message = tostring(message or "") }
    pcall(function() sendServerCommand(player, "PH_NPC_CONSOLE", "Result", payload) end)
end

local function isAdminPlayer(player)
    if not player then return false end
    if player.isAccessLevel and player:getAccessLevel() then
        local level = tostring(player:getAccessLevel()):lower()
        if level == "admin" or level == "moderator" or level == "gm" then return true end
    end
    if player.isAdmin and player:isAdmin() then return true end
    return false
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

-- [All spawn square finding functions identical to SOLO...]
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
            if nearest >= minDistance and nearest <= (NPCSpawner_MULTI.spawnRadius + 10) then return square end
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
            if nearest >= minDistance and nearest <= (NPCSpawner_MULTI.spawnRadius + 10) then return square end
        end
    end
    return nil
end

-- [Visual setup functions: IsoPlayer uniquement]
local function createIsoPlayerDescriptor(isFemale)
    if not SurvivorFactory or not SurvivorType or not SurvivorFactory.CreateSurvivor then return nil end
    local sType = SurvivorType.Neutral or SurvivorType.FriendlyArmed or SurvivorType.Aggressive
    if not sType then return nil end
    local ok, descriptor = pcall(function() return SurvivorFactory.CreateSurvivor(sType, isFemale == true) end)
    if ok then return descriptor end
    return nil
end

local function applyIsoPlayerVisual(npc, isFemale, npcData)
    if not npc then return end
    if npc.setNPC then pcall(function() npc:setNPC(true) end) end
    if npc.setSceneCulled then pcall(function() npc:setSceneCulled(false) end) end
    if npc.setInvisible then pcall(function() npc:setInvisible(false) end) end
    if npc.setGodMod then pcall(function() npc:setGodMod(false) end) end
    if npc.setCanBeZombie then pcall(function() npc:setCanBeZombie(false) end) end
    if npc.setBlockMovement then pcall(function() npc:setBlockMovement(false) end) end
    local outfit = NPCSpawner_MULTI.forcedOutfit
        or (isFemale and pickRandom(femaleOutfits) or pickRandom(maleOutfits))
    if outfit and npc.dressInNamedOutfit then pcall(function() npc:dressInNamedOutfit(outfit) end) end
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

    applyIsoPlayerVisual(npc, isFemale, npcData)

    if npc.getModData then
        local md = npc:getModData()
        md.PH_IsDynamicNPC = true
        md.PH_NPCId = npcData.id
    end
    return npc
end

-- [INSERT ALL MULTI-ONLY FUNCTIONS FROM NPCRANDOM LATER...]
function NPCSpawner_MULTI:create3DHumanProxy(square, npcData)
    if not square then return nil end
    -- Sur serveur dedié IsoPlayer.new() n'est pas disponible - les clients cree leurs proxies localement
    if not IsoPlayer or not IsoPlayer.new then
        self.lastSpawnFailureReason = "dedicated_server_no_iso_player"
        self.lastSpawnFailureTick = self.tickCounter
        return nil
    end
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

-- ============================================================================
-- MULTI: NPC BROADCAST (server -> tous les clients)
-- ============================================================================

local MULTI_SYNC_MODULE = "PH_NPC_SYNC"

local function getOnlinePlayerListSafe()
    local players = {}
    if type(getOnlinePlayers) == "function" then
        local ok, online = pcall(getOnlinePlayers)
        if ok and online and online.size then
            for i = 0, online:size() - 1 do players[#players + 1] = online:get(i) end
            return players
        end
    end
    if type(getNumActivePlayers) == "function" and type(getSpecificPlayer) == "function" then
        for i = 0, getNumActivePlayers() - 1 do
            local p = getSpecificPlayer(i)
            if p then players[#players + 1] = p end
        end
    end
    return players
end

function NPCSpawner_MULTI:broadcastNPCSpawn(npcId, entry)
    if not sendServerCommand then return end
    local d = entry.data
    local payload = {
        npcId = npcId,
        x = entry.x, y = entry.y, z = entry.z,
        isFemale = d and d.isFemale or false,
        outfit = d and d.outfit or nil,
        name = d and d.name or nil,
    }
    local players = getOnlinePlayerListSafe()
    for _, p in ipairs(players) do
        pcall(function() sendServerCommand(p, MULTI_SYNC_MODULE, "NPCSpawn", payload) end)
    end
end

function NPCSpawner_MULTI:broadcastNPCDespawn(npcId)
    if not sendServerCommand then return end
    local payload = { npcId = npcId }
    local players = getOnlinePlayerListSafe()
    for _, p in ipairs(players) do
        pcall(function() sendServerCommand(p, MULTI_SYNC_MODULE, "NPCDespawn", payload) end)
    end
end

function NPCSpawner_MULTI:broadcastNPCUpdates()
    if not sendServerCommand then return end
    local players = getOnlinePlayerListSafe()
    if #players == 0 then return end
    for npcId, entry in pairs(self.activeNPCs) do
        local ex, ey, ez = entry.x, entry.y, entry.z
        if entry.entity then
            ex = entry.entity.getX and entry.entity:getX() or ex
            ey = entry.entity.getY and entry.entity:getY() or ey
            ez = entry.entity.getZ and math.floor(entry.entity:getZ()) or ez
        end
        local d = entry.data
        local payload = {
            npcId = npcId,
            x = ex, y = ey, z = ez,
            animState = d and d.animState or "idle",
            isRunning = d and d.isRunning or false,
        }
        for _, p in ipairs(players) do
            pcall(function() sendServerCommand(p, MULTI_SYNC_MODULE, "NPCUpdate", payload) end)
        end
    end
end

-- ============================================================================
-- MULTI: LIFECYCLE (identique SOLO + broadcast reseau)
-- ============================================================================

local function createNpcDataForSpawnMulti(spawner)
    if NPCDataModel and type(NPCDataModel.new) == "function" then
        local ok, npc = pcall(function() return NPCDataModel.new() end)
        if ok and type(npc) == "table" then
            if not npc.id or tostring(npc.id) == "" then npc.id = nextFallbackNpcId(spawner) end
            return npc
        end
    end
    return { id = nextFallbackNpcId(spawner) }
end

function NPCSpawner_MULTI:isChunkActiveByPos(x, y, z)
    local cx = toChunkCoord(x)
    local cy = toChunkCoord(y)
    return self.activeChunkPool[chunkKey(cx, cy, z)] == true
end

function NPCSpawner_MULTI:rebuildActiveChunkPool(players)
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

function NPCSpawner_MULTI:buildRecordFromEntry(entry)
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
        x = math.floor(ex or 0), y = math.floor(ey or 0), z = math.floor(ez or 0),
        snapshot = snapshot, savedAtTick = self.tickCounter, dormantSinceTick = self.tickCounter
    }
end

function NPCSpawner_MULTI:pruneDormantByTTL()
    local removed = 0
    local nowTick = self.tickCounter
    for npcId, record in pairs(self.dormantNPCs) do
        if type(record) ~= "table" then
            self.dormantNPCs[npcId] = nil; removed = removed + 1
        else
            local since = record.dormantSinceTick or record.savedAtTick or nowTick
            if (nowTick - since) > self.dormantTTLticks then
                self.dormantNPCs[npcId] = nil; removed = removed + 1
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
        if item then self.dormantNPCs[item.id] = nil; removed = removed + 1 end
    end
    return removed
end

function NPCSpawner_MULTI:saveState()
    self:pruneDormantByTTL()
    local root = getPersistenceRoot()
    if not root then return false end
    local merged = {}
    for npcId, record in pairs(self.dormantNPCs) do merged[npcId] = deepCopy(record) end
    for npcId, entry in pairs(self.activeNPCs) do merged[npcId] = self:buildRecordFromEntry(entry) end
    root.version = 1; root.npcs = merged
    root.savedAtTick = self.tickCounter
    root.savedAtUnix = (os and os.time and os.time()) or 0
    if ModData and ModData.transmit then pcall(function() ModData.transmit(STATE_KEY) end) end
    return true
end

function NPCSpawner_MULTI:loadState()
    local root = getPersistenceRoot()
    self.dormantNPCs = {}
    if not root or not root.npcs then self.loadedPersistence = true; return false end
    for npcId, record in pairs(root.npcs) do
        if type(record) == "table" and record.id then
            self.dormantNPCs[npcId] = record
        end
    end
    self.loadedPersistence = true
    return true
end

function NPCSpawner_MULTI:spawnFromRecord(record, players)
    if not record or not record.id then return nil end
    local nearest = nearestPlayerDistance3D(players, record.x or 0, record.y or 0, record.z or 0)
    if nearest < self.minSpawnDistance or nearest > (self.spawnRadius + 10) then return nil end
    local cell = getCell and getCell() or nil
    if not cell then return nil end
    local square = cell:getGridSquare(record.x or 0, record.y or 0, record.z or 0)
    if not isSquareValidForSpawn(square) then
        square = findSpawnSquareNearPlayer(players[1], 8, self.minSpawnDistance, 8)
        if not square then return nil end
    end
    local npcData = nil
    if NPCDataModel and NPCDataModel.fromTable and record.snapshot then
        local ok, restored = pcall(function() return NPCDataModel.fromTable(record.snapshot) end)
        if ok and restored then npcData = restored end
    end
    if not npcData then
        npcData = createNpcDataForSpawnMulti(self)
        npcData.id = record.id
    end
    local entity = self:create3DHumanProxy(square, npcData)
    self.activeNPCs[npcData.id] = {
        id = npcData.id, data = npcData, entity = entity,
        x = square:getX(), y = square:getY(), z = square:getZ(),
        spawnedAtTick = self.tickCounter
    }
    self.dormantNPCs[record.id] = nil
    self:broadcastNPCSpawn(npcData.id, self.activeNPCs[npcData.id])
    return npcData.id
end

function NPCSpawner_MULTI:spawnFromChunkPool(players)
    if #self.activeChunkList == 0 then return nil end
    local chunk = self.activeChunkList[randInt(1, #self.activeChunkList)]
    local cx, cy, z = splitChunkKey(chunk)
    if not cx then return nil end
    local square = findIndoorSpawnSquareInChunk(cx, cy, z, players, self.minSpawnDistance, self.spawnAttemptsPerCycle)
        or findSpawnSquareInChunk(cx, cy, z, players, self.minSpawnDistance, self.spawnAttemptsPerCycle)
    if not square then return nil end
    local npcData = createNpcDataForSpawnMulti(self)
    local entity = self:create3DHumanProxy(square, npcData)
    self.activeNPCs[npcData.id] = {
        id = npcData.id, data = npcData, entity = entity,
        x = square:getX(), y = square:getY(), z = square:getZ(),
        spawnedAtTick = self.tickCounter
    }
    self:broadcastNPCSpawn(npcData.id, self.activeNPCs[npcData.id])
    return npcData.id
end

function NPCSpawner_MULTI:spawnOneNearPlayer(player)
    if not player then return nil end
    local square = findIndoorSpawnSquareNearPlayer(player, self.spawnRadius, self.minSpawnDistance, self.spawnAttemptsPerCycle * 2)
        or findSpawnSquareNearPlayer(player, self.spawnRadius, self.minSpawnDistance, self.spawnAttemptsPerCycle)
    if not square then return nil end
    local npcData = createNpcDataForSpawnMulti(self)
    local entity = self:create3DHumanProxy(square, npcData)
    self.activeNPCs[npcData.id] = {
        id = npcData.id, data = npcData, entity = entity,
        x = square:getX(), y = square:getY(), z = square:getZ(),
        spawnedAtTick = self.tickCounter
    }
    self:broadcastNPCSpawn(npcData.id, self.activeNPCs[npcData.id])
    return npcData.id
end

function NPCSpawner_MULTI:despawnNPC(npcId)
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
    self:broadcastNPCDespawn(npcId)
    return true
end

function NPCSpawner_MULTI:despawnFarFromPlayers(players)
    local removeIds = {}
    for npcId, entry in pairs(self.activeNPCs) do
        local ex = entry.x; local ey = entry.y; local ez = entry.z
        if entry.entity then
            ex = entry.entity.getX and entry.entity:getX() or ex
            ey = entry.entity.getY and entry.entity:getY() or ey
            ez = entry.entity.getZ and math.floor(entry.entity:getZ()) or ez
        end
        local nearest = nearestPlayerDistance(players, ex, ey)
        local chunkIsActive = self:isChunkActiveByPos(ex, ey, ez)
        if nearest > self.despawnRadius or not chunkIsActive then
            removeIds[#removeIds + 1] = npcId
        end
    end
    for i = 1, #removeIds do self:despawnNPC(removeIds[i]) end
end

function NPCSpawner_MULTI:spawnBudgeted(players)
    local active = self:getActiveCount()
    local targetByPlayers = math.min(self.maxActiveNPCs, #players * self.perPlayerBudget)
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
            if not okId then okId = self:spawnOneNearPlayer(players[randInt(1, #players)]) end
            if not okId then break end
        end
    end
end

function NPCSpawner_MULTI:clearAllNPCs()
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
-- MULTI UPDATE LOOP
-- ============================================================================

function NPCSpawner_MULTI:update()
    self.tickCounter = self.tickCounter + 1
    if not self.loadedPersistence then self:loadState() end
    if (self.tickCounter % self.updateEveryTicks) ~= 0 then
        if (self.tickCounter % self.saveEveryTicks) == 0 then self:saveState() end
        return
    end
    local players = getOnlinePlayerListSafe()
    if #players == 0 then
        if (self.tickCounter % self.saveEveryTicks) == 0 then self:saveState() end
        return
    end
    self:rebuildActiveChunkPool(players)
    self:despawnFarFromPlayers(players)
    self:pruneDormantByTTL()
    self:spawnBudgeted(players)
    if (self.tickCounter % self.replicationEveryTicks) == 0 then
        self:broadcastNPCUpdates()
    end
    if ModData and ModData.transmit then
        pcall(function() ModData.transmit(STATE_KEY) end)
    end
    if (self.tickCounter % self.saveEveryTicks) == 0 then self:saveState() end
end

-- [Multi-specific utils]
function NPCSpawner_MULTI:collectChunkCounts(source)
    local counts = {}
    for _, entry in pairs(source) do
        local x, y, z = entry.x, entry.y, entry.z
        if entry.entity then
            x = entry.entity.getX and entry.entity:getX() or x
            y = entry.entity.getY and entry.entity:getY() or y
            z = entry.entity.getZ and math.floor(entry.entity:getZ()) or z
        end
        if x ~= nil and y ~= nil and z ~= nil then
            local key = chunkKey(toChunkCoord(x), toChunkCoord(y), math.floor(z))
            counts[key] = (counts[key] or 0) + 1
        end
    end
    return counts
end

function NPCSpawner_MULTI:getActiveCount()
    local count = 0
    for _ in pairs(self.activeNPCs) do count = count + 1 end
    return count
end

function NPCSpawner_MULTI:getDormantCount()
    local count = 0
    for _ in pairs(self.dormantNPCs) do count = count + 1 end
    return count
end

function NPCSpawner_MULTI:update()
    self.tickCounter = self.tickCounter + 1

    if not self.loadedPersistence then
        self:loadState()
    end

    if (self.tickCounter % self.updateEveryTicks) ~= 0 then
        if (self.tickCounter % self.saveEveryTicks) == 0 then self:saveState() end
        return
    end

    local players = getOnlinePlayerList()
    if #players == 0 then
        if (self.tickCounter % self.saveEveryTicks) == 0 then self:saveState() end
        return
    end

    self:rebuildActiveChunkPool(players)
    self:despawnFarFromPlayers(players)
    self:pruneDormantByTTL()
    self:spawnBudgeted(players)

    -- MULTI-SPECIFIC: TRANSMIT NETWORK SYNC
    for npcId, entry in pairs(self.activeNPCs) do
        if not entry.initialSyncDone and entry.entity and entry.entity.getOnlineID then
            if entry.entity:getOnlineID() ~= -1 then
                if entry.entity.transmitModData then
                    pcall(function() entry.entity:transmitModData() end)
                end
                entry.initialSyncDone = true
            end
        end
    end

    -- MULTI-SPECIFIC: Admin replication
    if (self.tickCounter % self.replicationEveryTicks) == 0 then
        self:replicateDebugState(players)
    end

    if (self.tickCounter % self.saveEveryTicks) == 0 then
        self:saveState()
    end
end

function NPCSpawner_MULTI:start()
    if Events and Events.OnClientCommand then
        Events.OnClientCommand.Add(function(module, command, player, args)
            NPCSpawner_MULTI:onClientCommand(module, command, player, args)
        end)
    end
    if Events and Events.OnServerStarted then
        Events.OnServerStarted.Add(function()
            NPCSpawner_MULTI:loadState()
            if PHNPC_ConfigManager and PHNPC_ConfigManager.applyToRuntime then
                PHNPC_ConfigManager:applyToRuntime(true)
            end
        end)
    end
    if Events and Events.OnSave then Events.OnSave.Add(function() NPCSpawner_MULTI:saveState() end) end
    if Events and Events.OnPostSave then Events.OnPostSave.Add(function() NPCSpawner_MULTI:saveState() end) end
    if Events and Events.OnTick then Events.OnTick.Add(function() NPCSpawner_MULTI:update() end) end
end

-- ============================================================================
-- MULTI BOOTSTRAP
-- ============================================================================

NPCSpawner_MULTI:start()

return NPCSpawner_MULTI
