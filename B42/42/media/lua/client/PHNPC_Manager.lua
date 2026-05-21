--[[
    PHNPC_Manager.lua  v0.4  (client)
    Spawn / Enforce / Suivi / Menu contextuel / Inventaire NPC
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
local _openInventoryNPC = nil   -- NPC dont l'inventaire est actuellement ouvert

local function startFollowing(npc, player)
    local md = npc:getModData()
    npc:setUseless(false)
    if not md.PHNPC_Moving then
        md.PHNPC_Moving = true
        pcall(function() npc:setBumpType("IdleToWalk") end)
    end
    -- Pathfinder vers un point a FOLLOW_STOP_DISTANCE tiles du joueur (pas sur le joueur)
    -- Evite le "collant" en ne ciblant jamais la case exacte du joueur
    pcall(function()
        local stopDist = PHNPC.FOLLOW_STOP_DISTANCE or 3
        local px, py, pz = player:getX(), player:getY(), player:getZ()
        local nx, ny     = npc:getX(), npc:getY()
        local dx, dy     = px - nx, py - ny
        local d = math.sqrt(dx*dx + dy*dy)
        if d > stopDist + 0.5 then
            local ratio = (d - stopDist) / d
            npc:pathToLocationF(nx + dx * ratio, ny + dy * ratio, pz)
        end
        -- Si deja assez proche, stopMoving sera appele par OnTick
    end)
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

    -- 1. (setUseless gere en step 7 selon md.PHNPC_Moving — voir ci-dessous)

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

    -- 4. Prevenir comportement zombie (dents + manger cadavre + crawl)
    zombie:setNoTeeth(true)
    pcall(function() zombie:setEatBodyTarget(nil, false) end)
    zombie:setHealth(10000)
    -- Empecher tout etat "a terre" (falldown/staggerback/crawl) independamment des HP
    pcall(function() zombie:knockDown(false) end)
    pcall(function() zombie:setKnockedDown(false) end)
    pcall(function() zombie:setCanWalk(true) end)

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

    -- 7. setUseless : pattern EXACT NPC_Helper_Mod (GCCoreEnforceMain.lua fin)
    --    Recrute  => setUseless(false) TOUJOURS : IA active, pathfinding + animations sans gel
    --    Non-recr => setUseless(true)  : gele pour empecher errance zombie
    --    IMPORTANT : l'ancien code "setUseless selon PHNPC_Moving" gelait les animations
    --    bumped (WalkToIdle, PainHead, IdleToWalk) => NPC bloque en animation bousculade.
    --    IMPORTANT : setUseless(true) empeche aussi les variables AnimSet (PHNPC_IsNPC)
    --    d'etre evaluees => animations vanilla zombie (bras tendus) au lieu de Bob_*.
    if md.PHNPC_Recruited then
        zombie:setUseless(false)
    else
        zombie:setUseless(true)
        -- Reset periodique pour non-recrutes (evite pose zombie residuelle)
        md.PHNPC_IdleTick = (md.PHNPC_IdleTick or 0) + 1
        if md.PHNPC_IdleTick >= 60 then
            md.PHNPC_IdleTick = 0
            pcall(function() zombie:changeState(ZombieIdleState.instance()) end)
        end
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
    md.PHNPC_Moving    = false
    md.PHNPC_IdleTick  = 0
    PHNPC.recruited[npc] = true
    -- Transition propre vers idle humain (evite bras tendus zombie au moment du recrutement)
    pcall(function()
        npc:setUseless(false)
        npc:changeState(ZombieIdleState.instance())
        npc:setBumpType("Shrug")
    end)
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
    -- Fermer l'inventaire si c'est ce NPC qui est ouvert
    if _openInventoryNPC == npc then _openInventoryNPC = nil end
    -- Nettoyer toutes les references avant la suppression
    PHNPC.allNPCs[npc]   = nil
    PHNPC.recruited[npc] = nil
    _followTimers[npc]   = nil
    -- Supprimer du monde (removeFromWorld = retire immediatement)
    pcall(function() npc:removeFromWorld() end)
    print("[PHNPC] Supprime : " .. name)
end

-- ============================================================
-- INVENTAIRE NPC (GCMenuInventory.lua pattern EXACT)
-- Injecte le container du NPC dans le loot panel
-- ============================================================

local function openNPCInventory(npc)
    if not npc then return end
    local md = npc:getModData()
    local npcInv = npc:getInventory()
    pcall(function() npcInv:setType(md.PHNPC_Name or "Survivant") end)

    _openInventoryNPC = npc

    local player = getPlayer()
    if not player then return end
    local playerNum = player:getPlayerNum()
    local pdata = getPlayerData(playerNum)
    if pdata then
        local loot = pdata.lootInventory
        loot:refreshBackpacks()
        if loot.isCollapsed then
            loot.isCollapsed = false
            pcall(function() loot:clearMaxDrawHeight() end)
            loot.collapseCounter = 0
        end
        pcall(function() loot:selectButtonForContainer(npcInv) end)
    end
end

-- Hook refresh du loot panel : injecte le container NPC a chaque refresh
Events.OnRefreshInventoryWindowContainers.Add(function(page, step)
    if step ~= "beforeFloor" then return end
    if page.onCharacter then return end

    local npc = _openInventoryNPC
    if not npc then return end

    -- Fermer si NPC mort ou trop loin
    local dead = false
    pcall(function() dead = npc:isDead() end)
    if dead then _openInventoryNPC = nil ; return end

    local player = getPlayer()
    if player then
        local dx = npc:getX() - player:getX()
        local dy = npc:getY() - player:getY()
        if (dx*dx + dy*dy) > (PHNPC.INTERACTION_DIST + 2)^2 then
            _openInventoryNPC = nil ; return
        end
    end

    local md = npc:getModData()
    local npcInv = npc:getInventory()
    local loot = getPlayerLoot(page.player)
    if loot then
        loot:addContainerButton(
            npcInv,
            nil,
            md.PHNPC_Name or "Survivant",
            md.PHNPC_Name or "Survivant"
        )
    end
end)

-- ============================================================
-- MENU CONTEXTUEL (GCMenuContext.onFillWorldObjectContextMenu EXACT)
-- ============================================================

-- Affiche l'etat complet du NPC via Say() (visible en jeu)
local function showNPCInfo(npc)
    local md    = npc:getModData()
    local hp    = md.PHNPC_Health    or 0
    local maxHp = md.PHNPC_MaxHealth or 100
    local speed = string.format("%.0f%%", (md.PHNPC_SpeedMod or 0.8) * 100)
    local str   = tostring(md.PHNPC_Strength or "?")
    local outfit= tostring(md.PHNPC_Outfit or "?")
    local state = tostring(md.PHNPC_State or "idle")
    local genre = (md.PHNPC_Female and "F" or "M")
    -- Ligne 1 : identite
    pcall(function()
        npc:Say((md.PHNPC_Name or "?") .. " (" .. genre .. ") — " .. outfit)
    end)
    -- Ligne 2 : stats
    pcall(function()
        npc:Say("HP:" .. hp .. "/" .. maxHp .. "  Vit:" .. speed .. "  For:" .. str .. "  Etat:" .. state)
    end)
end

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
        local hp    = md.PHNPC_Health    or 0
        local maxHp = md.PHNPC_MaxHealth or 100
        -- Label avec HP integre pour visibilite immediate
        local label = string.format("[%s (%s) — %s — HP:%d/%d]",
                        name, genre, md.PHNPC_Outfit or "?", hp, maxHp)

        local menuOpt = context:addOption(label)
        local subMenu = ISContextMenu:getNew(context)
        context:addSubMenu(menuOpt, subMenu)

        -- Infos / stats (lecture seule)
        subMenu:addOption("Afficher l'etat...",   npc, showNPCInfo)

        if not md.PHNPC_Recruited then
            -- NPC non recrute : unique option de recrutement
            subMenu:addOption("Rejoins-moi !",    npc, recruitNPC)
        else
            -- NPC recrute : inventaire + sous-menu Ordres
            subMenu:addOption("Inventaire...",     npc, openNPCInventory)

            local ordreOpt = subMenu:addOption("Ordres...")
            local ordreSub = ISContextMenu:getNew(subMenu)
            subMenu:addSubMenu(ordreOpt, ordreSub)

            if md.PHNPC_State == "following" then
                ordreSub:addOption("Reste ici.",   npc, stayNPC)
            else
                ordreSub:addOption("Suis-moi !",   npc, followNPC)
            end
            ordreSub:addOption("Tu peux partir.",  npc, dismissNPC)
        end

        subMenu:addOption("[Supprimer]",           npc, deleteNPC)
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
    PHNPC.allNPCs        = {}
    PHNPC.recruited      = {}
    _followTimers        = {}
    _openInventoryNPC    = nil
    print("[PHNPC] Manager v0.4 pret")
end)

-- Enregistrer le menu contextuel
Events.OnPreFillWorldObjectContextMenu.Add(onFillContextMenu)

print("[PHNPC] PHNPC_Manager v0.4 loaded")
