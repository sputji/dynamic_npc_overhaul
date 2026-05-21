--[[
    PHNPC_Convert.lua  v1.0  (client)
    Conversion zombie => NPC (PHNPC.convertToNPC)
    Spawn d'un NPC sur une case (PHNPC.spawnNPC)

    Pattern : NHM GCCoreConvert.lua + GCCoreSpawn.lua EXACT
    Necessite : PHNPC_Core.lua (shared) + PHNPC_Stats.lua (shared)
]]

-- ============================================================
-- CONVERSION ZOMBIE => NPC (GCCoreConvert.convertToNPC EXACT)
-- Pattern Bandits Banditize() (BanditUpdate.lua)
-- IMPORTANT : NO setUseless, NO changeState, NO setTarget ici
-- ============================================================
function PHNPC.convertToNPC(zombie, outfit, isFemale, npcName)
    if not zombie then return end

    print("[PHNPC][CONVERT] " .. npcName .. " (" .. (isFemale and "F" or "M") .. ") outfit=" .. outfit)

    -- 1. Dents (Bandits linea 164)
    pcall(function() zombie:setNoTeeth(true) end)

    -- 2. Variables de vitesse (Bandits lineas 169-171)
    pcall(function() zombie:setVariable("LimpSpeed", 0.80) end)
    pcall(function() zombie:setVariable("RunSpeed",  0.75) end)
    pcall(function() zombie:setVariable("WalkSpeed", 1.04) end)

    -- 3. Variable PHNPC_IsNPC => active nos AnimSet XMLs (ZSIdle, ZSWalk, etc.)
    --    Sans cette variable, le jeu utilise Zombie_Idle et Zombie_Walk
    pcall(function() zombie:setVariable("PHNPC_IsNPC", true) end)

    -- 4. WalkType humain (Bandits lineas 178-179)
    --    setWalkType => API PZ, fixe zombieWalkType en interne (read-only)
    --    NE PAS appeler setVariable("zombieWalkType",...) => WARN read-only
    pcall(function() zombie:setWalkType("Walk") end)

    -- 5. Hit reaction humaine au lieu de zombie (Bandits linea 184)
    pcall(function() zombie:setVariable("ZombieHitReaction", "Chainsaw") end)

    -- 6. Desactiver lunge vers cible (Bandits linea 187)
    pcall(function() zombie:setVariable("NoLungeTarget", true) end)

    -- 7. Silencer sons zombie (Bandits linea 190)
    pcall(function() zombie:getEmitter():stopAll() end)

    -- 8. Vider les mains (Bandits lineas 192-195)
    pcall(function() zombie:setPrimaryHandItem(nil) end)
    pcall(function() zombie:setSecondaryHandItem(nil) end)
    pcall(function() zombie:resetEquippedHandsModels() end)
    pcall(function() zombie:clearAttachedItems() end)

    -- 9. Neutraliser TurnAlerted (Bandits linea 198)
    pcall(function() zombie:setTurnAlertedValues(-5, 5) end)

    -- 10. Prefixe voix : genre-based pour avoir footsteps
    pcall(function() zombie:getDescriptor():setVoicePrefix(isFemale and "FemaleZombie" or "MaleZombie") end)

    -- 11. Empecher re-habillage automatique par le moteur
    pcall(function() zombie:setDressInRandomOutfit(false) end)

    -- 11b. Genre : necessaire pour Bob_Walk/Kate_Walk + Bob_Idle/Kate_Idle
    pcall(function() zombie:setFemaleEtc(isFemale) end)

    -- 12. Premier bump => sortir de Zombie_Idle proprement
    pcall(function() zombie:setBumpType("Shrug") end)

    -- 13. Nettoyer visuels (salet, sang)
    pcall(function()
        local hv = zombie:getHumanVisual()
        if hv then hv:removeDirt() ; hv:removeBlood() end
    end)

    -- 14. ModData NPC
    local md = zombie:getModData()
    md.PHNPC_IsNPC         = true
    md.PHNPC_Recruited     = false
    md.PHNPC_State         = "idle"     -- "idle" | "following" | "staying"
    md.PHNPC_Name          = npcName
    md.PHNPC_Female        = isFemale
    md.PHNPC_Outfit        = outfit
    md.PHNPC_Moving        = false
    md.PHNPC_HitTicks      = 0
    md.PHNPC_CombatMode    = "auto"  -- "auto" | "off" : combat auto vs zombies proches
    md.PHNPC_PrevState     = nil     -- etat sauvegarde avant combat/fuite
    md.PHNPC_BarkTick      = 0       -- compteur pour barks auto
    md.PHNPC_AttackCooldown= 0       -- ticks restants avant prochain attack
    -- ShowTimer : ignore les premiers ticks le temps que les animations se stabilisent
    -- (GCCoreSpawn.lua pattern : GC_ShowTimer = 5)
    md.PHNPC_ShowTimer     = 5

    -- 15. Enregistrer dans le systeme
    PHNPC.allNPCs[zombie] = true

    -- 15b. Stats et inventaire par metier (PHNPC_Stats.lua)
    if PHNPC.initStats then
        PHNPC.initStats(zombie, outfit, isFemale)
    end
    if PHNPC.initInventory then
        PHNPC.initInventory(zombie, outfit)
    end

    print("[PHNPC] NPC cree OK : " .. npcName)
end

-- ============================================================
-- SPAWN (GCCoreSpawn.spawnCompanionNPC EXACT)
-- ============================================================
function PHNPC.spawnNPC(square)
    if not square then
        print("[PHNPC][SPAWN] Erreur : square nil")
        return nil
    end

    local x = square:getX()
    local y = square:getY()
    local z = square:getZ()

    local isFemale     = (ZombRand(2) == 0)
    local femaleChance = isFemale and 100 or 0
    local outfit       = PHNPC.OUTFITS[ZombRand(#PHNPC.OUTFITS) + 1]
    local npcName      = PHNPC.getRandomName(isFemale)

    print("[PHNPC][SPAWN] " .. x .. "," .. y .. "," .. z
          .. " outfit=" .. outfit .. " female=" .. tostring(isFemale))

    -- addZombiesInOutfit est une FONCTION GLOBALE (pas une methode de square)
    local zombieList = nil
    local ok, err = pcall(function()
        zombieList = addZombiesInOutfit(x, y, z, 1, outfit, femaleChance)
    end)

    if not ok then
        print("[PHNPC][SPAWN] ERREUR addZombiesInOutfit : " .. tostring(err))
        return nil
    end

    if not zombieList or zombieList:size() == 0 then
        print("[PHNPC][SPAWN] Erreur : zombieList vide")
        return nil
    end

    local zombie = zombieList:get(0)
    if not zombie then
        print("[PHNPC][SPAWN] Erreur : zombie nil apres spawn")
        return nil
    end

    PHNPC.convertToNPC(zombie, outfit, isFemale, npcName)
    return zombie
end

print("[PHNPC] Convert v0.0.9a loaded")
