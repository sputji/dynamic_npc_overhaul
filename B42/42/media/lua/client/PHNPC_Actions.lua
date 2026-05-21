--[[
    PHNPC_Actions.lua  v1.0  (client)
    Helpers de deplacement NPC : startFollowing / startMovingTo / stopMoving
    + findNearestZombie
    Variables internes partagees (_followTimers, _combatTimers, etc.)

    FIX v1.0 : startFollowing utilise pathToLocationF avec offset FOLLOW_STOP_DISTANCE
               au lieu de pathToCharacter => empeche le NPC de coller le joueur pixel par pixel

    Pattern : NHM GCCoreActions.lua
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
-- FIX PROXIMITY : cible a FOLLOW_STOP_DISTANCE tiles du joueur (pas sa case exacte)
function PHNPC.startFollowing(npc, player)
    local md = npc:getModData()
    npc:setUseless(false)
    if not md.PHNPC_Moving then
        md.PHNPC_Moving = true
        -- Transition Idle->Walk (NHM GCCoreActions pattern)
        pcall(function() npc:setBumpType("IdleToWalk") end)
    end
    -- Calculer la position cible : FOLLOW_STOP_DISTANCE tiles vers le NPC depuis le joueur
    -- Evite que le NPC marche jusqu'a la case exacte du joueur (pixel-sticking)
    local px, py, pz = player:getX(), player:getY(), player:getZ()
    local dx = px - npc:getX()
    local dy = py - npc:getY()
    local d  = math.sqrt(dx * dx + dy * dy)
    local stopDist = PHNPC.FOLLOW_STOP_DISTANCE or 3
    if d > stopDist then
        -- Reculer de stopDist depuis le joueur dans la direction NPC->joueur
        local tx = px - (dx / d) * stopDist
        local ty = py - (dy / d) * stopDist
        pcall(function() npc:pathToLocationF(tx, ty, pz) end)
    end
    -- Si deja dans la zone d'arret, ne pas demarrer un pathfind inutile
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

print("[PHNPC] Actions v1.0 loaded")
