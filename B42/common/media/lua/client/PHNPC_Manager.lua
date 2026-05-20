-- Project Humain: Dynamic NPC Overhaul - B42
-- client/PHNPC_Manager.lua  v2.0
-- Spawn / Mouvement / IA de base / Ordres / Inventaire / Combat / Peur zombies
-- Necessite: PHNPC_Core.lua (shared), PHNPC_Stats.lua (shared)
-- NO BOM. ASCII only.

-- ============================================================
-- CONFIG
-- ============================================================
local STOP_DIST       = 3    -- tiles: arreter le suivi
local RETARGET        = 15   -- ticks entre deux pathToLocationF
local CLEANUP         = 300  -- ticks entre deux passes de nettoyage
local MAX_NPCS        = 10   -- nombre max de NPC simultanes
local FEAR_CHECK_RATE = 30   -- ticks entre deux checks de peur
local COMBAT_RANGE    = 5    -- tiles: distance pour engager le combat

local OUTFITS = {
    "Farmer", "Police", "Fireman", "Doctor",
    "Ranger", "Chef", "Survivor",
}

-- ============================================================
-- STATE
-- PHNPC.npcs[IsoZombie] = {
--   id, name, isFemale, outfit, stats,
--   followMode, attackMode, fleeMode,
--   retarget, moving, bumpTicks, fearTicks,
--   target
-- }
-- ============================================================
local _ticks = 0

-- ============================================================
-- NPC VALIDITY
-- ============================================================
local function npcValid(npc)
    if not npc then return false end
    local ok, dead = pcall(function() return npc:isDead() end)
    return ok and not dead
end

-- ============================================================
-- MOUVEMENT
-- ============================================================
local function npcStartMoving(npc, x, y, z)
    local data = PHNPC.npcs[npc]
    pcall(function()
        npc:setUseless(false)
        npc:setVariable("PHNPC_IsNPC", true)
        npc:setVariable("zombieWalkType", "Walk")
        npc:setWalkType("Walk")
        npc:setSpeedMod(1.0)
        if data and not data.moving then
            data.moving = true
            npc:setBumpType("IdleToWalk")
        end
        npc:pathToLocationF(x, y, z)
    end)
end

local function npcStopMoving(npc)
    local data = PHNPC.npcs[npc]
    pcall(function()
        if data and data.moving then
            data.moving = false
            npc:setBumpType("WalkToIdle")
        end
    end)
end

-- ============================================================
-- CREATION NPC
-- ============================================================
local function createNPC(square)
    local x = square:getX()
    local y = square:getY()
    local z = square:getZ()

    local isFemale     = (ZombRand(2) == 1)
    local femaleChance = isFemale and 100 or 0
    local outfit       = OUTFITS[ZombRand(#OUTFITS) + 1]
    local npcName      = PHNPC.generateName(isFemale)
    local npcId        = "PHNPC_" .. npcName .. "_" .. tostring(getTimestampMs())
    local stats        = PHNPC.generateStats(outfit)

    -- 1. Spawn via addZombiesInOutfit
    local zombieList = nil
    local ok1, err1 = pcall(function()
        zombieList = addZombiesInOutfit(x, y, z, 1, outfit, femaleChance)
    end)
    if not ok1 then
        print("[PHNPC] ERREUR addZombiesInOutfit: " .. tostring(err1))
        return
    end
    if not zombieList or zombieList:size() == 0 then
        print("[PHNPC] addZombiesInOutfit: liste vide")
        return
    end

    local npc = zombieList:get(0)
    if not npc then
        print("[PHNPC] zombie nil apres addZombiesInOutfit")
        return
    end

    -- 2. Banditize: transformer zombie en NPC humain
    pcall(function()
        npc:setNoTeeth(true)
        npc:setVariable("PHNPC_IsNPC", true)
        npc:setWalkType("Walk")
        npc:setVariable("zombieWalkType", "Walk")
        npc:setVariable("ZombieHitReaction", "Chainsaw")
        npc:setVariable("NoLungeTarget", true)
        npc:setVariable("LimpSpeed", 0.80)
        npc:setVariable("WalkSpeed", 1.04)
        npc:setVariable("RunSpeed", 1.10)
        npc:setSpeedMod(1.0)
        npc:getEmitter():stopAll()
        npc:setPrimaryHandItem(nil)
        npc:setSecondaryHandItem(nil)
        npc:resetEquippedHandsModels()
        npc:clearAttachedItems()
        npc:setDressInRandomOutfit(false)
        npc:setTurnAlertedValues(-5, 5)
        npc:setBumpType("Shrug")
        local descNPC = npc:getDescriptor()
        if descNPC then descNPC:setVoicePrefix("NotAZombie") end
        npc:setTarget(nil)
        npc:clearAggroList()
        npc:setHealth(10000)
    end)

    -- 3. Visuels propres
    pcall(function()
        local hv = npc:getHumanVisual()
        if hv then hv:removeDirt() ; hv:removeBlood() end
    end)

    -- 4. ModData
    local md = npc:getModData()
    md.PHNPC_ID     = npcId
    md.PHNPC_Name   = npcName
    md.PHNPC_Female = isFemale
    md.PHNPC_Outfit = outfit
    md.PHNPC_Stats  = stats

    -- 5. Enregistrer dans PHNPC.npcs
    PHNPC.npcs[npc] = {
        id         = npcId,
        name       = npcName,
        isFemale   = isFemale,
        outfit     = outfit,
        stats      = stats,
        followMode = true,
        attackMode = false,
        fleeMode   = false,
        retarget   = 0,
        moving     = false,
        bumpTicks  = 0,
        fearTicks  = 0,
        target     = nil,
    }

    print("[PHNPC] NPC spawne: " .. npcName
        .. " (" .. (isFemale and "F" or "M") .. ")"
        .. " outfit=" .. outfit
        .. " courage=" .. stats.courage
        .. " @ " .. x .. "," .. y)
end

-- ============================================================
-- ORDRES
-- ============================================================
local function startFollow(npc)
    local d = PHNPC.npcs[npc]
    if not d then return end
    d.followMode = true
    d.fleeMode   = false
    d.retarget   = 0
    print("[PHNPC] " .. d.name .. " : suit le joueur")
end

local function stopFollow(npc)
    local d = PHNPC.npcs[npc]
    if not d then return end
    d.followMode = false
    npcStopMoving(npc)
    print("[PHNPC] " .. d.name .. " : reste ici")
end

local function startAttackMode(npc)
    local d = PHNPC.npcs[npc]
    if not d then return end
    d.attackMode = true
    print("[PHNPC] " .. d.name .. " : mode combat actif")
end

local function stopAttackMode(npc)
    local d = PHNPC.npcs[npc]
    if not d then return end
    d.attackMode = false
    d.target     = nil
    npcStopMoving(npc)
    pcall(function() npc:setTarget(nil) npc:clearAggroList() end)
    print("[PHNPC] " .. d.name .. " : mode combat desactive")
end

local function removeNPC(npc)
    local d = PHNPC.npcs[npc]
    if d then print("[PHNPC] Suppression: " .. d.name) end
    npcStopMoving(npc)
    pcall(function()
        npc:removeFromWorld()
        npc:removeFromSquare()
    end)
    PHNPC.npcs[npc] = nil
end

-- ============================================================
-- INVENTAIRE
-- ============================================================
local function openNPCInventory(npc)
    local d = PHNPC.npcs[npc]
    if not d then return end
    local player = getSpecificPlayer(0)
    if not player then return end
    pcall(function()
        ISInventoryTransferUI.transferBetween(player, npc)
    end)
end

-- ============================================================
-- STATS AFFICHAGE
-- ============================================================
local function showNPCStats(npc)
    local d = PHNPC.npcs[npc]
    if not d then return end
    local statsStr = PHNPC.statsToString(d.stats)
    local genre = d.isFemale and "F" or "M"
    print("[PHNPC] " .. d.name .. " (" .. genre .. ") - " .. d.outfit .. " | " .. statsStr)
    local player = getSpecificPlayer(0)
    if player then
        HaloTextHelper.addText(player,
            d.name .. ": " .. PHNPC.statsToString(d.stats),
            1, 1, 1, 1)
    end
end

-- ============================================================
-- CONTEXT MENU
-- ============================================================
local function onContextMenu(playerIndex, context, worldobjects, test)
    if test then return end

    local square = ISWorldObjectContextMenu.fetchVars.clickedSquare
    if not square then return end

    -- Detecter NPC pres du carre clique (rayon ~2 tiles)
    local clickedNPC = nil
    for npc, _ in pairs(PHNPC.npcs) do
        if npcValid(npc) then
            local dx = npc:getX() - square:getX()
            local dy = npc:getY() - square:getY()
            if (dx * dx + dy * dy) <= 4.0 then
                clickedNPC = npc
                break
            end
        end
    end

    if clickedNPC then
        local d     = PHNPC.npcs[clickedNPC]
        local name  = (d and d.name) or "PNJ"
        local genre = (d and d.isFemale) and "F" or "M"
        local title = "[PHNPC] " .. name .. " (" .. genre .. ")"

        local option  = context:addOption(title, clickedNPC, nil)
        local subMenu = context:addSubMenu(option, title)

        if d and d.followMode then
            context:addOptionOnSubmenu(subMenu, "Reste ici", clickedNPC, stopFollow)
        else
            context:addOptionOnSubmenu(subMenu, "Suis-moi", clickedNPC, startFollow)
        end

        if d and d.attackMode then
            context:addOptionOnSubmenu(subMenu, "Arreter le combat", clickedNPC, stopAttackMode)
        else
            context:addOptionOnSubmenu(subMenu, "Mode combat (tuer zombies)", clickedNPC, startAttackMode)
        end

        context:addOptionOnSubmenu(subMenu, "Voir l'inventaire", clickedNPC, openNPCInventory)
        context:addOptionOnSubmenu(subMenu, "Voir les stats",     clickedNPC, showNPCStats)
        context:addOptionOnSubmenu(subMenu, "Renvoyer",           clickedNPC, removeNPC)
    else
        context:addOption("[PHNPC] Faire apparaitre un PNJ", square,
            function(sq, pi)
                if not sq then return end
                local count = 0
                for _ in pairs(PHNPC.npcs) do count = count + 1 end
                if count >= MAX_NPCS then
                    print("[PHNPC] Limite atteinte (" .. MAX_NPCS .. ")")
                    return
                end
                createNPC(sq)
            end, playerIndex)
    end
end

-- ============================================================
-- PEUR DES ZOMBIES (check periodique)
-- ============================================================
local function checkFear(npc, data)
    if not data or data.attackMode then
        data.fleeMode = false
        return false
    end
    local stats = data.stats
    if not stats or stats.courage >= PHNPC.FEAR_COURAGE_THRESHOLD then
        data.fleeMode = false
        return false
    end
    local npcX = npc:getX()
    local npcY = npc:getY()
    local npcZ = npc:getZ()
    local nearestDist = 9999
    local nearestZombie = nil
    local cell = getCell()
    if not cell then return false end
    local zombList = cell:getZombieList()
    if not zombList then return false end
    for i = 0, zombList:size() - 1 do
        local z = zombList:get(i)
        if z and z ~= npc and not PHNPC.npcs[z] then
            local ok, r = pcall(function()
                local dx = z:getX() - npcX
                local dy = z:getY() - npcY
                return math.sqrt(dx * dx + dy * dy)
            end)
            if ok and r < nearestDist then
                nearestDist = r
                nearestZombie = z
            end
        end
    end
    if nearestZombie and nearestDist < PHNPC.FEAR_ZOMBIE_DIST then
        local zx = nearestZombie:getX()
        local zy = nearestZombie:getY()
        local dx = npcX - zx
        local dy = npcY - zy
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 0 then dx = dx / len ; dy = dy / len end
        local fleeX = npcX + dx * 15
        local fleeY = npcY + dy * 15
        data.fleeMode = true
        npcStartMoving(npc, fleeX, fleeY, npcZ)
        return true
    end
    data.fleeMode = false
    return false
end

-- ============================================================
-- COMBAT AUTO
-- ============================================================
local function checkCombat(npc, data)
    if not data or not data.attackMode then return false end
    local npcX = npc:getX()
    local npcY = npc:getY()
    local cell = getCell()
    if not cell then return false end
    local zombList = cell:getZombieList()
    if not zombList then return false end
    local nearestDist = 9999
    local nearestZombie = nil
    for i = 0, zombList:size() - 1 do
        local z = zombList:get(i)
        if z and z ~= npc and not PHNPC.npcs[z] then
            local ok, r = pcall(function()
                local dx = z:getX() - npcX
                local dy = z:getY() - npcY
                return math.sqrt(dx * dx + dy * dy)
            end)
            if ok and r < nearestDist then
                nearestDist = r
                nearestZombie = z
            end
        end
    end
    if nearestZombie and nearestDist < COMBAT_RANGE * 3 then
        data.target = nearestZombie
        if nearestDist < COMBAT_RANGE then
            pcall(function()
                npc:setUseless(false)
                npc:setTarget(nearestZombie)
                npc:NPCSetAttack(nearestZombie)
            end)
        else
            npcStartMoving(npc, nearestZombie:getX(), nearestZombie:getY(), nearestZombie:getZ())
        end
        return true
    end
    data.target = nil
    return false
end

-- ============================================================
-- ENFORCE NPC (OnZombieUpdate)
-- ============================================================
local function enforceNPC(zombie)
    local md = zombie:getModData()
    if not md or not md.PHNPC_ID then return end

    local data = PHNPC.npcs[zombie]

    -- setUseless(false) EN TOUT PREMIER
    pcall(function() zombie:setUseless(false) end)
    pcall(function() zombie:setHealth(10000) end)
    pcall(function() zombie:setNoTeeth(true) end)
    pcall(function() zombie:setEatBodyTarget(nil, false) end)

    -- Variables AnimSet
    pcall(function() zombie:setVariable("PHNPC_IsNPC", true) end)
    pcall(function() zombie:setVariable("NoLungeTarget", true) end)
    pcall(function() zombie:setVariable("zombieWalkType", "Walk") end)
    pcall(function() zombie:setWalkType("Walk") end)
    pcall(function() zombie:setSpeedMod(1.0) end)
    pcall(function() zombie:setAnimatingBackwards(false) end)

    local asn = ""
    pcall(function() asn = tostring(zombie:getActionStateName()) end)

    -- Etats a ne pas interrompre
    if asn == "pathfind" or asn == "thump" then
        pcall(function() zombie:setUseless(false) end)
        return
    end

    if asn == "attack" then
        if data and data.attackMode then
            pcall(function() zombie:setUseless(false) end)
            return
        end
        pcall(function() zombie:changeState(ZombieIdleState.instance()) end)
        pcall(function() zombie:setTarget(nil) end)
        pcall(function() zombie:clearAggroList() end)
        if data then data.moving = false end
        return
    end

    if asn == "lunge" or asn == "eatBody" then
        pcall(function() zombie:changeState(ZombieIdleState.instance()) end)
        pcall(function() zombie:setTarget(nil) end)
        pcall(function() zombie:clearAggroList() end)
        pcall(function() zombie:setUseless(false) end)
        if data then data.moving = false end
        return
    end

    if asn == "turnalerted" then
        pcall(function() zombie:changeState(ZombieIdleState.instance()) end)
        pcall(function() zombie:setTarget(nil) end)
        pcall(function() zombie:clearAggroList() end)
        pcall(function() zombie:setUseless(false) end)
        return
    end

    if asn == "bumped" then
        if data then
            data.bumpTicks = (data.bumpTicks or 0) + 1
            if data.bumpTicks > 30 then
                pcall(function() zombie:changeState(ZombieIdleState.instance()) end)
                pcall(function() zombie:setBumpType("Shrug") end)
                data.bumpTicks = 0
                data.moving    = false
            end
        end
        return
    end

    -- Normal
    if not (data and data.attackMode) then
        pcall(function() zombie:setTarget(nil) end)
        pcall(function() zombie:clearAggroList() end)
    end
    pcall(function() zombie:setUseless(false) end)
    if data then data.bumpTicks = 0 end
end

-- ============================================================
-- ONZOMBIEUPDATE
-- ============================================================
Events.OnZombieUpdate.Add(function(zombie)
    if not zombie then return end
    if not PHNPC or not PHNPC.npcs then return end
    if not PHNPC.npcs[zombie] then return end
    enforceNPC(zombie)
end)

-- ============================================================
-- MAIN TICK
-- ============================================================
Events.OnTick.Add(function()
    _ticks = _ticks + 1

    local player    = getSpecificPlayer(0)
    local doCleanup = (_ticks % CLEANUP == 0)
    local doFear    = (_ticks % FEAR_CHECK_RATE == 0)

    -- Cleanup NPC morts
    if doCleanup then
        local dead = {}
        for npc in pairs(PHNPC.npcs) do
            if not npcValid(npc) then dead[#dead + 1] = npc end
        end
        for i = 1, #dead do
            local d = PHNPC.npcs[dead[i]]
            print("[PHNPC] Cleanup: " .. (d and d.name or "?"))
            PHNPC.npcs[dead[i]] = nil
        end
    end

    if not player then return end
    local px = player:getX()
    local py = player:getY()
    local pz = player:getZ()

    for npc, data in pairs(PHNPC.npcs) do
        if npcValid(npc) then

            -- Check peur
            if doFear then checkFear(npc, data) end

            -- Check combat
            if data.attackMode and (_ticks % 10 == 0) then
                if not checkCombat(npc, data) and data.followMode then
                    pcall(function() npc:setTarget(nil) end)
                    pcall(function() npc:clearAggroList() end)
                end
            end

            -- Suivi joueur
            if data.followMode and not data.fleeMode
               and not (data.attackMode and data.target) then
                local dx   = npc:getX() - px
                local dy   = npc:getY() - py
                local dist = math.sqrt(dx * dx + dy * dy)

                if dist > STOP_DIST then
                    data.retarget = data.retarget - 1
                    if data.retarget <= 0 then
                        data.retarget = RETARGET
                        npcStartMoving(npc, px, py, pz)
                    end
                else
                    npcStopMoving(npc)
                    data.retarget = RETARGET
                end
            end
        end
    end
end)

-- ============================================================
-- GAME START
-- ============================================================
Events.OnGameStart.Add(function()
    PHNPC.npcs = {}
    _ticks = 0
    print("[PHNPC] PHNPC_Manager v2.0 pret (OnGameStart)")
end)

Events.OnPreFillWorldObjectContextMenu.Add(onContextMenu)
print("[PHNPC] PHNPC_Manager v2.0 loaded")
