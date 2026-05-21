--[[
    PHNPC_Combat.lua  v1.0  (client)
    IA Combat NPC : attaquer les zombies proches (npcCombatStep)
    IA Fuite NPC  : fuir si HP < 30% (npcFlightStep)

    FIX v1.0 : npcCombatStep appelle PHNPC.stopMoving quand plus de cible
               => evite que le NPC reste bloque en etat "walking" sans destination

    Pattern : NHM GCCombatActionsAttack.lua + GCHelpersEscape.lua simplifies
    Necessite :
      PHNPC_Actions.lua  (PHNPC.startMovingTo, PHNPC.stopMoving, PHNPC.findNearestZombie)
      PHNPC_Barks.lua    (PHNPC.sayBark)
]]

local ATTACK_VARIANTS = {"Shove", "FrontKick", "HighKick"}

-- ============================================================
-- COMBAT NPC : chercher et attaquer les zombies proches
-- Pattern GCCombatActionsAttack.lua (NPC_Helper_Mod) simplifie
-- ============================================================
function PHNPC.npcCombatStep(npc)
    local md = npc:getModData()
    if not md.PHNPC_Recruited then return end
    if md.PHNPC_CombatMode == "off" then return end
    -- Pas de combat si en fuite
    if md.PHNPC_State == "fleeing" then return end

    -- Decrementer cooldown attaque
    if (md.PHNPC_AttackCooldown or 0) > 0 then
        md.PHNPC_AttackCooldown = md.PHNPC_AttackCooldown - 1
        return
    end

    -- Timer : ne pas evaluer chaque tick
    PHNPC._combatTimers[npc] = (PHNPC._combatTimers[npc] or 0) + 1
    if PHNPC._combatTimers[npc] < (PHNPC.COMBAT_TICK_RATE or 30) then return end
    PHNPC._combatTimers[npc] = 0

    -- Chercher zombie dans le rayon de combat
    local target, dist = PHNPC.findNearestZombie(npc, PHNPC.COMBAT_RANGE or 8)

    if not target then
        -- Plus de cible : quitter l'etat "defending" si on y etait
        if md.PHNPC_State == "defending" then
            md.PHNPC_State = md.PHNPC_PrevState or "following"
            md.PHNPC_PrevState = nil
        end
        -- Stopper le deplacement de combat si le NPC est en mouvement
        if md.PHNPC_Moving then
            PHNPC.stopMoving(npc)
        end
        return
    end

    -- Entrer en mode defense si pas deja dedans
    if md.PHNPC_State ~= "defending" then
        md.PHNPC_PrevState = md.PHNPC_State
        md.PHNPC_State = "defending"
        -- Bark de combat (alerte)
        PHNPC.sayBark(npc, "defending", 0.9, 0.2, 0.2)
    end

    if dist <= (PHNPC.COMBAT_ATTACK_RANGE or 1.5) then
        -- Assez proche : attaquer
        local targetDead = false
        pcall(function() targetDead = target:isDead() end)
        if targetDead then return end

        pcall(function() npc:faceLocationF(target:getX(), target:getY()) end)

        local anim = ATTACK_VARIANTS[(ZombRand(#ATTACK_VARIANTS) + 1)]
        pcall(function() npc:setBumpType(anim) end)
        -- Knock down le zombie (seule methode safe sans setTarget)
        pcall(function() target:knockDown(true) end)
        md.PHNPC_AttackCooldown = 60
        print("[PHNPC][COMBAT] " .. tostring(md.PHNPC_Name) .. " : " .. anim
              .. " dist=" .. string.format("%.1f", dist))
    else
        -- Trop loin : se deplacer vers le zombie
        PHNPC.startMovingTo(npc, target:getX(), target:getY(), target:getZ())
    end
end

-- ============================================================
-- FUITE NPC : fuir si HP < 30%
-- Pattern GCHelpersEscape.lua (NPC_Helper_Mod) simplifie
-- ============================================================
function PHNPC.npcFlightStep(npc, player)
    local md = npc:getModData()
    if not md.PHNPC_Recruited then return end

    local hp    = md.PHNPC_Health    or 100
    local maxHp = md.PHNPC_MaxHealth or 100
    local ratio = hp / maxHp

    if ratio < (PHNPC.FLEE_HP_RATIO or 0.30) then
        -- Passer en etat fuite
        if md.PHNPC_State ~= "fleeing" then
            md.PHNPC_PrevState = md.PHNPC_State
            md.PHNPC_State     = "fleeing"
            pcall(function()
                npc:addLineChatElement((md.PHNPC_Name or "?") .. " : Je suis blesse ! Je fuis !", 0.9, 0.2, 0.2)
            end)
        end

        -- Chercher zombie le plus proche pour fuir dans la direction opposee
        local enemy, eDist = PHNPC.findNearestZombie(npc, 20)
        local nx, ny, nz   = npc:getX(), npc:getY(), npc:getZ()
        if enemy and eDist < 20 then
            local ex, ey = enemy:getX(), enemy:getY()
            local dx, dy = nx - ex, ny - ey
            local d = math.sqrt(dx * dx + dy * dy)
            if d > 0 then dx, dy = dx / d, dy / d end
            local fleeDist = PHNPC.FLEE_DISTANCE or 15
            PHNPC.startMovingTo(npc, nx + dx * fleeDist, ny + dy * fleeDist, nz)
        else
            -- Pas de zombie : se replier vers le joueur
            local target = player or getPlayer()
            if target then
                PHNPC.startMovingTo(npc, target:getX(), target:getY(), target:getZ())
            end
            -- Retourner a l'etat precedent
            md.PHNPC_State = md.PHNPC_PrevState or "following"
            md.PHNPC_PrevState = nil
        end
    else
        -- HP OK : sortir de l'etat fuite
        if md.PHNPC_State == "fleeing" then
            md.PHNPC_State     = md.PHNPC_PrevState or "following"
            md.PHNPC_PrevState = nil
            pcall(function()
                npc:addLineChatElement((md.PHNPC_Name or "?") .. " : Je peux continuer !", 0.2, 0.9, 0.2)
            end)
        end
    end
end

print("[PHNPC] Combat v1.0 loaded")
