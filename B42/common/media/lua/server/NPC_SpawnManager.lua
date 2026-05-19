--[[
    Project Humain : Dynamic NPC Overhaul — B42
    server/NPC_SpawnManager.lua

    Gestionnaire de spawn côté serveur.

    Reçoit la commande "PHNPC_SpawnRequest" envoyée par le client admin,
    valide la requête, exécute le spawn via addZombiesInOutfit, marque
    l'entité en ModData, puis répond au client via sendServerCommand.

    Flux de données :
      client (NPC_SpawnDebug) ─sendClientCommand──► Events.OnClientCommand (ici)
                                                         │
                                             addZombiesInOutfit(x,y,z,1,outfit,%)
                                                         │
                                             zombie:getModData() ← PHNPC_IsNPC = true
                                                         │
                             sendServerCommand ◄──────── PHNPC_SpawnConfirm
                                                         │
      client (NPC_FollowTick) ◄── Events.OnZombieUpdate picks up the new zombie
                                   and converts it (visuals + DataModel)

    En solo, Events.OnClientCommand est déclenché dans le même état Lua
    que le client (appel synchrone, pas de réseau).

    Note B42 API réseau :
      CLIENT→SERVEUR : sendClientCommand(getPlayer(), module, cmd, args)
                       déclenche Events.OnClientCommand côté serveur.
      SERVEUR→CLIENT : sendServerCommand(player, module, cmd, args)
                       déclenche Events.OnServerCommand côté client.
]]

local NPC_SpawnManager = {}

-- Outfits disponibles (cohérent avec client/NPC_SpawnDebug.lua)
local OUTFITS = { "Farmer", "Police", "Fireman", "Doctor", "Ranger", "Chef", "Survivor" }

-- Rayon de recherche d'une case libre autour des coordonnées du joueur
local SEARCH_RADIUS = 6

-- ============================================================
-- Helpers
-- ============================================================

--- Cherche une case libre à portée de marche autour de (px, py, pz).
-- @return IsoGridSquare ou nil
local function findFreeSquare(px, py, pz)
    local cell = getCell()
    if not cell then return nil end

    local ipx = math.floor(px)
    local ipy = math.floor(py)
    local ipz = math.floor(pz)

    for r = 2, SEARCH_RADIUS do
        for dx = -r, r do
            for dy = -r, r do
                -- Seulement le bord de l'anneau (évite de re-parcourir le centre)
                if math.abs(dx) == r or math.abs(dy) == r then
                    local sq = cell:getGridSquare(ipx + dx, ipy + dy, ipz)
                    if sq and sq:isFree(false) and not sq:isSolid() then
                        return sq
                    end
                end
            end
        end
    end
    return nil
end

-- ============================================================
-- Handler principal : Events.OnClientCommand
-- ============================================================

local function onClientCommand(module, command, player, args)
    -- Filtrer : uniquement les commandes de ce mod
    if module ~= PHNPC.MOD_ID then return end
    if command ~= "PHNPC_SpawnRequest" then return end

    local Log = PHNPC.getModule("NPC_Logger")

    -- ---- Validation admin ----
    local isAdmin = false
    pcall(function() isAdmin = player:isAccessLevel("admin") end)

    if not isAdmin and not getDebug() then
        if Log then
            Log.warn("Server/SpawnManager", "Spawn refusé — joueur non admin",
                { player = tostring(player:getUsername()) })
        end
        sendServerCommand(player, PHNPC.MOD_ID, "PHNPC_SpawnConfirm", { success = false })
        return
    end

    -- ---- Extraction des paramètres ----
    local reqX = tonumber(args and args.x) or player:getX()
    local reqY = tonumber(args and args.y) or player:getY()
    local reqZ = tonumber(args and args.z) or player:getZ()

    if Log then
        Log.info("Server/SpawnManager", "PHNPC_SpawnRequest reçu",
            { from = tostring(player:getUsername()), x = math.floor(reqX), y = math.floor(reqY) })
    end

    -- ---- Trouver une case libre ----
    local sq = findFreeSquare(reqX, reqY, reqZ)
    if not sq then
        if Log then
            Log.warn("Server/SpawnManager", "Aucune case libre trouvée", { x = reqX, y = reqY })
        end
        sendServerCommand(player, PHNPC.MOD_ID, "PHNPC_SpawnConfirm", { success = false })
        return
    end

    local spawnX = sq:getX()
    local spawnY = sq:getY()
    local spawnZ = sq:getZ()

    -- ---- Choix de l'outfit et du genre ----
    local outfit    = OUTFITS[PHNPC.randInt(1, #OUTFITS)]
    local isFemale  = PHNPC.randInt(0, 1) == 1
    local femaleChance = isFemale and 100 or 0

    -- ---- Spawn de l'entité ----
    local zombieList = nil
    local spawnOk, spawnErr = pcall(function()
        zombieList = addZombiesInOutfit(spawnX, spawnY, spawnZ, 1, outfit, femaleChance)
    end)

    if not spawnOk or not zombieList or zombieList:size() == 0 then
        if Log then
            Log.error("Server/SpawnManager", "addZombiesInOutfit échoué",
                { err = tostring(spawnErr) })
        end
        sendServerCommand(player, PHNPC.MOD_ID, "PHNPC_SpawnConfirm", { success = false })
        return
    end

    local zombie = zombieList:get(0)
    if not zombie then
        if Log then Log.error("Server/SpawnManager", "Zombie nil après addZombiesInOutfit") end
        sendServerCommand(player, PHNPC.MOD_ID, "PHNPC_SpawnConfirm", { success = false })
        return
    end

    -- ---- Marquage Java cross-VM (PRIORITAIRE sur ModData) ----
    -- En B42, serveur et client ont des VMs Lua séparées même en solo.
    -- zombie:setVariable() stocke côté Java (IsoEntity) et est lisible
    -- depuis n'importe quelle VM via getVariableBoolean() / getVariableString().
    pcall(function()
        zombie:setVariable("PHNPC_IsNPC",    true)
        zombie:setVariable("PHNPC_IsFemale", isFemale)
        zombie:setVariable("PHNPC_Outfit",   outfit)
    end)

    -- ---- Marquage ModData (détecté par client/NPC_FollowTick via OnZombieUpdate) ----
    -- On écrit uniquement les données stables ici ; la conversion visuelle
    -- (setWalkType, setHumanVisual, etc.) est laissée au client.
    local DataModel = PHNPC.getModule("NPC_DataModel")
    local npcData = DataModel and DataModel.new({ isFemale = isFemale })

    local md = zombie:getModData()
    md.PHNPC_IsNPC     = true
    md.PHNPC_IsFemale  = isFemale
    md.PHNPC_Outfit    = outfit
    md.PHNPC_ShowTimer = 5  -- ticks de stabilisation avant activation de l'IA

    if npcData then
        md.PHNPC_ID         = npcData.id
        md.PHNPC_FullName   = npcData.fullName
        md.PHNPC_FirstName  = npcData.firstName
        md.PHNPC_LastName   = npcData.lastName
        md.PHNPC_Profession = npcData.professionId
        md.PHNPC_Health     = npcData.health
        md.PHNPC_FsmState   = npcData.fsmState
    else
        -- Fallback si NPC_DataModel n'est pas disponible côté serveur
        md.PHNPC_FullName   = "Survivant"
        md.PHNPC_FirstName  = "Survivant"
        md.PHNPC_LastName   = ""
        md.PHNPC_Profession = "explorer"
        md.PHNPC_Health     = 100
        md.PHNPC_FsmState   = "idle"
    end

    if Log then
        Log.ok("Server/SpawnManager", "PNJ spawné avec succès", {
            name   = tostring(md.PHNPC_FullName),
            outfit = outfit,
            x      = spawnX,
            y      = spawnY,
        })
    end

    -- ---- Confirmation au client ----
    sendServerCommand(player, PHNPC.MOD_ID, "PHNPC_SpawnConfirm", {
        success  = true,
        x        = spawnX,
        y        = spawnY,
        outfit   = outfit,
        isFemale = isFemale,
        name     = md.PHNPC_FullName,
    })
end

-- ============================================================
-- Enregistrement
-- ============================================================

Events.OnClientCommand.Add(onClientCommand)

PHNPC.registerModule("NPC_SpawnManager", NPC_SpawnManager)
return NPC_SpawnManager
