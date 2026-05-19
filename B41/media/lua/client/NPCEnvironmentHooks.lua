if not isServer() then return {} end

--[[
    Project Humain : Dynamic_NPC_Overhaul
    NPCEnvironmentHooks.lua

    Couche serveur dediee aux interactions environnementales:
    - ouverture active de porte fermee
    - detection de barricade
    - gestion d'obstacle invalide
    - fallback de contournement
]]

local hasMemory, NPCMemory = pcall(require, "NPCMemory")
if not hasMemory then
    NPCMemory = nil
end

local NPCEnvironmentHooks = {
    interactionCooldownTicks = 45,
    eventCooldownTicks = 40,
    contourStepDistance = 2,
    maxContourCandidates = 8,
    metricWindowSeconds = 60,
    trackedMetricEvents = {
        "path_opened_door",
        "path_blocked_barricade",
        "path_contour_fallback"
    },
    metricsGlobal = {},
    metricsByNpc = {}
}

local trackedMetricLookup = {
    path_opened_door = true,
    path_blocked_barricade = true,
    path_contour_fallback = true
}

local function floorNumber(v)
    return math.floor(tonumber(v) or 0)
end

local function sign(v)
    if v > 0 then
        return 1
    end
    if v < 0 then
        return -1
    end
    return 0
end

local function nowSeconds()
    return (os and os.time and os.time()) or 0
end

local function pruneOldBuckets(bucketMap, cutoffSecond)
    if type(bucketMap) ~= "table" then
        return
    end

    for secondKey, _ in pairs(bucketMap) do
        if tonumber(secondKey) and tonumber(secondKey) < cutoffSecond then
            bucketMap[secondKey] = nil
        end
    end
end

local function sumBuckets(bucketMap)
    if type(bucketMap) ~= "table" then
        return 0
    end

    local total = 0
    for _, count in pairs(bucketMap) do
        total = total + (tonumber(count) or 0)
    end
    return total
end

local function getMetricSlot(container, eventType)
    container[eventType] = container[eventType] or {
        total = 0,
        lastMinute = 0,
        lastSeenSecond = 0,
        buckets = {}
    }
    return container[eventType]
end

local function recordMetric(container, eventType, currentSecond, windowSeconds)
    if type(container) ~= "table" then
        return
    end

    local slot = getMetricSlot(container, eventType)
    local sec = math.floor(tonumber(currentSecond) or 0)
    local cutoff = sec - math.max(1, tonumber(windowSeconds) or 60) + 1

    slot.total = (tonumber(slot.total) or 0) + 1
    slot.lastSeenSecond = sec
    slot.buckets[sec] = (tonumber(slot.buckets[sec]) or 0) + 1
    pruneOldBuckets(slot.buckets, cutoff)
    slot.lastMinute = sumBuckets(slot.buckets)
end

local function readMetricLastMinute(container, eventType, currentSecond, windowSeconds)
    if type(container) ~= "table" then
        return 0
    end

    local slot = container[eventType]
    if type(slot) ~= "table" then
        return 0
    end

    local sec = math.floor(tonumber(currentSecond) or 0)
    local cutoff = sec - math.max(1, tonumber(windowSeconds) or 60) + 1
    pruneOldBuckets(slot.buckets, cutoff)
    slot.lastMinute = sumBuckets(slot.buckets)
    return tonumber(slot.lastMinute) or 0
end

local function ensureNpcMetricContainer(npcId)
    if not npcId then
        return nil
    end

    local key = tostring(npcId)
    NPCEnvironmentHooks.metricsByNpc[key] = NPCEnvironmentHooks.metricsByNpc[key] or {}
    return NPCEnvironmentHooks.metricsByNpc[key]
end

local function recordPathMetric(npcData, eventType)
    if not trackedMetricLookup[eventType] then
        return
    end

    local currentSecond = nowSeconds()
    recordMetric(NPCEnvironmentHooks.metricsGlobal, eventType, currentSecond, NPCEnvironmentHooks.metricWindowSeconds)

    local npcId = npcData and (npcData.id or npcData.npcId or npcData.uuid) or nil
    local npcContainer = ensureNpcMetricContainer(npcId)
    if npcContainer then
        recordMetric(npcContainer, eventType, currentSecond, NPCEnvironmentHooks.metricWindowSeconds)
    end
end

local function pushEnvironmentEvent(npcData, ctx, eventType, payload)
    if not NPCMemory or not NPCMemory.PushRecentEvent or not npcData then
        return
    end

    local tick = payload and payload.tick or 0
    local lastTick = ctx.lastEnvironmentEventTick or 0
    if (tick - lastTick) < NPCEnvironmentHooks.eventCooldownTicks then
        return
    end

    ctx.lastEnvironmentEventTick = tick
    recordPathMetric(npcData, eventType)
    NPCMemory.PushRecentEvent(npcData, eventType, payload)
end

function NPCEnvironmentHooks:getAdminMetrics(npcId)
    local sec = nowSeconds()
    local windowSeconds = math.max(1, tonumber(self.metricWindowSeconds) or 60)

    local perMinute = {}
    local perMinuteNpc = {}
    local npcContainer = npcId and self.metricsByNpc[tostring(npcId)] or nil

    for i = 1, #self.trackedMetricEvents do
        local eventType = self.trackedMetricEvents[i]
        perMinute[eventType] = readMetricLastMinute(self.metricsGlobal, eventType, sec, windowSeconds)
        perMinuteNpc[eventType] = readMetricLastMinute(npcContainer, eventType, sec, windowSeconds)
    end

    return {
        generatedAt = sec,
        windowSeconds = windowSeconds,
        perMinute = perMinute,
        perMinuteNpc = perMinuteNpc
    }
end

local function canUseInteraction(ctx, nowTick)
    local last = ctx.lastEnvironmentInteractionTick or 0
    return (nowTick - last) >= NPCEnvironmentHooks.interactionCooldownTicks
end

local function markInteractionUsed(ctx, nowTick)
    ctx.lastEnvironmentInteractionTick = nowTick
end

local function entityPathTo(entity, tx, ty, tz)
    if not entity or not entity.pathToLocationF then
        return false
    end

    local ok = pcall(function()
        entity:pathToLocationF(tx, ty, tz)
    end)
    return ok == true
end

local function getSquare(cell, x, y, z)
    if not cell or not cell.getGridSquare then
        return nil
    end
    return cell:getGridSquare(floorNumber(x), floorNumber(y), floorNumber(z))
end

local function getClassName(obj)
    if not obj then
        return ""
    end

    if obj.getObjectName then
        local ok, name = pcall(function()
            return obj:getObjectName()
        end)
        if ok and type(name) == "string" then
            return name
        end
    end

    return tostring(obj)
end

local function isLikelyDoor(obj)
    if not obj then
        return false
    end

    if obj.ToggleDoorSilent or obj.ToggleDoor then
        return true
    end

    local className = string.lower(getClassName(obj))
    return string.find(className, "door", 1, true) ~= nil
end

local function isDoorOpen(obj)
    if not obj then
        return false
    end

    if obj.IsOpen then
        local ok, value = pcall(function()
            return obj:IsOpen()
        end)
        if ok then
            return value == true
        end
    end

    if obj.isOpen then
        local ok, value = pcall(function()
            return obj:isOpen()
        end)
        if ok then
            return value == true
        end
    end

    return false
end

local function isDoorBarricaded(obj, entity)
    if not obj then
        return false
    end

    if obj.getBarricadeForCharacter then
        local ok, barricade = pcall(function()
            return obj:getBarricadeForCharacter(entity)
        end)
        if ok and barricade then
            return true
        end
    end

    if obj.getBarricadeOnSameSquare then
        local ok, barricade = pcall(function()
            return obj:getBarricadeOnSameSquare()
        end)
        if ok and barricade then
            return true
        end
    end

    if obj.getBarricadeOnOppositeSquare then
        local ok, barricade = pcall(function()
            return obj:getBarricadeOnOppositeSquare()
        end)
        if ok and barricade then
            return true
        end
    end

    return false
end

local function tryOpenDoor(obj, entity)
    if not obj or not entity then
        return false
    end

    if isDoorOpen(obj) then
        return true
    end

    local toggled = false

    if obj.ToggleDoorSilent then
        local ok = pcall(function()
            obj:ToggleDoorSilent(entity)
        end)
        toggled = ok == true
    end

    if (not toggled) and obj.ToggleDoor then
        local ok = pcall(function()
            obj:ToggleDoor(entity)
        end)
        toggled = ok == true
    end

    if not toggled then
        return false
    end

    return isDoorOpen(obj)
end

local function scanBlockingObject(square, entity)
    if not square or not square.getObjects then
        return nil, "invalid_obstacle"
    end

    local objects = square:getObjects()
    if not objects or not objects.size then
        return nil, "invalid_obstacle"
    end

    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        if isLikelyDoor(obj) then
            if isDoorBarricaded(obj, entity) then
                return obj, "barricade"
            end
            if not isDoorOpen(obj) then
                return obj, "closed_door"
            end
        end
    end

    return nil, "invalid_obstacle"
end

local function buildContourCandidates(ex, ey, ez, tx, ty, tz)
    local step = NPCEnvironmentHooks.contourStepDistance
    local sx = sign(tx - ex)
    local sy = sign(ty - ey)

    local candidates = {
        { x = ex + (sx * step), y = ey + step, z = tz or ez },
        { x = ex + (sx * step), y = ey - step, z = tz or ez },
        { x = ex + step, y = ey + (sy * step), z = tz or ez },
        { x = ex - step, y = ey + (sy * step), z = tz or ez },
        { x = tx + step, y = ty, z = tz or ez },
        { x = tx - step, y = ty, z = tz or ez },
        { x = tx, y = ty + step, z = tz or ez },
        { x = tx, y = ty - step, z = tz or ez }
    }

    return candidates
end

function NPCEnvironmentHooks:tryPathWithEnvironment(args)
    local entity = args and args.entity or nil
    local npcEntry = args and args.npcEntry or nil
    local npcData = args and args.npcData or nil
    local ctx = args and args.ctx or nil
    local tx = args and args.x or nil
    local ty = args and args.y or nil
    local tz = args and args.z or nil
    local reason = args and args.reason or "move"
    local nowTick = args and args.tick or 0

    if not entity or not ctx then
        return false
    end

    if entityPathTo(entity, tx, ty, tz) then
        return true
    end

    local ex = entity.getX and entity:getX() or (npcEntry and npcEntry.x) or tx
    local ey = entity.getY and entity:getY() or (npcEntry and npcEntry.y) or ty
    local ez = entity.getZ and floorNumber(entity:getZ()) or (npcEntry and npcEntry.z) or tz

    local nx = floorNumber(ex + sign((tx or ex) - ex))
    local ny = floorNumber(ey + sign((ty or ey) - ey))
    local nz = floorNumber(tz or ez)

    local cell = entity.getCell and entity:getCell() or (getCell and getCell() or nil)
    local forwardSquare = getSquare(cell, nx, ny, nz)

    if not forwardSquare then
        pushEnvironmentEvent(npcData, ctx, "path_invalid_obstacle", {
            tick = nowTick,
            reason = reason,
            x = nx,
            y = ny,
            z = nz
        })
    else
        local blockingObj, policy = scanBlockingObject(forwardSquare, entity)

        if policy == "closed_door" and blockingObj and canUseInteraction(ctx, nowTick) then
            local opened = tryOpenDoor(blockingObj, entity)
            markInteractionUsed(ctx, nowTick)
            if opened and entityPathTo(entity, tx, ty, tz) then
                pushEnvironmentEvent(npcData, ctx, "path_opened_door", {
                    tick = nowTick,
                    reason = reason,
                    x = nx,
                    y = ny,
                    z = nz
                })
                return true
            end
        elseif policy == "barricade" then
            pushEnvironmentEvent(npcData, ctx, "path_blocked_barricade", {
                tick = nowTick,
                reason = reason,
                x = nx,
                y = ny,
                z = nz
            })
        else
            pushEnvironmentEvent(npcData, ctx, "path_invalid_obstacle", {
                tick = nowTick,
                reason = reason,
                x = nx,
                y = ny,
                z = nz
            })
        end
    end

    local candidates = buildContourCandidates(ex, ey, ez, tx or ex, ty or ey, tz or ez)
    local maxCandidates = math.min(#candidates, self.maxContourCandidates)
    for i = 1, maxCandidates do
        local c = candidates[i]
        if c and entityPathTo(entity, c.x, c.y, c.z) then
            pushEnvironmentEvent(npcData, ctx, "path_contour_fallback", {
                tick = nowTick,
                reason = reason,
                x = floorNumber(c.x),
                y = floorNumber(c.y),
                z = floorNumber(c.z)
            })
            return true
        end
    end

    return false
end

return NPCEnvironmentHooks

