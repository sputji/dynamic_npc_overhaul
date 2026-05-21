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

print("[PHNPC] Inventory v1.0 loaded")
