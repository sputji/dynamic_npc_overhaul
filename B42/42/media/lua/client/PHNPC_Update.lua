--[[
    PHNPC_Update.lua  v0.0.9c  (client)
    Boucles de mise a jour principales :
      OnZombieUpdate => enforce comportement NPC chaque tick
      OnTick         => IA suivi + combat + fuite + patrouille non-recrutes
      OnGameStart    => reinitialiser toutes les tables

    v0.0.9c :
      - Suppression anti-sticking repulsif (le NPC tournait autour du joueur).
        Nouveau comportement : arret si dist <= FOLLOW_STOP_DISTANCE,
        reprise si dist > FOLLOW_DISTANCE, rien au milieu.
      - Integration PHNPC_Danger.lua : NoiseTimer mis a jour selon l'etat
      - Integration PHNPC_Pathfind.lua : patrouille via findFreeSquareNear
    v0.0.9b :
      - Suivi : seuil stop a FOLLOW_STOP_DISTANCE (2 tiles)
      - Etat "goingto" + portes + stuck detection
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
        local valid = false
        pcall(function() valid = not npc:isDead() end)

        if not valid then
            local md = npc:getModData()
            PHNPC.recruited[npc]         = nil
            PHNPC.allNPCs[npc]           = nil
            PHNPC._followTimers[npc]     = nil
            PHNPC._combatTimers[npc]     = nil
            PHNPC._attackCooldowns[npc]  = nil
            print("[PHNPC] Cleanup mort : " .. tostring(md and md.PHNPC_Name or "?"))
        else
            local md = npc:getModData()

            -- Ouvrir portes adjacentes quand en mouvement
            pcall(function() PHNPC.checkAndOpenDoors(npc) end)

            -- Detection blocage (stuck)
            pcall(function() PHNPC.handleStuck(npc) end)

            -- 1. Evaluation fuite (priorite haute)
            pcall(function() PHNPC.npcFlightStep(npc, player) end)

            -- 2. Evaluation combat (si pas en fuite)
            pcall(function() PHNPC.npcCombatStep(npc) end)

            -- 3. Suivi joueur (etat "following")
            if md.PHNPC_State == "following" then
                local dx   = player:getX() - npc:getX()
                local dy   = player:getY() - npc:getY()
                local dist = math.sqrt(dx * dx + dy * dy)

                if dist <= (PHNPC.FOLLOW_STOP_DISTANCE or 2) then
                    -- Dans la zone d'arret : stopper
                    if md.PHNPC_Moving then
                        PHNPC.stopMoving(npc)
                    end
                    PHNPC._followTimers[npc] = 0

                elseif dist > (PHNPC.FOLLOW_DISTANCE or 6) then
                    -- Joueur trop loin : suivre toutes les FOLLOW_TICK_RATE ticks
                    PHNPC._followTimers[npc] = (PHNPC._followTimers[npc] or 0) + 1
                    if PHNPC._followTimers[npc] >= PHNPC.FOLLOW_TICK_RATE then
                        PHNPC._followTimers[npc] = 0
                        PHNPC.startFollowing(npc, player)
                    end

                elseif dist <= (PHNPC.FOLLOW_STOP_DISTANCE or 2) then
                    -- Dans la zone d'arret : stopper proprement
                    PHNPC.stopMoving(npc)
                    PHNPC._followTimers[npc] = 0
                end
                -- Entre FOLLOW_STOP_DISTANCE et FOLLOW_DISTANCE : NPC finit son chemin

            -- 4. Etat "goingto" : NPC se deplace vers une destination choisie
            elseif md.PHNPC_State == "goingto" and md.PHNPC_GoToX then
                local dx   = md.PHNPC_GoToX - npc:getX()
                local dy   = md.PHNPC_GoToY - npc:getY()
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist <= 1.5 then
                    -- Arrive a destination : passer en "staying"
                    md.PHNPC_State  = "staying"
                    md.PHNPC_GoToX  = nil
                    md.PHNPC_GoToY  = nil
                    md.PHNPC_GoToZ  = nil
                    PHNPC.stopMoving(npc)
                    pcall(function()
                        npc:addLineChatElement(string.format(getText("UI_PHNPC_BarkArrived"), md.PHNPC_Name or "?"), 0.9, 0.9, 0.2)
                    end)
                else
                    -- Continuer vers la destination, recalculer periodiquement
                    PHNPC._followTimers[npc] = (PHNPC._followTimers[npc] or 0) + 1
                    if PHNPC._followTimers[npc] >= PHNPC.FOLLOW_TICK_RATE then
                        PHNPC._followTimers[npc] = 0
                        PHNPC.startMovingTo(npc, md.PHNPC_GoToX, md.PHNPC_GoToY, md.PHNPC_GoToZ or npc:getZ())
                    end
                end
            end
            -- "staying"   : rien a faire (setUseless(false) dans enforceNPC)
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
                -- Patrouille aleatoire toutes les ~300 ticks avec cible marchable
                md.PHNPC_PatrolTick = (md.PHNPC_PatrolTick or 0) + 1
                if md.PHNPC_PatrolTick >= 300 then
                    md.PHNPC_PatrolTick = 0
                    -- Utiliser findFreeSquareNear (PHNPC_Pathfind.lua) si disponible
                    local tx, ty
                    if PHNPC.findFreeSquareNear then
                        tx, ty = PHNPC.findFreeSquareNear(npc:getX(), npc:getY(), npc:getZ(), 6, 6)
                    else
                        local cell
                        pcall(function() cell = getCell() end)
                        if cell then
                            for _ = 1, 5 do
                                local cx = npc:getX() + ZombRand(13) - 6
                                local cy = npc:getY() + ZombRand(13) - 6
                                local ok, walkable = pcall(function()
                                    local sq = cell:getGridSquare(math.floor(cx), math.floor(cy), math.floor(npc:getZ()))
                                    return sq and sq:isFree(false)
                                end)
                                if ok and walkable then tx, ty = cx, cy ; break end
                            end
                        end
                    end
                    if tx then
                        md.PHNPC_PatrolActive = 200
                        pcall(function()
                            npc:setUseless(false)
                            npc:pathToLocationF(tx, ty, npc:getZ())
                        end)
                        if ZombRand(4) == 0 then
                            PHNPC.sayBark(npc, "idle", 1.0, 1.0, 1.0)
                        end
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
    print("[PHNPC] v0.0.9c pret")
end)

print("[PHNPC] Update v0.0.9c loaded")
