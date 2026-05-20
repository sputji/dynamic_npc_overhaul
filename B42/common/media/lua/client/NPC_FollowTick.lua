--[[
    Project Humain : Dynamic NPC Overhaul — B42
    client/NPC_FollowTick.lua  — RÉÉCRITURE COMPLÈTE v2.0

    Architecture IsoPlayer (pattern "7-Custom NPC" B42 + Bandits B42.18)
    ─────────────────────────────────────────────────────────────────────
    AVANT (cassé) : IsoZombie converti → animations zombie permanentes
    MAINTENANT    : IsoPlayer.new() + SurvivorFactory → animations Bob/Kate
                    natives, sons humains, pathfinding réel

    Fonctionnalités :
      • Clic droit → "Faire apparaître un PNJ" sur n'importe quelle case
      • Genre aléatoire (50/50), nom + prénom PZ natifs
      • Profession + vêtements correspondants
      • Sons Bob (homme) ou Kate (femme) automatiques via IsoPlayer
      • Carte d'identité + inventaire de départ
      • Suivi du joueur via getPathFindBehavior2():pathToLocation()
      • Nettoyage automatique des entités mortes/invalides

    Compatibilité solo uniquement (IsoPlayer.new côté client).
    Multijoueur : étape future via commandes serveur.
]]

-- ============================================================
-- CONFIGURATION
-- ============================================================

local CFG = {
    FOLLOW_STOP  = 3.0,   -- (cases) distance d'arrêt
    FOLLOW_RUN   = 10.0,  -- (cases) distance à partir de laquelle le NPC court
    FOLLOW_MAX   = 80.0,  -- (cases) au-delà : NPC perdu, on annule le chemin
    RETARGET     = 8,     -- (ticks) fréquence de recalcul de la destination
    CLEANUP      = 300,   -- (ticks) fréquence du nettoyage des entités mortes
}

-- ============================================================
-- REGISTRE
-- ============================================================

-- _npcs[IsoPlayer] = { followMode, isFemale, forename, surname, fullname }
local _npcs  = {}
local _ticks = 0   -- compteur global OnTick

-- ============================================================
-- VALIDATION
-- ============================================================

local function isValidNPC(npc)
    if not npc then return false end
    if not instanceof(npc, "IsoPlayer") then return false end
    local dead = false
    pcall(function() dead = npc:isDead() end)
    return not dead
end

-- ============================================================
-- INVENTAIRE DE DÉPART
-- ============================================================

local ITEMS_BASE  = {"Base.WaterBottleFull", "Base.Bandage", "Base.BandageDirty"}
local ITEMS_EXTRA = {"Base.Chips", "Base.Crackers", "Base.TunaCan", "Base.Sardines"}
local ITEMS_TOOL  = {"Base.Flashlight", "Base.Knife", "Base.Screwdriver"}

local function giveStartingInventory(npc)
    pcall(function()
        local inv = npc:getInventory()
        for _, it in ipairs(ITEMS_BASE) do inv:AddItem(it) end
        inv:AddItem(ITEMS_EXTRA[ZombRand(#ITEMS_EXTRA) + 1])
        if ZombRand(3) > 0 then
            inv:AddItem(ITEMS_TOOL[ZombRand(#ITEMS_TOOL) + 1])
        end
    end)
end

-- ============================================================
-- CARTE D'IDENTITÉ
-- ============================================================

local function giveIDCard(npc, forename, surname)
    pcall(function()
        local inv  = npc:getInventory()
        local card = inv:AddItem("Base.IDCard")
        if card then
            card:setName(forename .. " " .. surname)
            if card.setCustomName then card:setCustomName(forename .. " " .. surname) end
        end
    end)
end

-- ============================================================
-- CRÉATION DE L'ISOPlayer NPC
-- ============================================================

local function spawnNPC(square, playerIndex)
    if not square then return end

    local cell = getWorld():getCell()
    if not cell then
        print("[PHNPC] Erreur spawnNPC : getCell() nil")
        return
    end

    local isFemale = (ZombRand(2) == 1)
    local forename = SurvivorFactory.getRandomForename(isFemale)
    local surname  = SurvivorFactory.getRandomSurname()

    -- Descripteur humain : peau, cheveux, visage, corps, vêtements de profession
    local desc = SurvivorFactory.CreateSurvivor(nil, isFemale)
    desc:setForename(forename)
    desc:setSurname(surname)

    pcall(function()
        local profList = ProfessionFactory.getProfessions()
        if profList and profList:size() > 0 then
            local prof = profList:get(ZombRand(profList:size()))
            desc:setProfession(prof:getType())
            desc:setProfessionSkills(prof)
        end
    end)

    -- Z-level plancher
    local z = 0
    if square:isSolidFloor() then z = square:getZ() end

    -- IsoPlayer.new() → animations Bob/Kate, sons humains, pathfinding natif
    local npc = IsoPlayer.new(cell, desc, square:getX(), square:getY(), z)
    if not npc then
        print("[PHNPC] Erreur spawnNPC : IsoPlayer.new() a retourné nil")
        return
    end

    npc:setNPC(true)
    npc:setForname(forename)
    npc:setSurname(surname)
    npc:setUsername(forename .. " " .. surname)
    npc:setSceneCulled(false)
    npc:setDir(IsoDirections.SE)
    pcall(function() npc:setDressInRandomOutfit(false) end)

    giveIDCard(npc, forename, surname)
    giveStartingInventory(npc)

    _npcs[npc] = {
        followMode = true,
        isFemale   = isFemale,
        forename   = forename,
        surname    = surname,
        fullname   = forename .. " " .. surname,
    }

    print(string.format("[PHNPC] NPC spawné : %s (%s) @ %d,%d,%d",
        forename .. " " .. surname,
        isFemale and "F" or "H",
        math.floor(square:getX()),
        math.floor(square:getY()),
        z))
end

-- ============================================================
-- MENU CONTEXTUEL (clic droit)
-- ============================================================

local function onContextMenu(playerIndex, context, worldobjects, test)
    local square = ISWorldObjectContextMenu.fetchVars.clickedSquare
    if not square then return end
    context:addOption(
        "[PHNPC] Faire apparaitre un PNJ",
        square,
        spawnNPC,
        playerIndex
    )
end

-- ============================================================
-- BOUCLE DE SUIVI (OnTick)
-- ============================================================
--  • Chaque tick       : getPathFindBehavior2():update() maintient le mouvement
--  • Toutes les N ticks: recalcul de la destination cible

Events.OnTick.Add(function()
    _ticks = _ticks + 1

    local player    = getSpecificPlayer(0)
    local doRetarget = (_ticks % CFG.RETARGET == 0)
    local doCleanup  = (_ticks % CFG.CLEANUP  == 0)

    for npc, data in pairs(_npcs) do

        if doCleanup and not isValidNPC(npc) then
            _npcs[npc] = nil

        elseif data.followMode and player then

            -- Maintenir le mouvement chaque tick
            pcall(function()
                npc:getPathFindBehavior2():update()
            end)

            -- Recalculer la destination toutes les N ticks
            if doRetarget then
                pcall(function()
                    local dx   = npc:getX() - player:getX()
                    local dy   = npc:getY() - player:getY()
                    local dist = math.sqrt(dx * dx + dy * dy)

                    if dist <= CFG.FOLLOW_STOP then
                        -- Arrêt et regard vers le joueur
                        npc:getPathFindBehavior2():cancel()
                        npc:setPath2(nil)
                        npc:faceThisObject(player)
                    elseif dist <= CFG.FOLLOW_MAX then
                        -- Viser 2.5 cases derrière le joueur (pas de chevauchement)
                        local len = math.max(dist, 0.01)
                        local tx = player:getX() + (dx / len) * 2.5
                        local ty = player:getY() + (dy / len) * 2.5
                        npc:getPathFindBehavior2():pathToLocation(tx, ty, player:getZ())
                    else
                        -- Trop loin : annuler
                        npc:getPathFindBehavior2():cancel()
                        npc:setPath2(nil)
                    end
                end)
            end
        end
    end
end)

-- ============================================================
-- RESET SUR CHARGEMENT DE PARTIE
-- ============================================================

Events.OnGameStart.Add(function()
    _npcs  = {}
    _ticks = 0
    print("[PHNPC] NPC_FollowTick reinitialise (OnGameStart)")
end)

-- ============================================================
-- ENREGISTREMENT
-- ============================================================

Events.OnFillWorldObjectContextMenu.Add(onContextMenu)

print("[PHNPC] NPC_FollowTick v2.0 charge — moteur IsoPlayer B42")