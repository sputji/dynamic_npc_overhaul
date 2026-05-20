-- Project Humain: Dynamic NPC Overhaul - B42
-- client/PHNPC_Manager.lua
-- Spawn: addZombiesInOutfit() + Banditize pattern (NPC_Helper_Mod / Bandits).
-- Movement: zombie:pathToLocationF + setBumpType transitions.
-- AnimSets: declenches par variable PHNPC_IsNPC = true.
-- NO BOM. ASCII only.

-- ============================================================
-- CONFIG
-- ============================================================
local STOP_DIST  = 3    -- tiles: arreter le suivi quand assez proche
local RETARGET   = 15   -- ticks entre deux pathToLocationF
local CLEANUP    = 300  -- ticks entre deux passes de nettoyage
local MAX_NPCS   = 10   -- nombre max de NPC simultanes

-- Outfits disponibles (addZombiesInOutfit accepte ces noms B42)
local OUTFITS = {
    "Farmer", "Police", "Fireman", "Doctor",
    "Ranger", "Chef", "Survivor",
}

-- Noms des NPC
local NPC_NAMES = {
    "Alex", "Jordan", "Sam", "Casey", "Riley",
    "Morgan", "Taylor", "Quinn", "Blake", "Drew",
    "Charlie", "Avery", "Reese", "Dakota", "Skyler",
}

-- ============================================================
-- STATE
-- PHNPC.npcs[IsoZombie] = { id, name, isFemale, followMode, retarget, moving }
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
-- Pattern: GCCore.startMoving / stopMoving (NPC_Helper_Mod GCCoreActions.lua)
--   start : setUseless(false) + setBumpType("IdleToWalk") + pathToLocationF
--   stop  : setBumpType("WalkToIdle")
-- ============================================================
local function npcStartMoving(npc, x, y, z)
    local data = PHNPC.npcs[npc]
    pcall(function()
        npc:setUseless(false)
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
-- Pattern: GCCoreSpawn.spawnCompanionNPC (NPC_Helper_Mod)
--       + Banditize (BanditUpdate.lua lignes 158-206)
-- 1. addZombiesInOutfit() -> IsoZombie avec tenue humaine
-- 2. Banditize: variables + walktype + sons + dents
-- 3. setVariable("PHNPC_IsNPC", true) -> active AnimSets custom
-- ============================================================
local function createNPC(square)
    local x = square:getX()
    local y = square:getY()
    local z = square:getZ()

    local isFemale     = (ZombRand(2) == 1)
    local femaleChance = isFemale and 100 or 0
    local outfit       = OUTFITS[ZombRand(#OUTFITS) + 1]
    local npcName      = NPC_NAMES[ZombRand(#NPC_NAMES) + 1]
    local npcId        = "PHNPC_" .. npcName .. "_" .. tostring(getTimestampMs())

    -- 1. Spawn via addZombiesInOutfit (approche prouvee NPC_Helper_Mod / Bandits)
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
    -- (copie exacte du pattern Bandits BanditUpdate.lua + GCCoreConvert.lua)
    pcall(function()
        -- Pas de dents zombie
        npc:setNoTeeth(true)

        -- Activer mes AnimSets XML (PHNPC_Idle.xml, PHNPC_Walk.xml)
        -- condition: PHNPC_IsNPC = true
        npc:setVariable("PHNPC_IsNPC", true)

        -- Marche humaine (doit correspondre a zombieWalkType dans PHNPC_Walk.xml)
        npc:setWalkType("Walk")
        npc:setVariable("zombieWalkType", "Walk")

        -- Evite crash dans testDefense (important, copie Bandits)
        npc:setVariable("ZombieHitReaction", "Chainsaw")

        -- Pas de lunge attack
        npc:setVariable("NoLungeTarget", true)

        -- Vitesses humaines
        npc:setVariable("LimpSpeed", 0.80)
        npc:setVariable("WalkSpeed", 1.04)
        npc:setVariable("RunSpeed", 0.75)

        -- Silence bruits zombie
        npc:getEmitter():stopAll()

        -- Supprimer armes et accessoires zombie
        npc:setPrimaryHandItem(nil)
        npc:setSecondaryHandItem(nil)
        npc:resetEquippedHandsModels()
        npc:clearAttachedItems()

        -- Pas de re-habillage automatique par le moteur
        npc:setDressInRandomOutfit(false)

        -- setTurnAlertedValues: debloquer apres spawn (Bandits)
        npc:setTurnAlertedValues(-5, 5)

        -- Bump initial pour sortir de l'etat zombie idle
        npc:setBumpType("Shrug")
    end)

    -- 3. Nettoyer les visuels zombie (sang, salet, degats)
    pcall(function()
        local hv = npc:getHumanVisual()
        if hv then
            hv:removeDirt()
            hv:removeBlood()
        end
    end)

    -- 4. ModData
    local md = npc:getModData()
    md.PHNPC_ID     = npcId
    md.PHNPC_Name   = npcName
    md.PHNPC_Female = isFemale

    -- 5. Enregistrer dans PHNPC.npcs
    PHNPC.npcs[npc] = {
        id         = npcId,
        name       = npcName,
        isFemale   = isFemale,
        followMode = true,
        retarget   = 0,
        moving     = false,
    }

    print("[PHNPC] NPC spawne: " .. npcName
        .. " (" .. (isFemale and "F" or "M") .. ")"
        .. " outfit=" .. outfit
        .. " @ " .. x .. "," .. y)
end

-- ============================================================
-- SPAWN MENU ACTION
-- ============================================================
local function spawnNPC(square, playerIndex)
    if not square then return end

    local count = 0
    for _ in pairs(PHNPC.npcs) do count = count + 1 end
    if count >= MAX_NPCS then
        print("[PHNPC] Limite de PNJ atteint (" .. MAX_NPCS .. ")")
        return
    end

    createNPC(square)
end

-- ============================================================
-- CONTEXT MENU ACTIONS (NPCs existants)
-- ============================================================
local function startFollow(npc)
    local d = PHNPC.npcs[npc]
    if not d then return end
    d.followMode = true
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
-- CONTEXT MENU
-- Pattern: Events.OnPreFillWorldObjectContextMenu
-- square via ISWorldObjectContextMenu.fetchVars.clickedSquare (B42)
-- ============================================================
local function onContextMenu(playerIndex, context, worldobjects, test)
    if test then return end

    local square = ISWorldObjectContextMenu.fetchVars.clickedSquare
    if not square then return end

    -- Detecter un NPC pres du carre clique (rayon 2 tiles)
    local clickedNPC = nil
    for npc, _ in pairs(PHNPC.npcs) do
        if npcValid(npc) then
            local dx = npc:getX() - square:getX()
            local dy = npc:getY() - square:getY()
            if (dx * dx + dy * dy) <= 2.0 then
                clickedNPC = npc
                break
            end
        end
    end

    if clickedNPC then
        local d    = PHNPC.npcs[clickedNPC]
        local name = (d and d.name) or "PNJ"
        if d and d.followMode then
            context:addOption("[PHNPC] " .. name .. " : Reste ici", clickedNPC, stopFollow)
        else
            context:addOption("[PHNPC] " .. name .. " : Suis-moi", clickedNPC, startFollow)
        end
        context:addOption("[PHNPC] Supprimer " .. name, clickedNPC, removeNPC)
    else
        -- Option spawn sur le sol vide
        context:addOption("[PHNPC] Faire apparaitre un PNJ", square, spawnNPC, playerIndex)
    end
end

-- ============================================================
-- MAIN TICK
-- Suivi + retarget + cleanup
-- ============================================================
Events.OnTick.Add(function()
    _ticks = _ticks + 1

    local player    = getSpecificPlayer(0)
    local doCleanup = (_ticks % CLEANUP == 0)

    -- Cleanup: retirer les NPC morts
    if doCleanup then
        local dead = {}
        for npc in pairs(PHNPC.npcs) do
            if not npcValid(npc) then
                dead[#dead + 1] = npc
            end
        end
        for i = 1, #dead do
            local d = PHNPC.npcs[dead[i]]
            print("[PHNPC] Cleanup NPC mort: " .. (d and d.name or "?"))
            PHNPC.npcs[dead[i]] = nil
        end
    end

    -- Mouvement
    if not player then return end
    local px = player:getX()
    local py = player:getY()
    local pz = player:getZ()

    for npc, data in pairs(PHNPC.npcs) do
        if npcValid(npc) and data.followMode then
            local dx   = npc:getX() - px
            local dy   = npc:getY() - py
            local dist = math.sqrt(dx * dx + dy * dy)

            if dist > STOP_DIST then
                -- Emettre un nouveau pathToLocationF periodiquement
                data.retarget = data.retarget - 1
                if data.retarget <= 0 then
                    data.retarget = RETARGET
                    npcStartMoving(npc, px, py, pz)
                end
            else
                -- Assez proche: arreter
                npcStopMoving(npc)
                data.retarget = RETARGET
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
    print("[PHNPC] PHNPC_Manager v1.0 pret (OnGameStart)")
end)

Events.OnPreFillWorldObjectContextMenu.Add(onContextMenu)
print("[PHNPC] PHNPC_Manager v1.0 loaded")
