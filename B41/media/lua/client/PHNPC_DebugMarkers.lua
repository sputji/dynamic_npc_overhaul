--[[
    Marquage client permanent des PNJ dynamiques.
    Objectif: rendre les proxies immediatement distinguables des zombies standards.
]]

PHNPC_DebugMarkers = PHNPC_DebugMarkers or {}


local M = PHNPC_DebugMarkers

M.enabled = false
M.mapEnabled = false
M.updateEveryTicks = 15
M.maxDistance = 90
M.color = { r = 0.15, g = 1.00, b = 0.20, a = 1.00 }
M._tick = 0
M.lastSeen = {}

local okLocator, PHNPC_ClientNPCLocator = pcall(require, "PHNPC_ClientNPCLocator")
if not okLocator then
    PHNPC_ClientNPCLocator = _G.PHNPC_ClientNPCLocator
end

local function sqDistance2D(ax, ay, bx, by)
    local dx = ax - bx
    local dy = ay - by
    return dx * dx + dy * dy
end

function M:setEnabled(value)
    self.enabled = value == true
    print(string.format("[PHNPC] Debug markers: %s", self.enabled and "ON" or "OFF"))
end

function M:setMapEnabled(value)
    self.mapEnabled = value == true
    print(string.format("[PHNPC] Map markers: %s", self.mapEnabled and "ON" or "OFF"))
end

local function updateMapMarkersForSeen(seen)
    if M.mapEnabled ~= true then
        return
    end

    local wm = getWorldMarkers and getWorldMarkers() or nil
    if not wm then
        return
    end

    for i = 1, #seen do
        local entry = seen[i]
        local e = entry and entry.entity or nil
        if e and e.getX and e.getY and e.getZ then
            local x = math.floor(e:getX())
            local y = math.floor(e:getY())
            local z = math.floor(e:getZ())

            -- Best effort API calls selon build moteur.
            if wm.addGridSquareMarker then
                pcall(function()
                    wm:addGridSquareMarker("PHNPC", x, y, z, 0.15, 1.00, 0.20, true, 120)
                end)
            elseif wm.addPlayerHomingPoint then
                pcall(function()
                    wm:addPlayerHomingPoint(x, y, z, false, 0.15, 1.00, 0.20, 0.8)
                end)
            end
        end
    end
end

local function applyMarker(z)
    if not z then
        return
    end

    local c = M.color

    if z.setOutlineHighlight then
        pcall(function()
            z:setOutlineHighlight(M.enabled == true)
        end)
    end

    if M.enabled == true and z.setOutlineHighlightCol then
        pcall(function()
            z:setOutlineHighlightCol(c.r, c.g, c.b, c.a)
        end)
    end

    if z.setHaloNote then
        if M.enabled == true then
            pcall(function()
                z:setHaloNote("PHNPC", 50, 255, 80, 220)
            end)
        else
            pcall(function()
                z:setHaloNote("", 255, 255, 255, 0)
            end)
        end
    end
end

local function updateMarkers()
    if M.enabled ~= true and M.mapEnabled ~= true then
        M.lastSeen = {}
        return
    end

    local player = getSpecificPlayer and getSpecificPlayer(0) or nil
    if not player then
        return
    end

    if not PHNPC_ClientNPCLocator or not PHNPC_ClientNPCLocator.collectNearby then
        return
    end

    local nearby = PHNPC_ClientNPCLocator.collectNearby(player, M.maxDistance)
    local seen = {}
    local px = player:getX()
    local py = player:getY()

    for i = 1, #nearby do
        local entry = nearby[i]
        local entity = entry and entry.entity or nil
        if entity then
            if M.enabled == true then
                applyMarker(entity)
            end
            local ex = entity.getX and entity:getX() or 0
            local ey = entity.getY and entity:getY() or 0
            seen[#seen + 1] = {
                entity = entity,
                id = tostring(entry.npcId or "unknown"),
                x = math.floor(ex),
                y = math.floor(ey),
                z = math.floor(entity.getZ and entity:getZ() or 0),
                distance = math.floor(math.sqrt(sqDistance2D(px, py, ex, ey)))
            }
        end
    end

    M.lastSeen = seen
    updateMapMarkersForSeen(seen)
end

local function onTick()
    M._tick = M._tick + 1
    if (M._tick % M.updateEveryTicks) ~= 0 then
        return
    end
    updateMarkers()
end

local function onServerCommand(module, command, args)
    if module == "PH_NPC" and command == "AdminDebugAck" and type(args) == "table" then
        if args.markEnabled ~= nil then
            M:setEnabled(args.markEnabled == true)
        end
        if args.mapEnabled ~= nil then
            M:setMapEnabled(args.mapEnabled == true)
        end
        return
    end

    if module == "PH_NPC_CONSOLE" and command == "Result" then
        local message = tostring((args and args.message) or "")
        local lower = string.lower(message)
        if string.find(lower, "phnpc mark: on", 1, true) then
            M:setEnabled(true)
        elseif string.find(lower, "phnpc mark: off", 1, true) then
            M:setEnabled(false)
        elseif string.find(lower, "phnpc map: on", 1, true) then
            M:setMapEnabled(true)
        elseif string.find(lower, "phnpc map: off", 1, true) then
            M:setMapEnabled(false)
        end
    end
end

if Events and Events.OnTick then
    Events.OnTick.Add(onTick)
end

if Events and Events.OnServerCommand then
    Events.OnServerCommand.Add(onServerCommand)
end

print("[PHNPC] Debug markers client charges (mark/map OFF par defaut)")
