--[[
    Project Humain : Dynamic_NPC_Overhaul
    PHNPC_SpeechBubbles.lua

    Bulles de dialogue inspirees de BravensNPCFramework, adaptees au flux
    DialogueResponse/NPCFx de Dynamic_NPC_Overhaul.
]]

local PHNPCSpeechBubbles = {
    active = {},
    maxEntries = 18,
    maxDistance = 20,
    fadeInTicks = 8,
    holdTicks = 170,
    fadeOutTicks = 28
}


local function getLocalPlayer()
    if type(getSpecificPlayer) == "function" then
        return getSpecificPlayer(0)
    end
    return nil
end

local function distance2D(a, b)
    if not a or not b then return 9999 end
    local ax, ay = a:getX(), a:getY()
    local bx, by = b:getX(), b:getY()
    local dx = ax - bx
    local dy = ay - by
    return math.sqrt(dx * dx + dy * dy)
end

local function findEntityByNpcId(npcId)
    if not npcId then
        return nil
    end

    local cell = getCell and getCell() or nil
    if not cell then
        return nil
    end

    local function matchEntity(entity)
        if not entity or not entity.getModData then
            return false
        end
        local md = entity:getModData()
        return md and tostring(md.PH_NPCId or "") == tostring(npcId)
    end

    local zlist = cell.getZombieList and cell:getZombieList() or nil
    if zlist and zlist.size then
        for i = 0, zlist:size() - 1 do
            local z = zlist:get(i)
            if matchEntity(z) then
                return z
            end
        end
    end

    local objects = cell.getObjectList and cell:getObjectList() or nil
    if objects and objects.size then
        for i = 0, objects:size() - 1 do
            local obj = objects:get(i)
            if obj then
                local okName, objectName = pcall(function()
                    return obj:getObjectName()
                end)
                if okName and objectName == "IsoPlayer" and matchEntity(obj) then
                    return obj
                end
            end
        end
    end

    return nil
end

local function getScreenXY(entity)
    if not entity then
        return nil, nil
    end

    local x = entity:getX()
    local y = entity:getY()
    local z = entity:getZ()

    local sx = nil
    local sy = nil

    if IsoUtils and IsoCamera and getCore then
        sx = IsoUtils.XToScreen(x, y, z, 0) - IsoCamera.getOffX() - (entity.getOffsetX and entity:getOffsetX() or 0)
        sy = IsoUtils.YToScreen(x, y, z, 0) - IsoCamera.getOffY() - (entity.getOffsetY and entity:getOffsetY() or 0)
        sy = sy - (getCore():getScreenHeight() / 100.0 * 13)
        sx = sx / getCore():getZoom(0)
        sy = sy / getCore():getZoom(0)
    elseif type(isoToScreenX) == "function" and type(isoToScreenY) == "function" then
        -- PZ attend (playerIndex, x, y, z), pas (x, y, z, playerIndex).
        local okX, resX = pcall(isoToScreenX, 0, x, y, z)
        local okY, resY = pcall(isoToScreenY, 0, x, y, z)
        if okX and okY then
            sx = resX
            sy = resY
        end
    end

    if not sx or not sy then
        return nil, nil
    end

    return sx, sy - 28
end

local function normalizeText(text)
    local t = tostring(text or "")
    t = t:gsub("[\r\n]+", " ")
    t = t:gsub("%s+", " ")
    t = t:gsub("^%s+", "")
    t = t:gsub("%s+$", "")
    if #t > 120 then
        t = t:sub(1, 117) .. "..."
    end
    return t
end

function PHNPCSpeechBubbles:push(npcId, text, color)
    local msg = normalizeText(text)
    if #msg == 0 then
        return
    end

    self.active[npcId] = {
        npcId = npcId,
        text = msg,
        color = color or { r = 0.85, g = 1.0, b = 0.85 },
        tick = 0,
        tdo = nil
    }

    local count = 0
    for _ in pairs(self.active) do
        count = count + 1
    end
    if count <= self.maxEntries then
        return
    end

    local oldestId = nil
    local oldestTick = nil
    for id, entry in pairs(self.active) do
        local age = tonumber(entry.tick) or 0
        if oldestTick == nil or age > oldestTick then
            oldestTick = age
            oldestId = id
        end
    end
    if oldestId then
        self.active[oldestId] = nil
    end
end

function PHNPCSpeechBubbles:alphaForTick(tick)
    if tick <= self.fadeInTicks then
        return math.min(1.0, tick / math.max(1, self.fadeInTicks))
    end

    local fadeStart = self.fadeInTicks + self.holdTicks
    local fadeEnd = fadeStart + self.fadeOutTicks

    if tick <= fadeStart then
        return 1.0
    end

    if tick <= fadeEnd then
        local p = (tick - fadeStart) / math.max(1, self.fadeOutTicks)
        return math.max(0, 1.0 - p)
    end

    return 0
end

function PHNPCSpeechBubbles:cleanupEntry(entry)
    if entry and entry.tdo and entry.tdo.removeBatchedDraw then
        pcall(function()
            entry.tdo:removeBatchedDraw()
        end)
    end
end

function PHNPCSpeechBubbles:renderOne(entry)
    local player = getLocalPlayer()
    if not player then
        return false
    end

    local entity = findEntityByNpcId(entry.npcId)
    if not entity then
        return true
    end

    if distance2D(player, entity) > self.maxDistance then
        return true
    end

    local x, y = getScreenXY(entity)
    if not x or not y then
        return true
    end

    local alpha = self:alphaForTick(entry.tick)
    if alpha <= 0 then
        return false
    end

    self:cleanupEntry(entry)

    local tdo = TextDrawObject.new()
    tdo:setAllowAnyImage(true)
    tdo:setDefaultFont(UIFont.Dialogue)
    tdo:ReadString(entry.text)
    tdo:setAllowChatIcons(true)

    local c = entry.color or { r = 1, g = 1, b = 1 }
    tdo:setDefaultColors(c.r or 1, c.g or 1, c.b or 1, alpha)
    tdo:AddBatchedDraw(x, y, true)

    entry.tdo = tdo
    return true
end

function PHNPCSpeechBubbles:update()
    local toRemove = {}
    for id, entry in pairs(self.active) do
        entry.tick = (entry.tick or 0) + 1

        if entry.tick > (self.fadeInTicks + self.holdTicks + self.fadeOutTicks + 10) then
            toRemove[#toRemove + 1] = id
        else
            local keep = self:renderOne(entry)
            if not keep then
                toRemove[#toRemove + 1] = id
            end
        end
    end

    for i = 1, #toRemove do
        local id = toRemove[i]
        self:cleanupEntry(self.active[id])
        self.active[id] = nil
    end
end

function PHNPCSpeechBubbles:onRealtimeEvent(eventName, payload)
    if eventName == "DialogueResponse" and payload and payload.npcId and payload.response then
        self:push(payload.npcId, payload.response, { r = 0.78, g = 1.0, b = 0.78 })
    elseif eventName == "IntelResponse" and payload and payload.npcId then
        local text = "Je n'ai rien de plus a dire."
        if payload.intel then
            text = "J'ai des infos pour vous."
        end
        self:push(payload.npcId, text, { r = 0.95, g = 0.92, b = 0.72 })
    elseif eventName == "ActionResult" and payload and payload.npcId and payload.ok == true then
        if payload.actionType == "TradeEvent" then
            self:push(payload.npcId, "Marche conclu.", { r = 0.85, g = 0.95, b = 1.0 })
        elseif payload.actionType == "RequestIntel" then
            self:push(payload.npcId, "Je partage ce que je sais.", { r = 1.0, g = 0.95, b = 0.75 })
        end
    end
end

function PHNPCSpeechBubbles:start()
    if Events and Events.OnRealtimeEvent then
        Events.OnRealtimeEvent.Add(function(evt)
            if type(evt) == "table" and evt.eventType then
                PHNPCSpeechBubbles:onRealtimeEvent(evt.eventType, evt)
            end
        end)
    end

    if PHNPCInteractionClient and PHNPCInteractionClient.addListener then
        PHNPCInteractionClient:addListener("PHNPCSpeechBubbles", function(eventName, payload)
            PHNPCSpeechBubbles:onRealtimeEvent(eventName, payload)
        end)
    end

    if Events and Events.OnPostUIDraw then
        Events.OnPostUIDraw.Add(function()
            -- pcall: protege contre les RuntimeException Java (TextDrawObject, UIFont.Dialogue)
            -- non-catchables mais au moins on evite un crash total du handler
            local ok, err = pcall(function() PHNPCSpeechBubbles:update() end)
            if not ok and err then
                -- silencieux : les speech bubbles sont optionnelles
            end
        end)
    end
end

PHNPCSpeechBubbles:start()

_G.PHNPCSpeechBubbles = PHNPCSpeechBubbles

return PHNPCSpeechBubbles
