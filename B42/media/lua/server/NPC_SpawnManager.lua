--[[
    Project Humain : Dynamic NPC Overhaul — B42
    server/NPC_SpawnManager.lua

    Gestion du spawn / despawn des PNJ dynamiques.
    Utilise IsoPlayer.new() + SurvivorFactory (API B42).
    Cadence : Events.EveryOneMinute + garde de spawn radius.
]]

if not isServer() then return end

local Log        = PHNPC.getModule("NPC_Logger")
local Config     = PHNPC.getModule("NPC_Config")
local DataModel  = PHNPC.getModule("NPC_DataModel")
local Brain      = PHNPC.getModule("NPC_Brain")
local Factions   = PHNPC.getModule("NPC_FactionManager")
local Professions= PHNPC.getModule("NPC_Professions")
local Dispatcher = PHNPC.getModule("NPC_NetworkDispatcher")

local NPC_SpawnManager = {
    _active = {},   -- { [npcId] = NPCDataModel }
    _started = false,
}

-- ============================================================
-- Création d'un PNJ B42
-- ============================================================

--- Crée l'entité IsoPlayer (NPC) sur la case donnée.
-- @param  square  IsoGridSquare
-- @param  data    NPCDataModel
-- @return IsoPlayer | nil
local function createIsoNPC(square, data)
    if not square then return nil end

    -- Construction du descriptor B42
    local desc = SurvivorFactory.CreateSurvivor(nil, data.isFemale)
    desc:setForename(data.firstName)
    desc:setSurname(data.lastName)

    -- Profession native PZ
    local profId = data.professionId
    local profDef = Professions and Professions.get(profId)
    if profDef then
        -- Appliquer un outfit cohérent avec la profession
        local outfit = Professions.getOutfit(profId, data.isFemale)
        local ok, _ = pcall(function() desc:dressInNamedOutfit(outfit) end)
        if not ok then
            -- Fallback : outfit générique
            pcall(function() desc:dressInNamedOutfit(data.isFemale and "Civilian_F" or "Civilian_M") end)
        end
    end

    -- Calcul de la hauteur Z
    local z = 0
    if square:isSolidFloor() then z = square:getZ() end

    local iso = IsoPlayer.new(getWorld():getCell(), desc, square:getX(), square:getY(), z)
    if not iso then return nil end

    iso:setNPC(true)
    iso:setUsername(data.firstName .. data.lastName)
    iso:setSceneCulled(false)
    iso:setDir(IsoDirections.SE)

    -- Attache les données dans ModData de l'entité
    iso:getModData().PHNPC_id       = data.id
    iso:getModData().PHNPC_faction  = Factions.getFaction(data.id)

    data.isoObject = iso
    return iso
end

-- ============================================================
-- Spawn d'un nouveau PNJ près d'un joueur
-- ============================================================

local function spawnNearPlayer(player)
    local cfg  = Config.get()
    if #NPC_SpawnManager._active >= cfg.MaxActiveNPCs then return end

    local x  = player:getX()
    local y  = player:getY()
    local r  = cfg.SpawnRadius
    local attempts = cfg.SpawnAttemptsPerCycle or 6

    for _ = 1, attempts do
        local tx = x + PHNPC.randInt(-r, r)
        local ty = y + PHNPC.randInt(-r, r)
        local sq = getCell():getOrLoadGridSquare(tx, ty, 0)
        if sq and sq:isFree(false) and sq:isSolidFloor() then
            local data = DataModel.new()
            Factions.assign(data.id, "survivors")
            local iso  = createIsoNPC(sq, data)
            if iso then
                NPC_SpawnManager._active[data.id] = data
                Brain.register(data)
                -- Notifier les clients du spawn
                if Dispatcher then
                    Dispatcher.send("all", "npc_spawn", data:serialize())
                end
                Log.ok("NPC_SpawnManager", "PNJ spawné", { id = data.id, x = tx, y = ty })
                return
            end
        end
    end
end

-- ============================================================
-- Despawn : PNJ trop loin de tout joueur
-- ============================================================

local function despawnFarNPCs()
    local cfg = Config.get()
    local dr  = cfg.DespawnRadius
    local players = getOnlinePlayers()

    for npcId, data in pairs(NPC_SpawnManager._active) do
        local iso = data.isoObject
        if not iso then
            -- Objet perdu, nettoyer
            NPC_SpawnManager._active[npcId] = nil
            Brain.unregister(npcId)
        else
            local tooFar = true
            for i = 0, players:size() - 1 do
                local p = players:get(i)
                local dx = iso:getX() - p:getX()
                local dy = iso:getY() - p:getY()
                if (dx * dx + dy * dy) <= (dr * dr) then
                    tooFar = false
                    break
                end
            end
            if tooFar then
                iso:removeFromWorld()
                NPC_SpawnManager._active[npcId] = nil
                Brain.unregister(npcId)
                if Dispatcher then
                    Dispatcher.send("all", "npc_despawn", { id = npcId })
                end
                Log.debug("NPC_SpawnManager", "PNJ despawné (trop loin)", { id = npcId })
            end
        end
    end
end

-- ============================================================
-- Boucle de spawn (toutes les minutes)
-- ============================================================

local function onEveryMinute()
    local players = getOnlinePlayers()
    for i = 0, players:size() - 1 do
        spawnNearPlayer(players:get(i))
    end
    despawnFarNPCs()
end

-- ============================================================
-- API publique
-- ============================================================

function NPC_SpawnManager.start()
    if NPC_SpawnManager._started then return end
    Events.EveryOneMinute.Add(onEveryMinute)
    NPC_SpawnManager._started = true
    Log.ok("NPC_SpawnManager", "SpawnManager démarré.")
end

--- Retourne la liste des PNJ actifs.
function NPC_SpawnManager.getActive()
    return NPC_SpawnManager._active
end

--- Retourne un PNJ actif par ID.
function NPC_SpawnManager.getById(npcId)
    return NPC_SpawnManager._active[npcId]
end

PHNPC.registerModule("NPC_SpawnManager", NPC_SpawnManager)
return NPC_SpawnManager
