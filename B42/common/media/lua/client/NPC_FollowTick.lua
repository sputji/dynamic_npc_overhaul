-- Project Humain: Dynamic NPC Overhaul - B42
-- client/NPC_FollowTick.lua v2.2
-- NPC spawn (via NetworkDispatcher), Brain FSM integration, follow/wander/flee behavior.
-- NO BOM. ASCII only.

-- ============================================================
-- CONFIG
-- ============================================================

local STOP_DIST  = 3.0    -- stop following when closer than X tiles
local FOLLOW_MAX = 80.0   -- abandon follow when farther than X tiles
local RETARGET   = 10     -- recalculate path every N ticks
local CLEANUP    = 200    -- check for dead NPCs every N ticks
local WANDER_R   = 8      -- wander radius in tiles

-- ============================================================
-- STATE
-- ============================================================

-- PHNPC.npcs[IsoPlayer] = {
--   id, forename, surname, fullname, isFemale,
--   followMode, fsmState, squareX, squareY, squareZ,
--   wander_target,
--   dataModel (reference to NPC_Brain model data)
-- }
PHNPC.npcs = PHNPC.npcs or {}
local _ticks = 0

-- ============================================================
-- HELPERS
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
-- NPC CREATION (called by PHNPC_DoSpawn handler)
-- ============================================================

local function createNPCFromData(data)
    if not data then return end
    local cell = getWorld and getWorld():getCell()
    if not cell then
        print("[PHNPC] createNPCFromData: getCell() is nil")
        return
    end

    local isFemale = data.isFemale
    local forename = data.forename
    local surname  = data.surname

    -- Build human visual descriptor (Bob/Kate animations)
    local ok1, desc = pcall(function()
        return SurvivorFactory.CreateSurvivor(nil, isFemale)
    end)
    if not ok1 or not desc then
        print("[PHNPC] createNPCFromData: SurvivorFactory returned nil")
        return
    end
    desc:setForename(forename)
    desc:setSurname(surname)

    -- Apply a random profession for visual outfit variety
    pcall(function()
        local plist = ProfessionFactory.getProfessions()
        if plist and plist:size() > 0 then
            local prof = plist:get(ZombRand(plist:size()))
            desc:setProfession(prof:getType())
            desc:setProfessionSkills(prof)
        end
    end)

    -- Create IsoPlayer entity (human animations and sounds)
    local ok2, npc = pcall(function()
        return IsoPlayer.new(cell, desc, data.x, data.y, data.z)
    end)
    if not ok2 or not npc then
        print("[PHNPC] createNPCFromData: IsoPlayer.new returned nil")
        return
    end

    npc:setNPC(true)
    npc:setForname(forename)
    npc:setSurname(surname)
    npc:setUsername(forename .. " " .. surname)
    npc:setSceneCulled(false)
    npc:setDir(IsoDirections.SE)
    pcall(function() npc:setDressInRandomOutfit(false) end)

    setupIDCard(npc, forename, surname)
    setupInventory(npc)

    -- Build NPC data entry
    local npcData = {
        id         = data.id,
        forename   = forename,
        surname    = surname,
        fullname   = forename .. " " .. surname,
        isFemale   = isFemale,
        followMode = true,
        fsmState   = "idle",
        squareX    = data.x,
        squareY    = data.y,
        squareZ    = data.z,
    }

    -- Register in NPC_Brain (provides autonomous FSM behavior)
    local Brain = PHNPC.getModule("NPC_Brain")
    if Brain then
        local modelData = {
            id           = data.id,
            fsmState     = "idle",
            isoObject    = npc,
            hunger       = 50,
            thirst       = 50,
            fatigue      = 20,
            morale       = 70,
            stress       = 0,
            trauma       = 0,
            followMode   = true,
            professionId = "explorer",
        }
        Brain.register(modelData)
        npcData.dataModel = modelData
    end

    PHNPC.npcs[npc] = npcData
    print("[PHNPC] NPC created: " .. forename .. " " .. surname
        .. " (" .. (isFemale and "F" or "M") .. ")"
        .. " @ " .. math.floor(data.x) .. "," .. math.floor(data.y))
end

-- ============================================================
-- SPAWN REQUEST (context menu → sends to server via dispatcher)
-- ============================================================

local function spawnNPC(square, playerIndex)
    if not square then return end

    -- NPC limit check
    local count = 0
    for _ in pairs(PHNPC.npcs) do count = count + 1 end
    local cfg     = PHNPC.getModule("NPC_Config")
    local maxNPCs = (cfg and cfg.get("maxNPCs")) or 5
    if count >= maxNPCs then
        print("[PHNPC] NPC limit reached (" .. maxNPCs .. ")")
        return
    end

    local x, y, z = square:getX(), square:getY(), 0
    pcall(function()
        if square:isSolidFloor() then z = square:getZ() end
    end)

    -- SOLO: NPC_NetworkDispatcher routes request directly to NPC_SpawnManager handler,
    -- which immediately broadcasts PHNPC_DoSpawn back to this same client.
    -- MULTI: request travels to the server, server broadcasts to all clients.
    local Dispatcher = PHNPC.getModule("NPC_NetworkDispatcher")
    if Dispatcher then
        Dispatcher.send("server", "PHNPC_RequestSpawn", { x = x, y = y, z = z })
    else
        -- Fallback (dispatcher not loaded yet): create directly
        local isFemale = (ZombRand(2) == 1)
        local forename = SurvivorFactory.getRandomForename(isFemale)
        local surname  = SurvivorFactory.getRandomSurname()
        local id = "PHNPC_" .. forename .. "_" .. surname .. "_" .. tostring(os.time())
        createNPCFromData({
            id = id, forename = forename, surname = surname,
            isFemale = isFemale, x = x, y = y, z = z,
        })
    end
end

-- ============================================================
-- NETWORK HANDLER: receive spawn command from server
-- ============================================================

local function registerNetworkHandlers()
    local Dispatcher = PHNPC.getModule("NPC_NetworkDispatcher")
    if not Dispatcher then
        print("[PHNPC] NPC_FollowTick: NPC_NetworkDispatcher not available, fallback to direct spawn")
        return
    end
    -- Server sends PHNPC_DoSpawn to all clients; each client creates the IsoPlayer locally
    Dispatcher.on("PHNPC_DoSpawn", function(data)
        createNPCFromData(data)
    end)
    print("[PHNPC] NPC_FollowTick: PHNPC_DoSpawn handler registered")
end

-- Delay registration so shared modules are fully loaded
Events.OnGameStart.Add(function()
    PHNPC.npcs = {}
    _ticks = 0
    registerNetworkHandlers()
    print("[PHNPC] NPC_FollowTick reset (OnGameStart)")
end)

-- ============================================================
-- NPC ACTIONS (called from context menu callbacks)
-- ============================================================

local function npcStartFollow(npc)
    local data = PHNPC.npcs[npc]
    if not data then return end
    data.followMode = true
    if data.dataModel then data.dataModel.followMode = true end
    print("[PHNPC] " .. (data.fullname or "NPC") .. " : follow mode ON")
end

local function npcStopFollow(npc)
    local data = PHNPC.npcs[npc]
    if not data then return end
    data.followMode = false
    if data.dataModel then
        data.dataModel.followMode = false
        -- Resume autonomous Brain behavior
        if data.dataModel.fsmState == "idle" then
            data.dataModel.fsmState = "wander"
            data.fsmState = "wander"
        end
    end
    stopNPC(npc)
    print("[PHNPC] " .. (data.fullname or "NPC") .. " : follow mode OFF (FSM wander)")
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
        local data  = PHNPC.npcs[clickedNPC]
        local pName = (data and data.fullname) or "NPC"
        context:addOption("Parler a " .. pName, clickedNPC, npcOpenDialogue)
        if data and data.followMode then
            context:addOption("[PHNPC] Reste ici", clickedNPC, npcStopFollow)
        else
            context:addOption("[PHNPC] Suis-moi", clickedNPC, npcStartFollow)
        end
    else
        context:addOption("[PHNPC] Faire apparaitre un PNJ", square, spawnNPC, playerIndex)
    end
end

-- ============================================================
-- MAIN TICK: Follow + FSM behavior
-- ============================================================

Events.OnTick.Add(function()
    _ticks = _ticks + 1

    local player     = getSpecificPlayer(0)
    local doRetarget = (_ticks % RETARGET == 0)
    local doCleanup  = (_ticks % CLEANUP  == 0)

    -- Cleanup dead/invalid NPCs
    if doCleanup then
        local dead = {}
        for npc in pairs(PHNPC.npcs) do
            if not npcValid(npc) then
                dead[#dead + 1] = npc
            end
        end
        local Brain = PHNPC.getModule("NPC_Brain")
        for i = 1, #dead do
            local d = PHNPC.npcs[dead[i]]
            if d and d.id and Brain then
                Brain.unregister(d.id)
            end
            PHNPC.npcs[dead[i]] = nil
            print("[PHNPC] Cleanup: removed dead NPC")
        end
    end

    -- Behavior tick for each NPC
    for npc, data in pairs(PHNPC.npcs) do
        -- Resolve current FSM state from Brain model (authoritative) or fallback to local
        local fsmState = "idle"
        if data.dataModel then
            fsmState = data.dataModel.fsmState or "idle"
        else
            fsmState = data.fsmState or "idle"
        end

        if data.followMode then
            -- ------------------------------------------------
            -- FOLLOW PLAYER (player-commanded override)
            -- ------------------------------------------------
            pcall(function()
                npc:getPathFindBehavior2():update()
            end)
            if doRetarget and player then
                pcall(function()
                    local dx   = npc:getX() - player:getX()
                    local dy   = npc:getY() - player:getY()
                    local dist = math.sqrt(dx * dx + dy * dy)
                    if dist <= STOP_DIST then
                        stopNPC(npc)
                        npc:faceThisObject(player)
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

        elseif fsmState == "wander" then
            -- ------------------------------------------------
            -- WANDER: random walk within WANDER_R tiles
            -- ------------------------------------------------
            pcall(function()
                npc:getPathFindBehavior2():update()
            end)
            if doRetarget then
                pcall(function()
                    -- Check arrival at wander target
                    local wt = data.wander_target
                    if wt then
                        local dx = npc:getX() - wt.x
                        local dy = npc:getY() - wt.y
                        if (dx * dx + dy * dy) < 2.0 then
                            data.wander_target = nil
                        end
                    end
                    -- Pick new target if none
                    if not data.wander_target then
                        data.wander_target = {
                            x = npc:getX() + ZombRand(WANDER_R * 2) - WANDER_R,
                            y = npc:getY() + ZombRand(WANDER_R * 2) - WANDER_R,
                        }
                    end
                    npc:getPathFindBehavior2():pathToLocation(
                        data.wander_target.x,
                        data.wander_target.y,
                        npc:getZ()
                    )
                end)
            end

        elseif fsmState == "flee" then
            -- ------------------------------------------------
            -- FLEE: move away from threat stored in dataModel.fsmTarget
            -- ------------------------------------------------
            pcall(function()
                npc:getPathFindBehavior2():update()
            end)
            if doRetarget then
                pcall(function()
                    local nx, ny  = npc:getX(), npc:getY()
                    local threat  = data.dataModel and data.dataModel.fsmTarget
                    local tx, ty
                    if threat then
                        local dx   = nx - threat.x
                        local dy   = ny - threat.y
                        local dist = math.max(math.sqrt(dx * dx + dy * dy), 0.01)
                        tx = nx + (dx / dist) * 15
                        ty = ny + (dy / dist) * 15
                    else
                        tx = nx + ZombRand(20) - 10
                        ty = ny + ZombRand(20) - 10
                    end
                    npc:getPathFindBehavior2():pathToLocation(tx, ty, npc:getZ())
                end)
            end

        else
            -- ------------------------------------------------
            -- IDLE / WORK / TRADE / DEFEND / GUARD
            -- Stand still; face player if nearby
            -- ------------------------------------------------
            if doRetarget and player then
                pcall(function()
                    local dx = npc:getX() - player:getX()
                    local dy = npc:getY() - player:getY()
                    if (dx * dx + dy * dy) < 100 then  -- within 10 tiles
                        npc:faceThisObject(player)
                    end
                end)
            end
        end
    end
end)

-- ============================================================
-- REGISTER CONTEXT MENU
-- ============================================================

Events.OnFillWorldObjectContextMenu.Add(onContextMenu)

print("[PHNPC] NPC_FollowTick v2.2 loaded - IsoPlayer + NPC_Brain + NetworkDispatcher")