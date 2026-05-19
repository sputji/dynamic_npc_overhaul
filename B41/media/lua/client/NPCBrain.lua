if not isServer() then return {} end

--[[
    Project Humain : Dynamic_NPC_Overhaul
    NPCBrain.lua

    FSM serveur legere pour PNJ dynamiques.
    Objectif: comportement autonome avec faible cout CPU.
]]


local hasSpawner, NPCSpawner = pcall(require, "NPCSpawner")
if not hasSpawner then
    NPCSpawner = nil
end

local hasNetServer, NPC_NetworkServer = pcall(require, "NPC_NetworkServer")
if not hasNetServer then
    NPC_NetworkServer = nil
end

local hasFactionMgr, NPCFactionManager = pcall(require, "NPCFactionManager")
if not hasFactionMgr then
    NPCFactionManager = nil
end

local hasMemory, NPCMemory = pcall(require, "NPCMemory")
if not hasMemory then
    NPCMemory = nil
end

local hasInteractionHooks, NPCInteractionHooks = pcall(require, "NPCInteractionHooks")
if not hasInteractionHooks then
    NPCInteractionHooks = nil
end

local hasEnvironmentHooks, NPCEnvironmentHooks = pcall(require, "NPCEnvironmentHooks")
if not hasEnvironmentHooks then
    NPCEnvironmentHooks = nil
end

local hasTuningProfiles, NPCTuningProfiles = pcall(require, "NPCTuningProfiles")
if not hasTuningProfiles then
    NPCTuningProfiles = nil
end

local hasLogger, PHNPC_Logger = pcall(require, "PHNPC_Logger")
if not hasLogger then
    PHNPC_Logger = _G.PHNPC_Logger
end

local NPCBrain = {
    contexts = {},
    tickCounter = 0,
    cachedZombieList = nil,
    cachedZombieListTick = 0,
    lastError = nil,
    lastErrorNpcId = nil,
    lastErrorTick = 0,

    updateEveryTicks = 12,   -- cadence globale FSM
    thinkEveryTicks = 30,    -- cadence de decision individuelle
    zombieVisionRange = 14,
    playerVisionRange = 12,
    containerSearchRange = 6,

    hungerCritical = 35,
    thirstCritical = 35,

    wanderMinDistance = 4,
    wanderMaxDistance = 10,

    cowardThreshold = 38,
    fleeDurationTicks = 220,
    combatSurvivalBonus = 3,
    debugSyncEveryTicks = 20,
    socialActionEveryTicks = 95,
    hostileActionRange = 3.2,
    tradeActionRange = 3.5,
    unstuckEnabled = true,
    unstuckMinMoveDistance = 0.35,
    unstuckThresholdTicks = 300,
    unstuckCooldownTicks = 240,
    unstuckTeleportMin = 1,
    unstuckTeleportMax = 3,
    unstuckSuspiciousWindowSec = 60,
    unstuckSuspiciousBurst = 3,
    freezeMinTicks = 28,
    freezeMaxTicks = 78,
    shelterSearchRange = 9,
    expeditionDistanceThreshold = 22,
    expeditionBaseDurationTicks = 220,
    expeditionDistanceFactor = 22,

    -- Types simplifies pour nourriture/eau dans inventaire simule.
    foodHints = {
        "Canned", "Tuna", "Sardines", "Crisps", "Beans", "Soup", "Chocolate", "Jerky"
    },
    waterHints = {
        "Water", "Bottle", "Soda", "Pop"
    }
}

NPCBrain.STATE_IDLE = "Idle"
NPCBrain.STATE_WANDER = "Wander"
NPCBrain.STATE_SURVIVE = "Survive"
NPCBrain.STATE_COMBAT = "Combat"
NPCBrain.STATE_FLEE = "Flee"
NPCBrain.STATE_FREEZE = "Freeze"

NPCBrain.GOAL_DANGER = "danger"
NPCBrain.GOAL_NEEDS = "needs"
NPCBrain.GOAL_EXPLORE = "explore"

local function randInt(minValue, maxValue)
    if type(ZombRand) == "function" then
        return minValue + ZombRand((maxValue - minValue) + 1)
    end
    return math.random(minValue, maxValue)
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

local function emitImmersionFx(fxType, npcData)
    if not NPC_NetworkServer or type(NPC_NetworkServer.broadcastNPCFx) ~= "function" then
        return
    end

    local npcId = npcData and (npcData.id or npcData.npcId) or nil
    if not npcId then
        return
    end

    pcall(function()
        NPC_NetworkServer:broadcastNPCFx(npcId, fxType, npcData)
    end)
end

local function stringContainsAny(text, hints)
    if type(text) ~= "string" then
        return false
    end
    local lower = string.lower(text)
    for i = 1, #hints do
        local h = string.lower(hints[i])
        if string.find(lower, h, 1, true) then
            return true
        end
    end
    return false
end

local function sqDistance2D(x1, y1, x2, y2)
    local dx = x1 - x2
    local dy = y1 - y2
    return math.sqrt(dx * dx + dy * dy)
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

local function canSeeTarget(observer, target)
    if not observer or not target then
        return false
    end

    -- Best effort: les API de vision peuvent varier selon build.
    if observer.CanSee then
        local ok, res = pcall(function()
            return observer:CanSee(target)
        end)
        if ok and res ~= nil then
            return res == true
        end
    end

    if observer.isCanSee and target.getX then
        local ok, res = pcall(function()
            return observer:isCanSee(target:getX(), target:getY(), math.floor(target:getZ() or 0))
        end)
        if ok and res ~= nil then
            return res == true
        end
    end

    -- Fallback: on considere visible si proche.
    local ox, oy = getEntityPos(observer)
    local tx, ty = getEntityPos(target)
    return sqDistance2D(ox, oy, tx, ty) <= NPCBrain.zombieVisionRange
end

local function isIsoPlayerEntity(entity)
    if not entity or not instanceof then
        return false
    end

    local ok, result = pcall(function()
        return instanceof(entity, "IsoPlayer")
    end)
    return ok and result == true
end

local function entityCanPathTo(entity, x, y, z)
    if not entity then return false end
    -- Build 41: IsoPlayer NPCs utilisent ISTimedActionQueue + ISPathFindAction
    -- C'est la méthode correcte pour les NPCs créés via IsoPlayer.new() en Build 41
    -- (BravensNPCFramework, référence Build 41 confirmée)
    if ISTimedActionQueue and ISPathFindAction and ISPathFindAction.pathToLocationF then
        local ok = pcall(function()
            ISTimedActionQueue.clear(entity)
            ISTimedActionQueue.add(ISPathFindAction:pathToLocationF(entity, x, y, z))
        end)
        return ok
    end
    -- Fallback: getPathFindBehavior2 (IsoZombie ou Build 42)
    if entity.getPathFindBehavior2 then
        local ok = pcall(function()
            local pfb = entity:getPathFindBehavior2()
            if pfb and pfb.pathToLocation then
                pfb:pathToLocation(x, y, z)
            end
        end)
        return ok
    end
    -- IsoZombie: pathToLocationF direct
    if entity.pathToLocationF then
        local ok = pcall(function()
            entity:pathToLocationF(x, y, z)
        end)
        return ok
    end
    return false
end

local function setNPCMotion(entity, running)
    if not entity then return end
    if entity.NPCSetRunning then pcall(function() entity:NPCSetRunning(running) end) end
    if entity.setRunning then pcall(function() entity:setRunning(running) end) end
    if not running then
        if entity.NPCSetWalking then pcall(function() entity:NPCSetWalking(true) end) end
    end
end

local function forceTeleportNear(entity, npcEntry, tx, ty, tz)
    if not entity then
        return false
    end

    local success = false

    if entity.setX and entity.setY then
        local ok = pcall(function()
            entity:setX(tx)
            entity:setY(ty)
            if entity.setZ then
                entity:setZ(tz)
            end
        end)
        success = ok == true
    end

    if (not success) and entity.getCell and entity.setCurrent then
        local okSquare, square = pcall(function()
            local cell = entity:getCell()
            return cell and cell:getGridSquare(math.floor(tx), math.floor(ty), math.floor(tz)) or nil
        end)
        if okSquare and square then
            local okSet = pcall(function()
                entity:setCurrent(square)
            end)
            success = okSet == true
        end
    end

    if success and npcEntry then
        npcEntry.x = tx
        npcEntry.y = ty
        npcEntry.z = tz
    end

    return success
end

function NPCBrain:getContext(npcId)
    local ctx = self.contexts[npcId]
    if ctx then
        return ctx
    end

    ctx = {
        state = self.STATE_IDLE,
        lastThinkTick = 0,
        lastStateChangeTick = self.tickCounter,
        lastWanderTick = 0,
        lastKnownZombie = nil,
        lastKnownZombiePos = nil,
        combatStartTick = nil,
        survivedCombats = 0,
        hadWeaponAtCombatStart = false,
        goalQueue = {},
        activeGoal = nil,
        activeOrder = nil,
        observedPlayer = nil,
        infectionProgress = 0,
        lastSocialActionTick = 0,
        socialRole = nil,
        lastGoalBuildTick = 0,
        patrolState = {},
        lastTrackedOrder = nil,
        lastTrackedOrderParams = nil,
        lastCompletedOrder = nil,
        lastCompletedOrderTick = 0,
        lastMoveCheckTick = 0,
        lastMoveX = nil,
        lastMoveY = nil,
        lastMoveZ = nil,
        stuckSinceTick = nil,
        lastUnstuckTick = 0,
        unstuckCount = 0,
        unstuckAuditTimestamps = {},
        unstuckSuspiciousCount = 0
    }

    self.contexts[npcId] = ctx
    return ctx
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
            local player = getSpecificPlayer(i)
            if player then
                players[#players + 1] = player
            end
        end
    end

    return players
end

local function findOnlinePlayerById(playerId)
    if not playerId then
        return nil
    end

    local players = getOnlinePlayerList()
    for i = 1, #players do
        local p = players[i]
        local pid = (p and p.getUsername and p:getUsername()) or nil
        if pid == playerId then
            return p
        end
    end

    return nil
end

function NPCBrain:sampleWeatherContext(npcEntry)
    local entity = npcEntry and npcEntry.entity or nil
    local climate = (type(getClimateManager) == "function" and getClimateManager()) or nil
    local weather = {
        temperatureC = 14,
        isRaining = false,
        isSnowing = false,
        hasShelter = false,
        hasWarmClothes = false,
        canLightFire = false
    }

    if climate then
        if climate.getTemperature then
            local ok, value = pcall(function()
                return climate:getTemperature()
            end)
            if ok and value ~= nil then
                weather.temperatureC = tonumber(value) or weather.temperatureC
            end
        end

        if climate.isRaining then
            local ok, value = pcall(function()
                return climate:isRaining()
            end)
            weather.isRaining = ok and value == true or weather.isRaining
        elseif climate.getRainIntensity then
            local ok, value = pcall(function()
                return climate:getRainIntensity()
            end)
            weather.isRaining = ok and (tonumber(value) or 0) > 0.01 or weather.isRaining
        end

        if climate.isSnowing then
            local ok, value = pcall(function()
                return climate:isSnowing()
            end)
            weather.isSnowing = ok and value == true or weather.isSnowing
        end
    end

    if entity and entity.getCurrentSquare then
        local okSq, square = pcall(function()
            return entity:getCurrentSquare()
        end)
        if okSq and square and square.getRoom then
            local okRoom, room = pcall(function()
                return square:getRoom()
            end)
            weather.hasShelter = okRoom and room ~= nil
        end
    end

    local inv = npcEntry and npcEntry.data and npcEntry.data.inventory and npcEntry.data.inventory.items or nil
    if type(inv) == "table" then
        for i = 1, #inv do
            local itemType = string.lower(tostring(inv[i] and inv[i].type or ""))
            if itemType:find("jacket", 1, true) or itemType:find("coat", 1, true) or itemType:find("sweater", 1, true) or itemType:find("hoodie", 1, true) then
                weather.hasWarmClothes = true
            end
            if itemType:find("lighter", 1, true) or itemType:find("matches", 1, true) then
                weather.canLightFire = true
            end
        end
    end

    return weather
end

function NPCBrain:findShelterSquare(npcEntry)
    local entity = npcEntry and npcEntry.entity or nil
    local cell = getCell and getCell() or nil
    if not entity or not cell or not cell.getGridSquare then
        return nil
    end

    local ex, ey, ez = getEntityPos(entity, npcEntry)
    local baseX, baseY, baseZ = math.floor(ex), math.floor(ey), math.floor(ez)

    for r = 1, self.shelterSearchRange do
        for dx = -r, r do
            for dy = -r, r do
                local sq = cell:getGridSquare(baseX + dx, baseY + dy, baseZ)
                if sq and sq.getRoom then
                    local room = sq:getRoom()
                    if room then
                        return sq
                    end
                end
            end
        end
    end

    return nil
end

function NPCBrain:removeStaleContexts(activeNPCs)
    for npcId in pairs(self.contexts) do
        if not activeNPCs[npcId] then
            self.contexts[npcId] = nil
        end
    end
end

function NPCBrain:setState(ctx, newState)
    if ctx.state == newState then
        return
    end

    ctx.state = newState
    ctx.lastStateChangeTick = self.tickCounter

    if newState == self.STATE_COMBAT or newState == self.STATE_FLEE then
        ctx.combatStartTick = self.tickCounter
    end
end

function NPCBrain:trackOrderRuntime(npcData, ctx)
    if not npcData or not ctx then
        return
    end

    local currentOrder = ctx.activeOrder
    local currentParams = ctx.activeOrderParams or nil
    local previousOrder = ctx.lastTrackedOrder
    local previousParams = ctx.lastTrackedOrderParams or nil

    npcData.activeOrder = currentOrder
    npcData.activeOrderParams = currentParams

    if previousOrder and previousOrder ~= currentOrder then
        ctx.lastCompletedOrder = previousOrder
        ctx.lastCompletedOrderTick = self.tickCounter
        npcData.lastExecutedOrder = previousOrder
        npcData.lastExecutedOrderParams = previousParams
        npcData.lastExecutedOrderTick = self.tickCounter

        if NPCMemory and NPCMemory.PushRecentEvent then
            NPCMemory.PushRecentEvent(npcData, "fsm_order_finished", {
                orderType = previousOrder,
                params = previousParams,
                tick = self.tickCounter
            })
        end
    end

    if currentOrder and currentOrder ~= previousOrder then
        npcData.lastExecutedOrder = currentOrder
        npcData.lastExecutedOrderParams = currentParams
        npcData.lastExecutedOrderTick = self.tickCounter

        if NPCMemory and NPCMemory.PushRecentEvent then
            NPCMemory.PushRecentEvent(npcData, "fsm_order_active", {
                orderType = currentOrder,
                params = currentParams,
                tick = self.tickCounter
            })
        end
    end

    ctx.lastTrackedOrder = currentOrder
    ctx.lastTrackedOrderParams = currentParams
end

function NPCBrain:runUnstuckCheck(npcId, npcEntry, npcData, ctx)
    if not self.unstuckEnabled then
        return false
    end

    local entity = npcEntry and npcEntry.entity or nil
    if not entity then
        return false
    end

    local nowTick = self.tickCounter
    local x, y, z = getEntityPos(entity, npcEntry)

    if not ctx.lastMoveX then
        ctx.lastMoveX = x
        ctx.lastMoveY = y
        ctx.lastMoveZ = z
        ctx.lastMoveCheckTick = nowTick
        return false
    end

    local moved = sqDistance2D(x, y, ctx.lastMoveX, ctx.lastMoveY)
    local movingEnough = moved >= self.unstuckMinMoveDistance

    if movingEnough then
        ctx.stuckSinceTick = nil
        ctx.lastMoveX = x
        ctx.lastMoveY = y
        ctx.lastMoveZ = z
        ctx.lastMoveCheckTick = nowTick
        return false
    end

    if not ctx.stuckSinceTick then
        ctx.stuckSinceTick = nowTick
        return false
    end

    if (nowTick - ctx.stuckSinceTick) < self.unstuckThresholdTicks then
        return false
    end

    if (nowTick - (ctx.lastUnstuckTick or 0)) < self.unstuckCooldownTicks then
        return false
    end

    local angle = math.rad(randInt(0, 359))
    local dist = randInt(self.unstuckTeleportMin, self.unstuckTeleportMax)
    local tx = x + math.cos(angle) * dist
    local ty = y + math.sin(angle) * dist
    local tz = z

    if self:requestPathMove(npcEntry, ctx, tx, ty, tz, "unstuck_environment") then
        ctx.stuckSinceTick = nowTick - math.floor(self.unstuckThresholdTicks / 3)
        return false
    end

    local teleported = forceTeleportNear(entity, npcEntry, tx, ty, tz)
    if not teleported then
        self:requestPathMove(npcEntry, ctx, tx, ty, tz, "unstuck_retry")
        return false
    end

    ctx.lastUnstuckTick = nowTick
    ctx.stuckSinceTick = nil
    ctx.unstuckCount = (ctx.unstuckCount or 0) + 1
    ctx.lastMoveX = tx
    ctx.lastMoveY = ty
    ctx.lastMoveZ = tz
    ctx.lastMoveCheckTick = nowTick

    if NPCMemory and NPCMemory.PushRecentEvent then
        NPCMemory.PushRecentEvent(npcData, "path_unstuck", {
            tick = nowTick,
            npcId = npcId,
            unstuckCount = ctx.unstuckCount,
            to = { x = math.floor(tx), y = math.floor(ty), z = math.floor(tz) }
        })
    end

    local auditNow = os.time()
    local windowSec = math.max(10, tonumber(self.unstuckSuspiciousWindowSec) or 60)
    local burst = math.max(2, tonumber(self.unstuckSuspiciousBurst) or 3)
    local marks = ctx.unstuckAuditTimestamps or {}
    marks[#marks + 1] = auditNow

    local filtered = {}
    for i = 1, #marks do
        if (auditNow - (tonumber(marks[i]) or auditNow)) <= windowSec then
            filtered[#filtered + 1] = marks[i]
        end
    end
    ctx.unstuckAuditTimestamps = filtered

    if #filtered >= burst then
        ctx.unstuckSuspiciousCount = (ctx.unstuckSuspiciousCount or 0) + 1
        local observedPlayerId = nil
        if type(ctx.observedPlayer) == "table" then
            observedPlayerId = ctx.observedPlayer.id
        end

        print(string.format("[NPCBrain][AntiStuck] Suspicious unstuck burst npc=%s burst=%d window=%ds player=%s",
            tostring(npcId), #filtered, windowSec, tostring(observedPlayerId or "none")))

        if NPCMemory and NPCMemory.PushRecentEvent then
            NPCMemory.PushRecentEvent(npcData, "path_unstuck_suspicious", {
                tick = nowTick,
                npcId = npcId,
                bursts = ctx.unstuckSuspiciousCount,
                inWindow = #filtered,
                windowSec = windowSec,
                observedPlayerId = observedPlayerId,
                pos = { x = math.floor(tx), y = math.floor(ty), z = math.floor(tz) }
            })
        end
    end

    return true
end

function NPCBrain:queuePush(ctx, goal)
    ctx.goalQueue[#ctx.goalQueue + 1] = goal
end

function NPCBrain:buildGoalQueue(npcEntry, npcData, ctx)
    local zombie, dist = self:findNearestVisibleZombie(npcEntry, self.zombieVisionRange)
    local hasThreat = zombie ~= nil
    local isHungry = npcData.stats.hunger <= self.hungerCritical
    local isThirsty = npcData.stats.thirst <= self.thirstCritical

    ctx.goalQueue = {}

    -- Priorite 1: danger
    if hasThreat then
        self:queuePush(ctx, {
            type = self.GOAL_DANGER,
            zombie = zombie,
            distance = dist,
            priority = 1
        })
    end

    -- Priorite 2: besoins
    if isHungry or isThirsty then
        self:queuePush(ctx, {
            type = self.GOAL_NEEDS,
            hunger = npcData.stats.hunger,
            thirst = npcData.stats.thirst,
            priority = 2
        })
    end

    -- Priorite 3: exploration
    self:queuePush(ctx, {
        type = self.GOAL_EXPLORE,
        priority = 3
    })

    ctx.lastGoalBuildTick = self.tickCounter
end

function NPCBrain:findNearestPlayerDisposition(npcEntry, npcData)
    if not NPCMemory then
        return nil, nil, 999999
    end

    local entity = npcEntry.entity
    if not entity then
        return nil, nil, 999999
    end

    local ex, ey, ez = getEntityPos(entity, npcEntry)
    local players = getOnlinePlayerList()
    local bestPlayer = nil
    local bestDisposition = nil
    local bestDistance = 999999

    for i = 1, #players do
        local player = players[i]
        if player and player.getX and player.getY and player.getZ then
            if math.floor(player:getZ()) == math.floor(ez) then
                local d = sqDistance2D(ex, ey, player:getX(), player:getY())
                if d <= self.playerVisionRange and d < bestDistance then
                    local pid = (player.getUsername and player:getUsername()) or tostring(i)
                    bestPlayer = player
                    bestDisposition = NPCMemory.GetDispositionTowardPlayer(npcData, pid)
                    bestDistance = d
                end
            end
        end
    end

    return bestPlayer, bestDisposition, bestDistance
end

function NPCBrain:findNearestNPCDisposition(npcId, npcEntry, npcData)
    if not NPCMemory or not NPCSpawner or type(NPCSpawner.activeNPCs) ~= "table" then
        return nil, nil, 999999
    end

    local entity = npcEntry.entity
    if not entity then
        return nil, nil, 999999
    end

    local ex, ey, ez = getEntityPos(entity, npcEntry)
    local bestId = nil
    local bestDisposition = nil
    local bestDistance = 999999

    for otherId, otherEntry in pairs(NPCSpawner.activeNPCs) do
        if otherId ~= npcId and otherEntry and otherEntry.entity then
            local ox, oy, oz = getEntityPos(otherEntry.entity, otherEntry)
            if math.floor(oz) == math.floor(ez) then
                local d = sqDistance2D(ex, ey, ox, oy)
                if d <= self.playerVisionRange and d < bestDistance then
                    bestId = otherId
                    bestDisposition = NPCMemory.GetDispositionTowardNPC(npcData, otherId)
                    bestDistance = d
                end
            end
        end
    end

    return bestId, bestDisposition, bestDistance
end

function NPCBrain:getPersonalityProfile(npcData)
    local traits = npcData and npcData.traits or {}
    local personality = traits and traits.personality or {}

    local stats = npcData and npcData.stats or {}
    local courage = stats.courage or 50
    local intelligence = stats.intelligence or 50

    local socialDrive = tonumber(personality.socialDrive) or clamp(math.floor((intelligence * 0.6) + randInt(0, 35)), 0, 100)
    local loneWolf = tonumber(personality.loneWolf) or clamp(100 - socialDrive + randInt(-12, 12), 0, 100)
    local brutality = tonumber(personality.brutality) or clamp(math.floor((100 - intelligence) * 0.35 + (100 - courage) * 0.2 + randInt(0, 25)), 0, 100)
    local opportunism = tonumber(personality.opportunism) or clamp(math.floor((100 - courage) * 0.25 + randInt(10, 45)), 0, 100)
    local adaptability = tonumber(personality.adaptability) or clamp(math.floor((intelligence * 0.5) + (courage * 0.2) + randInt(0, 30)), 0, 100)

    traits.personality = traits.personality or {}
    traits.personality.socialDrive = socialDrive
    traits.personality.loneWolf = loneWolf
    traits.personality.brutality = brutality
    traits.personality.opportunism = opportunism
    traits.personality.adaptability = adaptability
    npcData.traits = traits

    return traits.personality
end

function NPCBrain:computeSurvivalScore(npcData)
    local stats = npcData and npcData.stats or {}
    local health = npcData and npcData.health or {}
    local hp = (health.current or 75)
    local hunger = (stats.hunger or 50)
    local thirst = (stats.thirst or 50)
    local courage = (stats.courage or 50)
    local intelligence = (stats.intelligence or 50)

    local resistanceMult = math.max(0.3, tuningFactor("npcResistanceMult", 1))
    local base = ((hp * resistanceMult) * 0.35) + (hunger * 0.2) + (thirst * 0.2) + (courage * 0.1) + (intelligence * 0.15)
    if health.isBitten then
        base = base - 25
    end

    return clamp(math.floor(base), 0, 100)
end

function NPCBrain:chooseSocialRole(npcId, npcData)
    local personality = self:getPersonalityProfile(npcData)
    local survival = self:computeSurvivalScore(npcData)
    local factionId = NPCFactionManager and NPCFactionManager.getFactionOfNPC and NPCFactionManager:getFactionOfNPC(npcId) or nil

    if factionId then
        if personality.loneWolf >= 72 and survival >= 62 and randInt(1, 100) <= 12 then
            return "solo"
        end
        return "clan"
    end

    if survival <= 45 and personality.socialDrive >= 52 then
        return "community"
    end

    return personality.loneWolf >= 58 and "solo" or "community"
end

function NPCBrain:maybeRunSocialAction(npcId, npcEntry, npcData, ctx)
    if not NPCMemory or not NPCInteractionHooks then
        return
    end

    if (self.tickCounter - (ctx.lastSocialActionTick or 0)) < self.socialActionEveryTicks then
        return
    end

    local personality = self:getPersonalityProfile(npcData)
    local outgoing = NPCMemory.GetOutgoingProfile(npcData, "player", "*")
    local guilt = outgoing and outgoing.guilt or 0

    local player, pDisp, pDist = self:findNearestPlayerDisposition(npcEntry, npcData)
    local otherNpcId, nDisp, nDist = self:findNearestNPCDisposition(npcId, npcEntry, npcData)

    local acted = false

    if player and pDisp and pDist <= self.hostileActionRange then
        local brutalityDrive = personality.brutality + math.floor((pDisp.resentment or 0) * 0.6) + math.floor((pDisp.aggression or 0) * 0.5) - math.floor(guilt * 0.5)
        local opportunismDrive = personality.opportunism + math.floor((pDisp.fear or 0) * 0.4) - math.floor(guilt * 0.25)

        if brutalityDrive >= 70 and randInt(1, 100) <= 55 then
            emitImmersionFx("npc_social_threat", npcData)
            NPCInteractionHooks:handleMemoryEvent(nil, {
                sourceType = "npc",
                sourceId = npcId,
                targetType = "player",
                targetId = player:getUsername(),
                actionType = "threat",
                value = math.max(10, math.floor(brutalityDrive * 0.25)),
                hostilityType = "intimidation",
                tick = self.tickCounter
            })
            acted = true
        elseif opportunismDrive >= 62 and randInt(1, 100) <= 48 then
            emitImmersionFx("npc_social_trade", npcData)
            NPCInteractionHooks:handleMemoryEvent(nil, {
                sourceType = "npc",
                sourceId = npcId,
                targetType = "player",
                targetId = player:getUsername(),
                actionType = "theft",
                value = math.max(8, math.floor(opportunismDrive * 0.2)),
                itemType = "opportunistic_loot",
                tick = self.tickCounter
            })
            acted = true
        end
    end

    if not acted and otherNpcId and nDisp and nDist <= self.hostileActionRange then
        local warPressure = 0
        if NPCFactionManager and NPCFactionManager.getFactionOfNPC and NPCFactionManager.getRelation then
            local myFaction = NPCFactionManager:getFactionOfNPC(npcId)
            local hisFaction = NPCFactionManager:getFactionOfNPC(otherNpcId)
            if myFaction and hisFaction then
                local rel = NPCFactionManager:getRelation(myFaction, hisFaction)
                if rel == NPCFactionManager.relation.WAR then
                    warPressure = 25
                elseif rel == NPCFactionManager.relation.ALLY then
                    warPressure = -35
                end
            end
        end

        local hostilityDrive = personality.brutality + math.floor((nDisp.resentment or 0) * 0.6) + math.floor((nDisp.aggression or 0) * 0.5) + warPressure - math.floor(guilt * 0.35)
        local theftDrive = personality.opportunism + math.floor((nDisp.fear or 0) * 0.4) - math.floor(guilt * 0.2)

        if hostilityDrive >= 72 and randInt(1, 100) <= 52 then
            emitImmersionFx("npc_social_threat", npcData)
            NPCInteractionHooks:RecordNPCToNPC(npcId, otherNpcId, "hostile", {
                value = math.max(10, math.floor(hostilityDrive * 0.22)),
                hostilityType = "punish",
                tick = self.tickCounter
            })
            acted = true
        elseif theftDrive >= 64 and randInt(1, 100) <= 46 then
            emitImmersionFx("npc_social_trade", npcData)
            NPCInteractionHooks:RecordNPCToNPC(npcId, otherNpcId, "theft", {
                value = math.max(8, math.floor(theftDrive * 0.2)),
                itemType = "raided_supplies",
                tick = self.tickCounter
            })
            acted = true
        end
    end

    if not acted and player and pDisp and pDist <= self.tradeActionRange and ((pDisp.isTrusted and pDisp.trust >= 48) or (npcData and npcData.profession and npcData.profession.role == "merchant")) then
        local profession = npcData and npcData.profession or nil
        local isMerchant = profession and profession.role == "merchant"
        local offer = NPCMemory.BuildTradeOffer(npcData, "player", player:getUsername(), {
            tick = self.tickCounter,
            baseId = base and base.id or nil
        })
        local itemType = offer and offer.offers and offer.offers[1] or nil

        if isMerchant or (itemType and pDisp.trust >= 48) then
            emitImmersionFx("npc_social_trade", npcData)
            NPCInteractionHooks:handleTradeEvent(nil, {
            sourceType = "npc",
            sourceId = npcId,
            targetType = "player",
            targetId = player:getUsername(),
            mode = isMerchant and "sell" or "trade",
            itemType = itemType,
            quantity = 1,
            value = math.max(6, math.floor((pDisp.trust + (pDisp.respect or 0)) * 0.12)),
            requested = offer and offer.request and offer.request.detail or "contextual",
            tick = self.tickCounter
            })
            acted = true
        end
    end

    if not acted and otherNpcId and nDist <= self.tradeActionRange then
        local otherNpcData = NPCInteractionHooks and NPCInteractionHooks.getNPCData and select(1, NPCInteractionHooks:getNPCData(otherNpcId)) or nil
        local otherProfession = otherNpcData and otherNpcData.profession or nil
        local isMerchantTarget = otherProfession and otherProfession.role == "merchant"
        local canTrade = isMerchantTarget or (nDisp and nDisp.isTrusted and nDisp.trust >= 45)

        if canTrade then
            local offer = NPCMemory.BuildTradeOffer(npcData, "npc", otherNpcId, {
                tick = self.tickCounter,
                baseId = base and base.id or nil
            })
            local itemType = offer and offer.offers and offer.offers[1] or nil
            if itemType then
                local trustScore = nDisp and (nDisp.trust or 0) or 0
                local respectScore = nDisp and (nDisp.respect or 0) or 0
                emitImmersionFx("npc_social_trade", npcData)
                NPCInteractionHooks:handleTradeEvent(nil, {
                    sourceType = "npc",
                    sourceId = npcId,
                    targetType = "npc",
                    targetId = otherNpcId,
                    mode = isMerchantTarget and "buy" or (npcData and npcData.profession and npcData.profession.role == "merchant" and "sell" or "trade"),
                    itemType = itemType,
                    quantity = 1,
                    value = math.max(6, math.floor((trustScore + respectScore) * 0.12)),
                    requested = offer and offer.request and offer.request.detail or "mutual_help",
                    tick = self.tickCounter
                })
                acted = true
            end
        end
    end

    if acted then
        emitImmersionFx("npc_social_talk", npcData)
        ctx.lastSocialActionTick = self.tickCounter
    end
end

function NPCBrain:getTopGoal(ctx)
    return ctx.goalQueue and ctx.goalQueue[1] or nil
end

function NPCBrain:syncDebugModData(npcId, npcEntry, ctx)
    local entity = npcEntry and npcEntry.entity
    if not entity or not entity.getModData then
        return
    end

    local md = entity:getModData()
    md.PH_IsDynamicNPC = true
    md.PH_NPCId = npcId

    local goalNames = {}
    if type(ctx.goalQueue) == "table" then
        for i = 1, #ctx.goalQueue do
            local g = ctx.goalQueue[i]
            goalNames[i] = g and g.type or "unknown"
        end
    end

    local targetX, targetY, targetZ = nil, nil, nil
    if ctx.lastKnownZombie and ctx.lastKnownZombie.getX and ctx.lastKnownZombie.getY and ctx.lastKnownZombie.getZ then
        targetX = math.floor(ctx.lastKnownZombie:getX())
        targetY = math.floor(ctx.lastKnownZombie:getY())
        targetZ = math.floor(ctx.lastKnownZombie:getZ())
    elseif type(ctx.lastKnownZombiePos) == "table" then
        targetX = ctx.lastKnownZombiePos.x
        targetY = ctx.lastKnownZombiePos.y
        targetZ = ctx.lastKnownZombiePos.z
    end

    md.PH_FSM = {
        state = ctx.state,
        activeGoal = ctx.activeGoal,
        activeOrder = ctx.activeOrder,
        lastCompletedOrder = ctx.lastCompletedOrder,
        socialRole = ctx.socialRole,
        survivalScore = ctx.survivalScore,
        factionId = ctx.factionId,
        infectionStatus = ctx.infectionStatus,
        infectionProgress = ctx.infectionProgress,
        goalQueue = goalNames,
        tick = self.tickCounter,
        lastThinkTick = ctx.lastThinkTick,
        lastStateChangeTick = ctx.lastStateChangeTick,
        combatStartTick = ctx.combatStartTick,
        survivedCombats = ctx.survivedCombats,
        hadWeaponAtCombatStart = ctx.hadWeaponAtCombatStart,
        target = {
            x = targetX,
            y = targetY,
            z = targetZ
        }
    }

    if type(ctx.observedPlayer) == "table" then
        md.PH_FSM.observedPlayer = {
            id = ctx.observedPlayer.id,
            trust = ctx.observedPlayer.trust,
            fear = ctx.observedPlayer.fear,
            respect = ctx.observedPlayer.respect,
            reputation = ctx.observedPlayer.reputation,
            gratitude = ctx.observedPlayer.gratitude,
            resentment = ctx.observedPlayer.resentment,
            dangerous = ctx.observedPlayer.isDangerous,
            feared = ctx.observedPlayer.isFeared,
            trusted = ctx.observedPlayer.isTrusted,
            distance = ctx.observedPlayer.distance
        }
    else
        md.PH_FSM.observedPlayer = nil
    end

    if entity.transmitModData then
        pcall(function()
            entity:transmitModData()
        end)
    end
end

function NPCBrain:requestPathMove(npcEntry, ctx, x, y, z, reason)
    local entity = npcEntry and npcEntry.entity or nil
    if not entity then
        return false
    end

    if NPCEnvironmentHooks and NPCEnvironmentHooks.tryPathWithEnvironment then
        local ok, result = pcall(function()
            return NPCEnvironmentHooks:tryPathWithEnvironment({
                entity = entity,
                npcEntry = npcEntry,
                npcData = ctx and ctx.npcData or nil,
                ctx = ctx,
                x = x,
                y = y,
                z = z,
                reason = reason or "move",
                tick = self.tickCounter
            })
        end)

        if ok and result == true then
            return true
        end
    end

    return entityCanPathTo(entity, x, y, z)
end

function NPCBrain:doApproachPosition(npcEntry, ctx, x, y, z)
    local entity = npcEntry.entity
    if not entity then
        return false
    end

    self:setState(ctx, self.STATE_WANDER)
    return self:requestPathMove(npcEntry, ctx, x, y, z, "approach_position")
end

function NPCBrain:doAvoidPosition(npcEntry, ctx, x, y, z)
    local entity = npcEntry.entity
    if not entity then
        return false
    end

    self:setState(ctx, self.STATE_FLEE)

    local ex, ey, ez = getEntityPos(entity, npcEntry)
    local vx = ex - x
    local vy = ey - y
    local mag = math.sqrt((vx * vx) + (vy * vy))
    if mag < 0.1 then
        vx = randInt(-100, 100) / 100
        vy = randInt(-100, 100) / 100
        mag = math.sqrt((vx * vx) + (vy * vy))
    end

    vx = vx / mag
    vy = vy / mag
    local tx = ex + (vx * randInt(8, 14))
    local ty = ey + (vy * randInt(8, 14))
    return self:requestPathMove(npcEntry, ctx, tx, ty, z or ez, "avoid_position")
end

function NPCBrain:handleInfectionBehavior(npcEntry, npcData, ctx)
    if not NPCMemory then
        ctx.infectionStatus = nil
        return false
    end

    local result = NPCMemory.UpdateInfectionBehavior(npcData, {
        tick = self.tickCounter
    })
    ctx.infectionStatus = result and result.status or nil
    ctx.infectionProgress = result and result.progress or 0

    if not result or result.status == "healthy" or result.status == "infected" then
        return false
    end

    local entity = npcEntry.entity
    if not entity then
        return false
    end

    local player = select(1, self:findNearestPlayerDisposition(npcEntry, npcData))
    if result.status == "leave_discreetly" then
        if player then
            return self:doAvoidPosition(npcEntry, ctx, player:getX(), player:getY(), player:getZ())
        end
        return self:doIdleOrWander(npcEntry, ctx) or true
    end

    if result.status == "sudden_attack" then
        if player then
            self:setState(ctx, self.STATE_COMBAT)
            ctx.activeGoal = self.GOAL_DANGER
            return self:doApproachPosition(npcEntry, ctx, player:getX(), player:getY(), player:getZ())
        end

        local zombie = select(1, self:findNearestVisibleZombie(npcEntry, self.zombieVisionRange + 6))
        if zombie then
            self:doCombat(npcEntry, npcData, ctx, zombie)
            return true
        end
    end

    return false
end

function NPCBrain:pathToCenterIfFar(npcEntry, ctx, center, maxRadius)
    if not center then
        return false
    end

    local entity = npcEntry and npcEntry.entity or nil
    if not entity then
        return false
    end

    local ex, ey, ez = getEntityPos(entity)
    local dist = sqDistance2D(ex, ey, center.x or ex, center.y or ey)
    if dist <= (maxRadius or 4) then
        return false
    end

    return self:requestPathMove(npcEntry, ctx, center.x or ex, center.y or ey, center.z or ez, "order_center")
end

function NPCBrain:getOrderWaypoint(ctx, order)
    local params = order and order.params or nil
    if not params then
        return nil
    end

    local waypoints = params.waypoints or params.perimeter
    if type(waypoints) ~= "table" or #waypoints == 0 then
        return nil
    end

    local baseKey = params.baseId or "generic"
    ctx.patrolState[baseKey] = ctx.patrolState[baseKey] or {
        index = 1,
        lastAdvanceTick = 0
    }

    local tracker = ctx.patrolState[baseKey]
    local current = waypoints[tracker.index]
    if not current then
        tracker.index = 1
        current = waypoints[1]
    end

    -- Avance periodiquement sur le prochain point pour une boucle stable.
    if (self.tickCounter - tracker.lastAdvanceTick) > math.floor(self.thinkEveryTicks * 1.5) then
        tracker.index = (tracker.index % #waypoints) + 1
        tracker.lastAdvanceTick = self.tickCounter
        current = waypoints[tracker.index] or current
    end

    return current
end

function NPCBrain:runGuardOrder(npcEntry, npcData, ctx, order)
    local entity = npcEntry.entity
    if not entity then
        return false
    end

    local params = order.params or {}
    local center = params.center or { x = npcEntry.x, y = npcEntry.y, z = npcEntry.z }
    local radius = params.radius or 10

    self:setState(ctx, self.STATE_WANDER)
    ctx.activeGoal = self.GOAL_DANGER

    local used = self:pathToCenterIfFar(npcEntry, ctx, center, radius)
    if used then
        return true
    end

    -- Patrouille prioritaire via waypoints persistants de base.
    local wp = self:getOrderWaypoint(ctx, order)
    if wp then
        emitImmersionFx("npc_patrol", npcData)
        self:requestPathMove(npcEntry, ctx, wp.x or center.x, wp.y or center.y, wp.z or center.z or npcEntry.z, "guard_waypoint")
        ctx.lastWanderTick = self.tickCounter
        return true
    end

    -- Fallback: patrouille legere autour du centre de garde.
    if (self.tickCounter - (ctx.lastWanderTick or 0)) > self.thinkEveryTicks then
        local angle = math.rad(randInt(0, 359))
        local dist = randInt(3, radius)
        local tx = (center.x or npcEntry.x) + math.cos(angle) * dist
        local ty = (center.y or npcEntry.y) + math.sin(angle) * dist
        emitImmersionFx("npc_watch", npcData)
        self:requestPathMove(npcEntry, ctx, tx, ty, center.z or npcEntry.z, "guard_patrol")
        ctx.lastWanderTick = self.tickCounter
    end

    return true
end

function NPCBrain:runStayOrder(npcEntry, npcData, ctx, order)
    local params = order.params or {}
    local center = params.center or { x = npcEntry.x, y = npcEntry.y, z = npcEntry.z }
    local radius = params.radius or 2

    self:setState(ctx, self.STATE_IDLE)
    ctx.activeGoal = self.GOAL_EXPLORE

    local entity = npcEntry.entity
    if entity then
        emitImmersionFx("npc_watch", npcData)
        self:pathToCenterIfFar(npcEntry, ctx, center, radius)
    end

    return true
end

function NPCBrain:runFollowOrder(npcEntry, npcData, ctx, order)
    local params = order.params or {}
    local lx, ly, lz = nil, nil, nil

    if params.followPlayerId then
        local leaderPlayer = findOnlinePlayerById(params.followPlayerId)
        if not leaderPlayer then
            return false
        end
        lx, ly, lz = leaderPlayer:getX(), leaderPlayer:getY(), math.floor(leaderPlayer:getZ())
    else
        local leaderId = params.followNpcId or order.issuerId
        if not leaderId or not NPCSpawner or not NPCSpawner.activeNPCs then
            return false
        end

        local leader = NPCSpawner.activeNPCs[leaderId]
        if not leader or not leader.entity then
            return false
        end

        lx, ly, lz = getEntityPos(leader.entity, leader)
    end

    local entity = npcEntry.entity
    if not entity then
        return false
    end

    self:setState(ctx, self.STATE_WANDER)
    ctx.activeGoal = self.GOAL_EXPLORE

    local ex, ey = getEntityPos(entity, npcEntry)
    local d = sqDistance2D(ex, ey, lx, ly)
    local desiredDistance = math.max(2, tonumber(params.desiredDistance) or 3)
    local maxDistance = math.max(desiredDistance + 2, tonumber(params.maxDistance) or (desiredDistance + 5))
    local mobilityPenalty = npcData.runtimePenalties and tonumber(npcData.runtimePenalties.mobility) or 0
    local canMoveThisTick = true

    if mobilityPenalty >= 35 then
        desiredDistance = desiredDistance + 1
    end
    if mobilityPenalty >= 55 and (self.tickCounter % 2) == 0 then
        canMoveThisTick = false
    end

    if d > maxDistance and canMoveThisTick then
        self:requestPathMove(npcEntry, ctx, lx, ly, lz, "follow_leader")
    elseif d < desiredDistance then
        self:doAvoidPosition(npcEntry, ctx, lx, ly, lz)
    elseif not canMoveThisTick then
        self:setState(ctx, self.STATE_IDLE)
    end

    return true
end

function NPCBrain:runRecoverOrder(npcData, ctx)
    self:setState(ctx, self.STATE_SURVIVE)
    ctx.activeGoal = self.GOAL_NEEDS

    local stats = npcData.stats
    local recoveryMult = math.max(0.2, tuningFactor("recoveryRateMult", 1))
    stats.hunger = clamp(stats.hunger + (0.06 * recoveryMult), 0, 100)
    stats.thirst = clamp(stats.thirst + (0.08 * recoveryMult), 0, 100)
    emitImmersionFx("npc_recover", npcData)
    if (tonumber(stats.fatigue) or 0) > 0 then
        emitImmersionFx("npc_fatigue", npcData)
    end
    return true
end

function NPCBrain:runStudyOrder(npcData, ctx)
    self:setState(ctx, self.STATE_IDLE)
    ctx.activeGoal = self.GOAL_EXPLORE

    local stats = npcData.stats
    local learningMult = math.max(0.2, tuningFactor("learningRateMult", 1))
    stats.intelligence = clamp(stats.intelligence + (0.03 * learningMult), 0, 100)
    stats.craftSkill = clamp(stats.craftSkill + (0.02 * learningMult), 0, 100)

    local params = ctx.activeOrderParams or {}
    if params.businessService == "craft" and NPCMemory and NPCMemory.ResolveProductionPlan then
        local plan = params.productionPlan or NPCMemory.ResolveProductionPlan(npcData, params)
        params.productionPlan = plan

        if not params.ingredientsConsumed and NPCMemory.ConsumeProductionIngredients then
            local consumed, missing = NPCMemory.ConsumeProductionIngredients(npcData, plan)
            if not consumed then
                params.productionMissingIngredients = missing
                return true
            end
            params.ingredientsConsumed = true
        end

        if params.productionCompleted then
            return true
        end

        params.productionProgress = (tonumber(params.productionProgress) or 0) + 1 + math.floor((stats.craftSkill or 0) / 40)
        if params.productionProgress >= (plan.workUnits or 6) then
            local completed = false
            local result = nil
            if NPCMemory.CompleteProductionPlan then
                completed, result = NPCMemory.CompleteProductionPlan(npcData, plan)
            end
            if completed and result and params.deliveryToPlayerId and NPCInteractionHooks and NPCInteractionHooks.handleTradeEvent then
                NPCInteractionHooks:handleTradeEvent(nil, {
                    sourceType = "npc",
                    sourceId = ctx.npcId,
                    targetType = "player",
                    targetId = params.deliveryToPlayerId,
                    mode = "sell",
                    itemType = result.itemType,
                    quantity = result.quantity or 1,
                    price = 0,
                    value = 0,
                    prepaid = true,
                    requested = "business_delivery",
                    tick = NPCFactionManager and NPCFactionManager.tickCounter or 0
                })
                params.productionCompleted = true
            end
        end
        return true
    end
    return true
end

function NPCBrain:runCookOrder(npcEntry, npcData, ctx)
    self:setState(ctx, self.STATE_SURVIVE)
    ctx.activeGoal = self.GOAL_NEEDS

    if self:consumeFromInventory(npcData) then
        return true
    end

    local found = self:lootNearbyContainers(npcEntry, npcData)
    if found then
        self:consumeFromInventory(npcData)
    end

    return true
end

function NPCBrain:runBuildOrder(npcEntry, npcData, ctx, order)
    local entity = npcEntry.entity
    if not entity then
        return false
    end

    self:setState(ctx, self.STATE_WANDER)
    ctx.activeGoal = self.GOAL_EXPLORE

    local params = order.params or {}
    if params.businessService == "build" and NPCMemory and NPCMemory.ConsumeProductionIngredients then
        local plan = params.productionPlan or (NPCMemory.ResolveProductionPlan and NPCMemory.ResolveProductionPlan(npcData, params))
        params.productionPlan = plan
        if plan and not params.ingredientsConsumed then
            local consumed = NPCMemory.ConsumeProductionIngredients(npcData, plan)
            if consumed then
                params.ingredientsConsumed = true
            end
        end
    end
    local center = params.center or { x = npcEntry.x, y = npcEntry.y, z = npcEntry.z }
    local radius = params.radius or 10

    if params.baseId and params.buildSiteId and NPCFactionManager and NPCFactionManager.getBuildSite then
        local site = NPCFactionManager:getBuildSite(params.baseId, params.buildSiteId)
        if site and not site.completed then
            center = { x = site.x, y = site.y, z = site.z }
        end
    end

    -- Selection d'une zone de travail proche (waypoint prioritaire si fourni).
    local wp = self:getOrderWaypoint(ctx, order)
    if wp then
        self:requestPathMove(npcEntry, ctx, wp.x or npcEntry.x, wp.y or npcEntry.y, wp.z or npcEntry.z, "build_waypoint")
    else
        local angle = math.rad(randInt(0, 359))
        local dist = randInt(2, radius)
        local tx = (center.x or npcEntry.x) + math.cos(angle) * dist
        local ty = (center.y or npcEntry.y) + math.sin(angle) * dist
        self:requestPathMove(npcEntry, ctx, tx, ty, center.z or npcEntry.z, "build_patrol")
    end

    -- Progression legere de construction/craft.
    local stats = npcData.stats
    local fabricationMult = math.max(0.2, tuningFactor("fabricationSpeedMult", 1))
    stats.craftSkill = clamp(stats.craftSkill + (0.03 * fabricationMult), 0, 100)
    stats.strength = clamp(stats.strength + (0.01 * fabricationMult), 0, 100)

    if params.baseId and NPCFactionManager and NPCFactionManager.recordBuildWork then
        local work = 1 + math.floor((stats.craftSkill or 0) / 30)
        NPCFactionManager:recordBuildWork(params.baseId, npcEntry.id or "unknown", work)
    end

    return true
end

function NPCBrain:runDefendOrder(npcEntry, npcData, ctx, order)
    local params = order and order.params or {}

    if params.coverPlayerId then
        local player = findOnlinePlayerById(params.coverPlayerId)
        if player then
            local entity = npcEntry.entity
            if entity then
                local ex, ey = getEntityPos(entity, npcEntry)
                local px, py, pz = player:getX(), player:getY(), math.floor(player:getZ())
                local d = sqDistance2D(ex, ey, px, py)
                local coverRadius = math.max(2, tonumber(params.coverRadius) or 5)
                if d > coverRadius then
                    self:requestPathMove(npcEntry, ctx, px, py, pz, "defend_cover")
                    self:setState(ctx, self.STATE_WANDER)
                    ctx.activeGoal = self.GOAL_DANGER
                    return true
                end
            end
        end
    end

    local zombie = select(1, self:findNearestVisibleZombie(npcEntry, self.zombieVisionRange + 4))
    if zombie then
        local courage = npcData.stats.courage or 50
        local armed = self:hasWeapon(npcData)
        local attackThreshold = armed and 20 or 48
        if params.aggressiveCover == true then
            attackThreshold = math.max(8, attackThreshold - 12)
        end

        if courage >= attackThreshold then
            self:doCombat(npcEntry, npcData, ctx, zombie)
        else
            self:doFlee(npcEntry, npcData, ctx, zombie)
        end
        return true
    end

    return self:runGuardOrder(npcEntry, npcData, ctx, order)
end

function NPCBrain:tryStartOffscreenExpedition(npcId, npcEntry, npcData, ctx)
    if not NPCMemory or not NPCMemory.ScheduleExpedition then
        return false
    end

    local params = ctx.activeOrderParams or {}
    local targetDistance = math.max(
        tonumber(params.expeditionDistance) or 0,
        tonumber(params.targetDistance) or 0,
        tonumber(params.distance) or 0
    )

    local expeditionThreshold = math.max(1, math.floor(self.expeditionDistanceThreshold * math.max(0.2, tuningFactor("expeditionDistanceThresholdMult", 1))))
    if targetDistance < expeditionThreshold then
        return false
    end

    if npcData and npcData.memory and npcData.memory.expedition and npcData.memory.expedition.active then
        return true
    end

    local schedule = NPCMemory.ScheduleExpedition(npcData, {
        tick = self.tickCounter,
        distance = targetDistance,
        orderType = "scavenge",
        baseDuration = self.expeditionBaseDurationTicks,
        durationFactor = self.expeditionDistanceFactor,
        targetItemHint = params.targetItemHint,
        baseId = params.baseId,
        buildSiteId = params.buildSiteId
    })

    if NPCMemory and NPCMemory.PushRecentEvent then
        NPCMemory.PushRecentEvent(npcData, "scavenge_offscreen_departure", {
            tick = self.tickCounter,
            distance = targetDistance,
            returnTick = schedule and schedule.returnTick or nil,
            willReturn = schedule and schedule.willReturn or nil
        })
    end

    if NPCSpawner and NPCSpawner.despawnNPC then
        NPCSpawner:despawnNPC(npcId)
        ctx.activeOrder = "expedition"
        ctx.activeGoal = self.GOAL_EXPLORE
        return true
    end

    return false
end

function NPCBrain:runScavengeOrder(npcId, npcEntry, npcData, ctx)
    self:setState(ctx, self.STATE_SURVIVE)
    ctx.activeGoal = self.GOAL_NEEDS

    if self:tryStartOffscreenExpedition(npcId, npcEntry, npcData, ctx) then
        return true
    end

    local stealthMode = ctx.activeOrderParams and ctx.activeOrderParams.stealthScavenge == true
    if stealthMode then
        local zombie = select(1, self:findNearestVisibleZombie(npcEntry, self.zombieVisionRange))
        if zombie then
            self:doFlee(npcEntry, npcData, ctx, zombie)
            return true
        end
    end

    local targetItemHint = ctx.activeOrderParams and ctx.activeOrderParams.targetItemHint or nil
    if not self:lootNearbyContainers(npcEntry, npcData, targetItemHint) then
        self:doIdleOrWander(npcEntry, ctx)
    end
    return true
end

function NPCBrain:executeOrderObject(npcEntry, npcData, ctx, order)
    if not order then
        return false
    end

    local orderType = order.orderType
    ctx.activeOrder = orderType
    ctx.activeOrderParams = order.params or nil

    if orderType == "guard" or orderType == "patrol" then
        emitImmersionFx(orderType == "guard" and "npc_watch" or "npc_patrol", npcData)
        return self:runGuardOrder(npcEntry, npcData, ctx, order)
    elseif orderType == "stay" or orderType == "sleep" then
        emitImmersionFx(orderType == "sleep" and "npc_sleep" or "npc_watch", npcData)
        if orderType == "sleep" then
            ctx.recentSleepOrder = true
        end
        return self:runStayOrder(npcEntry, npcData, ctx, order)
    elseif orderType == "follow" then
        emitImmersionFx("npc_follow", npcData)
        return self:runFollowOrder(npcEntry, npcData, ctx, order)
    elseif orderType == "defend" then
        emitImmersionFx("npc_defend", npcData)
        return self:runDefendOrder(npcEntry, npcData, ctx, order)
    elseif orderType == "recover" then
        emitImmersionFx("npc_recover", npcData)
        return self:runRecoverOrder(npcData, ctx)
    elseif orderType == "study" then
        emitImmersionFx("npc_study", npcData)
        return self:runStudyOrder(npcData, ctx)
    elseif orderType == "cook" then
        emitImmersionFx("npc_cook", npcData)
        return self:runCookOrder(npcEntry, npcData, ctx)
    elseif orderType == "build" then
        emitImmersionFx("npc_build", npcData)
        return self:runBuildOrder(npcEntry, npcData, ctx, order)
    elseif orderType == "scavenge" then
        emitImmersionFx("npc_scavenge", npcData)
        return self:runScavengeOrder(ctx.npcId, npcEntry, npcData, ctx)
    end

    return false
end

function NPCBrain:executeOrder(npcId, npcEntry, npcData, ctx)
    if not NPCFactionManager or not NPCFactionManager.getOrder then
        ctx.activeOrder = nil
        return false
    end

    local order = NPCFactionManager:getOrder(npcId)
    if not order then
        ctx.activeOrder = nil
        return false
    end

    return self:executeOrderObject(npcEntry, npcData, ctx, order)
end

function NPCBrain:hasWeapon(npcData)
    local inv = npcData and npcData.inventory
    local items = inv and inv.items
    if type(items) ~= "table" then
        return false
    end

    for i = 1, #items do
        local it = items[i]
        local t = it and it.type or ""
        if stringContainsAny(t, { "Knife", "Axe", "Bat", "Hammer", "Crowbar", "Machete", "Spear", "Pistol", "Shotgun", "Rifle" }) then
            return true
        end
    end
    return false
end

function NPCBrain:findNearestVisibleZombie(npcEntry, maxDistance)
    local entity = npcEntry.entity
    if not entity then
        return nil, 999999
    end

    local zombies = self.cachedZombieList
    if not zombies then
        local cell = getCell and getCell() or nil
        if not cell or not cell.getZombieList then
            return nil, 999999
        end
        zombies = cell:getZombieList()
    end

    if not zombies or not zombies.size then
        return nil, 999999
    end

    local ex, ey, ez = getEntityPos(entity, npcEntry)
    local bestZombie = nil
    local bestDist = 999999

    for i = 0, zombies:size() - 1 do
        local z = zombies:get(i)
        if z and z.getX and z.getY and z.getZ then
            if math.floor(z:getZ()) == math.floor(ez) then
                local d = sqDistance2D(ex, ey, z:getX(), z:getY())
                if d < bestDist and d <= maxDistance and canSeeTarget(entity, z) then
                    bestZombie = z
                    bestDist = d
                end
            end
        end
    end

    return bestZombie, bestDist
end

function NPCBrain:consumeFromInventory(npcData)
    local stats = npcData and npcData.stats
    local inv = npcData and npcData.inventory
    if not stats or not inv or type(inv.items) ~= "table" then
        return false
    end

    local needsFood = stats.hunger <= self.hungerCritical
    local needsWater = stats.thirst <= self.thirstCritical
    if not needsFood and not needsWater then
        return false
    end

    for i = #inv.items, 1, -1 do
        local item = inv.items[i]
        local itemType = (item and item.type) or ""

        local isWater = needsWater and stringContainsAny(itemType, self.waterHints)
        local isFood = needsFood and stringContainsAny(itemType, self.foodHints)

        if isWater or isFood then
            if isWater then
                stats.thirst = clamp(stats.thirst + randInt(25, 45), 0, 100)
            end
            if isFood then
                stats.hunger = clamp(stats.hunger + randInt(18, 35), 0, 100)
            end

            if isWater then
                emitImmersionFx("npc_drink", npcData)
            end
            if isFood then
                emitImmersionFx("npc_eat", npcData)
            end

            item.quantity = (item.quantity or 1) - 1
            if item.quantity <= 0 then
                table.remove(inv.items, i)
            end

            inv.currentWeight = math.max(0, (inv.currentWeight or #inv.items) - 1)
            return true
        end
    end

    return false
end

function NPCBrain:lootNearbyContainers(npcEntry, npcData, targetItemHint)
    local entity = npcEntry.entity
    local cell = getCell and getCell() or nil
    if not entity or not cell or not cell.getGridSquare then
        return false
    end

    local ex, ey, ez = getEntityPos(entity, npcEntry)
    ex = math.floor(ex)
    ey = math.floor(ey)
    ez = math.floor(ez)

    local inv = npcData.inventory
    inv.items = inv.items or {}

    local maxChecks = 36
    local checks = 0

    for dx = -self.containerSearchRange, self.containerSearchRange do
        for dy = -self.containerSearchRange, self.containerSearchRange do
            if checks >= maxChecks then
                return false
            end
            checks = checks + 1

            local sq = cell:getGridSquare(ex + dx, ey + dy, ez)
            if sq and sq.getObjects then
                local objects = sq:getObjects()
                if objects and objects.size then
                    for i = 0, objects:size() - 1 do
                        local obj = objects:get(i)
                        local container = obj and obj.getContainer and obj:getContainer() or nil
                        if container and container.getItems then
                            local items = container:getItems()
                            if items and items.size then
                                for k = 0, items:size() - 1 do
                                    local worldItem = items:get(k)
                                    local fullType = worldItem and worldItem.getFullType and worldItem:getFullType() or ""

                                    local hasHint = type(targetItemHint) == "string" and targetItemHint ~= ""
                                    local matchesHint = hasHint and string.find(string.lower(fullType), string.lower(targetItemHint), 1, true) ~= nil
                                    if matchesHint or stringContainsAny(fullType, self.foodHints) or stringContainsAny(fullType, self.waterHints) then
                                        table.insert(inv.items, {
                                            type = fullType,
                                            condition = 100,
                                            quantity = 1
                                        })
                                        inv.currentWeight = (inv.currentWeight or #inv.items) + 1
                                        return true
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return false
end

function NPCBrain:doIdleOrWander(npcEntry, ctx)
    local entity = npcEntry.entity
    if not entity then
        return
    end

    if ctx.recentSleepOrder == true then
        emitImmersionFx("npc_wake", ctx.npcData or npcEntry.data or nil)
        ctx.recentSleepOrder = false
    end

    if (self.tickCounter - ctx.lastWanderTick) < self.thinkEveryTicks then
        self:setState(ctx, self.STATE_IDLE)
        return
    end

    local ex, ey, ez = getEntityPos(entity, npcEntry)
    local angle = math.rad(randInt(0, 359))
    local dist = randInt(self.wanderMinDistance, self.wanderMaxDistance)
    local tx = ex + math.cos(angle) * dist
    local ty = ey + math.sin(angle) * dist

    setNPCMotion(entity, false)  -- marche ou idle
    if self:requestPathMove(npcEntry, ctx, tx, ty, ez, "idle_wander") then
        self:setState(ctx, self.STATE_WANDER)
        ctx.lastWanderTick = self.tickCounter
    else
        self:setState(ctx, self.STATE_IDLE)
    end
end

function NPCBrain:doSurvive(npcEntry, npcData, ctx)
    self:setState(ctx, self.STATE_SURVIVE)

    local beforeHunger = tonumber(npcData and npcData.stats and npcData.stats.hunger) or 50
    local beforeThirst = tonumber(npcData and npcData.stats and npcData.stats.thirst) or 50
    if self:consumeFromInventory(npcData) then
        local afterHunger = tonumber(npcData and npcData.stats and npcData.stats.hunger) or beforeHunger
        local afterThirst = tonumber(npcData and npcData.stats and npcData.stats.thirst) or beforeThirst
        if afterHunger > beforeHunger then
            emitImmersionFx("npc_eat", npcData)
        end
        if afterThirst > beforeThirst then
            emitImmersionFx("npc_drink", npcData)
        end
        return
    end

    local foundLoot = self:lootNearbyContainers(npcEntry, npcData)
    if foundLoot then
        emitImmersionFx("npc_scavenge", npcData)
        self:consumeFromInventory(npcData)
        return
    end

    -- Pas de ressource: le PNJ continue a errer pour chercher.
    self:doIdleOrWander(npcEntry, ctx)
end

function NPCBrain:doFreeze(npcEntry, npcData, ctx, freezeUntilTick)
    self:setState(ctx, self.STATE_FREEZE)
    ctx.activeGoal = self.GOAL_DANGER
    local freezeDurationMult = math.max(0.25, tuningFactor("freezeDurationMult", 1))
    local fallbackFreeze = self.tickCounter + math.floor(randInt(self.freezeMinTicks, self.freezeMaxTicks) * freezeDurationMult)
    ctx.freezeUntilTick = math.max(tonumber(ctx.freezeUntilTick) or 0, tonumber(freezeUntilTick) or fallbackFreeze)

    if NPCMemory and NPCMemory.PushRecentEvent and (ctx.lastFreezeEventTick or 0) + 40 < self.tickCounter then
        ctx.lastFreezeEventTick = self.tickCounter
        NPCMemory.PushRecentEvent(npcData, "fsm_freeze", {
            tick = self.tickCounter,
            freezeUntilTick = ctx.freezeUntilTick
        })
    end

    local entity = npcEntry and npcEntry.entity or nil
    if entity and entity.StopAllActionQueue then
        pcall(function()
            entity:StopAllActionQueue()
        end)
    end

    return true
end

function NPCBrain:seekShelter(npcEntry, npcData, ctx, reason)
    local shelter = self:findShelterSquare(npcEntry)
    if not shelter then
        return false
    end

    local ok = self:requestPathMove(npcEntry, ctx, shelter:getX(), shelter:getY(), shelter:getZ(), reason or "seek_shelter")
    if ok and NPCMemory and NPCMemory.PushRecentEvent then
        NPCMemory.PushRecentEvent(npcData, "weather_shelter_path", {
            tick = self.tickCounter,
            x = shelter:getX(),
            y = shelter:getY(),
            z = shelter:getZ(),
            reason = reason
        })
    end
    return ok
end

function NPCBrain:doCombat(npcEntry, npcData, ctx, zombie)
    local entity = npcEntry.entity
    if not entity or not zombie then
        self:setState(ctx, self.STATE_IDLE)
        return
    end

    self:setState(ctx, self.STATE_COMBAT)
    ctx.activeGoal = self.GOAL_DANGER

    -- Comportement offensif best effort.
    -- IMPORTANT: pathToCharacter provoque des crashes sur les PNJ IsoPlayer
    -- (ClassCastException cote moteur, notamment autour des vehicules).
    local isoPlayerNpc = isIsoPlayerEntity(entity)

    if entity.setTarget then
        pcall(function()
            entity:setTarget(zombie)
        end)
    end

    if isoPlayerNpc then
        -- IsoPlayer: approche via getPathFindBehavior2, court vers la cible
        setNPCMotion(entity, true)
        if zombie.getX and zombie.getY then
            entityCanPathTo(entity, zombie:getX(), zombie:getY(), zombie:getZ() or 0)
        end
        if entity.faceThisObject then
            pcall(function() entity:faceThisObject(zombie) end)
        end
        if entity.NPCSetMelee then
            pcall(function() entity:NPCSetMelee(true) end)
        end
        if entity.NPCSetAttack then
            pcall(function() entity:NPCSetAttack(true) end)
        end
        if entity.AttemptAttack then
            pcall(function() entity:AttemptAttack(10.0) end)
        end
    elseif not isoPlayerNpc and entity.pathToCharacter then
        pcall(function()
            entity:pathToCharacter(zombie)
        end)
    elseif entity.pathToLocationF and zombie.getX and zombie.getY then
        pcall(function()
            entity:pathToLocationF(zombie:getX(), zombie:getY(), zombie:getZ() or 0)
        end)
    end

    -- Si la menace disparait, on valide la survie de combat.
    local stillSeen = canSeeTarget(entity, zombie)
    if not stillSeen and ctx.combatStartTick and (self.tickCounter - ctx.combatStartTick) > 80 then
        ctx.survivedCombats = (ctx.survivedCombats or 0) + 1
        self:setState(ctx, self.STATE_IDLE)
    end

    -- Evolution autonome du courage apres survies successives.
    if npcData.stats.courage <= self.cowardThreshold and ctx.survivedCombats > 0 then
        if (ctx.survivedCombats % self.combatSurvivalBonus) == 0 then
            if npcData.adjustStat then
                npcData:adjustStat("courage", 2)
            else
                npcData.stats.courage = clamp(npcData.stats.courage + 2, 0, 100)
            end
            ctx.survivedCombats = 0
        end
    end
end

function NPCBrain:doFlee(npcEntry, npcData, ctx, zombie)
    local entity = npcEntry.entity
    if not entity then
        self:setState(ctx, self.STATE_IDLE)
        return
    end

    self:setState(ctx, self.STATE_FLEE)
    ctx.activeGoal = self.GOAL_DANGER

    local ex, ey, ez = getEntityPos(entity, npcEntry)
    local zx, zy = ex - 1, ey - 1

    if zombie and zombie.getX and zombie.getY then
        zx, zy = zombie:getX(), zombie:getY()
    end

    local vx = ex - zx
    local vy = ey - zy
    local mag = math.sqrt((vx * vx) + (vy * vy))
    if mag < 0.1 then
        vx = randInt(-100, 100) / 100
        vy = randInt(-100, 100) / 100
        mag = math.sqrt((vx * vx) + (vy * vy))
    end

    vx = vx / mag
    vy = vy / mag

    local fleeDist = randInt(8, 13)
    local tx = ex + (vx * fleeDist)
    local ty = ey + (vy * fleeDist)
    setNPCMotion(entity, true)  -- court en fuyant
    self:requestPathMove(npcEntry, ctx, tx, ty, ez, "flee")

    if ctx.combatStartTick and (self.tickCounter - ctx.combatStartTick) > self.fleeDurationTicks then
        ctx.survivedCombats = (ctx.survivedCombats or 0) + 1
        self:setState(ctx, self.STATE_IDLE)

        if npcData.stats.courage <= self.cowardThreshold then
            if npcData.adjustStat then
                npcData:adjustStat("courage", 1)
            else
                npcData.stats.courage = clamp(npcData.stats.courage + 1, 0, 100)
            end
        end
    end
end

function NPCBrain:degradeNeeds(npcData)
    if self.disableNeedsDecay == true then
        return
    end

    local stats = npcData and npcData.stats
    if not stats then
        return
    end

    -- Simu legere d'usure des besoins.
    local needsDecayMult = math.max(0.2, tuningFactor("needsDecayMult", 1))
    stats.hunger = clamp(stats.hunger - (0.10 * needsDecayMult), 0, 100)
    stats.thirst = clamp(stats.thirst - (0.14 * needsDecayMult), 0, 100)
end

function NPCBrain:decideState(npcEntry, npcData, ctx)
    if (tonumber(ctx.freezeUntilTick) or 0) > self.tickCounter then
        self:doFreeze(npcEntry, npcData, ctx, ctx.freezeUntilTick)
        return
    end

    if self:handleInfectionBehavior(npcEntry, npcData, ctx) then
        return
    end

    if ctx.weatherState and (ctx.weatherState.needsShelter or ctx.weatherState.needsWarmth) then
        local shelterReason = ctx.weatherState.needsShelter and "weather_seek_shelter" or "weather_seek_warmth"
        if self:seekShelter(npcEntry, npcData, ctx, shelterReason) then
            self:setState(ctx, self.STATE_SURVIVE)
            ctx.activeGoal = self.GOAL_NEEDS
            return
        end
    end

    self:buildGoalQueue(npcEntry, npcData, ctx)
    local goal = self:getTopGoal(ctx)
    if not goal then
        ctx.activeGoal = self.GOAL_EXPLORE
        self:doIdleOrWander(npcEntry, ctx)
        return
    end

    ctx.activeGoal = goal.type

    if goal.type == self.GOAL_DANGER then
        local zombie = goal.zombie
        local dist = goal.distance or 999999
        local psychState = ctx.psychState or {}

        local courage = npcData.stats.courage or 50
        if psychState.rageActive then
            courage = courage + (psychState.rageBoost or 0)
        end
        local armed = self:hasWeapon(npcData)
        ctx.hadWeaponAtCombatStart = armed
        ctx.lastKnownZombie = zombie

        if zombie and zombie.getX and zombie.getY and zombie.getZ then
            ctx.lastKnownZombiePos = {
                x = math.floor(zombie:getX()),
                y = math.floor(zombie:getY()),
                z = math.floor(zombie:getZ())
            }
        end

        local attackThreshold = armed and 25 or 50
        local mobilityPenalty = npcData.runtimePenalties and npcData.runtimePenalties.mobility or 0
        if mobilityPenalty >= 55 then
            attackThreshold = attackThreshold + 8
        end

        if psychState.isFrozen or psychState.freezeTriggered then
            local freezeUntil = psychState.freezeUntilTick or (self.tickCounter + randInt(self.freezeMinTicks, self.freezeMaxTicks))
            self:doFreeze(npcEntry, npcData, ctx, freezeUntil)
            return
        end

        if courage >= attackThreshold and dist <= self.zombieVisionRange then
            self:doCombat(npcEntry, npcData, ctx, zombie)
        else
            self:doFlee(npcEntry, npcData, ctx, zombie)
        end
        return
    end

    if goal.type == self.GOAL_NEEDS then
        self:doSurvive(npcEntry, npcData, ctx)
        return
    end

    local player, disposition, distance = self:findNearestPlayerDisposition(npcEntry, npcData)
    if player and disposition then
        local pid = (player.getUsername and player:getUsername()) or "unknown"
        ctx.observedPlayer = {
            id = pid,
            trust = disposition.trust,
            fear = disposition.fear,
            respect = disposition.respect,
            gratitude = disposition.gratitude,
            resentment = disposition.resentment,
            reputation = disposition.reputation,
            isDangerous = disposition.isDangerous,
            isFeared = disposition.isFeared,
            isTrusted = disposition.isTrusted,
            distance = distance
        }

        if disposition.isFeared and disposition.fear > disposition.trust and distance <= self.playerVisionRange then
            ctx.activeGoal = self.GOAL_DANGER
            self:doAvoidPosition(npcEntry, ctx, player:getX(), player:getY(), player:getZ())
            return
        end

        if disposition.isTrusted and disposition.trust >= 55 and distance > 3 then
            ctx.activeGoal = self.GOAL_EXPLORE
            self:doApproachPosition(npcEntry, ctx, player:getX(), player:getY(), player:getZ())
            return
        end
    else
        ctx.observedPlayer = nil
    end

    self:doIdleOrWander(npcEntry, ctx)
end

function NPCBrain:updateOne(npcId, npcEntry)
    if not npcEntry or not npcEntry.data or not npcEntry.entity then
        return
    end

    local npcData = npcEntry.data
    local ctx = self:getContext(npcId)
    ctx.npcId = npcId
    ctx.npcData = npcData

    if NPCMemory then
        if NPCMemory.UpdateWeatherSurvival then
            ctx.weatherState = NPCMemory.UpdateWeatherSurvival(npcData, {
                tick = self.tickCounter,
                weather = self:sampleWeatherContext(npcEntry)
            })
        end

        if NPCMemory.UpdateSocialState then
            ctx.socialState = NPCMemory.UpdateSocialState(npcData, {
                tick = self.tickCounter
            })
        end

        if NPCMemory.ApplyLocalizedInjuryEffects then
            NPCMemory.ApplyLocalizedInjuryEffects(npcData, {
                tick = self.tickCounter
            })
        end

        if NPCMemory.UpdatePsychologicalStress then
            local _, threatDist = self:findNearestVisibleZombie(npcEntry, self.zombieVisionRange + 5)
            local threatLevel = 0
            if threatDist and threatDist < 999999 then
                threatLevel = clamp(math.floor((self.zombieVisionRange + 5 - threatDist) * 8), 0, 100)
            end
            ctx.psychState = NPCMemory.UpdatePsychologicalStress(npcData, {
                tick = self.tickCounter,
                threatLevel = threatLevel
            })
            if ctx.psychState and ctx.psychState.freezeUntilTick and ctx.psychState.freezeUntilTick > (ctx.freezeUntilTick or 0) then
                ctx.freezeUntilTick = ctx.psychState.freezeUntilTick
            end
        end
    end

    self:degradeNeeds(npcData)

    if (self.tickCounter % self.debugSyncEveryTicks) == 0 then
        self:syncDebugModData(npcId, npcEntry, ctx)
    end

    if (self.tickCounter - ctx.lastThinkTick) < self.thinkEveryTicks then
        return
    end

    ctx.lastThinkTick = self.tickCounter

    ctx.survivalScore = self:computeSurvivalScore(npcData)
    ctx.factionId = NPCFactionManager and NPCFactionManager.getFactionOfNPC and NPCFactionManager:getFactionOfNPC(npcId) or nil
    local base = NPCFactionManager and NPCFactionManager.getBaseOfNPC and NPCFactionManager:getBaseOfNPC(npcId) or nil
    local baseNeedProfile = base and NPCFactionManager and NPCFactionManager.getBaseNeedProfile and NPCFactionManager:getBaseNeedProfile(base) or nil
    local marketState = NPCFactionManager and NPCFactionManager.BuildLocalMarketState and NPCFactionManager:BuildLocalMarketState(npcId) or nil
    local personalNeed = math.max(0, 100 - (npcData.stats and npcData.stats.hunger or 50)) + math.max(0, 100 - (npcData.stats and npcData.stats.thirst or 50))
    local clanNeed = 0
    local groupNeeds = {}

    if baseNeedProfile then
        clanNeed = (baseNeedProfile.guards or 0) * 12 + (baseNeedProfile.cooks or 0) * 10 + (baseNeedProfile.builders or 0) * 14 + (baseNeedProfile.scavengers or 0) * 9 + (baseNeedProfile.recovers or 0) * 6 + (baseNeedProfile.scholars or 0) * 5
        groupNeeds = {
            food = math.max(0, (baseNeedProfile.cooks or 0) * 15 - ((npcData.stats and npcData.stats.hunger or 50) > 60 and 0 or 8)),
            water = math.max(0, (baseNeedProfile.cooks or 0) * 12 - ((npcData.stats and npcData.stats.thirst or 50) > 60 and 0 or 8)),
            materials = math.max(0, (baseNeedProfile.builders or 0) * 16),
            tools = math.max(0, (baseNeedProfile.builders or 0) * 10 + (baseNeedProfile.scavengers or 0) * 6),
            medicine = math.max(0, (baseNeedProfile.recovers or 0) * 14)
        }
    end

    if NPCMemory and NPCMemory.UpdateProfessionStrategy then
        local profession = NPCMemory.UpdateProfessionStrategy(npcData, {
            isInClan = ctx.factionId ~= nil,
            personalNeed = personalNeed,
            clanNeed = clanNeed,
            groupNeeds = groupNeeds,
            marketState = marketState,
            allowRoleShift = true,
            reason = "brain_tick"
        })
        ctx.profession = profession
        ctx.marketState = marketState
    end

    ctx.socialRole = self:chooseSocialRole(npcId, npcData)
    self:maybeRunSocialAction(npcId, npcEntry, npcData, ctx)

    local consumedByOrder = self:executeOrder(npcId, npcEntry, npcData, ctx)
    if not consumedByOrder then
        local autoOrder = nil
        if NPCFactionManager and NPCFactionManager.suggestAutonomousOrder then
            autoOrder = NPCFactionManager:suggestAutonomousOrder(npcId, npcData)
        end

        if autoOrder then
            self:executeOrderObject(npcEntry, npcData, ctx, autoOrder)
        else
            self:decideState(npcEntry, npcData, ctx)
        end
    end
    self:runUnstuckCheck(npcId, npcEntry, npcData, ctx)
    self:trackOrderRuntime(npcData, ctx)
    self:syncDebugModData(npcId, npcEntry, ctx)
end

function NPCBrain:processDormantExpeditions(players)
    if not NPCSpawner or type(NPCSpawner.dormantNPCs) ~= "table" or not NPCMemory or not NPCMemory.ResolveExpedition then
        return
    end

    local playerList = players or getOnlinePlayerList()
    if #playerList == 0 then
        return
    end

    local toDrop = {}

    for npcId, record in pairs(NPCSpawner.dormantNPCs) do
        if type(record) == "table" and type(record.snapshot) == "table" then
            local result = NPCMemory.ResolveExpedition(record.snapshot, self.tickCounter)
            if result and result.ready == true then
                if not result.willReturn then
                    toDrop[#toDrop + 1] = npcId
                else
                    local player = playerList[randInt(1, #playerList)]
                    if player and player.getX and player.getY and player.getZ then
                        record.x = math.floor(player:getX()) + randInt(-6, 6)
                        record.y = math.floor(player:getY()) + randInt(-6, 6)
                        record.z = math.floor(player:getZ())
                    end

                    record.dormantSinceTick = self.tickCounter
                    NPCSpawner:spawnFromRecord(record, playerList)
                end
            end
        end
    end

    for i = 1, #toDrop do
        NPCSpawner.dormantNPCs[toDrop[i]] = nil
    end
end

function NPCBrain:update()
    self.tickCounter = self.tickCounter + 1

    if (self.tickCounter % self.updateEveryTicks) ~= 0 then
        return
    end

    if not NPCSpawner or type(NPCSpawner.activeNPCs) ~= "table" then
        return
    end

    local cell = getCell and getCell() or nil
    self.cachedZombieList = (cell and cell.getZombieList and cell:getZombieList()) or nil
    self.cachedZombieListTick = self.tickCounter

    self:processDormantExpeditions(getOnlinePlayerList())

    self:removeStaleContexts(NPCSpawner.activeNPCs)

    for npcId, entry in pairs(NPCSpawner.activeNPCs) do
        local ok, err = pcall(function()
            self:updateOne(npcId, entry)
        end)
        if not ok then
            self.lastError = tostring(err or "unknown")
            self.lastErrorNpcId = npcId
            self.lastErrorTick = self.tickCounter
            _G.PHNPC_LastBrainError = self.lastError
            _G.PHNPC_LastBrainErrorNpcId = npcId
            _G.PHNPC_LastBrainErrorTick = self.tickCounter
            print(string.format("[NPCBrain][ERROR] updateOne failed npc=%s err=%s", tostring(npcId), tostring(err)))
            if PHNPC_Logger and PHNPC_Logger.error then
                PHNPC_Logger:error("NPCBrain", "updateOne", "NPC brain update failed", {
                    npcId = npcId,
                    tick = self.tickCounter,
                    error = tostring(err)
                })
            end
        end
    end
end

function NPCBrain:start()
    if Events and Events.OnTick then
        Events.OnTick.Add(function()
            NPCBrain:update()
        end)
    end
end

NPCBrain:start()

return NPCBrain

