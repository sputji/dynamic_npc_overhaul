--[[
    PHNPC_Loot.lua  -  v0.0.9n
    ----------------------------------------------------------------
    Transfert de l'inventaire complet du NPC DANS LE CADAVRE quand il meurt.

    v0.0.9n REFONTE :
      - Le joueur veut voir les items DANS le cadavre, pas par terre.
      - Pattern Bandits BanditUpdate.lua:2412 : body:getContainer():AddItem(item).
      - OnZombieDead fire AVANT que IsoDeadBody soit cree.
      - Strategie :
          1. OnZombieDead   : snapshot des items + worn + arme, stocke dans
             PHNPC._pendingLoot[id] = { x, y, z, items, gameTimeTick }
          2. OnDeadBodySpawn: pour chaque pending loot, on cherche un body proche
             (meme x,y,z a +/- 1) et on AddItem dans body:getContainer().
          3. Fallback (2s sans match) : drop AU SOL (pattern Bandits ZADrop).
      - Important : on retire les items de l'inventaire du NPC AVANT le snapshot
        pour eviter une double presence si le moteur fait sa propre copie.

    Verifie cote IsoDeadBody B42.18 :
      getContainer()  -> ItemContainer
      getX/Y/Z()      -> coordonnees
      getModData()    -> table de persistance
    Verifie cote ItemContainer B42.18 :
      AddItem(item)   -> ajoute un item
]]

PHNPC = PHNPC or {}
PHNPC._pendingLoot = PHNPC._pendingLoot or {}

-- ============================================================
-- HELPERS
-- ============================================================
local function dropItemOnGround(sq, item)
    if not sq or not item then return false end
    local ok = false
    pcall(function()
        local rx = ZombRandFloat(0.1, 0.9)
        local ry = ZombRandFloat(0.1, 0.9)
        sq:AddWorldInventoryItem(item, rx, ry, 0)
        ok = true
    end)
    return ok
end

local function nextPendingId()
    PHNPC._pendingLootCounter = (PHNPC._pendingLootCounter or 0) + 1
    return PHNPC._pendingLootCounter
end

local function pushUnique(items, seen, item)
    if not item then return end
    if seen[item] then return end
    seen[item] = true
    items[#items + 1] = item
end

-- ============================================================
-- 1. SNAPSHOT INVENTAIRE (au moment de la mort)
-- ============================================================
function PHNPC.snapshotNPCLoot(npc)
    if not npc then return end
    local md = npc:getModData()
    if not md.PHNPC_IsNPC then return end
    if md.PHNPC_Looted then return end
    md.PHNPC_Looted = true

    local name = tostring(md.PHNPC_Name or "NPC")
    if PHNPC.Log then PHNPC.Log.info("Loot", name .. " mort - snapshot inventaire") end

    local items = {}
    local seen = {}

    -- 1) WORN ITEMS
    local worn
    pcall(function() worn = npc:getWornItems() end)
    if worn then
        local n = 0; pcall(function() n = worn:size() end)
        for i = 0, n - 1 do
            local wi
            pcall(function() wi = worn:get(i) end)
            local it
            pcall(function() it = wi:getItem() end)
            pushUnique(items, seen, it)
        end
        pcall(function() npc:resetEquippedHandsModels() end)
    end

    -- 1b) ARMES EN MAIN (pas toujours presentes dans getWornItems)
    local primary, secondary
    pcall(function() primary = npc:getPrimaryHandItem() end)
    pcall(function() secondary = npc:getSecondaryHandItem() end)
    pushUnique(items, seen, primary)
    pushUnique(items, seen, secondary)

    -- 2) INVENTAIRE PRINCIPAL
    local inv
    pcall(function() inv = npc:getInventory() end)
    if inv then
        local list
        pcall(function() list = inv:getItems() end)
        if list then
            local n = 0; pcall(function() n = list:size() end)
            local snapshot = {}
            for i = 0, n - 1 do
                local it
                pcall(function() it = list:get(i) end)
                if it then snapshot[#snapshot + 1] = it end
            end
            for _, it in ipairs(snapshot) do
                pushUnique(items, seen, it)
                pcall(function() inv:Remove(it) end)
            end
            pcall(function() inv:setDrawDirty(true) end)
        end
    end

    -- 3) ARMES EN MAIN
    pcall(function() npc:setPrimaryHandItem(nil) end)
    pcall(function() npc:setSecondaryHandItem(nil) end)
    pcall(function() npc:clearAttachedItems() end)

    if #items == 0 then
        if PHNPC.Log then PHNPC.Log.info("Loot", name .. " : aucun item a transferer") end
        return
    end

    local nx, ny, nz = 0, 0, 0
    pcall(function() nx = npc:getX() end)
    pcall(function() ny = npc:getY() end)
    pcall(function() nz = npc:getZ() end)

    local id = nextPendingId()
    PHNPC._pendingLoot[id] = {
        name  = name,
        x     = nx,
        y     = ny,
        z     = nz,
        items = items,
        ticks = 0,  -- compteur d'attente, abandonne apres 120 ticks
    }

    if PHNPC.Log then
        PHNPC.Log.info("Loot", string.format("%s : %d items en attente du cadavre (id=%d, %.1f,%.1f,%.0f)",
            name, #items, id, nx, ny, nz))
    end
end

-- ============================================================
-- 2. TRANSFERT VERS CADAVRE (OnDeadBodySpawn)
-- ============================================================
local function transferToBody(body, entry)
    local container
    pcall(function() container = body:getContainer() end)
    if not container then return false, 0 end
    local dropped = 0
    for _, item in ipairs(entry.items) do
        local ok = false
        pcall(function()
            local added = container:AddItem(item)
            ok = added and true or false
        end)
        if (not ok) and item then
            local fullType = nil
            pcall(function() fullType = item:getFullType() end)
            if fullType and fullType ~= "" then
                pcall(function()
                    local added2 = container:AddItem(fullType)
                    ok = added2 and true or false
                end)
            end
        end
        if ok then dropped = dropped + 1 end
    end
    pcall(function()
        local bmd = body:getModData()
        bmd.PHNPC_WasNPC = true
        bmd.PHNPC_Name   = entry.name
    end)
    return true, dropped
end

local function onDeadBodySpawn(body)
    if not body then return end
    if not PHNPC._pendingLoot then return end
    local bx, by, bz = 0, 0, 0
    pcall(function() bx = body:getX() end)
    pcall(function() by = body:getY() end)
    pcall(function() bz = body:getZ() end)

    local bestId, bestDist = nil, 9999
    for id, entry in pairs(PHNPC._pendingLoot) do
        local dx = bx - entry.x
        local dy = by - entry.y
        local dz = bz - entry.z
        local d  = dx * dx + dy * dy + dz * dz
        if d < bestDist and d <= 4 then  -- 2 tiles tolerance
            bestDist = d
            bestId   = id
        end
    end

    if not bestId then return end
    local entry = PHNPC._pendingLoot[bestId]
    PHNPC._pendingLoot[bestId] = nil
    local ok, n = transferToBody(body, entry)
    if PHNPC.Log then
        if ok then
            PHNPC.Log.info("Loot", string.format("%s : %d items transferes DANS le cadavre", entry.name, n))
        else
            PHNPC.Log.warn("Loot", entry.name .. " : body:getContainer() KO, fallback sol")
            local sq
            pcall(function() sq = body:getSquare() end)
            if sq then
                for _, it in ipairs(entry.items) do dropItemOnGround(sq, it) end
            end
        end
    end
end

-- ============================================================
-- 3. FALLBACK GROUND DROP si pas de cadavre apres 120 ticks
--    (pattern de securite, ne devrait jamais arriver en pratique)
-- ============================================================
local function tickPendingLoot()
    if not PHNPC._pendingLoot then return end
    local cell = getCell()
    for id, entry in pairs(PHNPC._pendingLoot) do
        entry.ticks = entry.ticks + 1
        if entry.ticks >= 120 then
            PHNPC._pendingLoot[id] = nil
            if cell then
                local sq
                pcall(function() sq = cell:getGridSquare(math.floor(entry.x), math.floor(entry.y), math.floor(entry.z)) end)
                if sq then
                    local n = 0
                    for _, it in ipairs(entry.items) do
                        if dropItemOnGround(sq, it) then n = n + 1 end
                    end
                    if PHNPC.Log then
                        PHNPC.Log.warn("Loot", string.format("%s : pas de cadavre apres 120t, %d items au sol", entry.name, n))
                    end
                end
            end
        end
    end
end

-- ============================================================
-- EVENTS
-- ============================================================
local function onZombieDead(zombie)
    if not zombie then return end
    local md = zombie:getModData()
    if not md then return end
    if not md.PHNPC_IsNPC and not md.PHNPC_DeadPendingLoot then return end
    PHNPC.snapshotNPCLoot(zombie)
end

local function onZombieUpdateLootCheck(zombie)
    if not zombie then return end
    local md = zombie:getModData()
    if not md or md.PHNPC_Looted then return end
    if not md.PHNPC_IsNPC and not md.PHNPC_DeadPendingLoot then return end
    local dead = false
    pcall(function() dead = zombie:isDead() end)
    local hp = 100
    pcall(function() hp = zombie:getHealth() end)
    if dead or hp <= 0 then
        if PHNPC.Log then PHNPC.Log.info("Loot", "Mort detectee via OnZombieUpdate") end
        PHNPC.snapshotNPCLoot(zombie)
    end
end

Events.OnZombieDead.Add(onZombieDead)
Events.OnZombieUpdate.Add(onZombieUpdateLootCheck)
if Events.OnDeadBodySpawn then
    Events.OnDeadBodySpawn.Add(onDeadBodySpawn)
end
Events.OnTick.Add(tickPendingLoot)

print("[PHNPC] Loot v0.0.14 loaded")
