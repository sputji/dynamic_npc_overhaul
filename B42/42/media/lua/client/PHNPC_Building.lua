--[[
    PHNPC_Building.lua  -  v0.0.9l
    ----------------------------------------------------------------
    Detection des batiments et chambres pour l'ordre "Mets-toi a l'abri !"

    v0.0.9l : retire toute utilisation de pcall/wrapper interne (crash si
    pcall=nil dans certains scopes Kahlua). Les API Java appelees sont toutes
    presentes en B42.18 (verifie par class extraction). Les retours nullables
    sont garde-fous au niveau Lua avec des if simples.

    Fonctions exposees :
      PHNPC.isInsideBuilding(npc)            -> bool, BuildingDef
      PHNPC.findNearestBuildingSquare(x,y,z,maxRadius) -> sx,sy,sz,building
      PHNPC.findSafeRoomSquare(building, npc)-> sx,sy,sz
      PHNPC.pickShelterPoint(npc)            -> sx,sy,sz,reason

    API Java B42.18 utilisees (verifie via class extraction) :
      IsoGameCharacter:getCurrentBuilding()  IsoGridSquare:getBuilding()
      BuildingDef:getRooms()                 RoomDef:getRandomFreeSquare()
      IsoCell:getGridSquare(x,y,z)           IsoGridSquare:isFree(bool)
]]

PHNPC = PHNPC or {}

-- ============================================================
-- 1. Le NPC est-il deja dans un batiment ?
-- ============================================================
function PHNPC.isInsideBuilding(npc)
    if not npc then return false, nil end
    local b = npc:getCurrentBuilding()
    if b then return true, b end
    local sq = npc:getSquare()
    if sq then
        local b2 = sq:getBuilding()
        if b2 then return true, b2 end
    end
    return false, nil
end

-- ============================================================
-- 2. Trouver la case "interieure" la plus proche (scan spiral 1..maxRadius)
-- ============================================================
function PHNPC.findNearestBuildingSquare(x, y, z, maxRadius)
    maxRadius = maxRadius or 30
    local cell = getCell()
    if not cell then return nil end
    local cx, cy, cz = math.floor(x), math.floor(y), math.floor(z or 0)

    local function checkSquare(sx, sy)
        local sq = cell:getGridSquare(sx, sy, cz)
        if not sq then return nil end
        local building = sq:getBuilding()
        if not building then return nil end
        if not sq:isFree(false) then return nil end
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
--    On itere les rooms et on prefere celles sans zombie a proximite.
-- ============================================================
function PHNPC.findSafeRoomSquare(building, npc)
    if not building then return nil end
    local rooms = building:getRooms()
    if not rooms or rooms:size() == 0 then return nil end

    local bestX, bestY, bestZ = nil, nil, nil
    local bestZombies = 9999
    local cell = getCell()

    for i = 0, rooms:size() - 1 do
        local room = rooms:get(i)
        if room then
            local sq = room:getRandomFreeSquare()
            if sq then
                local rx, ry, rz = sq:getX(), sq:getY(), sq:getZ()
                local zombieCount = 0
                if cell then
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
                end
                if zombieCount < bestZombies then
                    bestZombies = zombieCount
                    bestX = rx + 0.5
                    bestY = ry + 0.5
                    bestZ = rz
                end
            end
        end
    end
    return bestX, bestY, bestZ
end

-- ============================================================
-- 4. Choisir un point de mise a l'abri pour un NPC
--    1) deja dans un batiment -> safe room du batiment
--    2) sinon -> nearest building + safe room (ou case d'entree)
--    3) sinon -> fallback findClearAreaNear
-- ============================================================
function PHNPC.pickShelterPoint(npc)
    if not npc then return nil end
    local nx, ny, nz = npc:getX(), npc:getY(), npc:getZ()

    local inside, building = PHNPC.isInsideBuilding(npc)
    if inside and building then
        local sx, sy, sz = PHNPC.findSafeRoomSquare(building, npc)
        if sx then return sx, sy, sz, "inside" end
    end

    local bx, by, bz, b2 = PHNPC.findNearestBuildingSquare(nx, ny, nz, 30)
    if bx and b2 then
        local sx, sy, sz = PHNPC.findSafeRoomSquare(b2, npc)
        if sx then return sx, sy, sz, "nearest_building" end
        return bx, by, bz, "building_entry"
    end

    if PHNPC.findClearAreaNear then
        local fx, fy = PHNPC.findClearAreaNear(nx, ny, nz, 15)
        if fx then return fx, fy, nz, "clear_area" end
    end

    return nil
end

print("[PHNPC] Building v0.0.9l loaded")
