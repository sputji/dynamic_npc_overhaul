--[[
    PHNPC_Actions.lua  v0.0.9m  (client)
    Helpers de deplacement NPC : startFollowing / startMovingTo / stopMoving
    + findNearestZombie + checkAndOpenDoors + handleStuck

    v0.0.9m :
      - SPLIT applyMoveSetup en applyMoveStart (au lancement, anim setup complet)
        + applyMoveTick (chaque tick, idempotent, sans setBumpType/faceLocationF).
        Pattern Bandits ZAGoTo.onStart confirme : ne PAS re-setBumpType ni
        faceLocationF tant que le NPC est en mouvement (causait les saccades).
      - startFollowing accepte forceWalkType ("Run"/"Walk") pour permettre a
        Update.lua de forcer la course quand le joueur est tres loin.
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
-- HELPERS DE DEPLACEMENT (Bandits B42.18 ZAGoTo/ZAMove pattern)
-- ============================================================
-- v0.0.9k REFONTE COMPLETE :
--   * pathToLocationF est appele UNE FOIS au start, plus en boucle (qui annulait
--     le pathfind en cours et faisait surplace le NPC).
--   * setVariable("BanditWalkType", walkType) + setWalkType + setRunning :
--     declenche les AnimSets B42 pour Walk OU Run (le NPC peut enfin courir).
--   * faceLocationF avant pathToLocationF : evite le tour sur soi-meme.
--   * Reset target/aggro UNIQUEMENT au lancement d'un nouveau path
--     (destination differente OU NPC a l'arret) - plus a chaque tick.
--   * Detection stuck dans Update.lua reclenche un re-path automatiquement.
-- ============================================================

-- Choisir Walk/Run selon distance + danger
local function pickWalkType(npc, md, dist)
    -- Force Run si en fuite/combat
    if md.PHNPC_State == "shelter" or md.PHNPC_State == "fleeing" then return "Run" end
    -- HP bas => Run
    local hp = 100
    pcall(function() hp = npc:getHealth() end)
    if hp < (PHNPC.MAX_HEALTH or 100) * 0.5 then return "Run" end
    -- Distance > RUN_DISTANCE => Run
    if dist and dist > (PHNPC.RUN_DISTANCE or 6) then return "Run" end
    return "Walk"
end
PHNPC._pickWalkType = pickWalkType

-- v0.0.9m : SPLIT en 2 fonctions pour eviter les saccades.
--
-- applyMoveStart : appele UNE FOIS au lancement d'un path. Configure tout :
--   setVariable + setWalkType + setRunning + faceLocationF + setBumpType.
--   Pattern Bandits ZAGoTo.onStart : faceLocationF + setBumpType seulement
--   au START et seulement si NPC pas deja en mouvement.
--
-- applyMoveTick : appele chaque tick (idempotent, ne touche PAS l'anim).
--   Maintient juste setRunning + BanditWalkType (au cas ou Enforce les reset).
--   PAS de faceLocationF (= re-rotation sur place) ni setBumpType (= reset anim).
local function applyMoveStart(npc, x, y, walkType)
    pcall(function() npc:setVariable("BanditWalkType", walkType) end)
    pcall(function() npc:setVariable("PHNPC_WalkType", walkType) end)
    pcall(function() npc:setWalkType(walkType) end)
    pcall(function() npc:setRunning(walkType == "Run") end)
    pcall(function() npc:faceLocationF(x, y) end)
    pcall(function() npc:setBumpType(walkType == "Run" and "IdleToRun" or "IdleToWalk") end)
end
local function applyMoveTick(npc, walkType)
    pcall(function() npc:setVariable("BanditWalkType", walkType) end)
    pcall(function() npc:setRunning(walkType == "Run") end)
end
PHNPC._applyMoveStart = applyMoveStart
PHNPC._applyMoveTick  = applyMoveTick
-- Alias retrocompat pour autres fichiers qui utilisaient l'ancien helper
PHNPC._applyMoveSetup = applyMoveStart
local applyMoveSetup  = applyMoveStart

-- Doit-on (re)lancer un pathfind ? Vrai si destination differente ou NPC a l'arret.
-- v0.0.9l : ajoute cooldown 8 ticks anti-spam (evite saccades quand le moteur
-- alterne entre etats idle/pathfind transitoires).
local PATH_COOLDOWN = 8
local _pathTickCounter = PHNPC._pathTickCounter or 0
PHNPC._pathTickCounter = _pathTickCounter
local function needNewPath(npc, md, x, y, z)
    if not md.PHNPC_PathX or not md.PHNPC_PathY then return true end
    local dx = (md.PHNPC_PathX - x)
    local dy = (md.PHNPC_PathY - y)
    if dx*dx + dy*dy > 4 then  -- > 2 tiles : nouvelle destination
        return true
    end
    if not md.PHNPC_Moving then
        -- pas en mouvement mais memes coords : verifier cooldown anti-spam
        if md.PHNPC_LastPathTick and (PHNPC._pathTickCounter - md.PHNPC_LastPathTick) < PATH_COOLDOWN then
            return false
        end
        return true
    end
    return false
end
PHNPC._needNewPath = needNewPath

-- startFollowing : faire suivre le NPC vers le joueur
-- v0.0.11 REFONTE : pattern NPC_Helper_Mod B42.18 (GCCoreActions.lua).
--   pathToCharacter(player) UNE FOIS au lancement => le moteur trace dynamiquement
--   le joueur cote Java. Plus aucun pathToLocationF chaque tick (cause des saccades
--   et de l'effet "colle au joueur" rapporte au test v0.0.10).
--   On ne re-path que si le joueur a bouge >= 5 tuiles depuis le dernier path.
function PHNPC.startFollowing(npc, player, forceWalkType)
    local md = npc:getModData()
    npc:setUseless(false)

    local px, py, pz = player:getX(), player:getY(), player:getZ()
    local dx = px - npc:getX()
    local dy = py - npc:getY()
    local d  = math.sqrt(dx*dx + dy*dy)
    local stopDist = (PHNPC.FOLLOW_STOP_DISTANCE or 3)
    if d <= stopDist + 0.35 then
        if md.PHNPC_Moving then PHNPC.stopMoving(npc) end
        md.PHNPC_FollowHoldTicks = 45
        return
    end

    -- Evite le yo-yo autour de la distance d'arret qui provoque des micro-saccades.
    if (md.PHNPC_FollowHoldTicks or 0) > 0 and d <= (stopDist + 1.2) then
        md.PHNPC_FollowHoldTicks = md.PHNPC_FollowHoldTicks - 1
        return
    end
    md.PHNPC_FollowHoldTicks = 0

    local walkType = forceWalkType or pickWalkType(npc, md, d)

    -- Suivi par point d'ancrage autour du joueur (evite le collage de pathToCharacter).
    local tx, ty
    if d > 0.001 then
        local ux = (npc:getX() - px) / d
        local uy = (npc:getY() - py) / d
        tx = px + ux * stopDist
        ty = py + uy * stopDist
    else
        tx = px + stopDist
        ty = py
    end

    local needPath = false
    local sinceLastPath = (PHNPC._pathTickCounter or 0) - (md.PHNPC_LastPathTick or -9999)
    if not md.PHNPC_Moving then
        -- Evite de relancer un path immediatement apres une micro-transition idle.
        needPath = sinceLastPath >= (PHNPC.FOLLOW_REPATH_TICKS or 45)
    else
        local moveThreshold = PHNPC.FOLLOW_MOVE_THRESHOLD or 2
        local lpx = md.PHNPC_LastPX or px
        local lpy = md.PHNPC_LastPY or py
        local pdx = px - lpx
        local pdy = py - lpy
        if (pdx * pdx + pdy * pdy) >= (moveThreshold * moveThreshold)
            and sinceLastPath >= (PHNPC.FOLLOW_REPATH_TICKS or 45) then
            needPath = true
        elseif (md.PHNPC_StuckTicks or 0) >= (PHNPC.STUCK_TICKS or 90) then
            needPath = true
        end
    end

    if walkType and walkType ~= md.PHNPC_WalkType then
        md.PHNPC_WalkType = walkType
        applyMoveTick(npc, walkType)
    end

    if not needPath then return end

    -- v0.0.13b : pendant recovery fence, on force une micro-redirection locale
    -- pour casser les tentatives repetitives de franchissement de cloture.
    if (md.PHNPC_FenceRecoverTicks or 0) > 0 and PHNPC.findFreeSquareNear then
        local rx, ry = PHNPC.findFreeSquareNear(npc:getX(), npc:getY(), pz, 3, 8)
        if rx then
            tx, ty = rx, ry
            walkType = "Walk"
        end
    end

    pcall(function() npc:setTarget(nil) end)
    pcall(function() npc:setAttackedBy(nil) end)
    pcall(function() npc:clearAggroList() end)
    pcall(function() PHNPC.checkAndOpenDoors(npc) end)
    pcall(function() PHNPC.checkAndOpenWindows(npc) end)
    if not md.PHNPC_Moving then
        applyMoveStart(npc, tx, ty, walkType)
    else
        applyMoveTick(npc, walkType)
    end
    pcall(function() npc:pathToLocationF(tx, ty, pz) end)
    md.PHNPC_Moving   = true
    md.PHNPC_PathX    = tx
    md.PHNPC_PathY    = ty
    md.PHNPC_PathZ    = pz
    md.PHNPC_LastPX   = px
    md.PHNPC_LastPY   = py
    md.PHNPC_WalkType = walkType
    md.PHNPC_LastPathTick = PHNPC._pathTickCounter
    md.PHNPC_StuckTicks = 0
    md.PHNPC_LastMoveX  = npc:getX()
    md.PHNPC_LastMoveY  = npc:getY()
    PHNPC.Log.debug("Actions", tostring(md.PHNPC_Name) .. " -> "..walkType.." follow anchor(" .. string.format("%.1f,%.1f", tx, ty) .. ")")
end

-- startMovingTo : deplacer le NPC vers des coordonnees (path-once pattern)
function PHNPC.startMovingTo(npc, x, y, z, forceWalkType)
    local md = npc:getModData()
    npc:setUseless(false)

    -- v0.0.13b : si recovery fence actif, on passe d'abord par une cible locale
    -- pour eviter de re-rentrer dans ClimbOverFenceState.
    if (md.PHNPC_FenceRecoverTicks or 0) > 0 and PHNPC.findFreeSquareNear then
        local rx, ry = PHNPC.findFreeSquareNear(npc:getX(), npc:getY(), z or npc:getZ(), 3, 8)
        if rx then
            x, y = rx, ry
            forceWalkType = "Walk"
        end
    end

    local d = math.sqrt((x - npc:getX())^2 + (y - npc:getY())^2)
    local walkType = forceWalkType or pickWalkType(npc, md, d)

    local targetChanged = false
    if not md.PHNPC_PathX or not md.PHNPC_PathY then
        targetChanged = true
    else
        local dx = x - md.PHNPC_PathX
        local dy = y - md.PHNPC_PathY
        if (dx * dx + dy * dy) > 4 then
            targetChanged = true
        end
    end

    if (not md.PHNPC_Moving) or targetChanged then
        pcall(function() npc:setTarget(nil) end)
        pcall(function() npc:setAttackedBy(nil) end)
        pcall(function() npc:clearAggroList() end)
        -- Forcer Idle si LungeState parasite
        pcall(function()
            local st = npc:getCurrentState()
            if st and tostring(st):find("LungeState") then
                npc:changeState(ZombieIdleState.instance())
            end
        end)
        pcall(function() PHNPC.checkAndOpenDoors(npc) end)
        pcall(function() PHNPC.checkAndOpenWindows(npc) end)
        -- v0.0.9o : setBumpType UNIQUEMENT au lancement initial. Si en mouvement,
        -- on retransmet juste pathToLocationF (le moteur enchaine sans saccade).
        if not md.PHNPC_Moving then
            applyMoveStart(npc, x, y, walkType)
        else
            applyMoveTick(npc, walkType)
        end
        pcall(function() npc:pathToLocationF(x, y, z) end)
        md.PHNPC_Moving   = true
        md.PHNPC_PathX    = x
        md.PHNPC_PathY    = y
        md.PHNPC_PathZ    = z
        md.PHNPC_WalkType = walkType
        md.PHNPC_LastPathTick = PHNPC._pathTickCounter
        md.PHNPC_StuckTicks = 0
        md.PHNPC_LastMoveX  = npc:getX()
        md.PHNPC_LastMoveY  = npc:getY()
        PHNPC.Log.debug("Actions", tostring(md.PHNPC_Name) .. " -> "..walkType.." pathToLocationF(" .. string.format("%.1f,%.1f", x, y) .. ")")
    else
        -- Destination identique et path deja actif : ne pas re-fire pathToLocationF.
        if walkType and walkType ~= md.PHNPC_WalkType then
            md.PHNPC_WalkType = walkType
            applyMoveTick(npc, walkType)
        end
    end
end

-- Force un re-path immediat (utilise par detection stuck dans Update)
function PHNPC.forceRepath(npc, x, y, z, walkType)
    local md = npc:getModData()
    md.PHNPC_PathX = nil  -- invalider le cache pour forcer needNewPath = true
    PHNPC.startMovingTo(npc, x, y, z, walkType)
end

-- stopMoving : arreter le deplacement du NPC proprement
-- v0.0.11 : NE refermE PLUS les portes/fenetres ici (causait le ping-pong
-- ouverture/fermeture rapporte au test v0.0.10). Le caller doit appeler
-- PHNPC.closeBehindNPC(npc) explicitement quand pertinent (ex: transition
-- vers state=staying apres arrivee a shelter).
function PHNPC.stopMoving(npc)
    local md = npc:getModData()
    if md.PHNPC_Moving then
        md.PHNPC_Moving   = false
        md.PHNPC_PathX    = nil
        md.PHNPC_PathY    = nil
        md.PHNPC_PathZ    = nil
        md.PHNPC_WalkType = "Walk"
        -- Transition Walk->Idle (NHM pattern) : Bob_WalkToStop via ZSWalkToIdle.xml
        pcall(function() npc:setBumpType("WalkToIdle") end)
        pcall(function() npc:setRunning(false) end)
        pcall(function() npc:setVariable("BanditWalkType", "Walk") end)
        pcall(function() npc:setVariable("PHNPC_WalkType", "Walk") end)
        pcall(function() npc:setWalkType("Walk") end)
        pcall(function() npc:setTarget(nil) end)
        pcall(function() npc:clearAggroList() end)
    end
end

-- v0.0.11 : fermeture differee, a appeler explicitement (transition staying)
function PHNPC.closeBehindNPC(npc)
    pcall(function() PHNPC.closeNearbyDoors(npc) end)
    pcall(function() PHNPC.closeNearbyWindows(npc) end)
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
                            -- v0.0.9o : ToggleDoorSilent() (sans arg) - ToggleDoor(npc)
                            -- crash car attend un IsoPlayer, npc est IsoZombie.
                            pcall(function() obj:ToggleDoorSilent() end)
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
                            -- v0.0.9o : ToggleDoorSilent() (sans arg)
                            pcall(function() obj:ToggleDoorSilent() end)
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
                                -- v0.0.9o : ToggleDoorSilent() (sans arg)
                                obj:ToggleDoorSilent()
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

print("[PHNPC] Actions v0.0.17 loaded")

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
