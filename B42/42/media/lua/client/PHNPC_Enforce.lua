--[[
    PHNPC_Enforce.lua  v1.0  (client)
    Enforcement du comportement NPC chaque tick (PHNPC.enforceNPC).
    Appele depuis OnZombieUpdate pour chaque IsoZombie marque comme NPC.

    FIX v1.0 ANIMATION COUPEE :
      Ajout du cas "idle" dans le handler d'etats : si le NPC etait en mouvement
      (PHNPC_Moving=true) et que le pathfind vient de se terminer (asn="idle"),
      on declenche proprement la transition WalkToIdle via PHNPC.stopMoving.
      Avant ce fix, le NPC restait avec PHNPC_Moving=true indefiniment apres
      l'arrivee a destination => WalkToIdle jamais joue => animation bras tendus.

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

    -- 1. Activer le moteur pour TOUS (NHM GCCoreEnforceMain.lua ligne 9 EXACT)
    --    PZ marque setUseless(true) apres certains hits => NPC se fige
    --    Revenir a false chaque tick, puis setUseless(true) en step 7 si non-recrute
    zombie:setUseless(false)

    -- 2. Fix B42 : empeche marche en arriere non souhaitee (Bandits ZAMove.lua 69-74)
    pcall(function() zombie:setAnimatingBackwards(false) end)

    -- 3. Variables critiques AnimSet (CHAQUE TICK — sinon Zombie_Idle reprend)
    --    "PHNPC_IsNPC" active nos ZSIdle.xml, ZSWalk.xml, etc.
    --    setWalkType("Walk") => PZ fixe zombieWalkType en interne (read-only, ne pas setVariable)
    pcall(function() zombie:setVariable("PHNPC_IsNPC", true) end)
    pcall(function() zombie:setVariable("NoLungeTarget", true) end)
    zombie:setWalkType("Walk")
    -- Genre : Bob = male, Kate = female — CRITIQUE pour idle/walk corrects
    pcall(function() zombie:setFemaleEtc(md.PHNPC_Female or false) end)
    zombie:setSpeedMod(md.PHNPC_SpeedMod or 0.8)

    -- 4. Prevenir comportement zombie (dents + manger cadavre)
    --    IMPORTANT : knockDown/setKnockedDown/setCanWalk sont retires d'ici.
    --    Bandits NE les appelle JAMAIS dans leur update loop. Les appeler a chaque tick
    --    (meme pendant "bumped") interrompait le moteur AnimSet et empechait
    --    BumpAnimFinished=true d'etre emis => boucle bumped infinie.
    --    Ces appels sont dans le handler "falldown/staggerback/down" (step 5) uniquement.
    zombie:setNoTeeth(true)
    pcall(function() zombie:setEatBodyTarget(nil, false) end)
    -- setHealth : seulement si trop bas, evite recalcul constant du moteur physique
    local _hp = 0
    pcall(function() _hp = zombie:getHealth() end)
    if _hp < 9000 then zombie:setHealth(10000) end

    -- 5. Gestion etats d'action (Bandits ManageActionState)
    local skipSecurity = false
    pcall(function()
        local asn = zombie:getActionStateName()

        -- Reset tick bumped si on n'est plus en bumped
        if asn ~= "bumped" then md.PHNPC_BumpTick = 0 end

        if asn == "idle" then
            -- FIX ANIMATION : pathfind vient de se terminer => WalkToIdle proprement
            -- Avant ce fix : PHNPC_Moving restait true indefiniment, WalkToIdle jamais joue
            if md.PHNPC_Moving then
                PHNPC.stopMoving(zombie)
            end

        elseif asn == "pathfind" then
            -- CRITIQUE : ne jamais interrompre un pathfinding en cours
            -- (GCCoreEnforceMain : "setTarget(nil) mata el pathfind")
            skipSecurity = true

        elseif asn == "bumped" then
            -- Safety net EXACT NHM GCCoreEnforce.lua :
            -- setBumpType("IdleToWalk") apres 30 ticks pour forcer sortie du bumped.
            -- ZSIdleToWalk.xml (Bob_IdleToWalk + Event=End) se termine proprement
            -- et emet BumpAnimFinished=true => moteur sort de bumped.
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
            -- NPC frappe : laisser l'animation se jouer (~25 ticks) puis reset
            skipSecurity = true
            md.PHNPC_HitTicks = (md.PHNPC_HitTicks or 0) + 1
            if md.PHNPC_HitTicks > 25 then
                zombie:changeState(ZombieIdleState.instance())
                pcall(function() zombie:setBumpType("Shrug") end)
                md.PHNPC_HitTicks = 0
                md.PHNPC_Moving   = false
            end

        elseif asn == "turnalerted" then
            zombie:changeState(ZombieIdleState.instance())
            pcall(function() zombie:clearAggroList() end)
            zombie:setTarget(nil)

        elseif asn == "lunge" then
            if md.PHNPC_Moving then
                -- Lunge de deplacement (navigation) — ne pas interrompre
                skipSecurity = true
            else
                zombie:changeState(ZombieIdleState.instance())
                pcall(function() zombie:clearAggroList() end)
                zombie:setTarget(nil)
                md.PHNPC_Moving = false
            end

        elseif asn == "attack" or asn == "eatBody" then
            zombie:changeState(ZombieIdleState.instance())
            pcall(function() zombie:clearAggroList() end)
            zombie:setTarget(nil)
            md.PHNPC_Moving = false

        elseif asn == "falldown" or asn == "staggerback" or asn == "down" then
            -- Empecher pose zombie rampant / animation morsure au sol
            zombie:changeState(ZombieIdleState.instance())
            pcall(function() zombie:knockDown(false) end)
            pcall(function() zombie:setKnockedDown(false) end)
            pcall(function() zombie:setCanWalk(true) end)
            md.PHNPC_Moving = false

        elseif asn == "getup" then
            -- Laisser finir le releve, puis on retombera en idle
            skipSecurity = true
        end
    end)

    -- 6. Securite : setTarget(nil) + clearAggroList SEULEMENT si pas en pathfind
    --    Appel inconditionnel TUERAIT le pathfinding (commentaire NPC_Helper_Mod)
    if not skipSecurity then
        zombie:setTarget(nil)
        pcall(function() zombie:clearAggroList() end)
    end

    -- 7. setUseless selon recrutement (pattern NHM GCCoreEnforceMain.lua exact)
    --    Recrutes  : setUseless(false) => pathfinding actif (following/combat)
    --    Non-recrutes : setUseless(true) => figes en place, moteur zombie bloque
    if md.PHNPC_Recruited then
        zombie:setUseless(false)
    else
        zombie:setUseless(true)
    end

    -- 8. Sons : VoicePrefix genre-based pour activer footsteps, voix zombie supprimees
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
end

print("[PHNPC] Enforce v0.0.9a loaded")
