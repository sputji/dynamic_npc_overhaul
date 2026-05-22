--[[
    PHNPC_Pathfind.lua  v0.0.9c  (client)
    Utilitaires de pathfinding et de deplacement pour les NPCs.

    Fonctions exportees :
      PHNPC.findFreeSquareNear(x, y, z, radius, maxTries)
        => Trouve une tuile libre dans un rayon donne.
      PHNPC.findEscapeDirection(npc, enemy, range)
        => Trouve la meilleure direction de fuite (teste 8 angles).
      PHNPC.findClearAreaNear(x, y, z, radius)
        => Cherche une zone degagee (sans zombies proches).

    Pattern : NPC_Helper_Mod GCHelpersMove.lua + GCHelpersEscape.lua (adaptes)
    Necessite :
      PHNPC_Core.lua (PHNPC global)
]]

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
-- opposee a l'ennemi, retourne la premiere case libre
-- Pattern GCHelpersEscape.lua (NPC_Helper_Mod)
-- ============================================================
function PHNPC.findEscapeDirection(npc, enemy, range)
    range = range or 15
    local nx, ny, nz = npc:getX(), npc:getY(), npc:getZ()
    local ex, ey     = enemy:getX(), enemy:getY()

    -- Direction de base : opposee a l'ennemi
    local bx = nx - ex
    local by_ = ny - ey
    local bl = math.sqrt(bx * bx + by_ * by_)
    if bl < 0.01 then bx, by_, bl = 1, 0, 1 end
    bx = bx / bl
    by_ = by_ / bl

    local cell = getCell()
    if not cell then
        -- Pas de cellule, retourner direction brute
        return nx + bx * range, ny + by_ * range
    end

    -- Tester 8 angles (0 = droit, puis alterner gauche/droite)
    local angles = { 0, 45, -45, 90, -90, 135, -135, 180 }
    for _, angDeg in ipairs(angles) do
        local ang = math.rad(angDeg)
        local cosA = math.cos(ang)
        local sinA = math.sin(ang)
        local dx = bx * cosA - by_ * sinA
        local dy = bx * sinA + by_ * cosA
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

    -- Fallback : direction de base sans verification
    return nx + bx * range, ny + by_ * range
end

-- ============================================================
-- findClearAreaNear : cherche une zone safe pour "Mets-toi a l'abri"
-- v0.0.9f : cherche en priorite une case couverte (interieur batiment),
--           a distance suffisante, avec le moins de zombies possible.
-- ============================================================
function PHNPC.findClearAreaNear(x, y, z, radius)
    radius = radius or 15
    local cell = getCell()
    if not cell then return nil, nil end
    z = math.floor(z or 0)

    -- 12 directions testees (cardinales + diagonales + intermediaires)
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
                -- Score : compter les zombies proches (moins = meilleur)
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

                -- Bonus important si la case est couverte (a l'interieur d'un batiment)
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

    -- Fallback : si aucune case trouvee, retourner nil (Update.lua gerera)
    return bestX, bestY
end

print("[PHNPC] Pathfind v0.0.9f loaded")
