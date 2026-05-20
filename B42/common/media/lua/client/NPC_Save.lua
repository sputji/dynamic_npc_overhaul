-- Project Humain: Dynamic NPC Overhaul - B42
-- client/NPC_Save.lua v1.0
-- Persistence: ModData (registry) + soul:save/load (IsoPlayer full state)
-- NO BOM. ASCII only. Solo and Multiplayer compatible.

-- ============================================================
-- CONSTANTS
-- ============================================================

local REGISTRY_KEY = "PHNPC_Registry"

local NPC_Save = {}

-- ============================================================
-- SAVE DIR
-- ============================================================

local function getSaveDir()
    local sep = getFileSeparator()
    return Core.getMyDocumentFolder()
        .. sep .. "Saves"
        .. sep .. getWorld():getGameMode()
        .. sep .. getWorld():getWorld()
        .. sep
end

-- ============================================================
-- SAVE ALL NPCs
-- ============================================================

function NPC_Save.saveAll()
    if not (getWorld and getWorld()) then return end
    local ok, saveDir = pcall(getSaveDir)
    if not ok or not saveDir then return end

    local reg = ModData.getOrCreate(REGISTRY_KEY)

    -- Remove registry entries that no longer have an active NPC
    local activeIds = {}
    for _, data in pairs(PHNPC.npcs) do
        if data.id then activeIds[data.id] = true end
    end
    for id in pairs(reg) do
        if not activeIds[id] then reg[id] = nil end
    end

    -- Save each alive NPC
    local saved = 0
    for npc, data in pairs(PHNPC.npcs) do
        if instanceof(npc, "IsoPlayer") and data.id then
            local alive = false
            pcall(function() alive = not npc:isDead() end)
            if alive then
                -- Capture current position
                data.squareX = npc:getX()
                data.squareY = npc:getY()
                data.squareZ = npc:getZ()
                local fsmState = "idle"
                if data.dataModel then fsmState = data.dataModel.fsmState or "idle" end

                -- Write registry entry
                reg[data.id] = {
                    id         = data.id,
                    forename   = data.forename,
                    surname    = data.surname,
                    isFemale   = data.isFemale,
                    followMode = data.followMode,
                    fsmState   = fsmState,
                    squareX    = data.squareX,
                    squareY    = data.squareY,
                    squareZ    = data.squareZ,
                    isAlive    = true,
                }

                -- Save full IsoPlayer state (appearance, skills, inventory)
                pcall(function()
                    npc:getModData().PHNPC_ID = data.id
                    npc:save(saveDir .. data.id)
                end)
                saved = saved + 1
                print("[PHNPC] Save: " .. data.forename .. " " .. data.surname)
            end
        end
    end

    ModData.transmit(REGISTRY_KEY)
    print("[PHNPC] NPC_Save.saveAll: " .. saved .. " NPCs saved.")
end

-- ============================================================
-- LOAD ALL NPCs
-- ============================================================

function NPC_Save.loadAll()
    if not (getWorld and getWorld()) then return end
    local ok, saveDir = pcall(getSaveDir)
    if not ok or not saveDir then return end

    local cell = getWorld():getCell()
    if not cell then return end

    local reg = ModData.getOrCreate(REGISTRY_KEY)
    if not reg then return end

    local Brain = PHNPC.getModule("NPC_Brain")
    local loaded = 0

    for id, entry in pairs(reg) do
        if entry.isAlive then
            local npcFileName = saveDir .. id
            if not fileExists(npcFileName) then
                print("[PHNPC] Load: save file missing, removing " .. id)
                reg[id] = nil
            else
                local isFemale = entry.isFemale
                local ok2, desc = pcall(function()
                    return SurvivorFactory.CreateSurvivor(nil, isFemale)
                end)
                if ok2 and desc then
                    desc:setForename(entry.forename)
                    desc:setSurname(entry.surname)
                    local ok3, npc = pcall(function()
                        return IsoPlayer.new(cell, desc,
                            entry.squareX, entry.squareY, entry.squareZ)
                    end)
                    if ok3 and npc then
                        -- Restore full IsoPlayer state
                        pcall(function() npc:load(npcFileName) end)
                        npc:setNPC(true)
                        npc:setForname(entry.forename)
                        npc:setSurname(entry.surname)
                        npc:setUsername(entry.forename .. " " .. entry.surname)
                        npc:setSceneCulled(false)
                        npc:setDir(IsoDirections.SE)

                        -- Build NPC data entry
                        local npcData = {
                            id         = entry.id,
                            forename   = entry.forename,
                            surname    = entry.surname,
                            fullname   = entry.forename .. " " .. entry.surname,
                            isFemale   = entry.isFemale,
                            followMode = entry.followMode or false,
                            fsmState   = entry.fsmState or "idle",
                            squareX    = entry.squareX,
                            squareY    = entry.squareY,
                            squareZ    = entry.squareZ,
                        }

                        -- Register in NPC_Brain (provides FSM updates)
                        if Brain then
                            local modelData = {
                                id           = entry.id,
                                fsmState     = entry.fsmState or "idle",
                                isoObject    = npc,
                                hunger       = 50,
                                thirst       = 50,
                                fatigue      = 20,
                                morale       = 70,
                                stress       = 0,
                                trauma       = 0,
                                followMode   = entry.followMode or false,
                                professionId = "explorer",
                            }
                            Brain.register(modelData)
                            npcData.dataModel = modelData
                        end

                        PHNPC.npcs[npc] = npcData
                        loaded = loaded + 1
                        print("[PHNPC] Load: " .. entry.forename .. " " .. entry.surname)
                    end
                end
            end
        end
    end

    print("[PHNPC] NPC_Save.loadAll: " .. loaded .. " NPCs restored.")
end

-- ============================================================
-- EVENT HOOKS
-- ============================================================

-- Save on every game save
Events.OnSave.Add(function()
    NPC_Save.saveAll()
end)

-- Load NPCs one tick after OnGameStart so the world cell is ready
local _loadPending = false
local _loadDone    = false

Events.OnGameStart.Add(function()
    _loadPending = true
    _loadDone    = false
end)

Events.OnTick.Add(function()
    if _loadPending and not _loadDone then
        _loadDone    = true
        _loadPending = false
        NPC_Save.loadAll()
    end
end)

-- ============================================================
-- MODULE REGISTRATION
-- ============================================================

PHNPC.registerModule("NPC_Save", NPC_Save)
return NPC_Save