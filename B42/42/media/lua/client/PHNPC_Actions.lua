--[[
    PHNPC_Actions.lua  v0.0.9e  (client)
    Helpers de deplacement NPC : startFollowing / startMovingTo / stopMoving
    + findNearestZombie + checkAndOpenDoors + handleStuck

    v0.0.9e :
      - startFollowing utilise pathToCharacter(player) — standard IsoZombie→IsoCharacter
        confirme par NPC_Helper_Mod B42.18 (GCUpdateAI.lua + GCCoreActions.lua).
        pathToLocationF ciblait une position FIXE => NPC recalculait vers un point change
        a chaque tick => tournait en boucle. pathToCharacter suit dynamiquement l'IsoPlayer.
    v0.0.9d :
      - pathToLocationF (remplace en v0.0.9e)
    v0.0.9b :
      - checkAndOpenDoors + handleStuck (GCUpdateStuck.lua pattern B42.18)

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
-- v0.0.9h FIX BUG 4 : remplace pathToCharacter par pathToLocationF avec
--   un point cible decale (joueur - direction * FOLLOW_STOP_DISTANCE) pour
--   eviter que le NPC se colle litteralement sur la case du joueur.
-- v0.0.9g : checkAndOpenDoors AVANT le pathfind.
-- v0.0.9h : + checkAndOpenWindows.
function PHNPC.startFollowing(npc, player)
    local md = npc:getModData()
    npc:setUseless(false)
    -- v0.0.9i FIX BUG 4 : casser tout target/aggressor zombie AVANT le pathfind.
    -- Sinon le moteur LungeState reoriente vers le joueur et override pathToLocationF.
    pcall(function() npc:setTarget(nil) end)
    pcall(function() npc:setAttackedBy(nil) end)
    pcall(function() npc:setAlertedBy(nil) end)
    pcall(function() npc:clearAggroList() end)
    pcall(function() npc:setPathTargetCharacter(nil) end)
    if not md.PHNPC_Moving then
        md.PHNPC_Moving = true
        pcall(function() npc:setBumpType("IdleToWalk") end)
    end
    -- Ouvrir les portes et fenetres AVANT le pathfind
    pcall(function() PHNPC.checkAndOpenDoors(npc) end)
    pcall(function() PHNPC.checkAndOpenWindows(npc) end)

    -- v0.0.9h : cible decalee (eviter de coller le joueur)
    local px, py, pz = player:getX(), player:getY(), player:getZ()
    local dx = px - npc:getX()
    local dy = py - npc:getY()
    local d  = math.sqrt(dx*dx + dy*dy)
    local stopDist = (PHNPC.FOLLOW_STOP_DISTANCE or 3)
    if d > stopDist + 0.1 then
        local nx, ny = dx / d, dy / d
        local tx = px - nx * stopDist
        local ty = py - ny * stopDist
        pcall(function() npc:pathToLocationF(tx, ty, pz) end)
        PHNPC.Log.debug("Actions", tostring(md.PHNPC_Name) .. " -> pathToLocationF offset (" .. string.format("%.1f,%.1f", tx, ty) .. ")")
    else
        -- Deja assez proche : arret propre, ne pas re-pathfinder
        PHNPC.stopMoving(npc)
    end
end

-- startMovingTo : deplacer le NPC vers des coordonnees
-- v0.0.9h : + checkAndOpenWindows AVANT le pathfind.
function PHNPC.startMovingTo(npc, x, y, z)
    local md = npc:getModData()
    npc:setUseless(false)
    -- v0.0.9i FIX BUG 2/4/5 : casser le ciblage zombie auto AVANT pathToLocationF.
    -- Sans ca, le moteur AI redirige vers le joueur le plus proche.
    pcall(function() npc:setTarget(nil) end)
    pcall(function() npc:setAttackedBy(nil) end)
    pcall(function() npc:setAlertedBy(nil) end)
    pcall(function() npc:clearAggroList() end)
    pcall(function() npc:setPathTargetCharacter(nil) end)
    -- Si le NPC est en LungeState, forcer Idle pour debloquer le pathfind.
    pcall(function()
        local st = npc:getCurrentState()
        if st and tostring(st):find("LungeState") then
            npc:changeState(ZombieIdleState.instance())
        end
    end)
    if not md.PHNPC_Moving then
        md.PHNPC_Moving = true
        pcall(function() npc:setBumpType("IdleToWalk") end)
    end
    pcall(function() PHNPC.checkAndOpenDoors(npc) end)
    pcall(function() PHNPC.checkAndOpenWindows(npc) end)
    pcall(function() npc:pathToLocationF(x, y, z) end)
    PHNPC.Log.debug("Actions", tostring(md.PHNPC_Name) .. " -> pathToLocationF(" .. string.format("%.1f,%.1f", x, y) .. ")")
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
        -- v0.0.9f : refermer les portes proches apres arret du NPC
        pcall(function() PHNPC.closeNearbyDoors(npc) end)
        -- v0.0.9h : refermer aussi les fenetres ouvertes a portee
        pcall(function() PHNPC.closeNearbyWindows(npc) end)
    end
end

-- ============================================================
-- FERMETURE DES PORTES (v0.0.9f)
-- Referme toutes les portes ouvertes dans un rayon de 2 tuiles.
-- Appele automatiquement depuis stopMoving.
-- ============================================================
function PHNPC.closeNearbyDoors(npc)
    local cell = npc:getCell()
    if not cell then return end
    local nx = math.floor(npc:getX())
    local ny = math.floor(npc:getY())
    local nz = math.floor(npc:getZ())
    local dirs = {{0,-1},{0,1},{1,0},{-1,0},{0,0},{1,1},{1,-1},{-1,1},{-1,-1}}
    for _, off in ipairs(dirs) do
        pcall(function()
            local sq = cell:getGridSquare(nx + off[1], ny + off[2], nz)
            if not sq then return end
            local objects = sq:getObjects()
            if objects then
                for i = 0, objects:size() - 1 do
                    local obj = objects:get(i)
                    if obj and instanceof(obj, "IsoDoor") then
                        local isOpen = false
                        pcall(function() isOpen = obj:IsOpen() end)
                        if isOpen then
                            pcall(function() obj:ToggleDoor(npc) end)
                        end
                    end
                end
            end
            local specials = sq:getSpecialObjects()
            if specials then
                for i = 0, specials:size() - 1 do
                    local obj = specials:get(i)
                    if obj and instanceof(obj, "IsoThumpable") then
                        local isDoor, isOpen = false, false
                        pcall(function() isDoor = obj:isDoor() end)
                        pcall(function() isOpen = obj:IsOpen() end)
                        if isDoor and isOpen then
                            pcall(function() obj:ToggleDoor(npc) end)
                        end
                    end
                end
            end
        end)
    end
end

-- ============================================================
-- PORTES : ouvrir les portes dans les 4 directions adjacentes
-- v0.0.9g REFONTE : pattern Bandits 42.18 (BanditUpdate.lua)
--   - ToggleDoorSilent() au lieu de ToggleDoor(npc)
--   - Support doubles portes (IsoDoor.toggleDoubleDoor)
--   - Support portes garage (IsoDoor.toggleGarageDoor)
--   - Recalcul pathfind apres ouverture (sinon le zombie continue de taper)
--   - Appele AVANT pathfind dans startMovingTo/startFollowing
--   - ET en continu dans OnTick via PHNPC_Update.lua (pour les mouvements longs)
-- ============================================================
function PHNPC.checkAndOpenDoors(npc)
    local cell = npc:getCell()
    if not cell then return end
    local nx = math.floor(npc:getX())
    local ny = math.floor(npc:getY())
    local nz = math.floor(npc:getZ())
    local dirs = {{0,-1},{0,1},{1,0},{-1,0}}
    local anyOpened = false

    for _, off in ipairs(dirs) do
        pcall(function()
            local sq = cell:getGridSquare(nx + off[1], ny + off[2], nz)
            if not sq then return end

            -- Objets normaux : IsoDoor (portes du jeu de base)
            local objects = sq:getObjects()
            if objects then
                for i = 0, objects:size() - 1 do
                    local obj = objects:get(i)
                    if obj and instanceof(obj, "IsoDoor") then
                        local isOpen = false
                        pcall(function() isOpen = obj:IsOpen() end)
                        if isOpen then return end  -- deja ouverte

                        local locked, barricaded = false, false
                        pcall(function() locked = obj:isLocked() or obj:isLockedByKey() end)
                        pcall(function() barricaded = obj:isBarricaded() end)
                        if locked or barricaded then return end  -- verrouille, ne pas forcer

                        -- Double porte (ex: entree principale, hopital)
                        local isDoubleDoor = false
                        pcall(function() isDoubleDoor = IsoDoor and IsoDoor.getDoubleDoorIndex(obj) > -1 end)
                        if isDoubleDoor then
                            pcall(function() IsoDoor.toggleDoubleDoor(obj, true) end)
                            anyOpened = true
                            return
                        end

                        -- Porte garage
                        local isGarage = false
                        pcall(function() isGarage = IsoDoor and IsoDoor.getGarageDoorIndex(obj) > -1 end)
                        if isGarage then
                            pcall(function() IsoDoor.toggleGarageDoor(obj, true) end)
                            anyOpened = true
                            return
                        end

                        -- Porte standard : ToggleDoorSilent (pattern Bandits B42.18)
                        pcall(function()
                            obj:DirtySlice()
                            IsoGridSquare.RecalcLightTime = -1.0
                            sq:InvalidateSpecialObjectPaths()
                            obj:ToggleDoorSilent()
                            sq:RecalcProperties()
                            obj:syncIsoObject(false, 1, nil, nil)
                        end)
                        anyOpened = true
                    end
                end
            end

            -- Objets speciaux : IsoThumpable avec isDoor() (portes construites in-game)
            local specials = sq:getSpecialObjects()
            if specials then
                for i = 0, specials:size() - 1 do
                    local obj = specials:get(i)
                    if obj and instanceof(obj, "IsoThumpable") then
                        local isDoor = false
                        pcall(function() isDoor = obj:isDoor() end)
                        if not isDoor then return end

                        local isOpen = false
                        pcall(function() isOpen = obj:IsOpen() end)
                        if isOpen then return end

                        local locked, barricaded = false, false
                        pcall(function() locked = obj:isLocked() end)
                        pcall(function() barricaded = obj:isBarricaded() end)
                        if locked or barricaded then return end

                        pcall(function()
                            obj:DirtySlice()
                            sq:InvalidateSpecialObjectPaths()
                            obj:ToggleDoorSilent()
                            sq:RecalcProperties()
                            obj:syncIsoObject(false, 1, nil, nil)
                        end)
                        anyOpened = true
                    end
                end
            end
        end)
    end

    -- Recalculer les paths/collisions dans un rayon de 2 tuiles autour du NPC
    -- (sinon le pathfinder zombie garde en memoire l'obstacle = continue de taper)
    if anyOpened then
        pcall(function()
            local sqSelf = cell:getGridSquare(nx, ny, nz)
            if not sqSelf then return end
            for dx = -2, 2 do
                for dy = -2, 2 do
                    local neighbor = cell:getGridSquare(nx + dx, ny + dy, nz)
                    if neighbor then
                        pcall(function() sqSelf:ReCalculateCollide(neighbor) end)
                        pcall(function() sqSelf:ReCalculatePathFind(neighbor) end)
                        pcall(function() neighbor:ReCalculateCollide(sqSelf) end)
                        pcall(function() neighbor:ReCalculatePathFind(sqSelf) end)
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

print("[PHNPC] Actions v0.0.9i loaded")

-- ============================================================
-- FENETRES (v0.0.9h NEW — Bug 6)
-- Pattern Bandits B42.18 ZAOpenWindow.lua : window:ToggleWindow(zombie)
-- ============================================================
function PHNPC.checkAndOpenWindows(npc)
    local cell = npc:getCell()
    if not cell then return end
    local nx = math.floor(npc:getX())
    local ny = math.floor(npc:getY())
    local nz = math.floor(npc:getZ())
    local dirs = {{0,-1},{0,1},{1,0},{-1,0},{0,0}}
    for _, off in ipairs(dirs) do
        pcall(function()
            local sq = cell:getGridSquare(nx + off[1], ny + off[2], nz)
            if not sq then return end
            local window
            pcall(function() window = sq:getWindow() end)
            if not window then return end
            local isOpen, smashed, perma, barricaded = false, false, false, false
            pcall(function() isOpen = window:IsOpen() end)
            if isOpen then return end
            pcall(function() smashed = window:isSmashed() end)
            pcall(function() perma = window:isPermaLocked() end)
            pcall(function() barricaded = window:isBarricaded() end)
            if smashed or perma or barricaded then return end
            pcall(function() window:ToggleWindow(npc) end)
            pcall(function() npc:playSound("OpenWindow") end)
        end)
    end
end

function PHNPC.closeNearbyWindows(npc)
    local cell = npc:getCell()
    if not cell then return end
    local nx = math.floor(npc:getX())
    local ny = math.floor(npc:getY())
    local nz = math.floor(npc:getZ())
    local dirs = {{0,-1},{0,1},{1,0},{-1,0},{0,0},{1,1},{1,-1},{-1,1},{-1,-1}}
    for _, off in ipairs(dirs) do
        pcall(function()
            local sq = cell:getGridSquare(nx + off[1], ny + off[2], nz)
            if not sq then return end
            local window
            pcall(function() window = sq:getWindow() end)
            if not window then return end
            local isOpen = false
            pcall(function() isOpen = window:IsOpen() end)
            if not isOpen then return end
            pcall(function() window:ToggleWindow(npc) end)
        end)
    end
end
