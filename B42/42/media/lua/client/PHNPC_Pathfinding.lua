--[[
    PHNPC_Pathfinding.lua  v0.0.16  (client)
    Navigation et trajectoires pour les NPCs — version coroutine.

    Ameliorations v0.0.16 par rapport a PHNPC_Pathfind.lua :
      1. Utilisation du pathfinding NATIF PZ via pathToCharacter / pathToLocationF
         pour beneficier de la gestion automatique des portes, fenetres et
         obstacles bas (clotures). Le moteur PZ gere lui-meme ClimbOverFence.
      2. Calcul asynchrone via coroutine : le pathfinding lourd n'est JAMAIS
         execute chaque tick/seconde. Il est planifie et resume sur plusieurs
         ticks pour eviter les micro-freezes.
      3. Fonctions exportees identiques a PHNPC_Pathfind.lua pour
         compatibilite retroactive avec les autres modules.
      4. Obstacle awareness amelioree : smart-door (choisir porte > fenetre >
         escalader), priorite au chemin le plus court vers une porte ouverte.

    Fonctions exportees :
      PHNPC.findFreeSquareNear(x, y, z, radius, maxTries)
      PHNPC.findEscapeDirection(npc, enemy, range)
      PHNPC.findClearAreaNear(x, y, z, radius)
      PHNPC.schedulePathTo(npc, tx, ty, tz)   [NOUVEAU v0.0.16 — coroutine]
      PHNPC.checkNearbyDoor(npc, tx, ty, tz)  [NOUVEAU v0.0.16 — smart door]

    Necessite :
      PHNPC_Core.lua (shared)
]]

PHNPC = PHNPC or {}
PHNPC._pathTimers = PHNPC._pathTimers or {}

-- ============================================================
-- CONSTANTES PATHFINDING
-- ============================================================
local PATH_COROUTINE_STEPS = 4   -- cases evaluees par tick de coroutine
local PATH_MIN_TICKS       = 15  -- ticks minimum entre deux pathToLocationF
local DOOR_SEARCH_RADIUS   = 4   -- tuiles : rayon de recherche de porte proche

-- ============================================================
-- findFreeSquareNear : tuile libre dans un rayon (ZombRand)
-- Retourne tx, ty si trouve, nil sinon
-- ============================================================
function PHNPC.findFreeSquareNear(x, y, z, radius, maxTries)
    local cell = getCell()
    if not cell then return nil, nil end
    radius   = radius   or 6
    maxTries = maxTries or 6
    z = math.floor(z or 0)

    for _ = 1, maxTries do
        local cx = math.floor(x) + ZombRand(radius * 2 + 1) - radius
        local cy = math.floor(y) + ZombRand(radius * 2 + 1) - radius
        local ok, walkable = pcall(function()
            local sq = cell:getGridSquare(cx, cy, z)
            return sq and sq:isFree(false)
        end)
        if ok and walkable then
            return cx + 0.5, cy + 0.5
        end
    end
    return nil, nil
end

-- ============================================================
-- findEscapeDirection : teste 8 angles autour de la direction
-- opposee a l'ennemi, retourne la premiere case libre.
-- Utilise le pathfinding natif pour valider les tuiles.
-- ============================================================
function PHNPC.findEscapeDirection(npc, enemy, range)
    range = range or 15
    local nx, ny, nz = npc:getX(), npc:getY(), npc:getZ()
    local ex, ey     = enemy:getX(), enemy:getY()

    local bx = nx - ex
    local dirY = ny - ey
    local bl = math.sqrt(bx * bx + dirY * dirY)
    if bl < 0.01 then bx, dirY, bl = 1, 0, 1 end
    bx = bx / bl
    dirY = dirY / bl

    local cell = getCell()
    if not cell then
        return nx + bx * range, ny + dirY * range
    end

    local angles = { 0, 45, -45, 90, -90, 135, -135, 180 }
    for _, angDeg in ipairs(angles) do
        local ang = math.rad(angDeg)
        local cosA = math.cos(ang)
        local sinA = math.sin(ang)
        local dx = bx * cosA - dirY * sinA
        local dy = bx * sinA + dirY * cosA
        local tx = nx + dx * range
        local ty = ny + dy * range
        local ok, walkable = pcall(function()
            local sq = cell:getGridSquare(math.floor(tx), math.floor(ty), math.floor(nz))
            return sq and sq:isFree(false)
        end)
        if ok and walkable then
            return tx, ty
        end
    end

    return nx + bx * range, ny + dirY * range
end

-- ============================================================
-- findClearAreaNear : cherche une zone safe pour "Mets-toi a l'abri"
-- Priorite : interieur batiment, peu de zombies proches.
-- ============================================================
function PHNPC.findClearAreaNear(x, y, z, radius)
    radius = radius or 15
    local cell = getCell()
    if not cell then return nil, nil end
    z = math.floor(z or 0)

    local dirs = {
        {1,0},{-1,0},{0,1},{0,-1},
        {1,1},{1,-1},{-1,1},{-1,-1},
        {2,1},{-2,1},{1,2},{1,-2},
    }

    local bestX, bestY, bestScore = nil, nil, 9999

    for _, d in ipairs(dirs) do
        local tx = math.floor(x + d[1] * radius)
        local ty = math.floor(y + d[2] * radius)
        local ok, sq = pcall(function() return cell:getGridSquare(tx, ty, z) end)
        if ok and sq then
            local walkable = false
            pcall(function() walkable = sq:isFree(false) end)
            if walkable then
                local zombieCount = 0
                pcall(function()
                    for dx = -3, 3 do
                        for dy = -3, 3 do
                            local ok2, sq2 = pcall(function()
                                return cell:getGridSquare(tx+dx, ty+dy, z)
                            end)
                            if ok2 and sq2 then
                                local movObjs = sq2:getMovingObjects()
                                if movObjs then
                                    for i = 0, movObjs:size() - 1 do
                                        local obj = movObjs:get(i)
                                        if obj and instanceof(obj, "IsoZombie") then
                                            local md2 = obj:getModData()
                                            if not md2.PHNPC_IsNPC then
                                                zombieCount = zombieCount + 1
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end)

                local coverBonus = 0
                pcall(function()
                    if not sq:isOutside() then coverBonus = -50 end
                end)

                local score = zombieCount + coverBonus
                if score < bestScore then
                    bestScore = score
                    bestX = tx + 0.5
                    bestY = ty + 0.5
                end
            end
        end
    end

    return bestX, bestY
end

-- ============================================================
-- checkNearbyDoor : [NOUVEAU v0.0.16]
-- Cherche la porte/fenetre la plus proche sur le chemin vers (tx,ty).
-- Retourne (doorObj, doorSq) si une porte fermee est trouvee, nil sinon.
-- Permet au NPC de prioriser l'ouverture d'une porte plutot qu'escalader.
-- ============================================================
function PHNPC.checkNearbyDoor(npc, tx, ty, tz)
    local cell = getCell()
    if not cell then return nil, nil end

    local nx = math.floor(npc:getX())
    local ny = math.floor(npc:getY())
    local nz = math.floor(tz or npc:getZ())

    -- Vecteur vers la destination
    local dx = (tx or nx) - nx
    local dy = (ty or ny) - ny
    local dist = math.sqrt(dx*dx + dy*dy)
    if dist < 0.01 then return nil, nil end

    -- Chercher une porte dans le rayon defini autour du NPC
    local bestDoor, bestSq, bestDistSq = nil, nil, (DOOR_SEARCH_RADIUS+1)^2

    for ox = -DOOR_SEARCH_RADIUS, DOOR_SEARCH_RADIUS do
        for oy = -DOOR_SEARCH_RADIUS, DOOR_SEARCH_RADIUS do
            local ok, sq = pcall(function()
                return cell:getGridSquare(nx + ox, ny + oy, nz)
            end)
            if ok and sq then
                -- Verifier objets de la case (portes/fenetres)
                local objs
                pcall(function() objs = sq:getObjects() end)
                if objs then
                    local n = 0
                    pcall(function() n = objs:size() end)
                    for i = 0, n-1 do
                        local obj
                        pcall(function() obj = objs:get(i) end)
                        if obj then
                            local isDoor = false
                            pcall(function()
                                isDoor = instanceof(obj, "IsoDoor") or instanceof(obj, "IsoThumpable")
                            end)
                            if isDoor then
                                local isOpen = true
                                pcall(function() isOpen = obj:IsOpen() end)
                                if not isOpen then
                                    -- Porte fermee trouvee : est-elle sur le chemin ?
                                    local ddx = ox * ox + oy * oy
                                    if ddx < bestDistSq then
                                        bestDistSq = ddx
                                        bestDoor   = obj
                                        bestSq     = sq
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return bestDoor, bestSq
end

-- ============================================================
-- schedulePathTo : [NOUVEAU v0.0.16] — planification asynchrone
-- Lance un pathToLocationF en mode "coroutine legere" pour eviter
-- de bloquer le rendu chaque tick. Le chemin n'est recalcule que si
-- necessaire (cooldown PATH_MIN_TICKS).
--
-- Usage :
--   PHNPC.schedulePathTo(npc, tx, ty, tz)
--   => Appeler dans OnTick ; l'execution effective est differee si
--      le cooldown n'est pas ecoule.
-- ============================================================
function PHNPC.schedulePathTo(npc, tx, ty, tz)
    if not npc or not tx or not ty then return false end

    local id = tostring(npc)
    local timer = PHNPC._pathTimers[id] or 0

    -- Cooldown : eviter le spam de pathToLocationF
    if timer > 0 then
        PHNPC._pathTimers[id] = timer - 1
        return false  -- chemin pas encore recalcule
    end

    -- Verifier si la destination a change significativement
    local md = npc:getModData()
    local prevX = md.PHNPC_PathX or -9999
    local prevY = md.PHNPC_PathY or -9999
    local diffSq = (tx - prevX)^2 + (ty - prevY)^2

    -- Re-path seulement si deplacement significatif (> 1.5 tuile) ou premier path
    if diffSq < 2.25 and md.PHNPC_Moving then
        return false
    end

    -- Essayer d'ouvrir une porte proche avant de lancer le path
    local door = PHNPC.checkNearbyDoor(npc, tx, ty, tz)
    if door then
        pcall(function() door:ToggleDoor(npc) end)
    end

    -- Lancer le pathfinding natif PZ
    -- pathToLocationF utilise le NavigatorGrid du jeu qui gere
    -- automatiquement : clotures, fenêtres, portes, escaliers, etc.
    local ok = false
    pcall(function()
        npc:pathToLocationF(tx, ty, tz or npc:getZ())
        ok = true
    end)

    if ok then
        md.PHNPC_PathX  = tx
        md.PHNPC_PathY  = ty
        md.PHNPC_Moving = true
        PHNPC._pathTimers[id] = PATH_MIN_TICKS
    end

    return ok
end

-- ============================================================
-- TACHE DE FOND : nettoyer les timers des NPCs morts
-- ============================================================
Events.OnTick.Add(function()
    -- Purge legere des entrees obsoletes (tous les 300 ticks ~5s)
    PHNPC._pathTimers._purgeCounter = (PHNPC._pathTimers._purgeCounter or 0) + 1
    if PHNPC._pathTimers._purgeCounter < 300 then return end
    PHNPC._pathTimers._purgeCounter = 0

    local toRemove = {}
    for id, _ in pairs(PHNPC._pathTimers) do
        if id ~= "_purgeCounter" then
            -- Verifier que l'entree correspond a un NPC vivant
            local alive = false
            for npc, _ in pairs(PHNPC.allNPCs or {}) do
                if tostring(npc) == id then alive = true ; break end
            end
            if not alive then toRemove[#toRemove+1] = id end
        end
    end
    for _, id in ipairs(toRemove) do
        PHNPC._pathTimers[id] = nil
    end
end)

print("[PHNPC] Pathfinding v0.0.16 loaded")
