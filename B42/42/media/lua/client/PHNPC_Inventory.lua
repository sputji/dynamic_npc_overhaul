--[[
    PHNPC_Inventory.lua  v0.0.16  (client)
    Gestion de l'inventaire NPC via le loot panel.
    Injecte le container du NPC dans le panneau de loot au clic.

    v0.0.16 :
      - La logique de scoring/equip vetements est deplacee dans PHNPC_Outfits.lua.
        autoEquipFromInventory() est conserve comme alias de compatibilite.
      - Synchronisation native amelioree : refreshBackpacks() appele apres chaque
        modification du container pour garantir la coherence avec l'UI PZ.
      - Ajout de PHNPC.onItemGiven(npc, item) : hook appele quand le joueur donne
        un item au NPC pour declencher l'equip automatique si c'est un vetement
        ou une arme.

    Pattern : NHM GCMenuInventory.lua
    Necessite :
      PHNPC_Actions.lua  (PHNPC._openInventoryNPC)
      PHNPC_Core.lua     (PHNPC.INTERACTION_DIST)
      PHNPC_Outfits.lua  (PHNPC.autoEquipBestOutfit)
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

-- autoEquipFromInventory : delegue a PHNPC_Outfits.lua (v0.0.16)
-- La logique de scoring et d'equip vetements est maintenant dans PHNPC_Outfits.lua.
-- Cette fonction est conservee pour la compatibilite retroactive avec les
-- modules qui l'appellaient directement (Convert.lua, Update.lua, etc.).
-- PHNPC_Outfits.lua definit l'alias, mais on s'assure qu'il existe.
function PHNPC.autoEquipFromInventory(npc)
    if PHNPC.autoEquipBestOutfit then
        return PHNPC.autoEquipBestOutfit(npc)
    end
    return 0
end

-- ============================================================
-- PHNPC.onItemGiven(npc, item) : [NOUVEAU v0.0.16]
-- Hook appele quand le joueur depose un item dans l'inventaire NPC.
-- Declenche l'auto-equip si l'item est un vetement ou une arme.
-- ============================================================
function PHNPC.onItemGiven(npc, item)
    if not npc or not item then return end
    local md = npc:getModData()
    if not md.PHNPC_IsNPC then return end

    -- Vetement : declencher autoEquipBestOutfit
    local isCloth = false
    pcall(function() isCloth = instanceof(item, "Clothing") end)
    if isCloth and PHNPC.autoEquipBestOutfit then
        pcall(function() PHNPC.autoEquipBestOutfit(npc) end)
        return
    end

    -- Arme : equiper si meilleure que l'arme actuelle
    local isHandWeapon = false
    pcall(function() isHandWeapon = instanceof(item, "HandWeapon") end)
    if isHandWeapon then
        pcall(function()
            local primary = npc:getPrimaryHandItem()
            if not primary then
                npc:setPrimaryHandItem(item)
            end
        end)
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

print("[PHNPC] Inventory v0.0.18 loaded")
