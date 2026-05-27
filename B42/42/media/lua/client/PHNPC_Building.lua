--[[
    PHNPC_Building.lua  -  v0.0.9n
    ----------------------------------------------------------------
    Detection batiments et chambres pour l'ordre "Mets-toi a l'abri !"

    v0.0.9n : ULTRA-DEFENSIF (apres crash en boucle v0.0.9m).
    Verification finale des classes B42.18 :
      - IsoBuilding:getRoom(int) N'EXISTE PAS. La methode est getRoom() (sans
        arg) qui retourne UNE IsoRoom, OU getRoomByID(long), OU getRandomRoom().
      - IsoBuilding:getRoomsNumber() existe mais signature peut differer.
      - IsoBuilding:getDef() retourne BuildingDef qui a getRooms() (ArrayList<RoomDef>).
      - IsoRoom:getRandomFreeSquare() existe et retourne IsoGridSquare ou null.

    Strategie : on essaie getRandomRoom() jusqu'a 8 fois avec pcall sur chaque
    appel Java. Si quoi que ce soit echoue, on retourne nil sans crasher.
    Le NPC restera en mode "shelter" mais sans nouvelle destination -> Update.lua
    le repasse en idle apres timeout (pas de crash en boucle).
]]

PHNPC = PHNPC or {}

-- ============================================================
-- 1. Le NPC est-il deja dans un batiment ?
-- ============================================================
function PHNPC.isInsideBuilding(npc)
    if not npc then return false, nil end
    local b = nil
    pcall(function() b = npc:getCurrentBuilding() end)
    if b then return true, b end
    local sq = nil
    pcall(function() sq = npc:getSquare() end)
    if sq then
        local b2 = nil
        pcall(function() b2 = sq:getBuilding() end)
        if b2 then return true, b2 end
    end
    return false, nil
end

-- ============================================================
-- 2. Trouver la case "interieure" la plus proche (scan spiral)
-- ============================================================
function PHNPC.findNearestBuildingSquare(x, y, z, maxRadius)
    maxRadius = maxRadius or 30
    local cell = getCell()
    if not cell then return nil end
    local cx, cy, cz = math.floor(x), math.floor(y), math.floor(z or 0)

    local function checkSquare(sx, sy)
        local sq = nil
        pcall(function() sq = cell:getGridSquare(sx, sy, cz) end)
        if not sq then return nil end
        local building = nil
        pcall(function() building = sq:getBuilding() end)
        if not building then return nil end
        local free = false
        pcall(function() free = sq:isFree(false) end)
        if not free then return nil end
        return sq, building
    end

    local sq0, bd0 = checkSquare(cx, cy)
    if sq0 then return cx + 0.5, cy + 0.5, cz, bd0 end

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
-- 3. Trouver une case libre dans une room d'un IsoBuilding
--    Pattern : pcall sur CHAQUE appel Java pour ne JAMAIS crasher.
-- ============================================================
function PHNPC.findSafeRoomSquare(building, npc)
    if not building then return nil end

    -- Tente getRandomRoom() jusqu'a 8 fois
    for attempt = 1, 8 do
        local room = nil
        pcall(function() room = building:getRandomRoom() end)
        if room then
            local sq = nil
            pcall(function() sq = room:getRandomFreeSquare() end)
            if sq then
                local rx, ry, rz = 0, 0, 0
                local ok = false
                pcall(function()
                    rx = sq:getX(); ry = sq:getY(); rz = sq:getZ(); ok = true
                end)
                if ok then return rx + 0.5, ry + 0.5, rz end
            end
        end
    end

    -- Fallback : passer par BuildingDef.getRooms() (ArrayList<RoomDef>)
    local def = nil
    pcall(function() def = building:getDef() end)
    if def then
        local roomsArr = nil
        pcall(function() roomsArr = def:getRooms() end)
        if roomsArr then
            local n = 0
            pcall(function() n = roomsArr:size() end)
            for i = 0, n - 1 do
                local roomDef = nil
                pcall(function() roomDef = roomsArr:get(i) end)
                if roomDef then
                    local isoRoom = nil
                    pcall(function() isoRoom = roomDef:getIsoRoom() end)
                    if isoRoom then
                        local sq = nil
                        pcall(function() sq = isoRoom:getRandomFreeSquare() end)
                        if sq then
                            local rx, ry, rz = 0, 0, 0
                            local ok = false
                            pcall(function()
                                rx = sq:getX(); ry = sq:getY(); rz = sq:getZ(); ok = true
                            end)
                            if ok then return rx + 0.5, ry + 0.5, rz end
                        end
                    end
                end
            end
        end
    end

    return nil
end

-- ============================================================
-- 4. Choisir un point de mise a l'abri pour un NPC
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

print("[PHNPC] Building v0.0.9n loaded")
