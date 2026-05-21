--[[
    PHNPC_Stats.lua  v0.1  (shared)
    Initialisation des stats et de l'inventaire par metier
    Project Humain : Dynamic NPC Overhaul

    Appelé depuis PHNPC_Manager.lua convertToNPC()
    Nécessite PHNPC_Core.lua chargé avant (namespace PHNPC + PHNPC.OUTFIT_STATS)
]]

-- ============================================================
-- INITIALISATION DES STATS PAR METIER
-- Applique vitesse, sante, speedMod selon le metier du NPC
-- ============================================================

function PHNPC.initStats(zombie, outfit, isFemale)
    if not zombie then return end
    local stats = PHNPC.getOutfitStats(outfit)
    local md    = zombie:getModData()

    -- Sante : stocker dans ModData (systeme PHNPC, pas le compteur PZ)
    md.PHNPC_Health    = stats.health
    md.PHNPC_MaxHealth = stats.health
    md.PHNPC_SpeedMod  = stats.speed   -- lu par enforceNPC chaque tick
    md.PHNPC_Strength  = stats.strength

    -- Vitesse de deplacement (variables AnimSet)
    pcall(function()
        local walkSpeed = stats.speed * 1.04   -- echelle PZ (1.04 = walk normal)
        local runSpeed  = stats.speed * 0.75
        local limpSpeed = stats.speed * 0.80
        zombie:setVariable("WalkSpeed", walkSpeed)
        zombie:setVariable("RunSpeed",  runSpeed)
        zombie:setVariable("LimpSpeed", limpSpeed)
    end)

    print(string.format("[PHNPC][STATS] %s outfit=%s HP=%d speed=%.2f",
        tostring(md.PHNPC_Name or "?"), outfit, stats.health, stats.speed))
end

-- ============================================================
-- INITIALISATION DE L'INVENTAIRE PAR METIER
-- Donne les items de depart et fixe le poids max
-- ============================================================

function PHNPC.initInventory(zombie, outfit)
    if not zombie then return end
    local stats = PHNPC.getOutfitStats(outfit)

    pcall(function()
        local inv = zombie:getInventory()
        if not inv then return end

        -- Poids max selon le metier
        inv:setCapacity(stats.maxWeight or 15.0)

        -- Items de depart
        for _, itemType in ipairs(stats.items or {}) do
            local ok, err = pcall(function() inv:AddItem(itemType) end)
            if not ok then
                print("[PHNPC][INV] Impossible d'ajouter " .. itemType .. " : " .. tostring(err))
            end
        end
    end)
end

print("[PHNPC] Stats v0.0.9a loaded")
