--[[
    PHNPC_Outfits.lua  v0.0.16  (client)
    Selection et equip automatique des vetements NPC selon les meilleurs
    scores de protection et de confort.

    Extrait de PHNPC_Inventory.lua (v0.0.15) et enrichi :
      - PHNPC.autoEquipBestOutfit(npc)  : equipe la meilleure tenue complete
      - PHNPC.scoreClothing(item)       : score d'un vetement (protection + etat)
      - PHNPC.getCurrentWorn(npc, loc)  : vetement actuellement porte sur un slot
      - PHNPC.setWornItem(npc, loc, it) : equiper un vetement sur un slot

    Raisons du split :
      - PHNPC_Inventory.lua doit rester focalise sur l'UI loot panel.
      - La logique d'equip vetements est appelee depuis plusieurs endroits
        (convertToNPC, OnTick apres don de vetement, ordres de shelter).
      - Facilite les tests unitaires de scoring independamment de l'UI.

    Necessite :
      PHNPC_Core.lua (shared)
]]

PHNPC = PHNPC or {}

-- ============================================================
-- scoreClothing : calcule un score de priorite pour un vetement
-- Prend en compte : morsure, egratignure, balle, etat, isolation
-- Retourne -1 si l'item n'est pas un vetement
-- ============================================================
function PHNPC.scoreClothing(item)
    if not item then return -1 end

    local isCloth = false
    pcall(function() isCloth = instanceof(item, "Clothing") end)
    if not isCloth then
        local alt = false
        pcall(function() alt = item.IsClothing and item:IsClothing() or false end)
        if not alt then return -1 end
    end

    local bite, scratch, bullet = 0, 0, 0
    pcall(function() bite    = item.getBiteDefense    and item:getBiteDefense()    or 0 end)
    pcall(function() scratch = item.getScratchDefense and item:getScratchDefense() or 0 end)
    pcall(function() bullet  = item.getBulletDefense  and item:getBulletDefense()  or 0 end)

    local cond, condMax = 1, 1
    pcall(function() cond    = item:getCondition()    or 1 end)
    pcall(function() condMax = item:getConditionMax() or 1 end)
    local condRatio = (condMax > 0) and (cond / condMax) or 1

    local insulation = 0
    pcall(function() insulation = item.getInsulation and item:getInsulation() or 0 end)

    -- Ponderation : balle > morsure > egratignure ; etat important
    return (bullet * 6) + (bite * 5) + (scratch * 3) + (condRatio * 2) + insulation
end

-- ============================================================
-- getCurrentWorn : retourne le vetement actuellement porte sur un slot
-- Compatible B42 (getWornItem prefer, fallback getWornItems():getItem)
-- ============================================================
function PHNPC.getCurrentWorn(npc, location)
    if not npc or not location then return nil end
    local current = nil
    if npc.getWornItem then
        pcall(function() current = npc:getWornItem(location) end)
    end
    if not current then
        local worn
        pcall(function() worn = npc:getWornItems() end)
        if worn and worn.getItem then
            pcall(function() current = worn:getItem(location) end)
        end
    end
    return current
end

-- ============================================================
-- setWornItem : equiper un vetement sur un slot
-- Compatible B42 (setWornItem prefer, fallback getWornItems():setItem)
-- ============================================================
function PHNPC.setWornItem(npc, location, item)
    if not npc or not location or not item then return false end
    local ok = false
    if npc.setWornItem then
        pcall(function() npc:setWornItem(location, item); ok = true end)
    end
    if not ok then
        local worn
        pcall(function() worn = npc:getWornItems() end)
        if worn and worn.setItem then
            pcall(function() worn:setItem(location, item); ok = true end)
        end
    end
    return ok
end

-- ============================================================
-- autoEquipBestOutfit : equipe automatiquement les vetements
-- presents dans l'inventaire NPC selon le meilleur score par slot.
-- Remplace un vetement deja porte si le nouveau a un meilleur score.
-- Retourne le nombre de slots mis a jour.
-- ============================================================
function PHNPC.autoEquipBestOutfit(npc)
    if not npc then return 0 end

    local inv
    pcall(function() inv = npc:getInventory() end)
    if not inv then return 0 end

    local items
    pcall(function() items = inv:getItems() end)
    if not items then return 0 end

    -- Phase 1 : identifier le meilleur vetement par slot (bodyLocation)
    local bestByLocation = {}
    local n = 0
    pcall(function() n = items:size() end)

    for i = 0, n - 1 do
        local it
        pcall(function() it = items:get(i) end)
        if it then
            local score = PHNPC.scoreClothing(it)
            if score >= 0 then
                local location = nil
                pcall(function() location = it:getBodyLocation() end)
                if location and tostring(location) ~= "" then
                    local cur = bestByLocation[location]
                    if (not cur) or score > cur.score then
                        bestByLocation[location] = { item = it, score = score }
                    end
                end
            end
        end
    end

    -- Phase 2 : comparer avec le vetement actuellement porte et equiper si meilleur
    local equipped = 0
    for location, entry in pairs(bestByLocation) do
        local current      = PHNPC.getCurrentWorn(npc, location)
        local currentScore = PHNPC.scoreClothing(current)

        if entry.score > currentScore then
            if PHNPC.setWornItem(npc, location, entry.item) then
                equipped = equipped + 1
                PHNPC.Log.debug("Outfits",
                    string.format("equip slot=%s score=%.1f -> %.1f",
                        tostring(location), currentScore, entry.score))
            end
        end
    end

    -- Refresh modele visuel si modification
    if equipped > 0 then
        pcall(function() npc:resetModelNextFrame() end)
        pcall(function() npc:resetEquippedHandsModels() end)
        local md = npc:getModData()
        PHNPC.Log.info("Outfits",
            string.format("%s : %d slot(s) mis a jour",
                tostring(md.PHNPC_Name or "NPC"), equipped))
    end

    return equipped
end

-- ============================================================
-- autoEquipFromInventory : alias de compatibilite v0.0.15
-- => PHNPC_Inventory.lua appelait cette fonction interne.
--    Maintenant elle deleguee a autoEquipBestOutfit.
-- ============================================================
function PHNPC.autoEquipFromInventory(npc)
    return PHNPC.autoEquipBestOutfit(npc)
end

print("[PHNPC] Outfits v0.0.16 loaded")
