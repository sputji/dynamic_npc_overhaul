-- Project Humain: Dynamic NPC Overhaul - B42
-- client/PHNPC_Manager.lua
-- NPC spawn, pathfinding tick, context menu.
-- Method: IsoPlayer.new() directly on client, no network dispatcher.
-- Pattern sourced from "7 - Custom NPC" (CnpcHuman.lua / ISHumanWalk.lua).
-- NO BOM. ASCII only.

-- ============================================================
-- CONFIG
-- ============================================================
local STOP_DIST   = 3   -- tiles: stop following when this close to player
local RETARGET    = 15  -- ticks: re-issue pathToLocation every N ticks
local CLEANUP     = 300 -- ticks: check dead NPCs every N ticks
local MAX_NPCS    = 10  -- maximum simultaneous NPCs

-- ============================================================
-- STATE
-- ============================================================
-- PHNPC.npcs[IsoPlayer] = { id, forename, surname, fullname, isFemale, followMode }
-- Initialised on OnGameStart to clear previous session data.
local _ticks = 0

-- ============================================================
-- NPC VALIDITY
-- ============================================================
local function npcValid(npc)
    if not npc then return false end
    if not instanceof(npc, "IsoPlayer") then return false end
    local ok, dead = pcall(function() return npc:isDead() end)
    return ok and not dead
end

-- ============================================================
-- MOVEMENT HELPERS
-- Pattern: ISHumanWalk (Custom NPC mod)
--   start  : npc:getPathFindBehavior2():pathToLocation(x, y, z)
--   update : npc:getPathFindBehavior2():update()  (called every tick)
--   cancel : npc:getPathFindBehavior2():cancel() + npc:setPath2(nil)
-- ============================================================
local function npcMoveTo(npc, x, y, z)
    pcall(function()
        npc:getPathFindBehavior2():pathToLocation(x, y, z)
    end)
end

local function npcUpdatePath(npc)
    pcall(function()
        npc:getPathFindBehavior2():update()
    end)
end

local function npcStopMoving(npc)
    pcall(function()
        npc:getPathFindBehavior2():cancel()
        npc:setPath2(nil)
    end)
end

-- ============================================================
-- NPC CREATION
-- Pattern: CnpcHuman.newIsoHuman + CnpcHuman.newHumanDescObj (Custom NPC mod)
-- ============================================================
local function createNPC(square)
    -- Floor check (same guard as Custom NPC to prevent mid-air spawn)
    local squareZ = 0
    if square:isSolidFloor() then
        squareZ = square:getZ()
    end

    local isFemale = (ZombRand(2) == 1)
    local forename = SurvivorFactory.getRandomForename(isFemale)
    local surname  = SurvivorFactory.getRandomSurname()
    local ts       = tostring(getTimestampMs())
    local npcId    = "PHNPC_" .. forename .. "_" .. surname .. "_" .. ts

    -- Build human visual descriptor (Bob/Kate skeleton for proper animations)
    local ok1, desc = pcall(function()
        return SurvivorFactory.CreateSurvivor(nil, isFemale)
    end)
    if not ok1 or not desc then
        print("[PHNPC] createNPC: SurvivorFactory.CreateSurvivor failed")
        return
    end
    desc:setForename(forename)
    desc:setSurname(surname)

    -- Random profession for outfit variety
    pcall(function()
        local profs = ProfessionFactory.getProfessions()
        if profs and profs:size() > 0 then
            local prof = profs:get(ZombRand(profs:size()))
            desc:setProfession(prof:getType())
            desc:setProfessionSkills(prof)
        end
    end)

    -- Spawn IsoPlayer entity (exact pattern from CnpcHuman.newIsoHuman)
    local ok2, npc = pcall(function()
        return IsoPlayer.new(getWorld():getCell(), desc, square:getX(), square:getY(), squareZ)
    end)
    if not ok2 or not npc then
        print("[PHNPC] createNPC: IsoPlayer.new failed")
        return
    end

    npc:getModData().PHNPC_ID = npcId
    npc:setUsername(forename .. " " .. surname)
    npc:setNPC(true)
    npc:setSceneCulled(false)
    npc:setDir(IsoDirections.SE)

    -- Basic starting inventory
    pcall(function()
        local inv = npc:getInventory()
        inv:AddItem("Base.WaterBottleFull")
        inv:AddItem("Base.Bandage")
        local foods = { "Base.Chips", "Base.Crackers", "Base.TunaCan" }
        inv:AddItem(foods[ZombRand(3) + 1])
        if ZombRand(2) == 0 then inv:AddItem("Base.Knife") end
    end)

    -- Store in active NPC table
    PHNPC.npcs[npc] = {
        id         = npcId,
        forename   = forename,
        surname    = surname,
        fullname   = forename .. " " .. surname,
        isFemale   = isFemale,
        followMode = true,
        retarget   = 0,   -- countdown to next pathToLocation call
    }

    print("[PHNPC] NPC spawned: " .. forename .. " " .. surname
        .. " (" .. (isFemale and "F" or "M") .. ")"
        .. " @ " .. square:getX() .. "," .. square:getY())
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
-- CONTEXT MENU ACTIONS (existing NPCs)
-- ============================================================
local function startFollow(npc)
    local d = PHNPC.npcs[npc]
    if not d then return end
    d.followMode = true
    d.retarget   = 0
    print("[PHNPC] " .. d.fullname .. " : suit le joueur")
end

local function stopFollow(npc)
    local d = PHNPC.npcs[npc]
    if not d then return end
    d.followMode = false
    npcStopMoving(npc)
    print("[PHNPC] " .. d.fullname .. " : reste ici")
end

local function removeNPC(npc)
    local d = PHNPC.npcs[npc]
    if d then print("[PHNPC] Suppression: " .. d.fullname) end
    npcStopMoving(npc)
    pcall(function() npc:removeFromWorld() end)
    PHNPC.npcs[npc] = nil
end

-- ============================================================
-- CONTEXT MENU
-- Pattern: Events.OnPreFillWorldObjectContextMenu (Custom NPC mod)
-- ============================================================
local function onContextMenu(playerIndex, context, worldobjects, test)
    if test then return end

    local square = ISWorldObjectContextMenu.fetchVars.clickedSquare
    if not square then return end

    -- Detect NPC on or near the clicked square (1 tile radius)
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
        -- Options for existing NPC
        local d = PHNPC.npcs[clickedNPC]
        local name = (d and d.fullname) or "PNJ"
        if d and d.followMode then
            context:addOption("[PHNPC] " .. name .. " : Reste ici", clickedNPC, stopFollow)
        else
            context:addOption("[PHNPC] " .. name .. " : Suis-moi", clickedNPC, startFollow)
        end
        context:addOption("[PHNPC] Supprimer " .. name, clickedNPC, removeNPC)
    else
        -- Spawn option on empty ground
        context:addOption("[PHNPC] Faire apparaitre un PNJ", square, spawnNPC, playerIndex)
    end
end

-- ============================================================
-- MAIN TICK
-- Every tick: update pathfinding for all NPCs.
-- Every RETARGET ticks: re-issue pathToLocation toward player.
-- Every CLEANUP ticks: remove dead/invalid NPCs.
-- Pattern: Events.OnRenderTick (Custom NPC) / Events.OnTick
-- ============================================================
Events.OnTick.Add(function()
    _ticks = _ticks + 1

    local player     = getSpecificPlayer(0)
    local doCleanup  = (_ticks % CLEANUP == 0)

    -- ---- Cleanup pass ----
    if doCleanup then
        local dead = {}
        for npc in pairs(PHNPC.npcs) do
            if not npcValid(npc) then
                dead[#dead + 1] = npc
            end
        end
        for i = 1, #dead do
            local d = PHNPC.npcs[dead[i]]
            print("[PHNPC] Cleanup NPC mort: " .. (d and d.fullname or "?"))
            PHNPC.npcs[dead[i]] = nil
        end
    end

    -- ---- Movement pass ----
    for npc, data in pairs(PHNPC.npcs) do
        if not npcValid(npc) then
            -- handled next cleanup
        elseif data.followMode and player then
            local px = player:getX()
            local py = player:getY()
            local pz = player:getZ()
            local dx = npc:getX() - px
            local dy = npc:getY() - py
            local dist = math.sqrt(dx * dx + dy * dy)

            if dist > STOP_DIST then
                -- Re-issue pathToLocation periodically
                data.retarget = data.retarget - 1
                if data.retarget <= 0 then
                    data.retarget = RETARGET
                    npcMoveTo(npc, px, py, pz)
                end
                -- Update path every tick (mandatory for IsoPlayer pathfinding)
                npcUpdatePath(npc)
            else
                -- Close enough: stop and reset retarget
                if data.retarget ~= 999 then
                    npcStopMoving(npc)
                    data.retarget = 999
                end
            end
        else
            -- followMode OFF: just keep path system updated so NPC doesn't freeze
            npcUpdatePath(npc)
        end
    end
end)

-- ============================================================
-- GAME START: reset NPC table for new session
-- ============================================================
Events.OnGameStart.Add(function()
    PHNPC.npcs = {}
    _ticks = 0
    print("[PHNPC] PHNPC_Manager v3.0 pret (OnGameStart)")
end)

-- ============================================================
-- REGISTER CONTEXT MENU
-- ============================================================
Events.OnPreFillWorldObjectContextMenu.Add(onContextMenu)

print("[PHNPC] PHNPC_Manager v3.0 loaded")
