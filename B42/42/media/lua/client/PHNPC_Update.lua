--[[
    PHNPC_Update.lua  v0.0.9n  (client)
    v0.0.9n :
      - pickShelterPoint en pcall (anti-crash Building.lua)
      - findNearestZombie en pcall pour etat attacking
    Boucles de mise a jour principales :
      OnZombieUpdate => enforce comportement NPC chaque tick
      OnTick         => IA suivi + etats comportement + patrouille
      OnGameStart    => reinitialiser toutes les tables

    v0.0.9d :
      - following : recalcul pathfind SEULEMENT si joueur bouge de FOLLOW_MOVE_THRESHOLD (2t)
        => elimine la rotation (le NPC ne recalcule plus en boucle vers un point changeant)
      - staying   : deplace libre dans un rayon STAY_RADIUS autour d'une zone memorisee
      - free      : errance autonome sur FREE_WANDER_DIST, NPC reste dans l'equipe
      - shelter   : cherche zone safe (findClearAreaNear) puis passe en staying
      - attacking : attaque active puis retour position de base
    v0.0.9c :
      - Suppression anti-sticking repulsif
      - Integration PHNPC_Danger.lua + PHNPC_Pathfind.lua
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

    -- v0.0.9l : compteur global pour cooldown anti-spam pathToLocationF
    PHNPC._pathTickCounter = (PHNPC._pathTickCounter or 0) + 1

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

            -- Verrou d'ordre explicite pour eviter les bascules parasites d'etat.
            if md.PHNPC_OrderLock == "goingto" and md.PHNPC_GoToX and md.PHNPC_State ~= "goingto" then
                md.PHNPC_State = "goingto"
            elseif md.PHNPC_OrderLock == "shelter"
                and md.PHNPC_State ~= "shelter"
                and md.PHNPC_State ~= "staying" then
                md.PHNPC_State = "shelter"
            end

            -- Auto-equip vetements donnes par le joueur (scan leger periodique).
            md.PHNPC_AutoEquipTick = (md.PHNPC_AutoEquipTick or 0) + 1
            if md.PHNPC_AutoEquipTick >= 120 then
                md.PHNPC_AutoEquipTick = 0
                if PHNPC.autoEquipFromInventory then
                    pcall(function() PHNPC.autoEquipFromInventory(npc) end)
                end
            end

            -- Barks meteo : une fois par ~1000 ticks pour les NPC recrutes. (v0.0.16)
            if md.PHNPC_Recruited then
                md.PHNPC_WeatherBarkTimer = (md.PHNPC_WeatherBarkTimer or 0) + 1
                if md.PHNPC_WeatherBarkTimer >= 1000 then
                    md.PHNPC_WeatherBarkTimer = 0
                    if type(PHNPC.sayWeatherBark) == "function" then
                        pcall(function() PHNPC.sayWeatherBark(npc) end)
                    end
                end
            end

            -- v0.0.11 : SUPPRIME les appels checkAndOpenDoors/Windows ici.
            -- Ils sont desormais appeles UNIQUEMENT au lancement d'un path
            -- (dans startFollowing/startMovingTo) -> elimine le ping-pong
            -- ouverture/fermeture rapporte au test v0.0.10.

            -- Detection blocage (stuck)
            pcall(function() PHNPC.handleStuck(npc) end)

            -- 1. Evaluation fuite (priorite haute)
            pcall(function() PHNPC.npcFlightStep(npc, player) end)

            -- 2. Evaluation combat (si pas en fuite)
            if type(PHNPC.npcCombatStep) == "function" then
                pcall(function() PHNPC.npcCombatStep(npc) end)
            end

            -- 3. Suivi joueur (etat "following")
            if md.PHNPC_State == "following" then
                local dx   = player:getX() - npc:getX()
                local dy   = player:getY() - npc:getY()
                local dist = math.sqrt(dx * dx + dy * dy)

                local stopDist = (PHNPC.FOLLOW_STOP_DISTANCE or 3)
                if dist <= stopDist then
                    -- Assez proche : stopper
                    if md.PHNPC_Moving then
                        PHNPC.stopMoving(npc)
                    end
                    PHNPC._followTimers[npc] = 0

                else
                    -- v0.0.17 : cadence de follow controlee pour eviter les
                    -- micro-saccades dues aux relances trop frequentes.
                    local runDist = PHNPC.RUN_DISTANCE or 6
                    local wt = (dist > runDist) and "Run" or "Walk"
                    md.PHNPC_FollowTick = (md.PHNPC_FollowTick or 0) + 1
                    local forceImmediate = dist > (runDist + 4)
                    if forceImmediate or md.PHNPC_FollowTick >= (PHNPC.FOLLOW_TICK_RATE or 20) then
                        md.PHNPC_FollowTick = 0
                        PHNPC.startFollowing(npc, player, wt)
                    end
                end

            -- 4. Etat "goingto" : NPC se deplace vers une destination designee
            elseif md.PHNPC_State == "goingto" and md.PHNPC_GoToX then
                local gdx  = md.PHNPC_GoToX - npc:getX()
                local gdy  = md.PHNPC_GoToY - npc:getY()
                local dist = math.sqrt(gdx * gdx + gdy * gdy)
                -- v0.0.9h : seuil dedie GOTO_ARRIVE_DISTANCE (=1) au lieu de
                -- FOLLOW_STOP_DISTANCE (=3) qui faisait arriver immediatement.
                local arriveDist = PHNPC.GOTO_ARRIVE_DISTANCE or 1
                if dist <= arriveDist then
                    -- Arrive : passer en "staying" SANS patrouille (v0.0.11 fix bug
                    -- "Va la-bas" -> NPC repartait dans direction aleatoire car staying
                    -- patrol active. NoPatrol bloque la patrouille jusqu'a nouvel ordre).
                    md.PHNPC_State    = "staying"
                    md.PHNPC_ZoneX    = md.PHNPC_GoToX
                    md.PHNPC_ZoneY    = md.PHNPC_GoToY
                    md.PHNPC_ZoneZ   = md.PHNPC_GoToZ or npc:getZ()
                    md.PHNPC_ZoneR    = PHNPC.STAY_RADIUS or 5
                    md.PHNPC_NoPatrol = true
                    md.PHNPC_GoToX    = nil
                    md.PHNPC_GoToY    = nil
                    md.PHNPC_GoToZ    = nil
                    md.PHNPC_OrderLock = nil
                    PHNPC.stopMoving(npc)
                    pcall(function() PHNPC.closeBehindNPC(npc) end)
                    PHNPC.Log.info("Update", tostring(md.PHNPC_Name) .. " arrive a destination -> staying (no patrol)")
                    pcall(function()
                        npc:addLineChatElement(string.format(getText("UI_PHNPC_BarkArrived"), md.PHNPC_Name or "?"), 0.9, 0.9, 0.2)
                    end)
                else
                    -- v0.0.9k : ne PAS rappeler pathToLocationF chaque 20 ticks (ca
                    -- reinitialisait le pathfind en cours et faisait surplace).
                    -- Le pathfind du moteur IsoZombie marche tout seul une fois lance.
                    -- On surveille juste si le NPC est STUCK et on re-path alors.
                    if not md.PHNPC_Moving then
                        PHNPC.startMovingTo(npc, md.PHNPC_GoToX, md.PHNPC_GoToY, md.PHNPC_GoToZ or npc:getZ())
                    else
                        local cx, cy = npc:getX(), npc:getY()
                        local lx = md.PHNPC_LastMoveX or cx
                        local ly = md.PHNPC_LastMoveY or cy
                        local moved = math.sqrt((cx-lx)^2 + (cy-ly)^2)
                        md.PHNPC_StuckTicks = (md.PHNPC_StuckTicks or 0) + 1
                        if moved > (PHNPC.STUCK_THRESHOLD or 0.3) then
                            md.PHNPC_StuckTicks = 0
                            md.PHNPC_LastMoveX  = cx
                            md.PHNPC_LastMoveY  = cy
                        elseif md.PHNPC_StuckTicks >= (PHNPC.STUCK_TICKS or 90) then
                            -- Bloque : forcer un nouveau path (avec Run pour debloquer)
                            md.PHNPC_StuckTicks = 0
                            md.PHNPC_LastMoveX  = cx
                            md.PHNPC_LastMoveY  = cy
                            pcall(function() npc:setBumpType("Shrug") end)
                            PHNPC.forceRepath(npc, md.PHNPC_GoToX, md.PHNPC_GoToY, md.PHNPC_GoToZ or npc:getZ(), "Run")
                            PHNPC.Log.info("Update", tostring(md.PHNPC_Name) .. " stuck -> force repath Run")
                        end
                    end
                end

            -- 5. Etat "staying" : rester dans une zone, deplacement libre dans le rayon
            elseif md.PHNPC_State == "staying" and md.PHNPC_ZoneX then
                local zx, zy = md.PHNPC_ZoneX, md.PHNPC_ZoneY
                local zdx, zdy = npc:getX() - zx, npc:getY() - zy
                local distZone = math.sqrt(zdx * zdx + zdy * zdy)
                local zoneR = md.PHNPC_ZoneR or (PHNPC.STAY_RADIUS or 5)

                if distZone > zoneR then
                    -- Hors zone : retourner au centre
                    PHNPC._followTimers[npc] = (PHNPC._followTimers[npc] or 0) + 1
                    if PHNPC._followTimers[npc] >= (PHNPC.FOLLOW_TICK_RATE or 20) then
                        PHNPC._followTimers[npc] = 0
                        PHNPC.startMovingTo(npc, zx, zy, md.PHNPC_ZoneZ or npc:getZ())
                    end
                else
                    -- Dans la zone : patrouille courte et libre (sauf si NoPatrol set,
                    -- v0.0.11 : NoPatrol=true apres arrivee goingto pour eviter que le
                    -- NPC reparte dans direction aleatoire apres "Va la-bas").
                    if not md.PHNPC_NoPatrol then
                        PHNPC._followTimers[npc] = (PHNPC._followTimers[npc] or 0) + 1
                        if PHNPC._followTimers[npc] >= (PHNPC.ZONE_PATROL_TICKS or 200) then
                            PHNPC._followTimers[npc] = 0
                            if not md.PHNPC_Moving and PHNPC.findFreeSquareNear then
                                local pr = PHNPC.PATROL_RADIUS or 3
                                local tx, ty = PHNPC.findFreeSquareNear(zx, zy, npc:getZ(), pr, 4)
                                if tx then PHNPC.startMovingTo(npc, tx, ty, npc:getZ()) end
                            end
                        end
                    end
                end

            -- 6. Etat "free" : NPC libre mais dans l'equipe, errance autonome
            elseif md.PHNPC_State == "free" then
                PHNPC._followTimers[npc] = (PHNPC._followTimers[npc] or 0) + 1
                if PHNPC._followTimers[npc] >= 300 then
                    PHNPC._followTimers[npc] = 0
                    if PHNPC.findFreeSquareNear then
                        local wd = PHNPC.FREE_WANDER_DIST or 10
                        local tx, ty = PHNPC.findFreeSquareNear(npc:getX(), npc:getY(), npc:getZ(), wd, 6)
                        if tx then PHNPC.startMovingTo(npc, tx, ty, npc:getZ()) end
                    end
                end

            -- 7. Etat "shelter" : chercher une zone safe, puis staying
            elseif md.PHNPC_State == "shelter" then
                local inBuilding = false
                pcall(function() inBuilding = npc:getCurrentBuilding() ~= nil end)
                if inBuilding then
                    md.PHNPC_State = "staying"
                    md.PHNPC_ZoneX = npc:getX()
                    md.PHNPC_ZoneY = npc:getY()
                    md.PHNPC_ZoneZ = npc:getZ()
                    md.PHNPC_ZoneR = PHNPC.STAY_RADIUS or 5
                    md.PHNPC_NoPatrol = true
                    md.PHNPC_OrderLock = nil
                    md.PHNPC_GoToX = nil
                    md.PHNPC_GoToY = nil
                    md.PHNPC_GoToZ = nil
                    PHNPC.stopMoving(npc)
                    pcall(function() PHNPC.closeBehindNPC(npc) end)
                    PHNPC.Log.info("Update", tostring(md.PHNPC_Name) .. " shelter inside-building -> staying")
                elseif not md.PHNPC_ZoneX then
                    -- v0.0.9k : nouveau systeme via PHNPC_Building.pickShelterPoint
                    --   (1) chambre safe si NPC deja dans batiment
                    --   (2) batiment le plus proche dans 30 tuiles + room safe
                    --   (3) fallback findClearAreaNear
                    local sx, sy, sz, reason
                    if PHNPC.pickShelterPoint then
                        pcall(function() sx, sy, sz, reason = PHNPC.pickShelterPoint(npc) end)
                    end
                    if not sx and PHNPC.findClearAreaNear then
                        pcall(function() sx, sy = PHNPC.findClearAreaNear(npc:getX(), npc:getY(), npc:getZ(), 15) end)
                        sz = npc:getZ()
                        reason = "fallback_clear"
                    end
                    -- Si rien : fallback aleatoire pour bouger quand meme
                    local nx0, ny0 = npc:getX(), npc:getY()
                    if not sx or ((sx - nx0)^2 + (sy - ny0)^2) < 4 then
                        local ang = math.random() * 2 * math.pi
                        sx = nx0 + math.cos(ang) * 10
                        sy = ny0 + math.sin(ang) * 10
                        sz = npc:getZ()
                        reason = "random"
                        PHNPC.Log.info("Update", tostring(md.PHNPC_Name) .. " shelter fallback aleatoire")
                    end
                    md.PHNPC_ZoneX = sx
                    md.PHNPC_ZoneY = sy
                    md.PHNPC_ZoneZ = sz
                    md.PHNPC_ZoneR = PHNPC.STAY_RADIUS or 5
                    PHNPC.startMovingTo(npc, sx, sy, sz, "Run")  -- toujours courir vers l'abri
                    PHNPC.Log.info("Update", tostring(md.PHNPC_Name) .. " -> shelter ["..tostring(reason).."] (" .. string.format("%.1f,%.1f", sx, sy) .. ")")
                else
                    local sdx = npc:getX() - md.PHNPC_ZoneX
                    local sdy = npc:getY() - md.PHNPC_ZoneY
                    if (sdx * sdx + sdy * sdy) < 4 then
                        md.PHNPC_State = "staying"  -- arrivee : passer en staying
                        md.PHNPC_NoPatrol = true     -- v0.0.11 : pas de patrouille apres shelter
                        md.PHNPC_OrderLock = nil
                        PHNPC.stopMoving(npc)
                        pcall(function() PHNPC.closeBehindNPC(npc) end)
                        PHNPC.Log.info("Update", tostring(md.PHNPC_Name) .. " shelter atteint -> staying (no patrol)")
                    else
                        -- v0.0.9k : detection stuck plutot que retry toutes les 20 ticks
                        if not md.PHNPC_Moving then
                            PHNPC.startMovingTo(npc, md.PHNPC_ZoneX, md.PHNPC_ZoneY, md.PHNPC_ZoneZ or npc:getZ(), "Run")
                        else
                            local cx, cy = npc:getX(), npc:getY()
                            local lx = md.PHNPC_LastMoveX or cx
                            local ly = md.PHNPC_LastMoveY or cy
                            local moved = math.sqrt((cx-lx)^2 + (cy-ly)^2)
                            md.PHNPC_StuckTicks = (md.PHNPC_StuckTicks or 0) + 1
                            if moved > (PHNPC.STUCK_THRESHOLD or 0.3) then
                                md.PHNPC_StuckTicks = 0
                                md.PHNPC_LastMoveX  = cx
                                md.PHNPC_LastMoveY  = cy
                            elseif md.PHNPC_StuckTicks >= (PHNPC.STUCK_TICKS or 90) then
                                md.PHNPC_StuckTicks = 0
                                md.PHNPC_LastMoveX  = cx
                                md.PHNPC_LastMoveY  = cy
                                pcall(function() npc:setBumpType("Shrug") end)
                                PHNPC.forceRepath(npc, md.PHNPC_ZoneX, md.PHNPC_ZoneY, md.PHNPC_ZoneZ or npc:getZ(), "Run")
                            end
                        end
                    end
                end

            -- 8. Etat "attacking" : attaquer, puis retourner a la position de base
            elseif md.PHNPC_State == "attacking" then
                local atarget
                if PHNPC.findNearestZombie then
                    pcall(function() atarget = PHNPC.findNearestZombie(npc, PHNPC.COMBAT_RANGE or 8) end)
                end
                if not atarget and md.PHNPC_ZoneX then
                    -- Plus de cibles : retourner a la position de base
                    local rdx = npc:getX() - md.PHNPC_ZoneX
                    local rdy = npc:getY() - md.PHNPC_ZoneY
                    if (rdx * rdx + rdy * rdy) > 4 then
                        PHNPC.startMovingTo(npc, md.PHNPC_ZoneX, md.PHNPC_ZoneY, md.PHNPC_ZoneZ or npc:getZ())
                    else
                        PHNPC.stopMoving(npc)
                    end
                end
                -- npcCombatStep (appel precedent) gere l'attaque effective
            end
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
    print("[PHNPC] v0.0.15 pret")
end)

print("[PHNPC] Update v0.0.17 loaded")
