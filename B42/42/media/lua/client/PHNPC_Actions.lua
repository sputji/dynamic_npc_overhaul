--[[
    PHNPC_Actions.lua  v0.0.9b  (client)
    Helpers de deplacement NPC : startFollowing / startMovingTo / stopMoving
    + findNearestZombie + checkAndOpenDoors + handleStuck

    v0.0.9b :
      - startFollowing utilise FOLLOW_TARGET_DIST (2.5 tiles) avec jitter ±0.3
        pour eviter que le NPC stagne exactement sur la meme case
      - checkAndOpenDoors : ouvre portes/IsoThumpable-isDoor dans les 4 directions
        adjacentes quand le NPC est en mouvement (pattern GCUpdateStuck.lua B42.18)
      - handleStuck : detecte blocage position et tente ouverture porte / direction libre

    Pattern : NHM GCCoreActions.lua + GCUpdateStuck.lua
    Necessite : PHNPC_Core.lua (shared) charge avant ce fichier.
]]

-- ============================================================
-- VARIABLES INTERNES PARTAGEES (accessibles via PHNPC._xxx)
-- Declarees ici car PHNPC_Actions.lua est le premier fichier
-- client charge alphabetiquement => disponibles pour tous les
-- fichiers suivants (Barks, Combat, Convert, Enforce, ..., Update)
-- ============================================================
PHNPC._followTimers     = PHNPC._followTimers    or {}   -- [npcRef] => ticks depuis dernier pathTo
PHNPC._combatTimers     = PHNPC._combatTimers    or {}   -- [npcRef] => ticks evaluation combat
PHNPC._attackCooldowns  = PHNPC._attackCooldowns or {}   -- [npcRef] => ticks avant prochain attack
PHNPC._openInventoryNPC = nil                            -- NPC dont l'inventaire est ouvert

-- ============================================================
-- HELPERS DE DEPLACEMENT (GCCoreActions.lua pattern)
-- ============================================================

-- startFollowing : faire suivre le NPC vers le joueur
-- FIX PROXIMITY : cible a FOLLOW_TARGET_DIST (2.5) avec jitter ±0.3 tiles
-- Le jitter empeche le NPC de bloquer toujours sur la meme case
function PHNPC.startFollowing(npc, player)
    local md = npc:getModData()
    npc:setUseless(false)
    if not md.PHNPC_Moving then
        md.PHNPC_Moving = true
        pcall(function() npc:setBumpType("IdleToWalk") end)
    end
    local px, py, pz = player:getX(), player:getY(), player:getZ()
    local dx = px - npc:getX()
    local dy = py - npc:getY()
    local d  = math.sqrt(dx * dx + dy * dy)
    local targetDist = PHNPC.FOLLOW_TARGET_DIST or 2.5
    if d > targetDist then
        -- Point cible : targetDist tiles depuis joueur vers NPC + jitter discret
        local jx = (ZombRand(7) - 3) * 0.1   -- ±0.3 tiles
        local jy = (ZombRand(7) - 3) * 0.1
        local tx = px - (dx / d) * targetDist + jx
        local ty = py - (dy / d) * targetDist + jy
        pcall(function() npc:pathToLocationF(tx, ty, pz) end)
    end
end

-- startMovingTo : deplacer le NPC vers des coordonnees
function PHNPC.startMovingTo(npc, x, y, z)
    local md = npc:getModData()
    npc:setUseless(false)
    if not md.PHNPC_Moving then
        md.PHNPC_Moving = true
        -- Transition Idle->Walk (NHM GCCoreActions pattern)
        pcall(function() npc:setBumpType("IdleToWalk") end)
    end
    pcall(function() npc:pathToLocationF(x, y, z) end)
end

-- stopMoving : arreter le deplacement du NPC proprement
function PHNPC.stopMoving(npc)
    local md = npc:getModData()
    if md.PHNPC_Moving then
        md.PHNPC_Moving = false
        -- Transition Walk->Idle (NHM pattern) : Bob_WalkToStop via ZSWalkToIdle.xml
        pcall(function() npc:setBumpType("WalkToIdle") end)
        pcall(function() npc:setTarget(nil) end)
        pcall(function() npc:clearAggroList() end)
    end
end

-- ============================================================
-- PORTES : ouvrir les portes dans les 4 directions adjacentes
-- Pattern GCUpdateStuck.lua (NPC_Helper_Mod B42.18)
-- Appeler quand le NPC est en mouvement pour debarrasser les passages
-- ============================================================
function PHNPC.checkAndOpenDoors(npc)
    local md = npc:getModData()
    if not md.PHNPC_Moving then return end
    local cell = npc:getCell()
    if not cell then return end
    local nx = math.floor(npc:getX())
    local ny = math.floor(npc:getY())
    local nz = math.floor(npc:getZ())
    local dirs = {{0,-1},{0,1},{1,0},{-1,0}}
    for _, off in ipairs(dirs) do
        pcall(function()
            local sq = cell:getGridSquare(nx + off[1], ny + off[2], nz)
            if not sq then return end
            -- Objets normaux (IsoDoor classique)
            local objects = sq:getObjects()
            if objects then
                for i = 0, objects:size() - 1 do
                    local obj = objects:get(i)
                    if obj and instanceof(obj, "IsoDoor") then
                        local locked = false
                        pcall(function() locked = obj:isLocked() end)
                        local barricaded = false
                        pcall(function() barricaded = obj:isBarricaded() end)
                        local isOpen = false
                        pcall(function() isOpen = obj:IsOpen() end)
                        if not locked and not barricaded and not isOpen then
                            obj:ToggleDoor(npc)
                        end
                    end
                end
            end
            -- Objets speciaux (IsoThumpable construit in-game)
            local specials = sq:getSpecialObjects()
            if specials then
                for i = 0, specials:size() - 1 do
                    local obj = specials:get(i)
                    if obj and instanceof(obj, "IsoThumpable") then
                        local isDoor = false
                        pcall(function() isDoor = obj:isDoor() end)
                        local locked = false
                        pcall(function() locked = obj:isLocked() end)
                        local barricaded = false
                        pcall(function() barricaded = obj:isBarricaded() end)
                        local isOpen = false
                        pcall(function() isOpen = obj:IsOpen() end)
                        if isDoor and not locked and not barricaded and not isOpen then
                            obj:ToggleDoor(npc)
                        end
                    end
                end
            end
        end)
    end
end

-- ============================================================
-- DETECTION BLOCAGE (stuck)
-- Appeler depuis OnTick pour les NPCs recrutes en mouvement.
-- Si la position (x*10, y*10) n'a pas change apres 30 ticks :
--   -> tenter ouverture porte adjacente
--   -> ou choisir une direction libre (GCUpdateStuck pattern)
-- ============================================================
function PHNPC.handleStuck(npc)
    local md = npc:getModData()
    if not md.PHNPC_Moving then
        md.PHNPC_StuckTicks = 0
        md.PHNPC_StuckLastX = nil
        md.PHNPC_StuckLastY = nil
        return
    end
    local cx = math.floor(npc:getX() * 10)
    local cy = math.floor(npc:getY() * 10)
    if cx == (md.PHNPC_StuckLastX or -9999) and cy == (md.PHNPC_StuckLastY or -9999) then
        md.PHNPC_StuckTicks = (md.PHNPC_StuckTicks or 0) + 1
    else
        md.PHNPC_StuckLastX = cx
        md.PHNPC_StuckLastY = cy
        md.PHNPC_StuckTicks = 0
    end
    if (md.PHNPC_StuckTicks or 0) >= 30 then
        md.PHNPC_StuckTicks = 0
        local cell = npc:getCell()
        if not cell then return end
        local snx = npc:getX()
        local sny = npc:getY()
        local snz = npc:getZ()
        -- Tentative 1 : ouvrir porte adjacente
        local doorFound = false
        local offsets = {{0,-1},{0,1},{1,0},{-1,0}}
        for _, off in ipairs(offsets) do
            if doorFound then break end
            pcall(function()
                local sq = cell:getGridSquare(math.floor(snx) + off[1], math.floor(sny) + off[2], math.floor(snz))
                if not sq then return end
                local objects = sq:getObjects()
                if objects then
                    for i = 0, objects:size() - 1 do
                        if doorFound then break end
                        local obj = objects:get(i)
                        if obj and instanceof(obj, "IsoDoor") then
                            local locked = false; pcall(function() locked = obj:isLocked() end)
                            local barricaded = false; pcall(function() barricaded = obj:isBarricaded() end)
                            local isOpen = false; pcall(function() isOpen = obj:IsOpen() end)
                            if not locked and not barricaded and not isOpen then
                                obj:ToggleDoor(npc)
                                doorFound = true
                            end
                        end
                    end
                end
            end)
        end
        if not doorFound then
            -- Tentative 2 : choisir une direction libre
            local freeAxes = {}
            local axDirs = {{dx=0,dy=-1},{dx=0,dy=1},{dx=1,dy=0},{dx=-1,dy=0}}
            for _, d in ipairs(axDirs) do
                pcall(function()
                    local sq = cell:getGridSquare(math.floor(snx + d.dx), math.floor(sny + d.dy), math.floor(snz))
                    if sq and sq:isFree(false) then
                        table.insert(freeAxes, d)
                    end
                end)
            end
            if #freeAxes > 0 then
                local escape = freeAxes[ZombRand(#freeAxes) + 1]
                pcall(function() npc:pathToLocationF(snx + escape.dx * 4, sny + escape.dy * 4, snz) end)
            end
        end
    end
end

-- ============================================================
-- HELPER COMBAT : zombie non-NPC le plus proche dans le rayon
-- Pattern GCCombatAI.lua NPC_Helper_Mod simplifie
-- ============================================================
function PHNPC.findNearestZombie(npc, range)
    local cell = npc:getCell()
    if not cell then return nil, 999 end
    local zlist = cell:getZombieList()
    local nx, ny = npc:getX(), npc:getY()
    local rangeSq = range * range
    local bestSq = rangeSq + 1
    local bestZ  = nil
    for i = 0, zlist:size() - 1 do
        local z = zlist:get(i)
        if z and not PHNPC.isNPC(z) then
            local dead = false
            pcall(function() dead = z:isDead() end)
            if not dead then
                local dx = z:getX() - nx
                local dy = z:getY() - ny
                local dSq = dx * dx + dy * dy
                if dSq < bestSq then
                    bestSq = dSq
                    bestZ  = z
                end
            end
        end
    end
    return bestZ, math.sqrt(bestSq)
end

print("[PHNPC] Actions v0.0.9b loaded")
