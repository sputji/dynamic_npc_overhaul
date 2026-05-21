--[[
    PHNPC_Manager.lua  v0.2  (client)
    Spawn / Enforce / Suivi / Menu contextuel
    Necessite: PHNPC_Core.lua (shared)

    Pattern copie EXACTEMENT NPC_Helper_Mod :
      - GCCoreConvert.lua  => convertToNPC
      - GCCoreEnforceMain.lua => enforceNPC
      - GCCoreSpawn.lua => spawnNPC
      - GCCoreActions.lua => startMoving / stopMoving
      - GCUpdate.lua => OnZombieUpdate
      - GCMenuContext.lua => menu clic droit
    Seules differences : variable "PHNPC_IsNPC" (nos XMLs) au lieu de "GCCompanion",
                          "zombieWalkType" (nos XMLs) au lieu de "GCWalkType".
]]

-- ============================================================
-- HELPERS DE DEPLACEMENT (GCCoreActions.lua pattern EXACT)
-- ============================================================

local _followTimers = {}   -- [npcRef] => ticks depuis dernier pathToCharacter

local function startFollowing(npc, player)
    local md = npc:getModData()
    npc:setUseless(false)
    if not md.PHNPC_Moving then
        md.PHNPC_Moving = true
        pcall(function() npc:setBumpType("IdleToWalk") end)
    end
    pcall(function() npc:pathToCharacter(player) end)
end

local function startMovingTo(npc, x, y, z)
    local md = npc:getModData()
    npc:setUseless(false)
    if not md.PHNPC_Moving then
        md.PHNPC_Moving = true
        pcall(function() npc:setBumpType("IdleToWalk") end)
    end
    pcall(function() npc:pathToLocationF(x, y, z) end)
end

local function stopMoving(npc)
    local md = npc:getModData()
    if md.PHNPC_Moving then
        md.PHNPC_Moving = false
        pcall(function() npc:setBumpType("WalkToIdle") end)
        -- Effacer la cible pour eviter lunge/turnalerted apres WalkToIdle
        pcall(function() npc:setTarget(nil) end)
        pcall(function() npc:clearAggroList() end)
    end
end

-- ============================================================
-- ENFORCE NPC (GCCoreEnforceMain._enforceMainBehavior EXACT)
-- Appele chaque tick depuis OnZombieUpdate
-- ============================================================

local function enforceNPC(zombie)
    local md = zombie:getModData()

    -- 1. Habilitar engine zombie (Bandits linea 2001)
    --    setUseless(false) requis pour que pathToCharacter fonctionne
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
    zombie:setNoTeeth(true)
    pcall(function() zombie:setEatBodyTarget(nil, false) end)
    zombie:setHealth(10000)

    -- 5. Gestion etats d'action (Bandits ManageActionState lineas 318-434)
    local skipSecurity = false
    pcall(function()
        local asn = zombie:getActionStateName()

        if asn == "pathfind" then
            -- CRITIQUE : ne jamais interrompre un pathfinding en cours
            -- (GCCoreEnforceMain : "setTarget(nil) mata el pathfind")
            skipSecurity = true

        elseif asn == "bumped" then
            -- Laisser les animations bumped (Shove, Pain, etc.) se terminer
            skipSecurity = true

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
        end
    end)

    -- 6. Securite : setTarget(nil) + clearAggroList SEULEMENT si pas en pathfind
    --    Appel inconditionnel TUERAIT le pathfinding (commentaire NPC_Helper_Mod)
    if not skipSecurity then
        zombie:setTarget(nil)
        pcall(function() zombie:clearAggroList() end)
    end

    -- 7. Freezer le zombie AI si NPC non-recrute
    --    setUseless(true) = moteur zombie desactive = pas de detection/attaque
    --    setUseless(false) = moteur zombie actif = pathfinding possible
    if not md.PHNPC_Recruited then
        zombie:setUseless(true)
    end

    -- 8. Sons : VoicePrefix genre-based pour activer footsteps, voix zombie supprimees
    --    VoicePrefix "PHNPC" n'a pas de soundbank => aucun son
    --    MaleZombie/FemaleZombie ont footsteps + voix => on garde footsteps, on coupe voix
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
end

-- ============================================================
-- CONVERSION ZOMBIE => NPC (GCCoreConvert.convertToNPC EXACT)
-- Pattern Bandits Banditize() (BanditUpdate.lua lignes 158-206)
-- IMPORTANT : NO setUseless, NO changeState, NO setTarget ici
-- ============================================================

local function convertToNPC(zombie, outfit, isFemale, npcName)
    if not zombie then return end

    print("[PHNPC][CONVERT] " .. npcName .. " (" .. (isFemale and "F" or "M") .. ") outfit=" .. outfit)

    -- 1. Dents (Bandits linea 164)
    pcall(function() zombie:setNoTeeth(true) end)

    -- 2. Variables de vitesse (Bandits lineas 169-171)
    pcall(function() zombie:setVariable("LimpSpeed", 0.80) end)
    pcall(function() zombie:setVariable("RunSpeed",  0.75) end)
    pcall(function() zombie:setVariable("WalkSpeed", 1.04) end)

    -- 3. Variable PHNPC_IsNPC => active nos AnimSet XMLs (ZSIdle, ZSWalk, etc.)
    --    Sans cette variable, le jeu utilise Zombie_Idle et Zombie_Walk
    pcall(function() zombie:setVariable("PHNPC_IsNPC", true) end)

    -- 4. WalkType humain (Bandits lineas 178-179)
    --    setWalkType => API PZ, fixe zombieWalkType en interne (read-only)
    --    NE PAS appeler setVariable("zombieWalkType",...) => WARN read-only
    pcall(function() zombie:setWalkType("Walk") end)

    -- 5. Hit reaction humaine au lieu de zombie (Bandits linea 184)
    pcall(function() zombie:setVariable("ZombieHitReaction", "Chainsaw") end)

    -- 6. Desactiver lunge vers cible (Bandits linea 187)
    pcall(function() zombie:setVariable("NoLungeTarget", true) end)

    -- 7. Silencer sons zombie (Bandits linea 190)
    pcall(function() zombie:getEmitter():stopAll() end)

    -- 8. Vider les mains (Bandits lineas 192-195)
    pcall(function() zombie:setPrimaryHandItem(nil) end)
    pcall(function() zombie:setSecondaryHandItem(nil) end)
    pcall(function() zombie:resetEquippedHandsModels() end)
    pcall(function() zombie:clearAttachedItems() end)

    -- 9. Neutraliser TurnAlerted (Bandits linea 198)
    pcall(function() zombie:setTurnAlertedValues(-5, 5) end)

    -- 10. Prefixe voix : genre-based pour avoir footsteps ("PHNPC" n'a pas de soundbank)
    pcall(function() zombie:getDescriptor():setVoicePrefix(isFemale and "FemaleZombie" or "MaleZombie") end)

    -- 11. Empecher re-habillage automatique par le moteur
    pcall(function() zombie:setDressInRandomOutfit(false) end)

    -- 11b. Genre : necessaire pour Bob_Walk/Kate_Walk + Bob_Idle/Kate_Idle
    --    Sans setFemaleEtc, une femme joue Bob_Idle (male) au lieu de Kate_Idle
    pcall(function() zombie:setFemaleEtc(isFemale) end)

    -- 12. Premier bump => sortir de Zombie_Idle proprement
    pcall(function() zombie:setBumpType("Shrug") end)

    -- 13. Nettoyer visuels (salet, sang)
    pcall(function()
        local hv = zombie:getHumanVisual()
        if hv then hv:removeDirt() ; hv:removeBlood() end
    end)

    -- 14. ModData NPC
    local md = zombie:getModData()
    md.PHNPC_IsNPC      = true
    md.PHNPC_Recruited  = false
    md.PHNPC_State      = "idle"     -- "idle" | "following" | "staying"
    md.PHNPC_Name       = npcName
    md.PHNPC_Female     = isFemale
    md.PHNPC_Outfit     = outfit
    md.PHNPC_Moving     = false
    md.PHNPC_HitTicks   = 0
    -- ShowTimer : ignore les premiers ticks le temps que les animations se stabilisent
    -- (GCCoreSpawn.lua pattern : GC_ShowTimer = 5)
    md.PHNPC_ShowTimer  = 5

    -- 15. Enregistrer dans le systeme
    PHNPC.allNPCs[zombie] = true

    -- 15b. Stats et inventaire par metier (PHNPC_Stats.lua)
    if PHNPC.initStats then
        PHNPC.initStats(zombie, outfit, isFemale)
    end
    if PHNPC.initInventory then
        PHNPC.initInventory(zombie, outfit)
    end

    print("[PHNPC] NPC cree OK : " .. npcName)
end

-- ============================================================
-- SPAWN (GCCoreSpawn.spawnCompanionNPC EXACT)
-- ============================================================

local function spawnNPC(square)
    if not square then
        print("[PHNPC][SPAWN] Erreur : square nil")
        return nil
    end

    local x = square:getX()
    local y = square:getY()
    local z = square:getZ()

    local isFemale     = (ZombRand(2) == 0)
    local femaleChance = isFemale and 100 or 0
    local outfit       = PHNPC.OUTFITS[ZombRand(#PHNPC.OUTFITS) + 1]
    local npcName      = PHNPC.getRandomName(isFemale)

    print("[PHNPC][SPAWN] " .. x .. "," .. y .. "," .. z
          .. " outfit=" .. outfit .. " female=" .. tostring(isFemale))

    -- addZombiesInOutfit est une FONCTION GLOBALE (pas une methode de square)
    local zombieList = nil
    local ok, err = pcall(function()
        zombieList = addZombiesInOutfit(x, y, z, 1, outfit, femaleChance)
    end)

    if not ok then
        print("[PHNPC][SPAWN] ERREUR addZombiesInOutfit : " .. tostring(err))
        return nil
    end

    if not zombieList or zombieList:size() == 0 then
        print("[PHNPC][SPAWN] Erreur : zombieList vide")
        return nil
    end

    local zombie = zombieList:get(0)
    if not zombie then
        print("[PHNPC][SPAWN] Erreur : zombie nil apres spawn")
        return nil
    end

    convertToNPC(zombie, outfit, isFemale, npcName)
    return zombie
end

-- ============================================================
-- ORDRES : RECRUTER / SUIVRE / RESTER / CONGEDIER
-- ============================================================

local function recruitNPC(npc)
    local md = npc:getModData()
    md.PHNPC_Recruited = true
    md.PHNPC_State     = "following"
    PHNPC.recruited[npc] = true
    pcall(function() npc:Say(md.PHNPC_Name .. " : D'accord, je vous suis !") end)
    print("[PHNPC] Recrute : " .. tostring(md.PHNPC_Name))
end

local function followNPC(npc)
    local md = npc:getModData()
    md.PHNPC_State = "following"
    pcall(function() npc:Say(md.PHNPC_Name .. " : Je vous suis !") end)
    print("[PHNPC] Suis le joueur : " .. tostring(md.PHNPC_Name))
end

local function stayNPC(npc)
    local md = npc:getModData()
    md.PHNPC_State = "staying"
    stopMoving(npc)
    pcall(function() npc:Say(md.PHNPC_Name .. " : Je reste ici.") end)
    print("[PHNPC] Reste ici : " .. tostring(md.PHNPC_Name))
end

local function dismissNPC(npc)
    local md = npc:getModData()
    md.PHNPC_Recruited = false
    md.PHNPC_State     = "idle"
    PHNPC.recruited[npc] = nil
    stopMoving(npc)
    pcall(function() npc:Say(md.PHNPC_Name .. " : Bonne chance.") end)
    print("[PHNPC] Congedie : " .. tostring(md.PHNPC_Name))
end

local function deleteNPC(npc)
    local md   = npc:getModData()
    local name = md.PHNPC_Name or "?"
    -- Nettoyer toutes les references avant la suppression
    PHNPC.allNPCs[npc]   = nil
    PHNPC.recruited[npc] = nil
    _followTimers[npc]   = nil
    -- Supprimer du monde (removeFromWorld = retire immediatement)
    pcall(function() npc:removeFromWorld() end)
    print("[PHNPC] Supprime : " .. name)
end

-- ============================================================
-- MENU CONTEXTUEL (GCMenuContext.onFillWorldObjectContextMenu EXACT)
-- ============================================================

local function onFillContextMenu(playerIndex, context, worldObjects, test)
    if test then return end

    local player = getSpecificPlayer(playerIndex)
    if not player or not PHNPC then return end

    local px = player:getX()
    local py = player:getY()

    local cell = player:getCell()
    if not cell then return end

    -- Rechercher NPCs a portee (via zombieList de la cellule)
    local nearbyNPCs = {}
    local zlist = cell:getZombieList()
    local distSq = PHNPC.INTERACTION_DIST * PHNPC.INTERACTION_DIST

    for i = 0, zlist:size() - 1 do
        local z = zlist:get(i)
        if z and PHNPC.isNPC(z) then
            local dx = z:getX() - px
            local dy = z:getY() - py
            if (dx * dx + dy * dy) <= distSq then
                table.insert(nearbyNPCs, z)
            end
        end
    end

    if #nearbyNPCs == 0 then
        -- Aucun NPC a portee : proposer spawn sur la case cliquee
        local square = ISWorldObjectContextMenu.fetchVars.clickedSquare
        if square then
            context:addOption("[PHNPC] Appeler un survivant", square, spawnNPC)
        end
        return
    end

    -- Menu pour chaque NPC a portee
    for _, npc in ipairs(nearbyNPCs) do
        local md    = npc:getModData()
        local name  = md.PHNPC_Name or "Survivant"
        local genre = md.PHNPC_Female and "F" or "M"
        local label = "[" .. name .. " (" .. genre .. ")]"

        local menuOpt = context:addOption(label)
        local subMenu = ISContextMenu:getNew(context)
        context:addSubMenu(menuOpt, subMenu)

        if not md.PHNPC_Recruited then
            subMenu:addOption("Rejoins-moi !", npc, recruitNPC)
        else
            if md.PHNPC_State == "following" then
                subMenu:addOption("Reste ici.",       npc, stayNPC)
            else
                subMenu:addOption("Suis-moi !",       npc, followNPC)
            end
            subMenu:addOption("Tu peux partir.",  npc, dismissNPC)
        end
        subMenu:addOption("[Supprimer]",          npc, deleteNPC)
    end
end

-- ============================================================
-- OnZombieUpdate (GCUpdate.onZombieUpdate EXACT)
-- ============================================================

Events.OnZombieUpdate.Add(function(zombie)
    if not zombie then return end
    if not PHNPC then return end
    if not PHNPC.isNPC(zombie) then return end

    -- IMMEDIAT : neutraliser avant tout traitement
    -- Pattern GCUpdate.lua : appels INCONDITIONNELS ici, avant enforce
    -- (setNoTeeth = empeche morsure pendant chargement)
    pcall(function() zombie:setNoTeeth(true) end)
    pcall(function() zombie:setTarget(nil) end)

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
    pcall(function() enforceNPC(zombie) end)
end)

-- ============================================================
-- OnTick : IA Suivi (GCUpdateAI.runAI pattern)
-- ============================================================

Events.OnTick.Add(function()
    local player = getPlayer()
    if not player or not PHNPC then return end

    for npc, _ in pairs(PHNPC.recruited) do
        -- Verifier validite NPC
        local valid = false
        pcall(function() valid = not npc:isDead() end)

        if not valid then
            -- NPC mort : nettoyer les tables
            local md = npc:getModData()
            PHNPC.recruited[npc] = nil
            PHNPC.allNPCs[npc]   = nil
            _followTimers[npc]   = nil
            print("[PHNPC] Cleanup mort : " .. tostring(md and md.PHNPC_Name or "?"))
        else
            local md = npc:getModData()

            if md.PHNPC_State == "following" then
                local dx   = player:getX() - npc:getX()
                local dy   = player:getY() - npc:getY()
                local dist = math.sqrt(dx * dx + dy * dy)

                if dist > PHNPC.FOLLOW_DISTANCE then
                    _followTimers[npc] = (_followTimers[npc] or 0) + 1
                    if _followTimers[npc] >= PHNPC.FOLLOW_TICK_RATE then
                        _followTimers[npc] = 0
                        startFollowing(npc, player)
                    end
                else
                    -- Proche du joueur : arreter
                    stopMoving(npc)
                    _followTimers[npc] = 0
                end
            end
            -- "staying" : rien a faire (setUseless(true) dans enforceNPC freeze le NPC)
        end
    end
end)

-- ============================================================
-- OnGameStart : reinitialiser l'etat
-- ============================================================

Events.OnGameStart.Add(function()
    PHNPC.allNPCs   = {}
    PHNPC.recruited = {}
    _followTimers   = {}
    print("[PHNPC] Manager v0.2 pret")
end)

-- Enregistrer le menu contextuel
Events.OnPreFillWorldObjectContextMenu.Add(onFillContextMenu)

print("[PHNPC] PHNPC_Manager v0.2 loaded")
