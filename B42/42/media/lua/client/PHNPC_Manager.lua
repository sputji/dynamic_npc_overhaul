--[[
    PHNPC_Manager.lua  v0.9  (client)
    Spawn / Enforce / Suivi / Menu contextuel / Inventaire NPC
    Combat NPC vs zombies / Fuite HP<30% / Dialogue contextuel
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

local _followTimers     = {}   -- [npcRef] => ticks depuis dernier pathToCharacter
local _openInventoryNPC = nil   -- NPC dont l'inventaire est actuellement ouvert
local _combatTimers     = {}   -- [npcRef] => ticks evaluation combat
local _attackCooldowns  = {}   -- [npcRef] => ticks avant prochain attack

local function startFollowing(npc, player)
    local md = npc:getModData()
    npc:setUseless(false)
    if not md.PHNPC_Moving then
        md.PHNPC_Moving = true
    end
    -- pathToCharacter : methode standard IsoZombie -> IsoPlayer (NPC_Helper_Mod + Bandits)
    -- Plus fiable que pathToLocationF manuel pour le suivi d'un IsoCharacter mobile
    pcall(function() npc:pathToCharacter(player) end)
end

local function startMovingTo(npc, x, y, z)
    local md = npc:getModData()
    npc:setUseless(false)
    if not md.PHNPC_Moving then
        md.PHNPC_Moving = true
        -- NE PAS appeler setBumpType("IdleToWalk") : le vanilla PZ reprendrait l'anim zombie
    end
    pcall(function() npc:pathToLocationF(x, y, z) end)
end

local function stopMoving(npc)
    local md = npc:getModData()
    if md.PHNPC_Moving then
        md.PHNPC_Moving = false
        -- NE PAS appeler setBumpType("WalkToIdle") : le vanilla PZ reprendrait l'anim zombie
        -- setTarget(nil) uniquement si pas en pathfind (cf. enforceNPC step 6)
        pcall(function() npc:setTarget(nil) end)
        pcall(function() npc:clearAggroList() end)
    end
end

-- ============================================================
-- HELPER COMBAT : chercher le zombie non-NPC le plus proche
-- (Pattern GCCombatAI.lua NPC_Helper_Mod simplifie)
-- ============================================================
local function findNearestZombie(npc, range)
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

        -- Reset tick bumped si on n'est plus en bumped
        if asn ~= "bumped" then md.PHNPC_BumpTick = 0 end

        if asn == "pathfind" then
            -- CRITIQUE : ne jamais interrompre un pathfinding en cours
            -- (GCCoreEnforceMain : "setTarget(nil) mata el pathfind")
            skipSecurity = true

        elseif asn == "bumped" then
            -- Laisser les animations bumped (Shove, Pain, etc.) se terminer
            -- Timeout court : 15 ticks (~0.25s) suffit car nos XMLs overrident les vanilla
            skipSecurity = true
            md.PHNPC_BumpTick = (md.PHNPC_BumpTick or 0) + 1
            if md.PHNPC_BumpTick >= 15 then
                md.PHNPC_BumpTick = 0
                md.PHNPC_Moving   = false
                pcall(function() zombie:changeState(ZombieIdleState.instance()) end)
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

    -- 7. setUseless(false) TOUJOURS — pattern NHM exact (GCCoreEnforceMain.lua)
    --    setUseless(true) BLOQUE les AnimSets (PHNPC_IsNPC) et Say() => animations zombie
    --    Les non-recrutes sont neutralises via setTarget(nil)+clearAggroList (step 6)
    zombie:setUseless(false)
    -- Non-recrute : forcer idle regulierement pour eviter reprise locomotion zombie
    if not md.PHNPC_Recruited then
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

    -- 9. Dialogue contextuel auto (bark selon etat, pool de phrases, timer)
    --    Uniquement pour les NPCs recrutes (reduire le bruit pour les non-recrutes)
    if md.PHNPC_Recruited then
        md.PHNPC_BarkTick = (md.PHNPC_BarkTick or 0) + 1
        if md.PHNPC_BarkTick >= (PHNPC.BARK_TICK_RATE or 500) then
            md.PHNPC_BarkTick = 0
            local state = md.PHNPC_State or "idle"
            local barkPool = PHNPC_BARKS[state] or PHNPC_BARKS["idle"]
            local bark = barkPool[ZombRand(#barkPool) + 1]
            pcall(function() zombie:addLineChatElement(bark, 1.0, 1.0, 1.0) end)
        end
    end
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
    md.PHNPC_HitTicks      = 0
    md.PHNPC_CombatMode    = "auto"  -- "auto" | "off" : combat auto vs zombies proches
    md.PHNPC_PrevState     = nil     -- etat sauvegarde avant combat/fuite
    md.PHNPC_BarkTick      = 0       -- compteur pour barks auto
    md.PHNPC_AttackCooldown= 0       -- ticks restants avant prochain attack
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
    pcall(function() npc:addLineChatElement(md.PHNPC_Name .. " : D'accord, je vous suis !", 0.2, 0.9, 0.2) end)
    print("[PHNPC] Recrute : " .. tostring(md.PHNPC_Name))
end

local function followNPC(npc)
    local md = npc:getModData()
    md.PHNPC_State = "following"
    pcall(function() npc:addLineChatElement(md.PHNPC_Name .. " : Je vous suis !", 0.2, 0.9, 0.2) end)
    print("[PHNPC] Suis le joueur : " .. tostring(md.PHNPC_Name))
end

local function stayNPC(npc)
    local md = npc:getModData()
    md.PHNPC_State = "staying"
    stopMoving(npc)
    pcall(function() npc:addLineChatElement(md.PHNPC_Name .. " : Je reste ici.", 0.9, 0.9, 0.2) end)
    print("[PHNPC] Reste ici : " .. tostring(md.PHNPC_Name))
end

local function dismissNPC(npc)
    local md = npc:getModData()
    md.PHNPC_Recruited = false
    md.PHNPC_State     = "idle"
    PHNPC.recruited[npc] = nil
    stopMoving(npc)
    pcall(function() npc:addLineChatElement(md.PHNPC_Name .. " : Bonne chance.", 0.9, 0.9, 0.2) end)
    print("[PHNPC] Congedie : " .. tostring(md.PHNPC_Name))
end

local function deleteNPC(npc)
    -- CRITIQUE : mettre PHNPC_IsNPC=nil AVANT setHealth(0)
    -- Sinon OnZombieUpdate (isNPC check) ressusciterait le NPC au tick suivant
    local md   = npc:getModData()
    local name = md.PHNPC_Name or "?"
    md.PHNPC_IsNPC = nil
    -- Fermer l'inventaire si c'est ce NPC qui est ouvert
    if _openInventoryNPC == npc then _openInventoryNPC = nil end
    -- Nettoyer toutes les references (enforceNPC ne traitera plus ce NPC)
    PHNPC.allNPCs[npc]    = nil
    PHNPC.recruited[npc]  = nil
    _followTimers[npc]    = nil
    _combatTimers[npc]    = nil
    _attackCooldowns[npc] = nil
    -- Mort naturelle via setHealth(0) : PZ cree un corpse lootable avec tout l'inventaire
    -- setHealth(1) NE tuait PAS le NPC -> pas de corpse -> bug inventaire
    pcall(function()
        npc:setHealth(0)
    end)
    print("[PHNPC] Supprime : " .. name)
end

-- ============================================================
-- BARKS CONTEXTUELS (dialogue automatique selon etat)
-- Pool de phrases par etat : following, staying, defending,
-- fleeing, idle.  Utilise dans enforceNPC step 9.
-- ============================================================
PHNPC_BARKS = {
    following = {
        "Je vous couvre !",
        "Je vous suis.",
        "Allons-y.",
        "Quel endroit sinistre...",
        "Restez groupes.",
        "J'espere qu'on va trouver un abri.",
        "Vous savez ou on va ?",
    },
    staying = {
        "Je monte la garde ici.",
        "Je reste ici.",
        "Soyez prudent.",
        "Je surveille les alentours.",
        "Revenez vite.",
    },
    defending = {
        "Zombie en vue !",
        "Je m'en occupe !",
        "Restez derriere moi !",
        "Reculez, je gere !",
        "Attention !",
    },
    fleeing = {
        "Je suis trop blesse !",
        "Je dois fuir !",
        "Aidez-moi !",
        "Trop de zombies !",
    },
    idle = {
        "Y a quelqu'un ?",
        "...",
        "Dieu merci, je suis encore en vie.",
        "Il fait froid ce soir.",
    },
}

-- ============================================================
-- COMBAT NPC : chercher et attaquer les zombies proches
-- Pattern GCCombatActionsAttack.lua (NPC_Helper_Mod) simplifie
-- Appele depuis OnTick pour chaque NPC recrute
-- ============================================================
local ATTACK_VARIANTS = {"Shove", "FrontKick", "HighKick"}

local function npcCombatStep(npc)
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
    _combatTimers[npc] = (_combatTimers[npc] or 0) + 1
    if _combatTimers[npc] < (PHNPC.COMBAT_TICK_RATE or 30) then return end
    _combatTimers[npc] = 0

    -- Chercher zombie dans le rayon de combat
    local target, dist = findNearestZombie(npc, PHNPC.COMBAT_RANGE or 8)

    if not target then
        -- Plus de cible : quitter l'etat "defending" si on y etait
        if md.PHNPC_State == "defending" then
            md.PHNPC_State = md.PHNPC_PrevState or "following"
            md.PHNPC_PrevState = nil
        end
        return
    end

    -- Entrer en mode defense si pas deja dedans
    if md.PHNPC_State ~= "defending" then
        md.PHNPC_PrevState = md.PHNPC_State
        md.PHNPC_State = "defending"
        -- Bark de combat (alerte)
        pcall(function()
            local pool = PHNPC_BARKS["defending"]
            npc:addLineChatElement(pool[ZombRand(#pool) + 1], 0.9, 0.2, 0.2)
        end)
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
        startMovingTo(npc, target:getX(), target:getY(), target:getZ())
    end
end

-- ============================================================
-- FUITE NPC : fuir si HP < 30%
-- Pattern GCHelpersEscape.lua (NPC_Helper_Mod) simplifie
-- Appele depuis OnTick pour chaque NPC recrute
-- ============================================================
local function npcFlightStep(npc, player)
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
        local enemy, eDist = findNearestZombie(npc, 20)
        local nx, ny, nz   = npc:getX(), npc:getY(), npc:getZ()
        if enemy and eDist < 20 then
            local ex, ey = enemy:getX(), enemy:getY()
            local dx, dy = nx - ex, ny - ey
            local d = math.sqrt(dx * dx + dy * dy)
            if d > 0 then dx, dy = dx / d, dy / d end
            local fleeDist = PHNPC.FLEE_DISTANCE or 15
            startMovingTo(npc, nx + dx * fleeDist, ny + dy * fleeDist, nz)
        else
            -- Pas de zombie : se replier vers le joueur
            local target = player or getPlayer()
            if target then
                startMovingTo(npc, target:getX(), target:getY(), target:getZ())
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

-- ============================================================
-- DIALOGUE IMMEDIAT : bark selon etat courant
-- (option "Parler" du menu clic-droit)
-- ============================================================
local function talkNPC(npc)
    if not npc then return end
    local md    = npc:getModData()
    local state = md.PHNPC_State or "idle"
    local pool  = PHNPC_BARKS[state] or PHNPC_BARKS["idle"]
    local bark  = pool[ZombRand(#pool) + 1]
    pcall(function() npc:addLineChatElement(bark, 0.9, 0.9, 0.2) end)
end

-- ============================================================
-- CALLBACKS DEBUG (appeles via menu clic-droit en mode debug)
-- ============================================================
local function dbgForceIdle(npc)
    npc:getModData().PHNPC_State = "idle"
    stopMoving(npc)
end
local function dbgForceDefending(npc)
    npc:getModData().PHNPC_State = "defending"
end
local function dbgForceFleeing(npc)
    local md = npc:getModData()
    md.PHNPC_State  = "fleeing"
    md.PHNPC_Health = 1
end
local function dbgHPFull(npc)
    local md = npc:getModData()
    md.PHNPC_Health = md.PHNPC_MaxHealth or 100
    pcall(function() npc:addLineChatElement((md.PHNPC_Name or "?") .. " : HP restaures.", 0.2, 0.9, 0.2) end)
end
local function dbgToggleCombat(npc)
    local md = npc:getModData()
    if md.PHNPC_CombatMode == "off" then
        md.PHNPC_CombatMode = "auto"
        pcall(function() npc:addLineChatElement((md.PHNPC_Name or "?") .. " : Mode combat actif.", 0.2, 0.9, 0.2) end)
    else
        md.PHNPC_CombatMode = "off"
        pcall(function() npc:addLineChatElement((md.PHNPC_Name or "?") .. " : Mode combat desactive.", 0.9, 0.9, 0.2) end)
    end
end
local function dbgAnimShove(npc)    pcall(function() npc:setBumpType("Shove")       end) end
local function dbgAnimFrontKick(npc) pcall(function() npc:setBumpType("FrontKick")  end) end
local function dbgAnimHighKick(npc)  pcall(function() npc:setBumpType("HighKick")   end) end
local function dbgAnimWaveHi(npc)    pcall(function() npc:setBumpType("WaveHi")     end) end
local function dbgAnimShrug(npc)     pcall(function() npc:setBumpType("Shrug")      end) end
local function dbgAnimStagger(npc)   pcall(function() npc:setBumpType("StaggerBack") end) end
local function dbgAnimYes(npc)       pcall(function() npc:setBumpType("Yes")        end) end
local function dbgAnimNo(npc)        pcall(function() npc:setBumpType("No")         end) end
local function dbgDeleteAll(_)
    local toDelete = {}
    for npc, _ in pairs(PHNPC.allNPCs) do table.insert(toDelete, npc) end
    for _, npc in ipairs(toDelete) do deleteNPC(npc) end
    print("[PHNPC][DEBUG] Tous les NPCs supprimes")
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
        npc:addLineChatElement((md.PHNPC_Name or "?") .. " (" .. genre .. ") — " .. outfit, 0.9, 0.9, 0.2)
    end)
    -- Ligne 2 : stats
    pcall(function()
        npc:addLineChatElement("HP:" .. hp .. "/" .. maxHp .. "  Vit:" .. speed .. "  For:" .. str .. "  Etat:" .. state, 0.9, 0.9, 0.2)
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
        -- Options debug globales (spawn/delete all) — uniquement en mode debug PZ
        if isDebugEnabled and isDebugEnabled() then
            context:addOption("[DEBUG] Supprimer tous les NPCs", player, dbgDeleteAll)
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

        -- "Parler" : bark immediat selon etat (toujours disponible)
        subMenu:addOption("Parler",                npc, talkNPC)

        if not md.PHNPC_Recruited then
            -- NPC non recrute : recrutement
            subMenu:addOption("Rejoins-moi !",     npc, recruitNPC)
        else
            -- NPC recrute : echange d'objets + ordres
            subMenu:addOption("Echange d'objets...", npc, openNPCInventory)

            local ordreOpt = subMenu:addOption("Ordres...")
            local ordreSub = ISContextMenu:getNew(subMenu)
            subMenu:addSubMenu(ordreOpt, ordreSub)

            if md.PHNPC_State == "following" then
                ordreSub:addOption("Reste ici.",    npc, stayNPC)
            else
                ordreSub:addOption("Suis-moi !",    npc, followNPC)
            end
            ordreSub:addOption("Tu peux partir.",   npc, dismissNPC)
        end

        -- Section debug (uniquement si mode debug PZ)
        if isDebugEnabled and isDebugEnabled() then
            local dbgOpt = subMenu:addOption("[DEBUG]...")
            local dbgSub = ISContextMenu:getNew(subMenu)
            subMenu:addSubMenu(dbgOpt, dbgSub)

            -- Toggle mode combat (debug uniquement)
            local combatLabel = "Mode combat : " .. (md.PHNPC_CombatMode == "off" and "OFF" or "AUTO")
            dbgSub:addOption(combatLabel,            npc, dbgToggleCombat)
            -- Etats forces
            dbgSub:addOption("Forcer : idle",        npc, dbgForceIdle)
            dbgSub:addOption("Forcer : defending",   npc, dbgForceDefending)
            dbgSub:addOption("Forcer : fleeing",     npc, dbgForceFleeing)
            dbgSub:addOption("HP full reset",        npc, dbgHPFull)
            -- Animations de test
            dbgSub:addOption("Anim : Shove",         npc, dbgAnimShove)
            dbgSub:addOption("Anim : FrontKick",     npc, dbgAnimFrontKick)
            dbgSub:addOption("Anim : HighKick",      npc, dbgAnimHighKick)
            dbgSub:addOption("Anim : WaveHi",        npc, dbgAnimWaveHi)
            dbgSub:addOption("Anim : Shrug",         npc, dbgAnimShrug)
            dbgSub:addOption("Anim : StaggerBack",   npc, dbgAnimStagger)
            dbgSub:addOption("Anim : Yes",           npc, dbgAnimYes)
            dbgSub:addOption("Anim : No",            npc, dbgAnimNo)
        end

        subMenu:addOption("[Supprimer]",             npc, deleteNPC)
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
    -- setNoTeeth : empeche morsure pendant chargement
    -- setTarget(nil) ICI serait INCONDITIONNEL et tuerait le pathfinding (bug bumped)
    -- => gere dans enforceNPC step 6 uniquement si pas en pathfind
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
    pcall(function() enforceNPC(zombie) end)
end)

-- ============================================================
-- OnTick : IA Suivi (GCUpdateAI.runAI pattern)
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
            PHNPC.recruited[npc]  = nil
            PHNPC.allNPCs[npc]    = nil
            _followTimers[npc]    = nil
            _combatTimers[npc]    = nil
            _attackCooldowns[npc] = nil
            print("[PHNPC] Cleanup mort : " .. tostring(md and md.PHNPC_Name or "?"))
        else
            local md = npc:getModData()

            -- 1. Evaluation fuite (priorite haute : peut overrider tous les etats)
            pcall(function() npcFlightStep(npc, player) end)

            -- 2. Evaluation combat (si pas en fuite)
            pcall(function() npcCombatStep(npc) end)

            -- 3. Suivi joueur (seulement si etat "following", pas en combat/fuite)
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
                    if ZombRand(4) == 0 and PHNPC_BARKS then
                        local pool = PHNPC_BARKS["idle"]
                        pcall(function() npc:addLineChatElement(pool[ZombRand(#pool) + 1], 1.0, 1.0, 1.0) end)
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
-- OnGameStart : reinitialiser l'etat
-- ============================================================

Events.OnGameStart.Add(function()
    PHNPC.allNPCs        = {}
    PHNPC.recruited      = {}
    _followTimers        = {}
    _openInventoryNPC    = nil
    _combatTimers        = {}
    _attackCooldowns     = {}
    print("[PHNPC] Manager v0.9 pret")
end)

-- Enregistrer le menu contextuel
Events.OnPreFillWorldObjectContextMenu.Add(onFillContextMenu)

print("[PHNPC] PHNPC_Manager v0.9 loaded")
