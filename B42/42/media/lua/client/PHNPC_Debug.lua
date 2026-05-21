--[[
    PHNPC_Debug.lua  v0.0.2  (client)
    Menu de DEBUG_PHNPC pour tester tous les comportements NPC.

    Acces : clic droit -> [DEBUG_PHNPC] -> sous-menu

    Ce fichier est UNIQUEMENT pour les tests. Il ne fait pas partie
    de la logique de production.

    Necessite: PHNPC_Core.lua + PHNPC_Manager.lua charges avant ce fichier.
]]

-- ============================================================
-- HELPERS DEBUG INTERNES
-- ============================================================

-- Compte le nombre de NPCs actifs (pairs() sur table)
local function countNPCs()
    local n = 0
    if PHNPC and PHNPC.allNPCs then
        for _ in pairs(PHNPC.allNPCs) do n = n + 1 end
    end
    return n
end

local function countRecruited()
    local n = 0
    if PHNPC and PHNPC.recruited then
        for _ in pairs(PHNPC.recruited) do n = n + 1 end
    end
    return n
end

-- Cherche le NPC le plus proche du joueur (rayon illimite)
local function findNearestNPC(player)
    if not PHNPC or not PHNPC.allNPCs then return nil end
    local best, bestDist = nil, math.huge
    local px, py = player:getX(), player:getY()
    for npc in pairs(PHNPC.allNPCs) do
        local alive = false
        pcall(function() alive = not npc:isDead() end)
        if alive then
            local dx = npc:getX() - px
            local dy = npc:getY() - py
            local d  = math.sqrt(dx*dx + dy*dy)
            if d < bestDist then bestDist = d ; best = npc end
        end
    end
    return best, bestDist
end

-- ============================================================
-- ACTIONS DEBUG
-- ============================================================

-- Affiche l'etat complet du NPC le plus proche dans la console
local function dbgShowState(_, player)
    local npc, dist = findNearestNPC(player)
    if not npc then
        print("[DEBUG_PHNPC] Aucun NPC trouve")
        return
    end
    local md = npc:getModData()
    local asn = "?"
    pcall(function() asn = npc:getActionStateName() end)

    print("[DEBUG_PHNPC] === ETAT NPC ===")
    print("  Nom      : " .. tostring(md.PHNPC_Name))
    print("  Genre    : " .. (md.PHNPC_Female and "F" or "M"))
    print("  Outfit   : " .. tostring(md.PHNPC_Outfit))
    print("  Distance : " .. string.format("%.1f", dist) .. " tiles")
    print("  State    : " .. tostring(md.PHNPC_State))
    print("  Recruited: " .. tostring(md.PHNPC_Recruited))
    print("  Moving   : " .. tostring(md.PHNPC_Moving))
    print("  HitTicks : " .. tostring(md.PHNPC_HitTicks))
    print("  ShowTimer: " .. tostring(md.PHNPC_ShowTimer))
    print("  PZ State : " .. asn)
    print("  isUseless: " .. tostring(npc:isUseless()))
    print("  isDead   : " .. tostring(npc:isDead()))
    print("  Health   : " .. tostring(npc:getHealth()))
    print("  Pos      : " .. npc:getX() .. "," .. npc:getY() .. "," .. npc:getZ())

    -- Variables AnimSet
    local isNPC, walkType = "?", "?"
    pcall(function() isNPC    = tostring(npc:getVariable("PHNPC_IsNPC")) end)
    pcall(function() walkType = tostring(npc:getVariable("zombieWalkType")) end)
    print("  PHNPC_IsNPC     : " .. isNPC)
    print("  zombieWalkType  : " .. walkType)
    print("[DEBUG_PHNPC] ================")
end

-- Liste tous les NPCs actifs dans la console
local function dbgListAll(_, _)
    local total    = countNPCs()
    local recruited = countRecruited()
    print("[DEBUG_PHNPC] === LISTE NPCs (" .. total .. " total, " .. recruited .. " recrutes) ===")
    if not PHNPC or not PHNPC.allNPCs then
        print("  (PHNPC.allNPCs vide)")
        return
    end
    local i = 0
    for npc in pairs(PHNPC.allNPCs) do
        i = i + 1
        local md = npc:getModData()
        local alive = "?"
        pcall(function() alive = not npc:isDead() and "vivant" or "mort" end)
        local rec = PHNPC.recruited[npc] and "[recrute]" or ""
        print(string.format("  %d. %-12s %s  state=%-10s %s",
            i, tostring(md.PHNPC_Name),
            (md.PHNPC_Female and "F" or "M"),
            tostring(md.PHNPC_State),
            rec))
    end
    print("[DEBUG_PHNPC] ==================")
end

-- Teleporte le NPC le plus proche sur la case du joueur
local function dbgTeleportToPlayer(_, player)
    local npc = findNearestNPC(player)
    if not npc then
        print("[DEBUG_PHNPC] Aucun NPC trouve")
        return
    end
    local md = npc:getModData()
    pcall(function()
        npc:setX(player:getX())
        npc:setY(player:getY())
        npc:setZ(player:getZ())
    end)
    print("[DEBUG_PHNPC] " .. tostring(md.PHNPC_Name) .. " teleporte au joueur")
end

-- Force l'animation Shrug sur le NPC le plus proche
local function dbgAnim(_, player, bumpType)
    local npc = findNearestNPC(player)
    if not npc then
        print("[DEBUG_PHNPC] Aucun NPC trouve") ; return
    end
    local md = npc:getModData()
    pcall(function() npc:setBumpType(bumpType) end)
    print("[DEBUG_PHNPC] " .. tostring(md.PHNPC_Name) .. " -> BumpType=" .. bumpType)
end

-- Wrapper pour les animations (closure avec bumpType)
local function dbgAnimWave(_, player)    dbgAnim(_, player, "WaveHi") end
local function dbgAnimShrug(_, player)   dbgAnim(_, player, "Shrug") end
local function dbgAnimYes(_, player)     dbgAnim(_, player, "Yes") end
local function dbgAnimNo(_, player)      dbgAnim(_, player, "No") end
local function dbgAnimPainH(_, player)   dbgAnim(_, player, "PainHead") end
local function dbgAnimPainT(_, player)   dbgAnim(_, player, "PainTorso") end
local function dbgAnimPushBk(_, player)  dbgAnim(_, player, "NPCPushedBack") end
local function dbgAnimShove(_, player)   dbgAnim(_, player, "Shove") end
local function dbgAnimKick(_, player)    dbgAnim(_, player, "FrontKick") end

-- Force l'etat hitreaction sur le NPC le plus proche (simule un coup)
local function dbgForceHitReaction(_, player)
    local npc = findNearestNPC(player)
    if not npc then
        print("[DEBUG_PHNPC] Aucun NPC trouve") ; return
    end
    local md = npc:getModData()
    md.PHNPC_HitTicks = 0
    pcall(function()
        npc:setUseless(false)
        npc:changeState(ZombieHitReactionState.instance())
    end)
    print("[DEBUG_PHNPC] " .. tostring(md.PHNPC_Name) .. " -> hitreaction forcee")
end

-- Force l'etat idle sur le NPC le plus proche
local function dbgForceIdle(_, player)
    local npc = findNearestNPC(player)
    if not npc then return end
    local md = npc:getModData()
    pcall(function()
        npc:changeState(ZombieIdleState.instance())
        npc:setBumpType("Shrug")
    end)
    md.PHNPC_Moving  = false
    md.PHNPC_HitTicks = 0
    print("[DEBUG_PHNPC] " .. tostring(md.PHNPC_Name) .. " -> idle force")
end

-- Force le suivi du joueur sur le NPC le plus proche
local function dbgForceFollow(_, player)
    local npc = findNearestNPC(player)
    if not npc then return end
    local md = npc:getModData()
    md.PHNPC_Recruited = true
    md.PHNPC_State     = "following"
    PHNPC.recruited[npc] = true
    pcall(function() npc:setUseless(false) end)
    print("[DEBUG_PHNPC] " .. tostring(md.PHNPC_Name) .. " -> follow force")
end

-- Force le mode stay sur le NPC le plus proche
local function dbgForceStay(_, player)
    local npc = findNearestNPC(player)
    if not npc then return end
    local md = npc:getModData()
    md.PHNPC_Recruited = true
    md.PHNPC_State     = "staying"
    PHNPC.recruited[npc] = true
    print("[DEBUG_PHNPC] " .. tostring(md.PHNPC_Name) .. " -> stay force")
end

-- Reset complet ShowTimer sur le NPC le plus proche
local function dbgResetShowTimer(_, player)
    local npc = findNearestNPC(player)
    if not npc then return end
    local md = npc:getModData()
    md.PHNPC_ShowTimer = 5
    print("[DEBUG_PHNPC] " .. tostring(md.PHNPC_Name) .. " -> ShowTimer reset a 5")
end

-- Spawn un NPC de test sur la case du joueur
local function dbgSpawnAtPlayer(_, player)
    local sq = player:getCurrentSquare()
    if not sq then
        print("[DEBUG_PHNPC] Impossible d'obtenir la case du joueur")
        return
    end
    -- PHNPC_Manager expose spawnNPC comme fonction dans PHNPC_Core ou via Events
    -- On reuse le pattern direct
    local x = player:getX()
    local y = player:getY()
    local z = player:getZ()
    local isFemale     = (ZombRand(2) == 0)
    local femaleChance = isFemale and 100 or 0
    local outfit       = PHNPC.OUTFITS[ZombRand(#PHNPC.OUTFITS) + 1]
    local npcName      = PHNPC.getRandomName(isFemale)

    print("[DEBUG_PHNPC] Spawn test : " .. npcName .. " (" .. outfit .. ")")
    local ok, err = pcall(function()
        local zlist = addZombiesInOutfit(x, y, z, 1, outfit, femaleChance)
        if zlist and zlist:size() > 0 then
            local zombie = zlist:get(0)
            if zombie then
                -- Convertir via Events (PHNPC_Manager doit exporter convertToNPC)
                -- Si non accessible, utiliser la version inline minimaliste
                local md = zombie:getModData()
                pcall(function() zombie:setNoTeeth(true) end)
                pcall(function() zombie:setVariable("PHNPC_IsNPC", true) end)
                pcall(function() zombie:setWalkType("Walk") end)
                pcall(function() zombie:setVariable("zombieWalkType", "Walk") end)
                pcall(function() zombie:setVariable("ZombieHitReaction", "Chainsaw") end)
                pcall(function() zombie:setVariable("NoLungeTarget", true) end)
                pcall(function() zombie:getEmitter():stopAll() end)
                pcall(function() zombie:setTurnAlertedValues(-5, 5) end)
                pcall(function() zombie:getDescriptor():setVoicePrefix("PHNPC") end)
                pcall(function() zombie:setDressInRandomOutfit(false) end)
                pcall(function() zombie:setBumpType("Shrug") end)
                md.PHNPC_IsNPC     = true
                md.PHNPC_Recruited = false
                md.PHNPC_State     = "idle"
                md.PHNPC_Name      = npcName
                md.PHNPC_Female    = isFemale
                md.PHNPC_Outfit    = outfit
                md.PHNPC_Moving    = false
                md.PHNPC_HitTicks  = 0
                md.PHNPC_ShowTimer = 5
                PHNPC.allNPCs[zombie] = true
                print("[DEBUG_PHNPC] Spawn OK : " .. npcName)
            end
        end
    end)
    if not ok then
        print("[DEBUG_PHNPC] Spawn ERREUR : " .. tostring(err))
    end
end

-- Supprime TOUS les NPCs
local function dbgKillAll(_, _)
    local count = countNPCs()
    if count == 0 then
        print("[DEBUG_PHNPC] Aucun NPC a supprimer")
        return
    end
    local removed = 0
    for npc in pairs(PHNPC.allNPCs) do
        pcall(function() npc:removeFromWorld() end)
        removed = removed + 1
    end
    PHNPC.allNPCs   = {}
    PHNPC.recruited = {}
    print("[DEBUG_PHNPC] " .. removed .. " NPC(s) supprimes")
end

-- Affiche les statistiques globales du systeme
local function dbgStats(_, player)
    print("[DEBUG_PHNPC] === STATS SYSTEME ===")
    print("  allNPCs   : " .. countNPCs())
    print("  recruited : " .. countRecruited())
    print("  PHNPC existe : " .. tostring(PHNPC ~= nil))
    if PHNPC then
        print("  FOLLOW_DISTANCE  : " .. tostring(PHNPC.FOLLOW_DISTANCE))
        print("  FOLLOW_TICK_RATE : " .. tostring(PHNPC.FOLLOW_TICK_RATE))
        print("  INTERACTION_DIST : " .. tostring(PHNPC.INTERACTION_DIST))
    end
    if player then
        local nearNPC, dist = findNearestNPC(player)
        if nearNPC then
            local md = nearNPC:getModData()
            print("  NPC le plus proche : " .. tostring(md.PHNPC_Name) ..
                  " (" .. string.format("%.1f", dist) .. " tiles)")
        else
            print("  NPC le plus proche : aucun")
        end
    end
    print("[DEBUG_PHNPC] ====================")
end

-- ============================================================
-- MENU CONTEXTUEL DEBUG
-- ============================================================

local function onFillDebugContextMenu(playerIndex, context, worldObjects, test)
    if test then return end

    local player = getSpecificPlayer(playerIndex)
    if not player then return end

    -- Toujours afficher le menu debug (independamment de PHNPC)
    local debugOpt = context:addOption("[DEBUG_PHNPC]")
    local sub      = ISContextMenu:getNew(context)
    context:addSubMenu(debugOpt, sub)

    -- Sous-menu : Spawn
    sub:addOption("Spawn NPC ici",          player, dbgSpawnAtPlayer)

    sub:addOption("---")

    -- Sous-menu : Info
    sub:addOption("Afficher etat NPC proche", player, dbgShowState)
    sub:addOption("Lister tous les NPCs",     player, dbgListAll)
    sub:addOption("Stats systeme",            player, dbgStats)

    sub:addOption("---")

    -- Sous-menu : Controle
    sub:addOption("Forcer FOLLOW (NPC proche)", player, dbgForceFollow)
    sub:addOption("Forcer STAY  (NPC proche)",  player, dbgForceStay)
    sub:addOption("Forcer IDLE  (NPC proche)",  player, dbgForceIdle)
    sub:addOption("Teleporter NPC au joueur",   player, dbgTeleportToPlayer)
    sub:addOption("Reset ShowTimer (NPC proche)", player, dbgResetShowTimer)

    sub:addOption("---")

    -- Sous-menu : Tests d'animation
    local animOpt = sub:addOption("Tester animations...")
    local animSub = ISContextMenu:getNew(sub)
    sub:addSubMenu(animOpt, animSub)

    animSub:addOption("WaveHi (salut)",         player, dbgAnimWave)
    animSub:addOption("Shrug (hausser epaules)", player, dbgAnimShrug)
    animSub:addOption("Yes (acquiescer)",         player, dbgAnimYes)
    animSub:addOption("No (refuser)",             player, dbgAnimNo)
    animSub:addOption("PainHead (coup tete)",     player, dbgAnimPainH)
    animSub:addOption("PainTorso (coup torse)",   player, dbgAnimPainT)
    animSub:addOption("NPCPushedBack (recule)",   player, dbgAnimPushBk)
    animSub:addOption("Shove (pousser)",          player, dbgAnimShove)
    animSub:addOption("FrontKick (coup pied)",    player, dbgAnimKick)
    animSub:addOption("ForceHitReaction",         player, dbgForceHitReaction)

    sub:addOption("---")

    -- Danger zone
    sub:addOption("[!] Supprimer TOUS les NPCs", player, dbgKillAll)
end

-- ============================================================
-- EVENTS
-- ============================================================

Events.OnPreFillWorldObjectContextMenu.Add(onFillDebugContextMenu)

print("[PHNPC] PHNPC_Debug v0.0.2 loaded")
