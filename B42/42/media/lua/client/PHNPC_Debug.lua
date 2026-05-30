--[[
    PHNPC_Debug.lua  v0.0.6  (client)
    Menu de DEBUG_PHNPC pour tester tous les comportements NPC.

    Acces : clic droit -> [DEBUG_PHNPC] -> sous-menu categorie

    Sous-menus :
      - "Spawn / Gestion"  : spawn, forcer etats, teleport, reset, supprimer
      - "Infos NPC"        : afficher etat, lister NPCs, stats systeme
      - "Animations"       : tester toutes les animations via setBumpType

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
    print("  Health PZ: " .. health)
    -- Sante PHNPC (notre systeme)
    local phnpcHp    = md.PHNPC_Health    or "?"
    local phnpcMaxHp = md.PHNPC_MaxHealth or "?"
    print("  Health   : " .. tostring(phnpcHp) .. " / " .. tostring(phnpcMaxHp))
    print("  SpeedMod : " .. tostring(md.PHNPC_SpeedMod or "?"))
    print("  Strength : " .. tostring(md.PHNPC_Strength or "?"))
    if PHNPC.getOutfitDefenseSummary then
        local ds = ""
        pcall(function() ds = PHNPC.getOutfitDefenseSummary(npc) end)
        if ds and ds ~= "" then
            print("  OutfitDef: " .. ds)
        end
    end
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
-- Pour les animations a priorite elevee (FrontKick, Shove) :
--   setUseless(false) + changeState(ZombieIdleState) requis avant setBumpType
--   sinon l'animation est ignoree si le NPC est freeze (useless=true)
local function dbgAnim(player, bumpType)
    local npc = findNearestNPC(player)
    if not npc then print("[DEBUG_PHNPC] Aucun NPC") ; return end
    local md = npc:getModData()
    pcall(function()
        npc:setUseless(false)                          -- debloquer AI avant bump (Bandits pattern)
        npc:changeState(ZombieIdleState.instance())   -- etat propre => bumped transition fiable
        npc:setBumpType(bumpType)
    end)
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
local function dbgAnimHighKick(player) dbgAnim(player, "HighKick") end

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
    local cell = player:getCell()
    if not cell then return end
    local sq = cell:getGridSquare(
        math.floor(player:getX()),
        math.floor(player:getY()),
        player:getZ()
    )
    if sq then
        PHNPC.spawnNPC(sq)
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

    -- ── Spawn / Gestion ──────────────────────────────────────────────
    local spawnOpt = sub:addOption("Spawn / Gestion...")
    local spawnSub = ISContextMenu:getNew(sub)
    sub:addSubMenu(spawnOpt, spawnSub)

    spawnSub:addOption("Spawn NPC ici",                player, dbgSpawnAtPlayer)
    spawnSub:addOption("Forcer FOLLOW (NPC proche)",   player, dbgForceFollow)
    spawnSub:addOption("Forcer STAY   (NPC proche)",   player, dbgForceStay)
    spawnSub:addOption("Forcer IDLE   (NPC proche)",   player, dbgForceIdle)
    spawnSub:addOption("Teleporter NPC au joueur",     player, dbgTeleportToPlayer)
    spawnSub:addOption("Reset ShowTimer (NPC proche)", player, dbgResetShowTimer)
    spawnSub:addOption("[!] Supprimer TOUS les NPCs",  player, dbgKillAll)

    -- ── Infos NPC ───────────────────────────────────────────────────
    local infoOpt = sub:addOption("Infos NPC...")
    local infoSub = ISContextMenu:getNew(sub)
    sub:addSubMenu(infoOpt, infoSub)

    infoSub:addOption("Afficher etat NPC proche",  player, dbgShowState)
    infoSub:addOption("Lister tous les NPCs",       player, dbgListAll)
    infoSub:addOption("Stats systeme PHNPC",        player, dbgStats)

    -- ── Animations ──────────────────────────────────────────────────
    local animOpt = sub:addOption("Animations...")
    local animSub = ISContextMenu:getNew(sub)
    sub:addSubMenu(animOpt, animSub)

    animSub:addOption("WaveHi  (salut main)",            player, dbgAnimWave)
    animSub:addOption("Shrug   (hausser epaules)",        player, dbgAnimShrug)
    animSub:addOption("Yes     (acquiescer)",             player, dbgAnimYes)
    animSub:addOption("No      (refuser)",                player, dbgAnimNo)
    animSub:addOption("PainHead  (douleur tete)",         player, dbgAnimPainH)
    animSub:addOption("PainTorso (douleur thorax)",       player, dbgAnimPainT)
    animSub:addOption("ZombiePushedBack (reculer)",       player, dbgAnimPushBk)
    animSub:addOption("Shove     (pousser)",              player, dbgAnimShove)
    animSub:addOption("FrontKick (coup pied avant)",      player, dbgAnimKick)
    animSub:addOption("HighKick  (coup pied haut)",       player, dbgAnimHighKick)
    animSub:addOption("ForceHitReaction (PainHead sim.)", player, dbgForceHitReaction)
end

-- ============================================================
-- EVENTS
-- ============================================================

Events.OnPreFillWorldObjectContextMenu.Add(onFillDebugContextMenu)

print("[PHNPC] Debug v0.0.18 loaded")