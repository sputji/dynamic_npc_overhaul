--[[
    PHNPC_Stats.lua  v0.0.9f  (shared)
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
    -- v0.0.9f : multiplicateurs reduits (1.04 etait trop rapide)
    pcall(function()
        local walkSpeed = stats.speed * 0.85   -- v0.0.9f: reduit (etait 1.04)
        local runSpeed  = stats.speed * 0.60   -- v0.0.9f: reduit (etait 0.75)
        local limpSpeed = stats.speed * 0.65   -- v0.0.9f: reduit (etait 0.80)
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
    local md    = zombie:getModData()

    pcall(function()
        local inv = zombie:getInventory()
        if not inv then return end

        -- Poids max selon le metier
        inv:setCapacity(stats.maxWeight or 15.0)

        -- Items de depart
        -- v0.0.9f : support groupes alternatifs { {"TypeA","TypeB"}, "TypeC" }
        -- Si un groupe est une table, on essaie chaque type jusqu'au premier succes.
        for _, itemEntry in ipairs(stats.items or {}) do
            local itemList = type(itemEntry) == "table" and itemEntry or { itemEntry }
            local added = false
            for _, itemType in ipairs(itemList) do
                if not added then
                    local item = nil
                    local ok2 = pcall(function() item = inv:AddItem(itemType) end)
                    if ok2 and item then
                        added = true
                        print("[PHNPC][INV] " .. (md.PHNPC_Name or "?") .. " += " .. itemType)
                    end
                end
            end
            if not added then
                print("[PHNPC][INV] Aucun item disponible : " .. table.concat(itemList, "/"))
            end
        end

        -- v0.0.9e : Synchronisation nom NPC <-> items d'identification
        -- Les outfits PZ (ex: "Police") incluent des badges dont le nom est
        -- un personnage PZ predéfini ("Trent Keen", etc.) qui diffère du nom du NPC.
        -- Solution : renommer tous les items de type Badge/Identification avec setCustomName.
        local npcName = md.PHNPC_Name or "NPC"
        local items = inv:getItems()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if item then
                local ft = ""
                pcall(function() ft = tostring(item:getFullType() or "") end)
                -- Renommer les badges et items d'identification nommés
                if ft:find("Badge") or ft:find("Officer") or ft:find("IDCard") or ft:find("Wallet") then
                    pcall(function() item:setCustomName(npcName) end)
                end
            end
        end
    end)
end

print("[PHNPC] Stats v0.0.9k loaded")
