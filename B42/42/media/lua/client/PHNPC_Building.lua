--[[
    PHNPC_Building.lua  -  v0.0.9k
    ----------------------------------------------------------------
    Detection des batiments et chambres pour l'ordre "Mets-toi a l'abri !"

    Fonctions exposees :
      PHNPC.isInsideBuilding(npc)
          -> bool, BuildingDef    (true si le NPC est dans un batiment)

      PHNPC.findNearestBuildingSquare(x, y, z, maxRadius)
          -> sqX, sqY, sqZ, building  (ou nil)
          Cherche en spirale la case "interieure" la plus proche.

      PHNPC.findSafeRoomSquare(building, npc)
          -> sqX, sqY, sqZ        (case libre dans une room sans zombie)

    API Java B42.18 utilisees (verifie via class extraction) :
      IsoGameCharacter:getCurrentBuilding() -> BuildingDef
      IsoGridSquare:getBuilding()           -> BuildingDef
      IsoGridSquare:getRoom()               -> RoomDef
      IsoGridSquare:isOutside()             -> bool
      IsoGridSquare:isFree(boolean)         -> bool
      BuildingDef:getRooms()                -> ArrayList<RoomDef>
      RoomDef:getRandomFreeSquare()         -> IsoGridSquare (peut etre nil)
]]

PHNPC = PHNPC or {}

local _pcall = pcall
local function spc(fn) local ok, err = _pcall(fn); return ok, err end

-- ============================================================
-- 1. Le NPC est-il deja dans un batiment ?
-- ============================================================
function PHNPC.isInsideBuilding(npc)
    if not npc then return false, nil end
    local b = nil
    spc(function() b = npc:getCurrentBuilding() end)
    if b then return true, b end
    local sq = nil
    spc(function() sq = npc:getSquare() end)
    if sq then
        local b2 = nil
        spc(function() b2 = sq:getBuilding() end)
        if b2 then return true, b2 end
    end
    return false, nil
end

-- ============================================================
-- 2. Trouver la case "interieure" la plus proche (scan spiral)
--    On parcourt tous les anneaux 1..maxRadius autour de (x,y,z)
--    et on retourne la PREMIERE case avec un building != nil et libre.
-- ============================================================
function PHNPC.findNearestBuildingSquare(x, y, z, maxRadius)
    maxRadius = maxRadius or 30
    local cell = getCell()
    if not cell then return nil end
    local cx, cy, cz = math.floor(x), math.floor(y), math.floor(z or 0)

    local function checkSquare(sx, sy)
        local sq = nil
        spc(function() sq = cell:getGridSquare(sx, sy, cz) end)
        if not sq then return nil end
        local building = nil
        spc(function() building = sq:getBuilding() end)
        if not building then return nil end
        local free = false
        spc(function() free = sq:isFree(false) end)
        if not free then return nil end
        return sq, building
    end

    -- Centre d'abord
    local sq, bd = checkSquare(cx, cy)
    if sq then return cx + 0.5, cy + 0.5, cz, bd end

    -- Spirale par anneaux croissants
    for r = 1, maxRadius do
        for dx = -r, r do
            for dy = -r, r do
                if math.abs(dx) == r or math.abs(dy) == r then
                    local sq2, bd2 = checkSquare(cx + dx, cy + dy)
                    if sq2 then return cx + dx + 0.5, cy + dy + 0.5, cz, bd2 end
                end
            end
        end
    end
    return nil
end

-- ============================================================
-- 3. Trouver une case libre dans une room safe d'un batiment
--    On itere les rooms et on prefere celles SANS zombie a proximite.
-- ============================================================
function PHNPC.findSafeRoomSquare(building, npc)
    if not building then return nil end
    local rooms = nil
    spc(function() rooms = building:getRooms() end)
    if not rooms or rooms:size() == 0 then return nil end

    local bestX, bestY, bestZ = nil, nil, nil
    local bestZombies = 9999

    for i = 0, rooms:size() - 1 do
        local room = rooms:get(i)
        if room then
            local sq = nil
            spc(function() sq = room:getRandomFreeSquare() end)
            if sq then
                -- Compte zombies (non-NPC) a 4 tuiles autour
                local zombieCount = 0
                local cell = getCell()
                if cell then
                    local rx, ry, rz = sq:getX(), sq:getY(), sq:getZ()
                    spc(function()
                        for dx = -4, 4 do
                            for dy = -4, 4 do
                                local s2 = cell:getGridSquare(rx + dx, ry + dy, rz)
                                if s2 then
                                    local mov = s2:getMovingObjects()
                                    if mov then
                                        for k = 0, mov:size() - 1 do
                                            local o = mov:get(k)
                                            if o and instanceof(o, "IsoZombie") then
                                                local m2 = o:getModData()
                                                if not (m2 and m2.PHNPC_IsNPC) then
                                                    zombieCount = zombieCount + 1
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end)
                end
                if zombieCount < bestZombies then
                    bestZombies = zombieCount
                    bestX = sq:getX() + 0.5
                    bestY = sq:getY() + 0.5
                    bestZ = sq:getZ()
                end
            end
        end
    end
    return bestX, bestY, bestZ
end

-- ============================================================
-- 4. Helper : choisir un point de mise a l'abri pour un NPC
--    1) si NPC deja dans un batiment -> safe room du batiment
--    2) sinon -> nearest building square + safe room
--    3) sinon -> fallback findClearAreaNear (Pathfind.lua)
-- ============================================================
function PHNPC.pickShelterPoint(npc)
    if not npc then return nil end
    local nx, ny, nz = npc:getX(), npc:getY(), npc:getZ()

    -- 1. Deja dans un batiment ?
    local inside, building = PHNPC.isInsideBuilding(npc)
    if inside and building then
        local sx, sy, sz = PHNPC.findSafeRoomSquare(building, npc)
        if sx then return sx, sy, sz, "inside" end
    end

    -- 2. Trouver le batiment le plus proche
    local bx, by, bz, b2 = PHNPC.findNearestBuildingSquare(nx, ny, nz, 30)
    if bx and b2 then
        local sx, sy, sz = PHNPC.findSafeRoomSquare(b2, npc)
        if sx then return sx, sy, sz, "nearest_building" end
        return bx, by, bz, "building_entry"
    end

    -- 3. Fallback : ancienne logique
    if PHNPC.findClearAreaNear then
        local fx, fy = PHNPC.findClearAreaNear(nx, ny, nz, 15)
        if fx then return fx, fy, nz, "clear_area" end
    end

    return nil
end

print("[PHNPC] Building v0.0.9k loaded")
