--[[
    PHNPC_ClientNPCLocator.lua
    Localisateur PNJ dynamique cote client:
    - detection robuste (zombies, objects, moving objects sur grille)
    - fallback best effort pour reduire les faux negatifs en solo/serveur
]]

local Locator = {}


local function sqDistance2D(ax, ay, bx, by)
    local dx = ax - bx
    local dy = ay - by
    return (dx * dx) + (dy * dy)
end

local function isLikelyDynamicNpc(entity)
    if not entity or not entity.getModData then
        return false, nil
    end

    local md = entity:getModData()
    if not md then
        return false, nil
    end

    if md.PH_IsDynamicNPC == true and md.PH_NPCId ~= nil then
        return true, md
    end

    -- Fallback utile quand la sync modData est partielle sur certaines sessions.
    if md.PH_NPCId ~= nil then
        return true, md
    end

    return false, md
end

local function collectFromSquare(square, pz, outList, seen)
    if not square or not square.getMovingObjects then
        return
    end

    local moving = square:getMovingObjects()
    if not moving or not moving.size then
        return
    end

    for i = 0, moving:size() - 1 do
        local entity = moving:get(i)
        if entity and not seen[entity] then
            local ez = math.floor(entity.getZ and entity:getZ() or -999)
            if ez == pz then
                local okNpc, md = isLikelyDynamicNpc(entity)
                if okNpc then
                    seen[entity] = true
                    outList[#outList + 1] = {
                        entity = entity,
                        modData = md,
                        npcId = tostring(md.PH_NPCId or "unknown")
                    }
                end
            end
        end
    end
end

function Locator.collectNearby(player, maxDistance)
    local out = {}
    if not player or not player.getX or not player.getY then
        return out
    end

    local cell = getCell and getCell() or nil
    if not cell then
        return out
    end

    local px = player:getX()
    local py = player:getY()
    local pz = math.floor(player.getZ and player:getZ() or 0)
    local radius = math.max(2, math.floor(tonumber(maxDistance) or 6))
    local maxDistSq = radius * radius
    local seen = {}

    local function tryEntity(entity)
        -- IsoFallingClothing et autres IsoObject Java n'exposent pas getX/getY ;
        -- instanceof(entity, IsoGameCharacter) filtre aux seuls zombies/joueurs valides.
        if not entity or seen[entity] or not instanceof(entity, IsoGameCharacter) then
            return
        end

        local ex = entity:getX()
        local ey = entity:getY()
        local ez = math.floor(entity:getZ())
        if not ex or not ey or ez ~= pz then
            return
        end

        if sqDistance2D(px, py, ex, ey) > maxDistSq then
            return
        end

        local okNpc, md = isLikelyDynamicNpc(entity)
        if not okNpc then
            return
        end

        seen[entity] = true
        out[#out + 1] = {
            entity = entity,
            modData = md,
            npcId = tostring(md.PH_NPCId or "unknown")
        }
    end

    local zlist = cell.getZombieList and cell:getZombieList() or nil
    if zlist and zlist.size then
        for i = 0, zlist:size() - 1 do
            tryEntity(zlist:get(i))
        end
    end

    local objects = cell.getObjectList and cell:getObjectList() or nil
    if objects and objects.size then
        for i = 0, objects:size() - 1 do
            tryEntity(objects:get(i))
        end
    end

    local centerX = math.floor(px)
    local centerY = math.floor(py)
    for dx = -radius, radius do
        for dy = -radius, radius do
            local x = centerX + dx
            local y = centerY + dy
            local d2 = (dx * dx) + (dy * dy)
            if d2 <= maxDistSq then
                local sq = cell.getGridSquare and cell:getGridSquare(x, y, pz) or nil
                collectFromSquare(sq, pz, out, seen)
            end
        end
    end

    table.sort(out, function(a, b)
        local ae = a.entity
        local be = b.entity
        local ad = ae and sqDistance2D(px, py, ae:getX(), ae:getY()) or 999999
        local bd = be and sqDistance2D(px, py, be:getX(), be:getY()) or 999999
        return ad < bd
    end)

    return out
end

function Locator.findNearest(player, maxDistance)
    local list = Locator.collectNearby(player, maxDistance)
    local first = list[1]
    return first and first.entity or nil, first and first.modData or nil
end

_G.PHNPC_ClientNPCLocator = Locator

return Locator
