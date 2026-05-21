--[[
    PHNPC_Update.lua  v1.0  (client)
    Boucles de mise a jour principales :
      OnZombieUpdate => enforce comportement NPC chaque tick
      OnTick         => IA suivi + combat + fuite + patrouille non-recrutes
      OnGameStart    => reinitialiser toutes les tables

    FIX v1.0 SUIVI : la zone entre FOLLOW_STOP_DISTANCE et FOLLOW_DISTANCE
      laisse le NPC finir son chemin en cours au lieu de declencher stopMoving
      trop tot. stopMoving est declenche UNIQUEMENT en dessous de FOLLOW_STOP_DISTANCE.

    Pattern : NHM GCUpdate.lua + GCUpdateAI.lua
    Necessite : tous les modules PHNPC_*.lua charges avant (ordre alphabetique PZ)
]]

-- ============================================================
-- OnZombieUpdate : enforce comportement NPC chaque tick
-- Pattern GCUpdate.onZombieUpdate EXACT
-- ============================================================
Events.OnZombieUpdate.Add(function(zombie)
    if not zombie then return end
    if not PHNPC then return end
    if not PHNPC.isNPC(zombie) then return end

    -- IMMEDIAT : neutraliser avant tout traitement
    pcall(function() zombie:setNoTeeth(true) end)

    -- Gerer etat mort (fakeDead, knockdown invisible)
    local dead = false
    pcall(function() dead = zombie:isDead() end)
    if dead then
        -- Tenter de reviver (GCUpdate.lua pattern)
        pcall(function()
            zombie:setHealth(10000)
            zombie:setFakeDead(false)
            zombie:knockDown(false)
            zombie:setKnockedDown(false)
            zombie:setCanWalk(true)
            zombie:setUseless(false)
            zombie:changeState(ZombieIdleState.instance())
        end)
        -- Re-verifier apres tentative
        local stillDead = false
        pcall(function() stillDead = zombie:isDead() end)
        if stillDead then return end
    end

    -- ShowTimer : ignorer les premiers ticks (animations de spawn en cours)
    -- GCCoreSpawn.lua pattern : md.GC_ShowTimer = 5
    local md = zombie:getModData()
    if (md.PHNPC_ShowTimer or 0) > 0 then
        md.PHNPC_ShowTimer = md.PHNPC_ShowTimer - 1
        return
    end

    -- Enforce comportement NPC (chaque tick)
    pcall(function() PHNPC.enforceNPC(zombie) end)
end)

-- ============================================================
-- OnTick : IA Suivi + Combat + Fuite + Patrouille
-- Pattern GCUpdateAI.runAI
-- ============================================================
Events.OnTick.Add(function()
    local player = getPlayer()
    if not player or not PHNPC then return end

    -- ---- NPCs recrutes : fuite + combat + suivi ----
    for npc, _ in pairs(PHNPC.recruited) do
        -- Verifier validite NPC
        local valid = false
        pcall(function() valid = not npc:isDead() end)

        if not valid then
            -- NPC mort : nettoyer les tables
            local md = npc:getModData()
            PHNPC.recruited[npc]         = nil
            PHNPC.allNPCs[npc]           = nil
            PHNPC._followTimers[npc]     = nil
            PHNPC._combatTimers[npc]     = nil
            PHNPC._attackCooldowns[npc]  = nil
            print("[PHNPC] Cleanup mort : " .. tostring(md and md.PHNPC_Name or "?"))
        else
            local md = npc:getModData()

            -- 1. Evaluation fuite (priorite haute : peut overrider tous les etats)
            pcall(function() PHNPC.npcFlightStep(npc, player) end)

            -- 2. Evaluation combat (si pas en fuite)
            pcall(function() PHNPC.npcCombatStep(npc) end)

            -- 3. Suivi joueur (seulement si etat "following", pas en combat/fuite)
            if md.PHNPC_State == "following" then
                local dx   = player:getX() - npc:getX()
                local dy   = player:getY() - npc:getY()
                local dist = math.sqrt(dx * dx + dy * dy)

                if dist > PHNPC.FOLLOW_DISTANCE then
                    -- Joueur trop loin : declencher suivi toutes les FOLLOW_TICK_RATE ticks
                    PHNPC._followTimers[npc] = (PHNPC._followTimers[npc] or 0) + 1
                    if PHNPC._followTimers[npc] >= PHNPC.FOLLOW_TICK_RATE then
                        PHNPC._followTimers[npc] = 0
                        PHNPC.startFollowing(npc, player)
                    end
                elseif dist <= (PHNPC.FOLLOW_STOP_DISTANCE or 3) then
                    -- Dans la zone d'arret : stopper proprement
                    PHNPC.stopMoving(npc)
                    PHNPC._followTimers[npc] = 0
                end
                -- Entre FOLLOW_STOP_DISTANCE et FOLLOW_DISTANCE :
                -- laisser le NPC finir son chemin en cours (pas de stopMoving ici)
            end
            -- "staying"   : rien a faire (setUseless(false) mais pas de pathfind)
            -- "defending" : gere par npcCombatStep
            -- "fleeing"   : gere par npcFlightStep
        end
    end

    -- ---- NPCs non recrutes : patrouille autonome ----
    local deadIdle = {}
    for npc, _ in pairs(PHNPC.allNPCs) do
        if not PHNPC.recruited[npc] then
            local valid = false
            pcall(function() valid = not npc:isDead() end)
            if not valid then
                table.insert(deadIdle, npc)
            else
                local md = npc:getModData()
                -- Patrouille aleatoire toutes les ~300 ticks (~5 secondes a 60fps)
                md.PHNPC_PatrolTick = (md.PHNPC_PatrolTick or 0) + 1
                if md.PHNPC_PatrolTick >= 300 then
                    md.PHNPC_PatrolTick = 0
                    -- Destination aleatoire dans un rayon de 6 tiles
                    local nx = npc:getX() + ZombRand(13) - 6
                    local ny = npc:getY() + ZombRand(13) - 6
                    pcall(function() npc:pathToLocationF(nx, ny, npc:getZ()) end)
                    -- Bark idle occasionnel (1 chance sur 4)
                    if ZombRand(4) == 0 then
                        PHNPC.sayBark(npc, "idle", 1.0, 1.0, 1.0)
                    end
                end
            end
        end
    end
    for _, npc in ipairs(deadIdle) do
        PHNPC.allNPCs[npc] = nil
    end
end)

-- ============================================================
-- OnGameStart : reinitialiser toutes les tables
-- ============================================================
Events.OnGameStart.Add(function()
    PHNPC.allNPCs           = {}
    PHNPC.recruited         = {}
    PHNPC._followTimers     = {}
    PHNPC._openInventoryNPC = nil
    PHNPC._combatTimers     = {}
    PHNPC._attackCooldowns  = {}
    print("[PHNPC] v0.14 pret")
end)

print("[PHNPC] Update v1.0 loaded")
