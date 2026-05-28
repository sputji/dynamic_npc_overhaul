--[[
    PHNPC_Enforce.lua  v0.0.9b  (client)
    Enforcement du comportement NPC chaque tick (PHNPC.enforceNPC).
    Appele depuis OnZombieUpdate pour chaque IsoZombie marque comme NPC.

    FIX v0.0.9b ANIMATION BRAS TENDUS (zombie idle) :
      setVariable("PHNPC_IsNPC", true) et setWalkType("Walk") sont desormais
      appeles EN FIN de fonction (step 10), APRES toutes les changeState().
      changeState(ZombieIdleState) peut effacer les variables AnimSet =>
      les re-appliquer en dernier garantit que nos XMLs custom restent actifs.

    FIX v0.0.9b PATROL NON-RECRUTES :
      Step 7 : setUseless(true) est DESORMAIS conditionnel — si le NPC a
      md.PHNPC_PatrolActive > 0, il reste setUseless(false) et peut bouger.
      La valeur est decrementee a chaque tick (durée ~200 ticks = ~3s).

    FIX v0.0.9a ANIMATION COUPEE :
      Ajout du cas "idle" dans le handler d'etats : si le NPC etait en mouvement
      et que le pathfind se termine (asn="idle"), on declenche WalkToIdle.

    Pattern : NHM GCCoreEnforceMain.lua
    Necessite :
      PHNPC_Actions.lua (PHNPC.stopMoving)
      PHNPC_Barks.lua   (PHNPC.sayBark)
]]

-- ============================================================
-- ENFORCE NPC (GCCoreEnforceMain._enforceMainBehavior EXACT)
-- Appele chaque tick depuis OnZombieUpdate
-- ============================================================
function PHNPC.enforceNPC(zombie)
    local md = zombie:getModData()
    local behaviorState = tostring(md.PHNPC_State or "idle")
    local orderMovingState = (behaviorState == "following"
        or behaviorState == "goingto"
        or behaviorState == "shelter"
        or behaviorState == "fleeing")

    -- 1. Activer le moteur pour TOUS (NHM GCCoreEnforceMain.lua ligne 9 EXACT)
    zombie:setUseless(false)

    -- 2. Fix B42 : empeche marche en arriere non souhaitee (Bandits ZAMove.lua 69-74)
    pcall(function() zombie:setAnimatingBackwards(false) end)

    -- v0.0.13b : mitigation agressive anti ClimbOverFenceState.
    -- En B42.18 les NPCs (IsoZombie banditises) peuvent declencher des NPE Java
    -- en entree d'etat ClimbOverFenceState (BodyDamage nil). On intercepte et on
    -- casse immediatement la transition pour eviter la boucle d'erreurs.
    local inFenceState = false
    pcall(function()
        local st = zombie:getCurrentState()
        if st and tostring(st):find("ClimbOverFenceState") then
            inFenceState = true
        end
    end)
    if inFenceState then
        md.PHNPC_Moving = false
        md.PHNPC_PathX = nil
        md.PHNPC_PathY = nil
        md.PHNPC_PathZ = nil
        md.PHNPC_FenceRecoverTicks = 180
        pcall(function() zombie:changeState(ZombieIdleState.instance()) end)
        pcall(function() zombie:setBumpType("Shrug") end)
        pcall(function() zombie:setTarget(nil) end)
        pcall(function() zombie:clearAggroList() end)
        pcall(function() zombie:setRunning(false) end)
    end

    if (md.PHNPC_FenceRecoverTicks or 0) > 0 then
        md.PHNPC_FenceRecoverTicks = md.PHNPC_FenceRecoverTicks - 1
    end

    -- 3. Genre + vitesse (pas les variables AnimSet — celles-ci vont en step 10 apres changeState)
    pcall(function() zombie:setFemaleEtc(md.PHNPC_Female or false) end)
    zombie:setSpeedMod(md.PHNPC_SpeedMod or 0.8)

    -- 4. Prevenir comportement zombie
    zombie:setNoTeeth(true)
    pcall(function() zombie:setEatBodyTarget(nil, false) end)
    -- v0.0.9k : ne plus reset setAttackedBy/clearAggroList chaque tick si NPC en mouvement
    --   ces resets cassaient le pathfind. On les fait UNIQUEMENT a l'arret.
    if not md.PHNPC_Moving then
        pcall(function() zombie:setAttackedBy(nil) end)
        pcall(function() zombie:clearAggroList() end)
    end
    -- v0.0.9j : setAlertedBy/setPathTargetCharacter/setPrimaryTarget/setSecondaryTarget
    -- n'existent PAS en B42.18 (KahluaException non-rattrapable). Retirees.
    -- Si l'AnimEngine est en LungeState alors qu'on a un ordre explicite (goingto/shelter),
    -- forcer la sortie immediate vers ZombieIdleState (l'attaque parasite l'IA).
    if md.PHNPC_State == "goingto" or md.PHNPC_State == "shelter" then
        pcall(function()
            local st = zombie:getCurrentState()
            if st and tostring(st):find("LungeState") then
                zombie:changeState(ZombieIdleState.instance())
            end
        end)
    end
    local _hp = 0
    pcall(function() _hp = zombie:getHealth() end)
    if _hp < 9000 then pcall(function() zombie:setHealth(10000) end) end

    -- 5. Gestion etats d'action (Bandits ManageActionState)
    local skipSecurity = false
    pcall(function()
        local asn = zombie:getActionStateName()

        if asn ~= "bumped" then md.PHNPC_BumpTick = 0 end

        if asn == "idle" then
            -- v0.0.11 : seuil 60 (au lieu de 15) - moteur PathFindBehavior2 peut alterner
            -- idle/pathfind sur de plus longues fenetres pendant les redirections.
            -- 60 ticks = 2 sec evite le stopMoving brutal qui coupait l'anim toutes
            -- les secondes au test v0.0.10.
            if md.PHNPC_Moving then
                md.PHNPC_IdleTicks = (md.PHNPC_IdleTicks or 0) + 1
                local idleLimit = orderMovingState and 120 or 60
                if md.PHNPC_IdleTicks >= idleLimit then
                    md.PHNPC_IdleTicks = 0
                    PHNPC.stopMoving(zombie)
                end
            else
                md.PHNPC_IdleTicks = 0
            end

        elseif asn == "pathfind" then
            md.PHNPC_IdleTicks = 0  -- v0.0.9l reset si on pathfind
            skipSecurity = true

        elseif asn == "bumped" then
            skipSecurity = true
            md.PHNPC_BumpTick = (md.PHNPC_BumpTick or 0) + 1
            if md.PHNPC_BumpTick >= 30 then
                md.PHNPC_BumpTick = 0
                md.PHNPC_Moving   = false
                pcall(function()
                    zombie:changeState(ZombieIdleState.instance())
                    zombie:setBumpType("IdleToWalk")
                end)
                skipSecurity = false
            end

        elseif asn == "hitreaction" then
            skipSecurity = true
            md.PHNPC_HitTicks = (md.PHNPC_HitTicks or 0) + 1
            if md.PHNPC_HitTicks > 25 then
                zombie:changeState(ZombieIdleState.instance())
                pcall(function() zombie:setBumpType("Shrug") end)
                md.PHNPC_HitTicks = 0
                md.PHNPC_Moving   = false
            end

        elseif asn == "turnalerted" then
            pcall(function() zombie:changeState(ZombieIdleState.instance()) end)
            pcall(function() zombie:clearAggroList() end)
            pcall(function() zombie:setTarget(nil) end)

        elseif asn == "lunge" then
            if orderMovingState then
                pcall(function() zombie:changeState(ZombieIdleState.instance()) end)
                pcall(function() zombie:clearAggroList() end)
                pcall(function() zombie:setTarget(nil) end)
                skipSecurity = md.PHNPC_Moving and true or false
            elseif md.PHNPC_Moving then
                skipSecurity = true
            else
                pcall(function() zombie:changeState(ZombieIdleState.instance()) end)
                pcall(function() zombie:clearAggroList() end)
                pcall(function() zombie:setTarget(nil) end)
                md.PHNPC_Moving = false
            end

        elseif asn == "attack" or asn == "eatBody" then
            pcall(function() zombie:changeState(ZombieIdleState.instance()) end)
            pcall(function() zombie:clearAggroList() end)
            pcall(function() zombie:setTarget(nil) end)
            if not orderMovingState then
                md.PHNPC_Moving = false
            end

        elseif asn == "falldown" or asn == "staggerback" or asn == "down" then
            -- v0.0.9i FIX BUG 3 : T-pose lors de la transition falldown -> idle.
            -- En B42.18 l'AnimEngine bloque la transition tant que les variables
            -- BumpFall* restent actives. Il faut les reset EN PLUS de l'API Java.
            pcall(function() zombie:setVariable("BumpFall", false) end)
            pcall(function() zombie:setVariable("BumpFallType", "") end)
            pcall(function() zombie:setVariable("BumpDone", true) end)
            pcall(function() zombie:setVariable("OnTheFloor", false) end)
            pcall(function() zombie:setVariable("WasOnFloor", false) end)
            pcall(function() zombie:setOnFloor(false) end)
            pcall(function() zombie:knockDown(false) end)
            pcall(function() zombie:setKnockedDown(false) end)
            pcall(function() zombie:setBecomeCrawler(false) end)
            pcall(function() zombie:setCrawler(false) end)
            pcall(function() zombie:setCanWalk(true) end)
            pcall(function() zombie:setSprinting(false) end)
            pcall(function() zombie:setAnimatingBackwards(false) end)
            -- Forcer la reinitialisation du modele 3D (essentiel pour casser la T-pose).
            pcall(function() zombie:resetModel() end)
            pcall(function() zombie:resetModelNextFrame() end)
            -- v0.0.9j : setSkeletonResetting n'existe pas en B42.18. Retire.
            zombie:changeState(ZombieIdleState.instance())
            pcall(function() zombie:setBumpType("IdleToWalk") end)
            md.PHNPC_Moving = false

        elseif asn == "getup" then
            skipSecurity = true
        end
    end)

    -- 6. Securite : setTarget(nil) SEULEMENT si pas en pathfind ET pas en mouvement
    -- v0.0.9k : ne PAS casser le pathfind en cours (md.PHNPC_Moving=true) avec setTarget(nil)
    if not skipSecurity and not md.PHNPC_Moving then
        pcall(function() zombie:setTarget(nil) end)
        pcall(function() zombie:clearAggroList() end)
    end

    -- 7. setUseless selon recrutement + patrol
    --    PatrolActive : NPC non-recrute en patrouille => setUseless(false) temporairement
    if md.PHNPC_Recruited then
        pcall(function() zombie:setUseless(false) end)
    elseif (md.PHNPC_PatrolActive or 0) > 0 then
        md.PHNPC_PatrolActive = md.PHNPC_PatrolActive - 1
        pcall(function() zombie:setUseless(false) end)
    else
        pcall(function() zombie:setUseless(true) end)
    end

    -- 8. Sons : voix zombie supprimees
    pcall(function()
        local voicePrefix = (md.PHNPC_Female) and "FemaleZombie" or "MaleZombie"
        zombie:getDescriptor():setVoicePrefix(voicePrefix)
        local emitter = zombie:getEmitter()
        emitter:stopSoundByName("MaleZombieVoiceA")
        emitter:stopSoundByName("MaleZombieVoiceB")
        emitter:stopSoundByName("MaleZombieVoiceC")
        emitter:stopSoundByName("FemaleZombieVoiceA")
        emitter:stopSoundByName("FemaleZombieVoiceB")
        emitter:stopSoundByName("FemaleZombieVoiceC")
    end)

    -- 9. Bark auto (recrutes seulement)
    if md.PHNPC_Recruited then
        md.PHNPC_BarkTick = (md.PHNPC_BarkTick or 0) + 1
        if md.PHNPC_BarkTick >= (PHNPC.BARK_TICK_RATE or 500) then
            md.PHNPC_BarkTick = 0
            PHNPC.sayBark(zombie, md.PHNPC_State or "idle", 1.0, 1.0, 1.0)
        end
    end

    -- 10. Variables AnimSet TOUJOURS en DERNIER (apres tous les changeState)
    --     FIX BRAS TENDUS : changeState(ZombieIdleState) peut effacer ces variables.
    --     Les re-appliquer ici garantit que nos AnimSet XMLs custom restent actifs.
    pcall(function() zombie:setVariable("PHNPC_IsNPC", true) end)
    pcall(function() zombie:setVariable("NoLungeTarget", true) end)
    -- v0.0.9k : suivre le walkType demande par Actions/Update (Walk ou Run), pas hardcoded
    local wt = md.PHNPC_WalkType or "Walk"
    pcall(function() zombie:setVariable("BanditWalkType", wt) end)
    pcall(function() zombie:setVariable("PHNPC_WalkType", wt) end)
    pcall(function() zombie:setWalkType(wt) end)
    if md.PHNPC_Moving then
        pcall(function() zombie:setRunning(wt == "Run") end)
    end
end

print("[PHNPC] Enforce v0.0.9p loaded")
