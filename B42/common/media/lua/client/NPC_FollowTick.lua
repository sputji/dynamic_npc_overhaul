--[[
    Project Humain : Dynamic NPC Overhaul — B42
    client/NPC_FollowTick.lua

    Boucle Events.OnZombieUpdate — cœur comportemental côté client.

    Responsabilités :
      1. Détection  : identifie les zombies portant PHNPC_IsNPC = true en ModData
                      (marqué par le serveur lors du spawn).
      2. Conversion : applique une seule fois les paramètres visuels et
                      comportementaux (pattern "Banditize" B42).
      3. DataModel  : crée l'instance NPCDataModel et la relie à l'entité.
      4. Enforce    : chaque tick, réinitialise les comportements zombie
                      (pas de morsure, pas de cible, santé haute).
      5. Follow     : pathfinding vers le joueur à quelques cases de distance.

    NPC_Brain sera branché plus tard en remplaçant l'état FSM "follow".
]]

local PHNPC_FollowTick = {}

-- Table locale (VM client) pour éviter de re-convertir le même zombie chaque tick.
-- Clé = objet Java IsoZombie (utilisable comme clé de table en Kahlua).
local _convertedNPCs = {}

-- Distance (en cases) en dessous de laquelle le PNJ s'arrête.
local FOLLOW_MIN_DIST = 2.5
-- Distance au-delà de laquelle le PNJ court pour rattraper le joueur.
local FOLLOW_RUN_DIST = 12.0
-- Décalage de la cible par rapport au joueur (le PNJ vise légèrement derrière).
local FOLLOW_OFFSET   = 2.0

-- ============================================================
-- Visuals humains (exécuté une seule fois par entité)
-- Source : pattern GCCoreVisuals + GCCoreConvert du mod NPC_Helper_Mod B42
-- ============================================================

local function applyHumanVisuals(zombie, isFemale)
    local humanVisual = nil
    local ok, err = pcall(function() humanVisual = zombie:getHumanVisual() end)
    if not ok or not humanVisual then
        local Log = PHNPC.getModule("NPC_Logger")
        if Log then Log.warn("FollowTick", "getHumanVisual() échoué", { err = tostring(err) }) end
        return
    end

    -- Nettoyer le sang et la saleté du zombie source
    pcall(function()
        humanVisual:removeDirt()
        humanVisual:removeBlood()
    end)

    -- Nettoyer le sang sur les vêtements
    pcall(function()
        local itemVisuals = zombie:getItemVisuals()
        if not itemVisuals then return end
        for i = 0, itemVisuals:size() - 1 do
            local iv = itemVisuals:get(i)
            if iv then
                iv:setBlood(BloodBodyPartType.Neck, 0)
                iv:setDirt(BloodBodyPartType.Neck, 0)
            end
        end
    end)

    -- Retirer les body visuals de zombie (ZedDmg_* = cicatrices zombie)
    pcall(function()
        local bodyVisuals = humanVisual:getBodyVisuals()
        if not bodyVisuals then return end
        local toRemove = {}
        for i = 0, bodyVisuals:size() - 1 do
            local bv = bodyVisuals:get(i)
            if bv then
                local itemType = bv:getItemType()
                if itemType and itemType:find("ZedDmg_") then
                    toRemove[#toRemove + 1] = itemType
                end
            end
        end
        for _, it in ipairs(toRemove) do
            humanVisual:removeBodyVisualFromItemType(it)
        end
    end)

    -- Texture de peau humaine
    pcall(function()
        if isFemale then
            local skins = { "FemaleBody01", "FemaleBody02", "FemaleBody03", "FemaleBody04" }
            humanVisual:setSkinTextureName(skins[PHNPC.randInt(1, #skins)])
        else
            local skins = { "MaleBody01a", "MaleBody02a", "MaleBody03a", "MaleBody04a" }
            humanVisual:setSkinTextureName(skins[PHNPC.randInt(1, #skins)])
        end
    end)

    -- Modèle de cheveux
    pcall(function()
        if isFemale then
            local hairs = { "Long", "Long2", "Ponytail", "BunCurly" }
            humanVisual:setHairModel(hairs[PHNPC.randInt(1, #hairs)])
        else
            local hairs = { "OverEye", "Messy", "Short", "Fauxhawk" }
            humanVisual:setHairModel(hairs[PHNPC.randInt(1, #hairs)])
            -- Barbe aléatoire pour les hommes
            local beards = { "", "GoatBeard", "Full", "Chops" }
            local beard = beards[PHNPC.randInt(1, #beards)]
            if beard ~= "" then
                pcall(function() humanVisual:setBeardModel(beard) end)
            end
        end
    end)

    -- Couleur de cheveux cohérente
    pcall(function()
        local r = 0.2 + ZombRandFloat(0, 0.6)
        local g = r * (0.6 + ZombRandFloat(0, 0.3))
        local b = g * (0.4 + ZombRandFloat(0, 0.3))
        local hairColor = ImmutableColor.new(r, g, b)
        humanVisual:setHairColor(hairColor)
        if not isFemale then
            pcall(function() humanVisual:setBeardColor(hairColor) end)
        end
    end)

    -- Forcer le recalcul du modèle 3D
    pcall(function() zombie:resetModelNextFrame() end)
    pcall(function() zombie:resetModel() end)
end

-- ============================================================
-- Conversion zombie → PNJ PHNPC (une seule fois par entité)
-- Basé sur le pattern "Banditize" du mod Bandits B42, validé par NPC_Helper_Mod.
-- ============================================================

local function convertToNPC(zombie, isFemale)
    local Log = PHNPC.getModule("NPC_Logger")
    isFemale = isFemale or false

    -- 1. Désactiver les mécaniques zombie (Bandits : lignes 164-204)
    pcall(function() zombie:setNoTeeth(true) end)
    pcall(function() zombie:setTarget(nil) end)
    pcall(function() zombie:clearAggroList() end)
    pcall(function() zombie:setEatBodyTarget(nil, false) end)

    -- 2. Variables de vitesse
    pcall(function() zombie:setVariable("LimpSpeed", 0.80) end)
    pcall(function() zombie:setVariable("RunSpeed",  0.75) end)
    pcall(function() zombie:setVariable("WalkSpeed", 1.04) end)

    -- 3. Variables d'animation — désactivent le comportement zombie dans les AnimSets
    pcall(function() zombie:setVariable("NoLungeTarget", true) end)
    pcall(function() zombie:setVariable("ZombieHitReaction", "Chainsaw") end)

    -- 4. Type de marche humaine
    pcall(function() zombie:setWalkType("Walk") end)
    pcall(function() zombie:setVariable("GCWalkType", "Walk") end)

    -- 5. Silencier les sons zombie
    pcall(function() zombie:getEmitter():stopAll() end)

    -- 6. Nettoyer les objets équipés du zombie source
    pcall(function() zombie:setPrimaryHandItem(nil) end)
    pcall(function() zombie:setSecondaryHandItem(nil) end)
    pcall(function() zombie:resetEquippedHandsModels() end)
    pcall(function() zombie:clearAttachedItems() end)

    -- 7. Valeur de rotation sur alerte (Bandits : ligne 198)
    pcall(function() zombie:setTurnAlertedValues(-5, 5) end)

    -- 8. Voice prefix — genre différencié ; si le préfixe n'existe pas → silencieux (pas de son zombie)
    pcall(function()
        zombie:getDescriptor():setVoicePrefix(isFemale and "PHNPC_Female" or "PHNPC_Male")
    end)

    -- 9. Marqueur "Bandit" = flag interne PZ pour désactiver l'IA zombie native
    pcall(function() zombie:setVariable("Bandit", true) end)
    pcall(function() zombie:setVariable("NoLungeAttack", true) end)
    pcall(function() zombie:clearAggroList() end)

    -- 10. Genre et visuals humains
    pcall(function() zombie:setFemaleEtc(isFemale) end)
    applyHumanVisuals(zombie, isFemale)

    -- 10b. Santé initiale raisonnable (appliquée une seule fois, pas en enforceNPC)
    pcall(function() zombie:setMaxHealth(500) end)
    pcall(function() zombie:setHealth(500) end)

    -- 11. Empêcher le moteur de re-vêtir l'entité automatiquement
    pcall(function() zombie:setDressInRandomOutfit(false) end)

    -- 12. Marquer côté Java AVANT l'animation de sortie (condition AnimSet déjà vraie lors de la transition)
    pcall(function()
        zombie:setVariable("PHNPC_IsNPC",    true)
        zombie:setVariable("PHNPC_IsFemale", isFemale)
    end)

    -- 13. Animation initiale pour sortir de Zombie_Idle (PHNPC_IsNPC déjà positionné → Bob_Idle actif)
    pcall(function() zombie:setBumpType("Shrug") end)

    if Log then
        Log.ok("FollowTick", "Entité convertie en PNJ",
            { isFemale = tostring(isFemale) })
    end
    print(string.format("[PHNPC] NPC converti : %s @ %d,%d",
        isFemale and "FEMME" or "HOMME",
        math.floor(zombie:getX()), math.floor(zombie:getY())))
end

-- ============================================================
-- Attachement du DataModel (une seule fois par entité)
-- ============================================================

local function attachDataModel(zombie)
    local DataModel = PHNPC.getModule("NPC_DataModel")
    if not DataModel then return end

    -- Lire ModData si disponible (même VM solo) ; sinon tout en défaut.
    local md = {}
    pcall(function() md = zombie:getModData() or {} end)

    -- Reconstruire une instance NPCDataModel à partir des données ModData
    local npcData = DataModel.deserialize({
        id           = md.PHNPC_ID         or "PHNPC_unknown",
        firstName    = md.PHNPC_FirstName  or "Inconnu",
        lastName     = md.PHNPC_LastName   or "",
        fullName     = md.PHNPC_FullName   or "Inconnu",
        isFemale     = md.PHNPC_IsFemale   or false,
        professionId = md.PHNPC_Profession or "explorer",
        health       = md.PHNPC_Health     or 100,
        fsmState     = md.PHNPC_FsmState   or "idle",
    })
    npcData.isoObject = zombie

    -- Enregistrer dans le registre global
    PHNPC._activeNPCs[zombie] = npcData
end

-- ============================================================
-- Enforce — appliqué chaque tick pour éviter les régressions moteur
-- ============================================================

local function enforceNPC(zombie)
    -- Aucune morsure, aucune cible zombie
    pcall(function() zombie:setNoTeeth(true) end)
    pcall(function() zombie:setTarget(nil) end)
    pcall(function() zombie:clearAggroList() end)
    -- Maintenir le flag d'identité NPC côté Java chaque tick (cross-VM)
    pcall(function() zombie:setVariable("PHNPC_IsNPC", true) end)
    -- Flag Bandit : maintenu chaque tick pour que le moteur ne réactive pas l'IA zombie
    pcall(function() zombie:setVariable("Bandit", true) end)
    pcall(function() zombie:setVariable("NoLungeAttack", true) end)
    pcall(function() zombie:setVariable("ZombieHitReaction", "Chainsaw") end)
    -- Silencer les sons zombie (stopAll chaque tick empêche tout son résiduel)
    pcall(function() zombie:getEmitter():stopAll() end)
    -- Empêcher le moteur de marquer l'entité comme "useless" (arrêt de l'IA)
    pcall(function() zombie:setUseless(false) end)
    -- Garder la marche humaine
    pcall(function() zombie:setWalkType("Walk") end)
end

-- ============================================================
-- Suivi du joueur
-- ============================================================

local function doFollow(zombie, player)
    local nx, ny = zombie:getX(), zombie:getY()
    local px, py = player:getX(), player:getY()
    local dx, dy = nx - px, ny - py
    local dist = math.sqrt(dx * dx + dy * dy)

    if dist <= FOLLOW_MIN_DIST then
        -- Assez proche : arrêt du pathfinding (on ne change pas l'état du moteur)
        return
    end

    -- Vitesse selon distance
    if dist > FOLLOW_RUN_DIST then
        pcall(function() zombie:setWalkType("Run") end)
    else
        pcall(function() zombie:setWalkType("Walk") end)
    end

    -- Cible : légèrement derrière le joueur (évite de le bloquer)
    local len = math.max(dist, 0.01)
    local targetX = px + (dx / len) * FOLLOW_OFFSET
    local targetY = py + (dy / len) * FOLLOW_OFFSET

    -- Utilise pathToLocation plutôt que pathToCharacter
    -- (évite ClassCastException sur certains types d'entités proches de véhicules)
    pcall(function()
        zombie:pathToLocation(targetX, targetY, player:getZ())
    end)
end

-- ============================================================
-- Boucle principale
-- ============================================================

local function onZombieUpdate(zombie)
    if not zombie then return end

    -- DEBUG : confirme que l'event fire (imprime au 1er appel puis toutes les 500 calls)
    PHNPC_FollowTick._dbgCount = (PHNPC_FollowTick._dbgCount or 0) + 1
    if PHNPC_FollowTick._dbgCount == 1 or PHNPC_FollowTick._dbgCount % 500 == 0 then
        print("[PHNPC DEBUG] onZombieUpdate appels=" .. PHNPC_FollowTick._dbgCount
            .. "  pendingNPCs=" .. tostring(PHNPC._pendingNPCs and #PHNPC._pendingNPCs or 0))
    end

    -- ================================================================
    -- DÉTECTION : triple méthode pour robustesse face aux VMs séparées B42
    -- En B42, même en solo, serveur et client ont des états Lua distincts.
    -- ModData set côté serveur n'est pas visible dans Events.OnZombieUpdate
    -- (qui s'exécute dans la VM client). On utilise 3 méthodes de fallback.
    -- ================================================================
    local isNPC   = false
    local isFemale = false

    -- Méthode A : variable Java (zombie:setVariable) — cross-VM car stockée
    -- directement sur l'objet Java IsoEntity, pas dans une KahluaTable.
    pcall(function()
        isNPC   = zombie:getVariableBoolean("PHNPC_IsNPC") == true
        if isNPC then
            isFemale = zombie:getVariableBoolean("PHNPC_IsFemale") == true
        end
    end)

    -- Méthode B : ModData — fonctionne quand client/serveur partagent la même VM
    -- (certaines versions solo B42 ou futur moteur unifié).
    if not isNPC then
        local mdOk, md = pcall(function() return zombie:getModData() end)
        if mdOk and md and md.PHNPC_IsNPC then
            isNPC    = true
            isFemale = md.PHNPC_IsFemale or false
        end
    end

    -- Méthode C : position proche d'un spawn pending reçu via PHNPC_SpawnConfirm.
    -- Le serveur envoie sendServerCommand → client stocke dans PHNPC._pendingNPCs.
    if not isNPC and PHNPC._pendingNPCs and #PHNPC._pendingNPCs > 0 then
        local zx, zy = zombie:getX(), zombie:getY()
        for i = #PHNPC._pendingNPCs, 1, -1 do
            local p = PHNPC._pendingNPCs[i]
            if math.abs(zx - p.x) < 3.0 and math.abs(zy - p.y) < 3.0 then
                isNPC    = true
                isFemale = p.isFemale or false
                table.remove(PHNPC._pendingNPCs, i)
                -- Marquer côté Java pour que les méthodes A/B fonctionnent ensuite
                pcall(function()
                    zombie:setVariable("PHNPC_IsNPC",    true)
                    zombie:setVariable("PHNPC_IsFemale", isFemale)
                end)
                local Log = PHNPC.getModule("NPC_Logger")
                if Log then
                    Log.ok("FollowTick", "PNJ détecté via position pending",
                        { x = tostring(math.floor(zx)), y = tostring(math.floor(zy)) })
                end
                break
            end
        end
    end

    if not isNPC then return end

    -- ================================================================
    -- CONVERSION (une seule fois — table locale, pas ModData)
    -- ================================================================
    if not _convertedNPCs[zombie] then
        convertToNPC(zombie, isFemale)
        attachDataModel(zombie)
        _convertedNPCs[zombie] = true
    end

    -- Enforce chaque tick
    enforceNPC(zombie)

    -- FSM minimal : toujours suivre le joueur
    local player = getPlayer()
    if player then
        doFollow(zombie, player)
    end
end

-- ============================================================
-- Nettoyage du registre (entités mortes ou déchargées)
-- ============================================================

Events.OnTick.Add(function()
    PHNPC_FollowTick._cleanTick = (PHNPC_FollowTick._cleanTick or 0) + 1
    if PHNPC_FollowTick._cleanTick < 300 then return end
    PHNPC_FollowTick._cleanTick = 0

    -- Nettoyer les entrées mortes/déchargées des deux tables
    local toRemove = {}
    for isoObj, _ in pairs(PHNPC._activeNPCs) do
        local ok, dead = pcall(function() return isoObj:isDead() end)
        if not ok or dead then toRemove[#toRemove + 1] = isoObj end
    end
    for _, isoObj in ipairs(toRemove) do
        PHNPC._activeNPCs[isoObj]  = nil
        _convertedNPCs[isoObj]     = nil
    end
end)

-- ============================================================
-- Enregistrement
-- ============================================================

Events.OnZombieUpdate.Add(onZombieUpdate)

PHNPC.registerModule("PHNPC_FollowTick", PHNPC_FollowTick)
return PHNPC_FollowTick
