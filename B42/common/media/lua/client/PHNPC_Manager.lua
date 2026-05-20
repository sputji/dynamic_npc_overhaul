-- Project Humain: Dynamic NPC Overhaul - B42
-- client/PHNPC_Manager.lua  v2.2
-- Spawn / Mouvement / IA / Ordres / Inventaire / Combat / Peur / Colere
-- Necessite: PHNPC_Core.lua (shared), PHNPC_Stats.lua (shared)
-- Traductions: Translate/EN/UI.json + Translate/FR/UI.json
-- NO BOM. ASCII only.

-- ============================================================
-- CONFIG
-- ============================================================
local STOP_DIST       = 3     -- tiles: distance min pour arreter le suivi
local RETARGET        = 15    -- ticks entre deux pathToLocationF
local CLEANUP         = 300   -- ticks entre passes de nettoyage
local MAX_NPCS        = 10    -- nombre max de NPC simultanes
local FEAR_CHECK_RATE = 30    -- ticks entre checks de peur
local COMBAT_RANGE    = 15    -- tiles: rayon de detection combat
local ATTACK_RANGE    = 1.8   -- tiles: distance d'attaque corps a corps
local ATTACK_COOLDOWN = 60    -- ticks entre deux coups
local ANGER_DECAY     = 6000  -- ticks avant que la colere diminue de 1 niveau
local ANGER_ATK_TICKS = 180   -- duree d'attaque vs joueur (colere niveau 4+)
local ANGER_ATK_CD    = 80    -- ticks entre coups sur le joueur

local OUTFITS = {
    "Farmer", "Police", "Fireman", "Doctor",
    "Ranger", "Chef", "Survivor",
}

-- Variantes d'animations d'attaque (en alternance)
local ATTACK_VARIANTS = { "Shove", "FrontKick", "HighKick" }
local _attackIdx = 0

-- Cles de traduction pour la colere (getText via Translate/XX/UI.json)
local ANGER_KEYS_M = {
    [1] = "PHNPC_Anger_M_1",
    [2] = "PHNPC_Anger_M_2",
    [3] = "PHNPC_Anger_M_3",
    [4] = "PHNPC_Anger_M_4",
}
local ANGER_KEYS_F = {
    [1] = "PHNPC_Anger_F_1",
    [2] = "PHNPC_Anger_F_2",
    [3] = "PHNPC_Anger_F_3",
    [4] = "PHNPC_Anger_F_4",
}

-- ============================================================
-- STATE INTERNE
-- ============================================================
local _ticks    = 0
local _openInvNPC = nil  -- NPC dont on ouvre l'inventaire

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
-- NOTE: pas de setBumpType ici — le walk est gere par pathToLocationF
-- ============================================================
local function npcStartMoving(npc, x, y, z)
    local data = PHNPC.npcs[npc]
    pcall(function()
        npc:setUseless(false)
        npc:setVariable("PHNPC_IsNPC", true)
        npc:setVariable("zombieWalkType", "Walk")
        npc:setWalkType("Walk")
        npc:setSpeedMod(0.8)
        if data then data.moving = true end
        npc:pathToLocationF(x, y, z)
    end)
end

local function npcStopMoving(npc)
    local data = PHNPC.npcs[npc]
    if data then data.moving = false end
    pcall(function() npc:setBumpType("Shrug") end)
end

-- ============================================================
-- COMBAT MANUEL (comme NPC_Helper_Mod — pas de setTarget/NPCSetAttack)
-- npc:setBumpType(anim) + enemy:knockDown(true)
-- ============================================================
local function doMeleeAttack(npc, target)
    if not target then return false end
    local hit = false
    pcall(function()
        local ok2, dead = pcall(function() return target:isDead() end)
        if ok2 and dead then return end

        _attackIdx = _attackIdx % #ATTACK_VARIANTS
        local anim = ATTACK_VARIANTS[_attackIdx + 1]
        _attackIdx = _attackIdx + 1

        npc:faceLocationF(target:getX(), target:getY())
        npc:setBumpType(anim)

        -- Knockdown sur zombies uniquement (pas sur nos propres NPCs)
        local tmd = target:getModData()
        if not tmd.PHNPC_ID then
            pcall(function() target:knockDown(true) end)
        end
        hit = true
    end)
    return hit
end

-- ============================================================
-- COLERE — REACTION AUX POUSSEES (4 niveaux)
-- ============================================================
local function handleAnger(npc, data)
    if not data then return end
    data.angerLevel = (data.angerLevel or 0) + 1
    data.angerTimer = ANGER_DECAY

    local level  = math.min(data.angerLevel, 4)
    local keys   = data.isFemale and ANGER_KEYS_F or ANGER_KEYS_M
    local msg    = getText(keys[level] or keys[4])

    -- Dialogue via Say() — bulle de parole au-dessus du NPC
    pcall(function() npc:Say(msg) end)

    -- Niveau 4+ : le NPC attaque le joueur brievement
    if data.angerLevel >= 4 then
        data.playerAngerTicks  = ANGER_ATK_TICKS
        data.playerAngerCooldown = 0
        print("[PHNPC] " .. (data.name or "?") .. " est furieux (niveau 4) !")
    end
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
        npc:setUseless(false)
        npc:setNoTeeth(true)
        npc:setVariable("PHNPC_IsNPC", true)
        npc:setWalkType("Walk")
        npc:setVariable("zombieWalkType", "Walk")
        npc:setVariable("ZombieHitReaction", "Chainsaw")
        npc:setVariable("NoLungeTarget", true)
        npc:setVariable("LimpSpeed", 0.70)
        npc:setVariable("WalkSpeed", 0.85)
        npc:setVariable("RunSpeed", 0.92)
        npc:setSpeedMod(0.8)
        npc:getEmitter():stopAll()
        npc:setPrimaryHandItem(nil)
        npc:setSecondaryHandItem(nil)
        npc:resetEquippedHandsModels()
        npc:clearAttachedItems()
        npc:setDressInRandomOutfit(false)
        npc:setTurnAlertedValues(-5, 5)
        npc:setBumpType("Shrug")
        npc:setTarget(nil)
        npc:clearAggroList()
        npc:setHealth(10000)
    end)

    -- 3. Visuels propres
    pcall(function()
        local hv = npc:getHumanVisual()
        if hv then hv:removeDirt() ; hv:removeBlood() end
    end)

    -- 4. Nom affiché via Say()
    pcall(function()
        npc:Say(npcName)
    end)

    -- 5. ModData
    local md = npc:getModData()
    md.PHNPC_ID     = npcId
    md.PHNPC_Name   = npcName
    md.PHNPC_Female = isFemale
    md.PHNPC_Outfit = outfit
    md.PHNPC_Stats  = stats

    -- 6. Enregistrer dans PHNPC.npcs
    PHNPC.npcs[npc] = {
        id                 = npcId,
        name               = npcName,
        isFemale           = isFemale,
        outfit             = outfit,
        stats              = stats,
        followMode         = true,
        attackMode         = false,
        fleeMode           = false,
        retarget           = 0,
        moving             = false,
        bumpTicks          = 0,
        fearTicks          = 0,
        target             = nil,
        attackCooldown     = 0,
        angerLevel         = 0,
        angerTimer         = 0,
        playerAngerTicks   = 0,
        playerAngerCooldown = 0,
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
    d.attackMode     = true
    d.attackCooldown = 0
    d.target         = nil
    print("[PHNPC] " .. d.name .. " : mode combat actif")
end

local function stopAttackMode(npc)
    local d = PHNPC.npcs[npc]
    if not d then return end
    d.attackMode     = false
    d.attackCooldown = 0
    d.target         = nil
    npcStopMoving(npc)
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
    if _openInvNPC == npc then _openInvNPC = nil end
end

-- ============================================================
-- INVENTAIRE — hook OnRefreshInventoryWindowContainers
-- (ISInventoryTransferUI.transferBetween ne fonctionne pas en B42)
-- ============================================================
local function openNPCInventory(npc)
    local d = PHNPC.npcs[npc]
    if not d then return end
    pcall(function()
        local inv = npc:getInventory()
        inv:setType(d.name)
        _openInvNPC = npc
        local pdata = getPlayerData(0)
        if pdata and pdata.lootInventory then
            pdata.lootInventory:refreshBackpacks()
        end
    end)
end

Events.OnRefreshInventoryWindowContainers.Add(function(page, step)
    if step ~= "beforeFloor" then return end
    if page.onCharacter then return end
    if not _openInvNPC then return end

    local ok, dead = pcall(function() return _openInvNPC:isDead() end)
    if not ok or dead then _openInvNPC = nil ; return end

    local d = PHNPC.npcs[_openInvNPC]
    local inv = _openInvNPC:getInventory()
    local loot = getPlayerLoot(page.player)
    if loot then
        pcall(function()
            loot:addContainerButton(inv, nil,
                (d and d.name) or "PNJ",
                (d and d.name) or "PNJ")
        end)
    end
end)

-- ============================================================
-- STATS AFFICHAGE — Say() au-dessus du NPC
-- ============================================================
local function showNPCStats(npc)
    local d = PHNPC.npcs[npc]
    if not d then return end
    local genre    = d.isFemale and "F" or "M"
    local statsStr = PHNPC.statsToString(d.stats)
    print("[PHNPC] " .. d.name .. " (" .. genre .. ") - " .. d.outfit .. " | " .. statsStr)
    pcall(function()
        npc:Say(d.name .. " (" .. genre .. "): " .. statsStr)
    end)
end

-- ============================================================
-- CONTEXT MENU  (pattern B42 confirme dans NPC_Helper_Mod)
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

        local option  = context:addOption(title)
        local subMenu = ISContextMenu:getNew(context)
        context:addSubMenu(option, subMenu)

        if d and d.followMode then
            subMenu:addOption(getText("PHNPC_Menu_StayHere"),    clickedNPC, stopFollow)
        else
            subMenu:addOption(getText("PHNPC_Menu_FollowMe"),    clickedNPC, startFollow)
        end

        if d and d.attackMode then
            subMenu:addOption(getText("PHNPC_Menu_StopCombat"),  clickedNPC, stopAttackMode)
        else
            subMenu:addOption(getText("PHNPC_Menu_StartCombat"), clickedNPC, startAttackMode)
        end

        subMenu:addOption(getText("PHNPC_Menu_OpenInventory"), clickedNPC, openNPCInventory)
        subMenu:addOption(getText("PHNPC_Menu_ShowStats"),     clickedNPC, showNPCStats)
        subMenu:addOption(getText("PHNPC_Menu_Dismiss"),       clickedNPC, removeNPC)
    else
        context:addOption(getText("PHNPC_Menu_SpawnNPC"), square,
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
    local nearestDist   = 9999
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
                nearestDist   = r
                nearestZombie = z
            end
        end
    end
    if nearestZombie and nearestDist < PHNPC.FEAR_ZOMBIE_DIST then
        local zx  = nearestZombie:getX()
        local zy  = nearestZombie:getY()
        local dx  = npcX - zx
        local dy  = npcY - zy
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 0 then dx = dx / len ; dy = dy / len end
        data.fleeMode = true
        npcStartMoving(npc, npcX + dx * 15, npcY + dy * 15, npcZ)
        return true
    end
    data.fleeMode = false
    return false
end

-- ============================================================
-- COMBAT MANUEL VS ZOMBIES
-- NPC_Helper_Mod pattern: faceLocationF + setBumpType + knockDown
-- Pas de setTarget / NPCSetAttack (ne fonctionnent pas en B42)
-- ============================================================
local function checkCombat(npc, data)
    if not data or not data.attackMode then return false end

    -- Decompte du cooldown d'attaque
    if (data.attackCooldown or 0) > 0 then
        data.attackCooldown = data.attackCooldown - 1
        -- Pendant cooldown: continuer a s'approcher de la cible
        if data.target and npcValid(data.target) then
            local dx = data.target:getX() - npc:getX()
            local dy = data.target:getY() - npc:getY()
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist > ATTACK_RANGE then
                npcStartMoving(npc, data.target:getX(), data.target:getY(), data.target:getZ())
            end
        end
        return true
    end

    -- Chercher le zombie le plus proche
    local npcX = npc:getX()
    local npcY = npc:getY()
    local cell = getCell()
    if not cell then return false end
    local zombList = cell:getZombieList()
    if not zombList then return false end

    local nearestDist   = 9999
    local nearestZombie = nil

    for i = 0, zombList:size() - 1 do
        local z = zombList:get(i)
        if z and z ~= npc and not PHNPC.npcs[z] then
            local ok, dead = pcall(function() return z:isDead() end)
            if ok and not dead then
                local ok2, r = pcall(function()
                    local dx = z:getX() - npcX
                    local dy = z:getY() - npcY
                    return math.sqrt(dx * dx + dy * dy)
                end)
                if ok2 and r < nearestDist then
                    nearestDist   = r
                    nearestZombie = z
                end
            end
        end
    end

    if nearestZombie and nearestDist < COMBAT_RANGE then
        data.target = nearestZombie
        if nearestDist <= ATTACK_RANGE then
            -- ATTAQUE
            doMeleeAttack(npc, nearestZombie)
            data.attackCooldown = ATTACK_COOLDOWN
            data.moving = false
        else
            -- APPROCHE
            npcStartMoving(npc,
                nearestZombie:getX(), nearestZombie:getY(), nearestZombie:getZ())
        end
        return true
    end

    -- Aucun zombie a portee
    data.target = nil
    return false
end

-- ============================================================
-- ENFORCE NPC (OnZombieUpdate)
-- Toujours effacer la cible (comme NPC_Helper_Mod) — combat est manuel
-- ============================================================
local function enforceNPC(zombie)
    local md = zombie:getModData()
    if not md or not md.PHNPC_ID then return end

    local data = PHNPC.npcs[zombie]

    -- TOUJOURS garder l'etat NPC sain EN PREMIER
    pcall(function() zombie:setUseless(false) end)
    pcall(function() zombie:setHealth(10000) end)
    pcall(function() zombie:setNoTeeth(true) end)
    pcall(function() zombie:setEatBodyTarget(nil, false) end)

    -- Variables AnimSet
    pcall(function() zombie:setVariable("PHNPC_IsNPC", true) end)
    pcall(function() zombie:setVariable("NoLungeTarget", true) end)
    pcall(function() zombie:setVariable("zombieWalkType", "Walk") end)
    pcall(function() zombie:setWalkType("Walk") end)
    pcall(function() zombie:setSpeedMod(0.8) end)

    -- TOUJOURS effacer la cible zombie sauf pendant colere vs joueur
    -- (comme NPC_Helper_Mod — le combat est entierement manuel)
    local angerAtk = data and (data.playerAngerTicks or 0) > 0
    if not angerAtk then
        pcall(function() zombie:setTarget(nil) end)
        pcall(function() zombie:clearAggroList() end)
    end

    local asn = ""
    pcall(function() asn = tostring(zombie:getActionStateName()) end)

    -- Pathfinding / porte : laisser faire
    if asn == "pathfind" or asn == "thump" then
        return
    end

    -- Manger / alerte : reset immediat
    if asn == "eatBody" or asn == "turnalerted" then
        pcall(function() zombie:changeState(ZombieIdleState.instance()) end)
        if data then data.moving = false end
        return
    end

    -- Poussee : detection + dialogue de colere
    if asn == "bumped" then
        if data then
            local isNewBump = (data.bumpTicks == 0)
            data.bumpTicks  = data.bumpTicks + 1

            if isNewBump then
                handleAnger(zombie, data)
                -- Niveau 4+ : frappe pendant la poussee
                if data.angerLevel >= 4 then
                    pcall(function() zombie:setBumpType("AttackBareHands1") end)
                end
            end

            -- Sortir de l'etat bumped apres 35 ticks
            if data.bumpTicks > 35 then
                pcall(function() zombie:changeState(ZombieIdleState.instance()) end)
                pcall(function() zombie:setBumpType("Shrug") end)
                data.bumpTicks = 0
                data.moving    = false
            end
        end
        return
    end

    -- Etat normal : reset bumpTicks
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
    local doCombat  = (_ticks % 10 == 0)

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

            -- Colere vs joueur : frappe manuelle
            if data.playerAngerTicks > 0 then
                data.playerAngerTicks = data.playerAngerTicks - 1

                data.playerAngerCooldown = (data.playerAngerCooldown or 0) - 1
                if data.playerAngerCooldown <= 0 then
                    local dx = player:getX() - npc:getX()
                    local dy = player:getY() - npc:getY()
                    local dist = math.sqrt(dx * dx + dy * dy)
                    if dist <= ATTACK_RANGE then
                        doMeleeAttack(npc, player)
                        data.playerAngerCooldown = ANGER_ATK_CD
                    else
                        npcStartMoving(npc, px, py, pz)
                        data.playerAngerCooldown = 5
                    end
                end

                if data.playerAngerTicks == 0 then
                    pcall(function() npc:setBumpType("Shrug") end)
                    data.moving = false
                    print("[PHNPC] " .. data.name .. " se calme.")
                end
            end

            -- Forgiveness : colere diminue naturellement
            if data.angerLevel > 0 then
                data.angerTimer = (data.angerTimer or ANGER_DECAY) - 1
                if data.angerTimer <= 0 then
                    data.angerLevel = data.angerLevel - 1
                    data.angerTimer = ANGER_DECAY
                end
            end

            -- Check peur des zombies
            if doFear then checkFear(npc, data) end

            -- Combat manuel vs zombies
            if doCombat and data.attackMode and data.playerAngerTicks == 0 then
                checkCombat(npc, data)
            end

            -- Suivi joueur
            if data.followMode and not data.fleeMode
               and not data.attackMode
               and data.playerAngerTicks == 0 then
                local dx   = npc:getX() - px
                local dy   = npc:getY() - py
                local dist = math.sqrt(dx * dx + dy * dy)

                if dist > STOP_DIST then
                    data.retarget = (data.retarget or 0) - 1
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
    PHNPC.npcs  = {}
    _ticks      = 0
    _openInvNPC = nil
    print("[PHNPC] PHNPC_Manager v2.2 pret (OnGameStart)")
end)

Events.OnPreFillWorldObjectContextMenu.Add(onContextMenu)
print("[PHNPC] PHNPC_Manager v2.2 loaded")
