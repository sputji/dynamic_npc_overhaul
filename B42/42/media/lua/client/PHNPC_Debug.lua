--[[
    PHNPC_Debug.lua  v0.0.4  (client)
    Menu de DEBUG_PHNPC pour tester tous les comportements NPC.

    Acces : clic droit -> [DEBUG_PHNPC] -> sous-menu

    IMPORTANT - Signature callbacks ISContextMenu:
        addOption(texte, target, onselect)  =>  onselect(target)
        Le PREMIER argument est "target", PAS un contexte.
        Toutes les fonctions ont donc la signature (player) et non (_, player).

    Necessite: PHNPC_Core.lua + PHNPC_Manager.lua charges avant ce fichier.
]]

-- ============================================================
-- HELPERS DEBUG INTERNES
-- ============================================================

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

-- Cherche le NPC le plus proche du joueur
local function findNearestNPC(player)
    if not PHNPC or not PHNPC.allNPCs then return nil end
    if not player then return nil end
    local best, bestDist = nil, math.huge
    local px, py
    pcall(function() px = player:getX() ; py = player:getY() end)
    if not px then return nil end

    for npc in pairs(PHNPC.allNPCs) do
        local alive = false
        pcall(function() alive = not npc:isDead() end)
        if alive then
            local dx, dy
            pcall(function()
                dx = npc:getX() - px
                dy = npc:getY() - py
            end)
            if dx then
                local d = math.sqrt(dx*dx + dy*dy)
                if d < bestDist then bestDist = d ; best = npc end
            end
        end
    end
    return best, bestDist
end

-- ============================================================
-- ACTIONS DEBUG
-- ============================================================

local function dbgShowState(player)
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
    print("  Distance : " .. string.format("%.1f", dist or 0) .. " tiles")
    print("  State    : " .. tostring(md.PHNPC_State))
    print("  Recruited: " .. tostring(md.PHNPC_Recruited))
    print("  Moving   : " .. tostring(md.PHNPC_Moving))
    print("  HitTicks : " .. tostring(md.PHNPC_HitTicks))
    print("  ShowTimer: " .. tostring(md.PHNPC_ShowTimer))
    print("  PZ State : " .. asn)
    local isUseless = "?"
    pcall(function() isUseless = tostring(npc:isUseless()) end)
    print("  isUseless: " .. isUseless)
    local health = "?"
    pcall(function() health = tostring(npc:getHealth()) end)
    print("  Health   : " .. health)
    local nx, ny, nz = "?", "?", "?"
    pcall(function() nx = npc:getX() ; ny = npc:getY() ; nz = npc:getZ() end)
    print("  Pos      : " .. tostring(nx) .. "," .. tostring(ny) .. "," .. tostring(nz))
    local isNPCVar = "?"
    pcall(function() isNPCVar = tostring(npc:getVariable("PHNPC_IsNPC")) end)
    print("  PHNPC_IsNPC (AnimVar) : " .. isNPCVar)
    print("[DEBUG_PHNPC] ================")
end

local function dbgListAll(player)
    local total     = countNPCs()
    local recruited = countRecruited()
    print("[DEBUG_PHNPC] === LISTE NPCs (" .. total .. " total, " .. recruited .. " recrutes) ===")
    if not PHNPC or not PHNPC.allNPCs then
        print("  (PHNPC.allNPCs vide)") ; return
    end
    local i = 0
    for npc in pairs(PHNPC.allNPCs) do
        i = i + 1
        local md = npc:getModData()
        local rec = PHNPC.recruited[npc] and "[recrute]" or ""
        print(string.format("  %d. %-12s %s  state=%-10s %s",
            i, tostring(md.PHNPC_Name),
            (md.PHNPC_Female and "F" or "M"),
            tostring(md.PHNPC_State), rec))
    end
    print("[DEBUG_PHNPC] ==================")
end

local function dbgTeleportToPlayer(player)
    local npc = findNearestNPC(player)
    if not npc then print("[DEBUG_PHNPC] Aucun NPC") ; return end
    local md = npc:getModData()
    pcall(function()
        npc:setX(player:getX()) ; npc:setY(player:getY()) ; npc:setZ(player:getZ())
    end)
    print("[DEBUG_PHNPC] " .. tostring(md.PHNPC_Name) .. " teleporte au joueur")
end

-- Base animation via setBumpType
local function dbgAnim(player, bumpType)
    local npc = findNearestNPC(player)
    if not npc then print("[DEBUG_PHNPC] Aucun NPC") ; return end
    local md = npc:getModData()
    pcall(function() npc:setBumpType(bumpType) end)
    print("[DEBUG_PHNPC] " .. tostring(md.PHNPC_Name) .. " -> BumpType=" .. bumpType)
end

-- Wrappers 1 argument (signature callback correcte)
local function dbgAnimWave(player)    dbgAnim(player, "WaveHi") end
local function dbgAnimShrug(player)   dbgAnim(player, "Shrug") end
local function dbgAnimYes(player)     dbgAnim(player, "Yes") end
local function dbgAnimNo(player)      dbgAnim(player, "No") end
local function dbgAnimPainH(player)   dbgAnim(player, "PainHead") end
local function dbgAnimPainT(player)   dbgAnim(player, "PainTorso") end
local function dbgAnimPushBk(player)  dbgAnim(player, "ZombiePushedBack") end
local function dbgAnimShove(player)   dbgAnim(player, "Shove") end
local function dbgAnimKick(player)    dbgAnim(player, "FrontKick") end

local function dbgForceHitReaction(player)
    local npc = findNearestNPC(player)
    if not npc then return end
    local md = npc:getModData()
    md.PHNPC_HitTicks = 0
    -- ZombieHitReactionState n'existe pas en Lua B42 => crash
    -- Simuler une hit reaction via setBumpType PainHead (bumped state)
    pcall(function()
        npc:setUseless(false)
        npc:setBumpType("PainHead")
    end)
    print("[DEBUG_PHNPC] " .. tostring(md.PHNPC_Name) .. " -> hitreaction simulee (PainHead)")
end

local function dbgForceIdle(player)
    local npc = findNearestNPC(player)
    if not npc then return end
    local md = npc:getModData()
    pcall(function()
        npc:changeState(ZombieIdleState.instance())
        npc:setBumpType("Shrug")
    end)
    md.PHNPC_Moving   = false
    md.PHNPC_HitTicks = 0
    print("[DEBUG_PHNPC] " .. tostring(md.PHNPC_Name) .. " -> idle force")
end

local function dbgForceFollow(player)
    local npc = findNearestNPC(player)
    if not npc then return end
    local md = npc:getModData()
    md.PHNPC_Recruited = true
    md.PHNPC_State     = "following"
    PHNPC.recruited[npc] = true
    pcall(function() npc:setUseless(false) end)
    print("[DEBUG_PHNPC] " .. tostring(md.PHNPC_Name) .. " -> follow force")
end

local function dbgForceStay(player)
    local npc = findNearestNPC(player)
    if not npc then return end
    local md = npc:getModData()
    md.PHNPC_Recruited = true
    md.PHNPC_State     = "staying"
    PHNPC.recruited[npc] = true
    print("[DEBUG_PHNPC] " .. tostring(md.PHNPC_Name) .. " -> stay force")
end

local function dbgResetShowTimer(player)
    local npc = findNearestNPC(player)
    if not npc then return end
    local md = npc:getModData()
    md.PHNPC_ShowTimer = 5
    print("[DEBUG_PHNPC] " .. tostring(md.PHNPC_Name) .. " -> ShowTimer reset a 5")
end

local function dbgSpawnAtPlayer(player)
    if not player then return end
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
                local md = zombie:getModData()
                pcall(function() zombie:setNoTeeth(true) end)
                pcall(function() zombie:setVariable("PHNPC_IsNPC", true) end)
                pcall(function() zombie:setVariable("NoLungeTarget", true) end)
                pcall(function() zombie:setVariable("ZombieHitReaction", "Chainsaw") end)
                pcall(function() zombie:setVariable("LimpSpeed", 0.80) end)
                pcall(function() zombie:setVariable("RunSpeed",  0.75) end)
                pcall(function() zombie:setVariable("WalkSpeed", 1.04) end)
                -- setWalkType fixe zombieWalkType en interne (PAS setVariable)
                pcall(function() zombie:setWalkType("Walk") end)
                -- Genre : Bob (male) ou Kate (female)
                pcall(function() zombie:setFemaleEtc(isFemale) end)
                pcall(function() zombie:setDressInRandomOutfit(false) end)
                pcall(function() zombie:getEmitter():stopAll() end)
                pcall(function() zombie:setTurnAlertedValues(-5, 5) end)
                pcall(function() zombie:getDescriptor():setVoicePrefix(isFemale and "FemaleZombie" or "MaleZombie") end)
                pcall(function() zombie:setPrimaryHandItem(nil) end)
                pcall(function() zombie:setSecondaryHandItem(nil) end)
                pcall(function() zombie:resetEquippedHandsModels() end)
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

local function dbgKillAll(player)
    local count = countNPCs()
    if count == 0 then print("[DEBUG_PHNPC] Aucun NPC") ; return end
    local removed = 0
    for npc in pairs(PHNPC.allNPCs) do
        pcall(function() npc:removeFromWorld() end)
        removed = removed + 1
    end
    PHNPC.allNPCs   = {}
    PHNPC.recruited = {}
    print("[DEBUG_PHNPC] " .. removed .. " NPC(s) supprimes")
end

local function dbgStats(player)
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
                  " (" .. string.format("%.1f", dist or 0) .. " tiles)")
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

    local debugOpt = context:addOption("[DEBUG_PHNPC]")
    local sub      = ISContextMenu:getNew(context)
    context:addSubMenu(debugOpt, sub)

    sub:addOption("Spawn NPC ici",               player, dbgSpawnAtPlayer)
    sub:addOption("---")
    sub:addOption("Afficher etat NPC proche",    player, dbgShowState)
    sub:addOption("Lister tous les NPCs",         player, dbgListAll)
    sub:addOption("Stats systeme",                player, dbgStats)
    sub:addOption("---")
    sub:addOption("Forcer FOLLOW (NPC proche)",  player, dbgForceFollow)
    sub:addOption("Forcer STAY  (NPC proche)",   player, dbgForceStay)
    sub:addOption("Forcer IDLE  (NPC proche)",   player, dbgForceIdle)
    sub:addOption("Teleporter NPC au joueur",    player, dbgTeleportToPlayer)
    sub:addOption("Reset ShowTimer (NPC proche)",player, dbgResetShowTimer)
    sub:addOption("---")

    local animOpt = sub:addOption("Tester animations...")
    local animSub = ISContextMenu:getNew(sub)
    sub:addSubMenu(animOpt, animSub)
    animSub:addOption("WaveHi (salut)",           player, dbgAnimWave)
    animSub:addOption("Shrug (hausser epaules)",   player, dbgAnimShrug)
    animSub:addOption("Yes (acquiescer)",           player, dbgAnimYes)
    animSub:addOption("No (refuser)",               player, dbgAnimNo)
    animSub:addOption("PainHead (douleur tete)",        player, dbgAnimPainH)
    animSub:addOption("PainTorso (douleur thoracique)",  player, dbgAnimPainT)
    animSub:addOption("ZombiePushedBack (reculer)",      player, dbgAnimPushBk)
    animSub:addOption("Shove (pousser)",            player, dbgAnimShove)
    animSub:addOption("FrontKick (coup pied)",      player, dbgAnimKick)
    animSub:addOption("ForceHitReaction",           player, dbgForceHitReaction)

    sub:addOption("---")
    sub:addOption("[!] Supprimer TOUS les NPCs",  player, dbgKillAll)
end

-- ============================================================
-- EVENTS
-- ============================================================

Events.OnPreFillWorldObjectContextMenu.Add(onFillDebugContextMenu)

print("[PHNPC] PHNPC_Debug v0.0.4 loaded")