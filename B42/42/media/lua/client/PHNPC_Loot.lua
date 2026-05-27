--[[
    PHNPC_Loot.lua  -  v0.0.9k
    ----------------------------------------------------------------
    Drop l'inventaire complet du NPC quand il meurt.

    Comportement :
      - Au moment de la mort (OnZombieDead) on transfere TOUS les items de
        l'inventaire du NPC :
          1) en priorite dans le IsoDeadBody que le moteur vient de creer
             sur la case (getSquare():getDeadBodys()),
          2) sinon, on les drop au sol via AddWorldInventoryItem.
      - Marque le NPC comme deja loote (md.PHNPC_Looted) pour eviter le
        double drop si l'event est rappele plusieurs fois.

    Fonctions :
      PHNPC.dropNPCInventory(npc)  -  appel direct si besoin
      Events.OnZombieDead          -  handler global

    Note B42.18 : IsoZombie:getInventory() est herite de IsoGameCharacter.
    IsoDeadBody:getContainer() retourne l'ItemContainer ou ajouter les items.
    IsoGridSquare:getDeadBodys() retourne la liste des corps sur la case.
]]

PHNPC = PHNPC or {}

-- pcall fallback (cohérence avec Core/Update : Kahlua peut perdre pcall)
local _pcall = pcall
local function safePcall(fn) local ok, err = _pcall(fn); return ok, err end

-- ============================================================
-- DROP INVENTAIRE
-- ============================================================
function PHNPC.dropNPCInventory(npc)
    if not npc then return end
    local md = npc:getModData()
    if not md.PHNPC_IsNPC then return end
    if md.PHNPC_Looted then return end
    md.PHNPC_Looted = true

    local inv = nil
    safePcall(function() inv = npc:getInventory() end)
    if not inv then return end

    local items = nil
    safePcall(function() items = inv:getItems() end)
    if not items or items:size() == 0 then
        if PHNPC.Log then PHNPC.Log.info("Loot", tostring(md.PHNPC_Name) .. " no items to drop") end
        return
    end

    local sq = nil
    safePcall(function() sq = npc:getSquare() end)
    if not sq then return end

    -- 1) Essayer de transferer dans le corpse fraichement cree
    local target = nil
    safePcall(function()
        local bodies = sq:getDeadBodys()
        if bodies and bodies:size() > 0 then
            local body = bodies:get(bodies:size() - 1)  -- le plus recent
            if body then target = body:getContainer() end
        end
    end)

    local x, y, z = npc:getX(), npc:getY(), npc:getZ()
    local total = items:size()
    local moved = 0

    -- Copie la liste car on va vider l'inventaire
    local snapshot = {}
    for i = 0, total - 1 do snapshot[#snapshot + 1] = items:get(i) end

    for _, item in ipairs(snapshot) do
        if item then
            local ok = false
            if target then
                safePcall(function() target:addItem(item); ok = true end)
            end
            if not ok then
                safePcall(function() sq:AddWorldInventoryItem(item, 0.0, 0.0, 0.0); ok = true end)
            end
            if ok then
                safePcall(function() inv:Remove(item) end)
                moved = moved + 1
            end
        end
    end

    if PHNPC.Log then
        PHNPC.Log.info("Loot", string.format("%s mort : %d/%d items %s",
            tostring(md.PHNPC_Name), moved, total,
            target and "transferes dans le corps" or "droppe au sol"))
    end
end

-- ============================================================
-- EVENT : detection mort NPC
-- ============================================================
local function onZombieDead(zombie)
    if not zombie then return end
    local md = nil
    safePcall(function() md = zombie:getModData() end)
    if not md or not md.PHNPC_IsNPC then return end
    -- Petit delai pour laisser le moteur creer le IsoDeadBody
    PHNPC.dropNPCInventory(zombie)
end

Events.OnZombieDead.Add(onZombieDead)

print("[PHNPC] Loot v0.0.9k loaded")
