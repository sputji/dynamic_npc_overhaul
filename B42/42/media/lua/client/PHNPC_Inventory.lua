--[[
    PHNPC_Inventory.lua  v1.0  (client)
    Gestion de l'inventaire NPC via le loot panel.
    Injecte le container du NPC dans le panneau de loot au clic.

    Pattern : NHM GCMenuInventory.lua
    Necessite :
      PHNPC_Actions.lua  (PHNPC._openInventoryNPC)
      PHNPC_Core.lua     (PHNPC.INTERACTION_DIST)
]]

-- ============================================================
-- PHNPC.openNPCInventory : ouvrir le container du NPC dans le loot panel
-- ============================================================
function PHNPC.openNPCInventory(npc)
    if not npc then return end
    local md = npc:getModData()
    local npcInv = npc:getInventory()
    pcall(function() npcInv:setType(md.PHNPC_Name or "Survivant") end)

    PHNPC._openInventoryNPC = npc

    local player = getPlayer()
    if not player then return end
    local playerNum = player:getPlayerNum()
    local pdata = getPlayerData(playerNum)
    if pdata then
        local loot = pdata.lootInventory
        loot:refreshBackpacks()
        if loot.isCollapsed then
            loot.isCollapsed = false
            pcall(function() loot:clearMaxDrawHeight() end)
            loot.collapseCounter = 0
        end
        pcall(function() loot:selectButtonForContainer(npcInv) end)
    end
end

-- Equipe automatiquement les vetements presents dans l'inventaire du NPC
-- si le slot est libre (best-effort, silencieux en cas d'API absente).
function PHNPC.autoEquipFromInventory(npc)
    if not npc then return 0 end
    local inv
    pcall(function() inv = npc:getInventory() end)
    if not inv then return 0 end

    local items
    pcall(function() items = inv:getItems() end)
    if not items then return 0 end

    local function isClothingItem(it)
        if not it then return false end
        local ok, val = pcall(function() return instanceof(it, "Clothing") end)
        if ok and val then return true end
        local alt = false
        pcall(function() alt = it.IsClothing and it:IsClothing() or false end)
        return alt and true or false
    end

    local function scoreClothing(it)
        if not it then return -1 end
        if not isClothingItem(it) then return -1 end

        local bite, scratch, bullet = 0, 0, 0
        pcall(function() bite = it.getBiteDefense and it:getBiteDefense() or 0 end)
        pcall(function() scratch = it.getScratchDefense and it:getScratchDefense() or 0 end)
        pcall(function() bullet = it.getBulletDefense and it:getBulletDefense() or 0 end)

        local cond, condMax = 1, 1
        pcall(function() cond = it:getCondition() or 1 end)
        pcall(function() condMax = it:getConditionMax() or 1 end)
        local condRatio = (condMax > 0) and (cond / condMax) or 1

        -- Priorite defense + etat; leger bonus isolation thermique.
        local insulation = 0
        pcall(function() insulation = it.getInsulation and it:getInsulation() or 0 end)
        return (bite * 5) + (scratch * 3) + (bullet * 6) + (condRatio * 2) + insulation
    end

    local bestByLocation = {}
    local n = 0
    pcall(function() n = items:size() end)
    for i = 0, n - 1 do
        local it
        pcall(function() it = items:get(i) end)
        if it then
            if isClothingItem(it) then
                local location = nil
                pcall(function() location = it:getBodyLocation() end)
                if location and tostring(location) ~= "" then
                    local score = scoreClothing(it)
                    local cur = bestByLocation[location]
                    if (not cur) or score > cur.score then
                        bestByLocation[location] = { item = it, score = score }
                    end
                end
            end
        end
    end

    local worn
    pcall(function() worn = npc:getWornItems() end)

    local function getCurrentWorn(location)
        local current = nil
        if npc.getWornItem then
            pcall(function() current = npc:getWornItem(location) end)
        end
        if (not current) and worn and worn.getItem then
            pcall(function() current = worn:getItem(location) end)
        end
        return current
    end

    local function setWorn(location, item)
        local ok = false
        if npc.setWornItem then
            pcall(function() npc:setWornItem(location, item); ok = true end)
        end
        if (not ok) and worn and worn.setItem then
            pcall(function() worn:setItem(location, item); ok = true end)
        end
        return ok
    end

    local equipped = 0
    for location, entry in pairs(bestByLocation) do
        local current = getCurrentWorn(location)
        local currentScore = scoreClothing(current)
        if entry.score > currentScore then
            if setWorn(location, entry.item) then
                equipped = equipped + 1
            end
        end
    end

    if equipped > 0 then
        pcall(function() npc:resetModelNextFrame() end)
        pcall(function() npc:resetEquippedHandsModels() end)
    end
    return equipped
end

-- ============================================================
-- Hook refresh du loot panel : injecte le container NPC a chaque refresh
-- Ferme automatiquement si le NPC est mort ou trop loin
-- ============================================================
Events.OnRefreshInventoryWindowContainers.Add(function(page, step)
    if step ~= "beforeFloor" then return end
    if page.onCharacter then return end

    local npc = PHNPC._openInventoryNPC
    if not npc then return end

    -- Fermer si NPC mort ou trop loin
    local dead = false
    pcall(function() dead = npc:isDead() end)
    if dead then PHNPC._openInventoryNPC = nil ; return end

    local player = getPlayer()
    if player then
        local dx = npc:getX() - player:getX()
        local dy = npc:getY() - player:getY()
        if (dx*dx + dy*dy) > (PHNPC.INTERACTION_DIST + 2)^2 then
            PHNPC._openInventoryNPC = nil ; return
        end
    end

    local md = npc:getModData()
    local npcInv = npc:getInventory()
    local loot = getPlayerLoot(page.player)
    if loot then
        loot:addContainerButton(
            npcInv,
            nil,
            md.PHNPC_Name or "Survivant",
            md.PHNPC_Name or "Survivant"
        )
    end
end)

print("[PHNPC] Inventory v0.0.14 loaded")
