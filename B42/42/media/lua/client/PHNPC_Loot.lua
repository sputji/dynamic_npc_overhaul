--[[
    PHNPC_Loot.lua  -  v0.0.9m
    ----------------------------------------------------------------
    Drop l'inventaire complet du NPC quand il meurt.

    v0.0.9m REFONTE :
      - Pattern Bandits ZADrop confirme : sq:AddWorldInventoryItem(item, rx, ry, 0)
      - Drop AU SOL en priorite (toujours fiable), avec offset aleatoire.
      - Drop aussi les WORN ITEMS (vetements, armures).
      - 2eme passe via OnIsoZombieUpdate juste apres mort si OnZombieDead n'a pas
        ete declenche (cas multi-shot/explosion).
      - Logs INFO explicites a chaque etape pour diagnostic.
      - Retrait pcall (cause d'echec silencieux v0.0.9k/l) - les API utilisees
        sont stables en B42.18.

    Verifie cote IsoZombie B42.18 :
      getInventory()    -> ItemContainer
      getWornItems()    -> List<WornItem>
      getSquare()       -> IsoGridSquare
    Verifie cote IsoGridSquare B42.18 :
      AddWorldInventoryItem(item, dx, dy, dz) -> drop visible au sol
]]

PHNPC = PHNPC or {}

local function dropItemOnGround(sq, item)
    if not sq or not item then return false end
    -- Offset aleatoire pour ne pas empiler tout au meme pixel
    local rx = ZombRandFloat(0.1, 0.9)
    local ry = ZombRandFloat(0.1, 0.9)
    sq:AddWorldInventoryItem(item, rx, ry, 0)
    return true
end

function PHNPC.dropNPCInventory(npc)
    if not npc then return end
    local md = npc:getModData()
    if not md.PHNPC_IsNPC then return end
    if md.PHNPC_Looted then
        if PHNPC.Log then PHNPC.Log.debug("Loot", tostring(md.PHNPC_Name) .. " deja loote, skip") end
        return
    end
    md.PHNPC_Looted = true

    local name = tostring(md.PHNPC_Name or "NPC")
    if PHNPC.Log then PHNPC.Log.info("Loot", name .. " mort - debut drop inventaire") end

    local sq = npc:getSquare()
    if not sq then
        if PHNPC.Log then PHNPC.Log.info("Loot", name .. " ECHEC : pas de square") end
        return
    end

    local total = 0
    local dropped = 0

    -- 1) WORN ITEMS (vetements/armures) en priorite : ils restent attaches sinon
    local worn = npc:getWornItems()
    if worn and worn:size() > 0 then
        if PHNPC.Log then PHNPC.Log.info("Loot", name .. " - " .. worn:size() .. " worn items detectes") end
        local snapshot = {}
        for i = 0, worn:size() - 1 do
            local wi = worn:get(i)
            if wi and wi:getItem() then snapshot[#snapshot + 1] = wi:getItem() end
        end
        for _, it in ipairs(snapshot) do
            total = total + 1
            if dropItemOnGround(sq, it) then dropped = dropped + 1 end
        end
        -- Vider le worn container (le NPC ne porte plus rien)
        npc:resetEquippedHandsModels()
    end

    -- 2) INVENTAIRE principal
    local inv = npc:getInventory()
    if inv then
        local items = inv:getItems()
        if items and items:size() > 0 then
            if PHNPC.Log then PHNPC.Log.info("Loot", name .. " - " .. items:size() .. " items en inventaire") end
            local snapshot = {}
            for i = 0, items:size() - 1 do
                local it = items:get(i)
                if it then snapshot[#snapshot + 1] = it end
            end
            for _, it in ipairs(snapshot) do
                total = total + 1
                if dropItemOnGround(sq, it) then
                    dropped = dropped + 1
                    inv:Remove(it)
                end
            end
            inv:setDrawDirty(true)
        end
    end

    -- 3) ARME EN MAIN (au cas ou : Bandit pattern clearAttachedItems)
    npc:setPrimaryHandItem(nil)
    npc:setSecondaryHandItem(nil)
    npc:clearAttachedItems()

    if PHNPC.Log then
        PHNPC.Log.info("Loot", string.format("%s : %d/%d items droppes au sol", name, dropped, total))
    end
end

-- ============================================================
-- EVENT : detection mort NPC (handler principal)
-- ============================================================
local function onZombieDead(zombie)
    if not zombie then return end
    local md = zombie:getModData()
    if not md or not md.PHNPC_IsNPC then return end
    PHNPC.dropNPCInventory(zombie)
end

Events.OnZombieDead.Add(onZombieDead)

-- ============================================================
-- BACKUP : OnZombieUpdate detecte les NPC morts sans OnZombieDead
-- (cas connus en B42 : explosions, multi-degats simultanes)
-- ============================================================
local function onZombieUpdateLootCheck(zombie)
    if not zombie then return end
    local md = zombie:getModData()
    if not md or not md.PHNPC_IsNPC or md.PHNPC_Looted then return end
    if zombie:isDead() or zombie:getHealth() <= 0 then
        if PHNPC.Log then PHNPC.Log.info("Loot", "Detection mort via OnZombieUpdate (OnZombieDead manque)") end
        PHNPC.dropNPCInventory(zombie)
    end
end

Events.OnZombieUpdate.Add(onZombieUpdateLootCheck)

print("[PHNPC] Loot v0.0.9m loaded")
