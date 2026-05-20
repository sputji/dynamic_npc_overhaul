-- Project Humain: Dynamic NPC Overhaul - B42
-- client/NPC_FollowTick.lua v2.1
-- NPC spawn (IsoPlayer), follow, and context menu
-- Solo mode. No BOM. ASCII only in code and comments.

-- ============================================================
-- CONFIG
-- ============================================================

local STOP_DIST  = 3.0    -- stop following when closer than X tiles
local FOLLOW_MAX = 80.0   -- abandon follow when farther than X tiles
local RETARGET   = 10     -- recalculate path every N ticks
local CLEANUP    = 200    -- check for dead NPCs every N ticks

-- ============================================================
-- STATE
-- ============================================================

-- NPC registry: { [IsoPlayer] = { forename, surname, fullname, followMode, isFemale } }
PHNPC.npcs = PHNPC.npcs or {}
local _ticks = 0

-- ============================================================
-- VALIDATION
-- ============================================================

local function npcValid(npc)
    if not npc then return false end
    if not instanceof(npc, "IsoPlayer") then return false end
    local ok, dead = pcall(function() return npc:isDead() end)
    return ok and not dead
end

local function stopNPC(npc)
    pcall(function()
        npc:getPathFindBehavior2():cancel()
        npc:setPath2(nil)
    end)
end

-- ============================================================
-- INVENTORY
-- ============================================================

local function setupInventory(npc)
    pcall(function()
        local inv = npc:getInventory()
        inv:AddItem("Base.WaterBottleFull")
        inv:AddItem("Base.Bandage")
        local foodList = { "Base.Chips", "Base.Crackers", "Base.TunaCan" }
        inv:AddItem(foodList[ZombRand(3) + 1])
        if ZombRand(2) == 0 then inv:AddItem("Base.Knife") end
        if ZombRand(3) == 0 then inv:AddItem("Base.Flashlight") end
    end)
end

local function setupIDCard(npc, forename, surname)
    pcall(function()
        local inv  = npc:getInventory()
        local card = inv:AddItem("Base.IDCard")
        if card then
            card:setName(forename .. " " .. surname)
        end
    end)
end

-- ============================================================
-- SPAWN
-- ============================================================

local function spawnNPC(square, playerIndex)
    if not square then return end

    local cell = getWorld():getCell()
    if not cell then
        print("[PHNPC] ERROR spawnNPC: getCell() is nil")
        return
    end

    -- NPC limit check
    local count = 0
    for _ in pairs(PHNPC.npcs) do count = count + 1 end
    local cfg     = PHNPC.getModule("NPC_Config")
    local maxNPCs = (cfg and cfg.get("maxNPCs")) or 5
    if count >= maxNPCs then
        print("[PHNPC] NPC limit reached (" .. maxNPCs .. ")")
        return
    end

    -- Random gender + name
    local isFemale = (ZombRand(2) == 1)
    local forename = SurvivorFactory.getRandomForename(isFemale)
    local surname  = SurvivorFactory.getRandomSurname()

    -- Build human visual descriptor
    local desc = SurvivorFactory.CreateSurvivor(nil, isFemale)
    if not desc then
        print("[PHNPC] ERROR spawnNPC: SurvivorFactory.CreateSurvivor returned nil")
        return
    end
    desc:setForename(forename)
    desc:setSurname(surname)

    -- Random profession
    pcall(function()
        local plist = ProfessionFactory.getProfessions()
        if plist and plist:size() > 0 then
            local prof = plist:get(ZombRand(plist:size()))
            desc:setProfession(prof:getType())
            desc:setProfessionSkills(prof)
        end
    end)

    -- Floor level
    local z = 0
    pcall(function()
        if square:isSolidFloor() then
            z = square:getZ()
        end
    end)

    -- Create IsoPlayer entity (Bob/Kate animations, human sounds)
    local npc = IsoPlayer.new(cell, desc, square:getX(), square:getY(), z)
    if not npc then
        print("[PHNPC] ERROR spawnNPC: IsoPlayer.new returned nil")
        return
    end

    -- Configure NPC identity
    npc:setNPC(true)
    npc:setForname(forename)
    npc:setSurname(surname)
    npc:setUsername(forename .. " " .. surname)
    npc:setSceneCulled(false)
    npc:setDir(IsoDirections.SE)
    pcall(function() npc:setDressInRandomOutfit(false) end)

    -- Give starting items
    setupIDCard(npc, forename, surname)
    setupInventory(npc)

    -- Register NPC in global registry
    PHNPC.npcs[npc] = {
        isFemale   = isFemale,
        forename   = forename,
        surname    = surname,
        fullname   = forename .. " " .. surname,
        followMode = true,
    }

    print("[PHNPC] NPC spawned: " .. forename .. " " .. surname
        .. " (" .. (isFemale and "F" or "M") .. ")"
        .. " @ " .. math.floor(square:getX()) .. "," .. math.floor(square:getY()))
end

-- ============================================================
-- NPC ACTIONS (called from context menu callbacks)
-- ============================================================

local function npcStartFollow(npc)
    local data = PHNPC.npcs[npc]
    if data then data.followMode = true end
end

local function npcStopFollow(npc)
    local data = PHNPC.npcs[npc]
    if data then
        data.followMode = false
        stopNPC(npc)
    end
end

local function npcOpenDialogue(npc)
    local data = PHNPC.npcs[npc]
    if not data then return end
    if NPC_DialogueWindow and NPC_DialogueWindow.open then
        NPC_DialogueWindow.open(npc, data)
    else
        print("[PHNPC] Talk: " .. (data.fullname or "NPC"))
    end
end

-- ============================================================
-- CONTEXT MENU
-- ============================================================

local function onContextMenu(playerIndex, context, worldobjects, test)
    if test then return end

    local square = ISWorldObjectContextMenu.fetchVars.clickedSquare
    if not square then return end

    -- Find NPC near the clicked square
    local clickedNPC = nil
    for npc, _ in pairs(PHNPC.npcs) do
        if npcValid(npc) then
            local dx = npc:getX() - square:getX()
            local dy = npc:getY() - square:getY()
            if (dx * dx + dy * dy) <= 2.5 then
                clickedNPC = npc
                break
            end
        end
    end

    if clickedNPC then
        -- Options for the NPC
        local data  = PHNPC.npcs[clickedNPC]
        local pName = (data and data.fullname) or "NPC"
        context:addOption("Parler a " .. pName, clickedNPC, npcOpenDialogue)
        if data and data.followMode then
            context:addOption("[PHNPC] Reste ici", clickedNPC, npcStopFollow)
        else
            context:addOption("[PHNPC] Suis-moi", clickedNPC, npcStartFollow)
        end
    else
        -- Spawn option when no NPC nearby
        context:addOption("[PHNPC] Faire apparaitre un PNJ", square, spawnNPC, playerIndex)
    end
end

-- ============================================================
-- FOLLOW TICK
-- ============================================================

Events.OnTick.Add(function()
    _ticks = _ticks + 1

    local player     = getSpecificPlayer(0)
    local doRetarget = (_ticks % RETARGET == 0)
    local doCleanup  = (_ticks % CLEANUP  == 0)

    -- Cleanup dead/invalid NPCs (collect first, remove after iteration)
    if doCleanup then
        local dead = {}
        for npc in pairs(PHNPC.npcs) do
            if not npcValid(npc) then
                dead[#dead + 1] = npc
            end
        end
        for i = 1, #dead do
            print("[PHNPC] Cleanup: removing dead/invalid NPC")
            PHNPC.npcs[dead[i]] = nil
        end
    end

    -- Update follow behavior for each NPC
    for npc, data in pairs(PHNPC.npcs) do
        if data.followMode and player then

            -- Keep pathfinding active every tick
            pcall(function()
                npc:getPathFindBehavior2():update()
            end)

            -- Recalculate destination every RETARGET ticks
            if doRetarget then
                pcall(function()
                    local dx   = npc:getX() - player:getX()
                    local dy   = npc:getY() - player:getY()
                    local dist = math.sqrt(dx * dx + dy * dy)

                    if dist <= STOP_DIST then
                        stopNPC(npc)
                        pcall(function() npc:faceThisObject(player) end)
                    elseif dist <= FOLLOW_MAX then
                        local len = math.max(dist, 0.01)
                        local tx  = player:getX() + (dx / len) * 2.5
                        local ty  = player:getY() + (dy / len) * 2.5
                        npc:getPathFindBehavior2():pathToLocation(tx, ty, player:getZ())
                    else
                        stopNPC(npc)
                    end
                end)
            end

        end
    end
end)

-- ============================================================
-- RESET ON GAME START
-- ============================================================

Events.OnGameStart.Add(function()
    PHNPC.npcs = {}
    _ticks     = 0
    print("[PHNPC] NPC_FollowTick reset (OnGameStart)")
end)

-- ============================================================
-- REGISTER CONTEXT MENU EVENT
-- ============================================================

Events.OnFillWorldObjectContextMenu.Add(onContextMenu)
print("[PHNPC] NPC_FollowTick v2.1 loaded - IsoPlayer B42")