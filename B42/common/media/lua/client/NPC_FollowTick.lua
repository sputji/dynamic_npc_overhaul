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
-- Distance au-delà de laquelle le PNJ erre de façon autonome (plus de suivi).
local FOLLOW_DIST_MAX = 20.0
-- Portée max du rôdage : cases max de déplacement par direction.
local WANDER_RANGE    = 8
-- Ticks minimum avant de choisir une nouvelle direction (~6 s à 30 fps).
local WANDER_HOLD     = 180
-- Table des cibles de rôdage { [zombie] = {x, y, z, setAt} }
local _wanderTargets  = {}
local _wanderTick     = 0  -- compteur incrémenté dans OnTick

-- ============================================================
-- Visuals humains (exécuté une seule fois par entité)
-- Source : pattern GCCoreVisuals + GCCoreConvert du mod NPC_Helper_Mod B42
-- ============================================================

local function applyHumanVisuals(zombie, isFemale)
    -- DIAGNOSTIC: confirme le début de la fonction
    print("[PHNPC][VISUALS] applyHumanVisuals START isFemale=" .. tostring(isFemale))

    local humanVisual = nil
    local ok, err = pcall(function() humanVisual = zombie:getHumanVisual() end)
    if not ok or not humanVisual then
        print("[PHNPC][VISUALS] ERREUR getHumanVisual: " .. tostring(err))
        return
    end
    print("[PHNPC][VISUALS] getHumanVisual OK")

    -- 1. Nettoyer sang/saleté du corps — boucle complète (pattern GCCoreVisuals)
    pcall(function()
        humanVisual:removeDirt()
        humanVisual:removeBlood()
        local maxIdx = BloodBodyPartType.MAX:index()
        for i = 0, maxIdx - 1 do
            local part = BloodBodyPartType.FromIndex(i)
            humanVisual:setBlood(part, 0)
            humanVisual:setDirt(part, 0)
        end
    end)
    print("[PHNPC][VISUALS] blood/dirt body OK")

    -- 2. Nettoyer sang/saleté/trous sur les vêtements — boucle complète (pattern GCCoreVisuals)
    pcall(function()
        local itemVisuals = zombie:getItemVisuals()
        if not itemVisuals then return end
        local maxIdx = BloodBodyPartType.MAX:index()
        for i = 0, itemVisuals:size() - 1 do
            local iv = itemVisuals:get(i)
            if iv then
                for j = 0, maxIdx - 1 do
                    local part = BloodBodyPartType.FromIndex(j)
                    iv:removeHole(j)
                    iv:setBlood(part, 0)
                    iv:setDirt(part, 0)
                end
            end
        end
    end)
    print("[PHNPC][VISUALS] itemVisuals clean OK")

    -- 3. Retirer body visuals zombie : ZedDmg_* ET Base.M_Beard_Stubble (pattern GCCoreVisuals)
    pcall(function()
        local bodyVisuals = humanVisual:getBodyVisuals()
        if not bodyVisuals then return end
        local toRemove = {}
        for i = 0, bodyVisuals:size() - 1 do
            local bv = bodyVisuals:get(i)
            if bv then
                local itemType = bv:getItemType()
                if itemType and (itemType:find("ZedDmg_") or itemType == "Base.M_Beard_Stubble") then
                    toRemove[#toRemove + 1] = itemType
                end
            end
        end
        for _, it in ipairs(toRemove) do
            humanVisual:removeBodyVisualFromItemType(it)
        end
    end)
    print("[PHNPC][VISUALS] bodyVisuals cleanup OK")

    -- 4. Texture de peau humaine (pattern GCCoreVisuals : ZombRand natif B42)
    local skinOk = pcall(function()
        if isFemale then
            local skins = { "FemaleBody01", "FemaleBody02", "FemaleBody03", "FemaleBody04" }
            humanVisual:setSkinTextureName(skins[ZombRand(#skins) + 1])
        else
            local skins = { "MaleBody01a", "MaleBody02a", "MaleBody03a", "MaleBody04a" }
            humanVisual:setSkinTextureName(skins[ZombRand(#skins) + 1])
        end
    end)
    print("[PHNPC][VISUALS] setSkinTextureName ok=" .. tostring(skinOk))

    -- 5. Modèle de cheveux
    local hairOk = pcall(function()
        if isFemale then
            local hairs = { "Long", "Long2", "Ponytail", "BunCurly" }
            humanVisual:setHairModel(hairs[ZombRand(#hairs) + 1])
        else
            local hairs = { "OverEye", "Messy", "Short", "Fauxhawk" }
            humanVisual:setHairModel(hairs[ZombRand(#hairs) + 1])
            local beards = { "", "GoatBeard", "Full", "Chops" }
            local beard = beards[ZombRand(#beards) + 1]
            if beard ~= "" then humanVisual:setBeardModel(beard) end
        end
    end)
    print("[PHNPC][VISUALS] setHairModel ok=" .. tostring(hairOk))

    -- 6. Couleur de cheveux
    pcall(function()
        local r = 0.2 + ZombRandFloat(0, 0.6)
        local g = r * (0.6 + ZombRandFloat(0, 0.3))
        local b = g * (0.4 + ZombRandFloat(0, 0.3))
        local hairColor = ImmutableColor.new(r, g, b)
        humanVisual:setHairColor(hairColor)
        if not isFemale then humanVisual:setBeardColor(hairColor) end
    end)

    -- 7. Forcer le recalcul du modèle 3D
    pcall(function() zombie:resetModelNextFrame() end)
    pcall(function() zombie:resetModel() end)

    print("[PHNPC][VISUALS] applyHumanVisuals DONE")
end

-- ============================================================
-- Conversion zombie → PNJ PHNPC (une seule fois par entité)
-- Basé sur le pattern "Banditize" du mod Bandits B42, validé par NPC_Helper_Mod.
-- ============================================================

local function convertToNPC(zombie, isFemale)
    local Log = PHNPC.getModule("NPC_Logger")
    isFemale = isFemale or false

    -- 1a. LA CLÉ ANIMENGINE : setVariable hors pcall pour garantir l'écriture
    --     L'AnimEngine Java lit BOOL via getVariableBoolean(), PAS le ModData Lua.
    --     On écrit string ET bool pour couvrir les deux modes de lecture du moteur.
    zombie:setVariable("PHNPC_IsNPC",    "true")  -- STRING fallback
    zombie:setVariable("PHNPC_IsNPC",    true)     -- BOOL  (condition XML : BOOL true)
    zombie:setVariable("PHNPC_IsFemale", isFemale)

    -- 1b. Désactiver les mécaniques zombie (safeCall = ignore si méthode absente en B42)
    safeCall(zombie, "setNoTeeth",           true)
    safeCall(zombie, "setTarget",            nil)
    safeCall(zombie, "clearAggroList")
    safeCall(zombie, "setEatBodyTarget",     nil, false)
    safeCall(zombie, "setTimeSinceSeenFlesh", 1000000)

    -- 1c. (Bandits pattern) setBumpType force la réévaluation AnimEngine sans toucher ActionContext
    --     ActionContext.clear() n'est PAS exposé à Kahlua → erreur "non-table" à chaque appel.

    -- 2. Variables de vitesse
    pcall(function() zombie:setVariable("LimpSpeed", 0.80) end)
    pcall(function() zombie:setVariable("RunSpeed",  0.75) end)
    pcall(function() zombie:setVariable("WalkSpeed", 1.04) end)

    -- 3. Variables d'animation — désactivent le comportement zombie dans les AnimSets
    pcall(function() zombie:setVariable("NoLungeTarget", true) end)
    pcall(function() zombie:setVariable("ZombieHitReaction", "Chainsaw") end)

    -- 4. Type de marche humaine (setWalkType supprimé : pose zombiewalktype en read-only)
    pcall(function() zombie:setVariable("GCWalkType", "Walk") end)

    -- 5. Silencier les sons zombie
    pcall(function()
        local emitter = zombie:getEmitter()
        if emitter then emitter:stopAll() end
    end)

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

    -- 11. Empêcher le moteur de re-vêtir l'entité automatiquement
    pcall(function() zombie:setDressInRandomOutfit(false) end)

    -- 12. Forcer une transition d'état pour déclencher la réévaluation des AnimSets
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

    -- Brancher NPC_Brain : le cerveau lira/écrira npcData.fsmState à chaque tick
    local Brain = PHNPC.getModule("NPC_Brain")
    if Brain then pcall(function() Brain.register(npcData) end) end
end

-- ============================================================
-- Helper B42 : appelle obj:method(...) uniquement si la méthode existe.
-- Évite les "Object tried to call nil in pcall" causés par des méthodes
-- supprimées en B42 (setTimeSinceSeenFlesh, stopSoundByName, etc.).
-- ============================================================

local function safeCall(obj, method, ...)
    if obj and obj[method] then
        pcall(obj[method], obj, ...)
    end
end

-- ============================================================
-- Enforce — appliqué chaque tick pour éviter les régressions moteur
-- ============================================================

local function enforceNPC(zombie)
    if not zombie then return end
    local dead = false
    pcall(function() dead = zombie:isDead() end)
    if dead then return end

    -- Flags identité / anti-IA-zombie (setVariable = méthode la plus sûre et stable)
    pcall(function() zombie:setVariable("PHNPC_IsNPC",        true)       end)
    pcall(function() zombie:setVariable("Bandit",             true)       end)
    pcall(function() zombie:setVariable("NoLungeTarget",      true)       end)  -- Bandits : NoLungeTarget (pas NoLungeAttack)
    pcall(function() zombie:setVariable("ZombieHitReaction",  "Chainsaw") end)

    -- KEY (pattern Bandits B42.18) : setUseless(true) neutralise l'IA zombie chaque tick.
    -- Le moteur ne déclenche plus d'action propre ; nos appels pathToLocationF / doSprinter etc.
    -- fonctionnent indépendamment de cet état et continuent de s'exécuter normalement.
    safeCall(zombie, "setUseless", true)

    -- Désactiver cible + posture humaine (nouvelles méthodes officielles B42.18)
    safeCall(zombie, "setTarget",  nil)
    safeCall(zombie, "setUpright", true)
    safeCall(zombie, "setCanWalk", true)

    -- Intercepter lunge/turnalerted : pattern Bandits (pas de getActionContext().clear())
    pcall(function()
        local asn = zombie:getActionStateName()
        if asn == "lunge" or asn == "turnalerted" then
            safeCall(zombie, "clearAggroList")
            safeCall(zombie, "setTarget",    nil)
            -- setUseless déjà appliqué ci-dessus → annule le lunge sans ActionContext
        end
    end)

    -- Silencer tous les sons zombie d'un coup (stopAll > appels par nom)
    pcall(function()
        local emitter = zombie:getEmitter()
        if emitter then safeCall(emitter, "stopAll") end
    end)
end

-- ============================================================
-- Suivi du joueur
-- ============================================================

local function doFollow(zombie, player)
    if not zombie or not player then return end
    if not instanceof(zombie, "IsoZombie") then return end
    if not instanceof(player, "IsoPlayer") then return end

    -- Distance via méthode Java native (évite le calcul manuel)
    local dist = FOLLOW_RUN_DIST + 1
    pcall(function() dist = zombie:DistTo(player) end)

    if dist <= FOLLOW_MIN_DIST then
        -- Assez proche : arrêter et faire face au joueur
        pcall(function()
            if zombie.setPath2  then zombie:setPath2(nil)   end
            if zombie.setMoving then zombie:setMoving(false) end
            zombie:faceThisObject(player)
            local fwd = player:getForwardDirection()
            if fwd then zombie:setForwardDirection(fwd) end
        end)
        return
    end

    -- Nouvelle API vitesse B42.18 : doSprinter / doFastShambler
    -- Remplace zombieWalkType + setWalkType (read-only / absent en B42.18)
    pcall(function()
        if dist > FOLLOW_RUN_DIST then
            if zombie.doSprinter     then zombie:doSprinter()     end
        else
            if zombie.doFastShambler then zombie:doFastShambler() end
        end
    end)

    -- Pathfinding : pathToLocationF (stable B42) avec fallback WalkTo
    pcall(function()
        local px, py, pz = player:getX(), player:getY(), player:getZ()
        local dx = zombie:getX() - px
        local dy = zombie:getY() - py
        local len = math.max(dist, 0.01)
        local targetX = px + (dx / len) * FOLLOW_OFFSET
        local targetY = py + (dy / len) * FOLLOW_OFFSET
        if zombie.pathToLocationF then
            zombie:pathToLocationF(targetX, targetY, pz)
        elseif zombie.WalkTo then
            zombie:WalkTo(targetX, targetY, pz)
        end
    end)
end

-- ============================================================
-- Rôdage autonome (joueur loin ou hors de portée)
-- Le NPC choisit un point aléatoire à WANDER_RANGE cases et s'y dirige.
-- Une nouvelle cible est choisie à l'arrivée ou après WANDER_HOLD ticks.
-- ============================================================
local function doWander(zombie)
    if not instanceof(zombie, "IsoZombie") then return end

    local wt = _wanderTargets[zombie]
    local zx, zy = zombie:getX(), zombie:getY()

    -- Arrivé à destination ?
    local arrived = false
    if wt then
        local ddx, ddy = zx - wt.x, zy - wt.y
        arrived = (ddx * ddx + ddy * ddy) <= 4.0   -- ≤ 2 cases
    end

    local expired = wt and ((_wanderTick - wt.setAt) >= WANDER_HOLD)
    if (not wt) or arrived or expired then
        -- Décalage aléatoire dans [-WANDER_RANGE, +WANDER_RANGE]
        local ox = ZombRand(WANDER_RANGE * 2 + 1) - WANDER_RANGE
        local oy = ZombRand(WANDER_RANGE * 2 + 1) - WANDER_RANGE
        -- Déplacement minimal pour éviter de tourner sur place
        if ox == 0 then ox = 1 end
        if oy == 0 then oy = 1 end
        local tx = zx + ox
        local ty = zy + oy
        _wanderTargets[zombie] = { x = tx, y = ty, z = zombie:getZ(), setAt = _wanderTick }
        -- Nouvelle API vitesse B42.18 : doFakeShambler = marche naturelle
        pcall(function() if zombie.doFakeShambler then zombie:doFakeShambler() end end)
        -- Pathfinding : pathToLocationF (stable B42) avec fallback WalkTo
        pcall(function()
            local tz = zombie:getZ()
            if zombie.pathToLocationF then
                zombie:pathToLocationF(tx, ty, tz)
            elseif zombie.WalkTo then
                zombie:WalkTo(tx, ty, tz)
            end
        end)
    end
end

-- ============================================================
-- Comportement autonome piloté par NPC_Brain
-- Lit npcData.fsmState (mis à jour par NPC_Brain chaque tick) et dispatch
-- vers l'action physique correspondante.
-- ============================================================
local function doBrainAction(zombie, npcData)
    if not instanceof(zombie, "IsoZombie") then return end
    local state = npcData and npcData.fsmState or "wander"

    if state == "wander" or state == "work" then
        -- Errance / travail : se déplacer vers un point aléatoire voisin
        doWander(zombie)

    elseif state == "flee" then
        -- Fuir en sens opposé de la MENACE, pas forcément du joueur.
        -- Priorité décroissante :
        --   1. npcData.fsmTarget  — position stockée par NPC_Brain.evaluateThreat
        --   2. Zombie hostile le plus proche (scan léger, cap 60 entités, rayon 12 cases)
        --   3. Joueur (fallback si aucune menace physique détectée)
        local nx, ny = zombie:getX(), zombie:getY()
        local tx, ty  -- coordonnées de la source de menace

        -- 1. Menace explicite stockée par NPC_Brain
        local ft = npcData and npcData.fsmTarget
        if ft and type(ft) == "table" and ft.x then
            tx, ty = ft.x, ft.y
        end

        -- 2. Zombie hostile le plus proche (pas un NPC)
        if not tx then
            pcall(function()
                local cell = zombie:getCell()
                if not cell then return end
                local zList = cell:getZombieList()
                if not zList then return end
                local best, bestD = nil, 999
                for i = 0, math.min(zList:size() - 1, 60) do
                    local z = zList:get(i)
                    if z and z ~= zombie then
                        local isNPC = false
                        pcall(function() isNPC = z:getVariableBoolean("PHNPC_IsNPC") end)
                        if not isNPC then
                            local ddx, ddy = z:getX() - nx, z:getY() - ny
                            local d = ddx * ddx + ddy * ddy
                            if d < bestD and d < 144 then  -- rayon 12 cases
                                best, bestD = z, d
                            end
                        end
                    end
                end
                if best then tx, ty = best:getX(), best:getY() end
            end)
        end

        -- 3. Fallback : fuir en sens opposé du joueur
        if not tx then
            local player = getPlayer()
            if player then tx, ty = player:getX(), player:getY() end
        end

        if tx then
            local dx, dy = nx - tx, ny - ty
            local len    = math.max(math.sqrt(dx * dx + dy * dy), 0.01)
            local destX  = nx + (dx / len) * 12
            local destY  = ny + (dy / len) * 12
            -- Nouvelle API vitesse B42.18
            pcall(function() if zombie.doSprinter then zombie:doSprinter() end end)
            -- Pathfinding : pathToLocationF avec fallback WalkTo
            pcall(function()
                local tz = zombie:getZ()
                if zombie.pathToLocationF then
                    zombie:pathToLocationF(destX, destY, tz)
                elseif zombie.WalkTo then
                    zombie:WalkTo(destX, destY, tz)
                end
            end)
        end

    elseif state == "guard" or state == "defend" or state == "trade" then
        -- Rester sur place : stopper le pathfinding
        pcall(function()
            zombie:setPath2(nil)
            zombie:setVariable("zombieWalkType", "")
        end)

    else
        -- idle et cas non gérés : errance légère
        doWander(zombie)
    end
end

-- ============================================================
-- Boucle principale
-- ============================================================

-- Désactive le tiered zombie updates (même logique que Bandits BanditZombie.flush())
-- Appelé ici + dans 00_Init.lua:EveryOneMinute pour garantir le hook OnZombieUpdate
local function _disableTiered()
    pcall(function() getCore():setOptionTieredZombieUpdates(false) end)
end

Events.EveryOneMinute.Add(_disableTiered)

-- ============================================================
-- Réinitialisation des caches sur chargement de partie
-- (gère aussi le cas "charger une sauvegarde sans quitter" en solo)
-- ============================================================
Events.OnGameStart.Add(function()
    -- Vider toutes les tables locales (objets Java différents après reload)
    _convertedNPCs = {}
    _wanderTargets  = {}
    _wanderTick     = 0
    -- Vider le registre actif (sera reconstruit par OnZombieUpdate)
    if PHNPC._activeNPCs then
        for k in pairs(PHNPC._activeNPCs) do PHNPC._activeNPCs[k] = nil end
    end
    print("[PHNPC] OnGameStart: caches locaux réinitialisés — re-conversion des NPC à venir")
end)

-- ============================================================
-- Persistance de l'état FSM vers ModData (toutes les ~4 secondes)
-- Garantit que l'état FSM et la santé survivent aux reloads de partie.
-- ============================================================
local _fsmSaveTick = 0
Events.OnTick.Add(function()
    _fsmSaveTick = _fsmSaveTick + 1
    if _fsmSaveTick < 120 then return end
    _fsmSaveTick = 0
    for zombie, _ in pairs(_convertedNPCs) do
        local npcData = PHNPC._activeNPCs and PHNPC._activeNPCs[zombie]
        if npcData then
            pcall(function()
                local md = zombie:getModData()
                if md then
                    md.PHNPC_FsmState = npcData.fsmState or "idle"
                    md.PHNPC_Health   = npcData.health   or 100
                end
            end)
        end
    end
end)

local function onZombieUpdate(zombie)
    if not zombie then return end
    -- Guard null Java : un zombie Java null n'est pas nil en Kahlua,
    -- instanceof retourne false et évite le crash "non-table: null".
    if not instanceof(zombie, "IsoZombie") then return end

    -- DEBUG : confirme que l'event fire (imprime au 1er appel puis toutes les 200 calls)
    PHNPC_FollowTick._dbgCount = (PHNPC_FollowTick._dbgCount or 0) + 1
    if PHNPC_FollowTick._dbgCount == 1 or PHNPC_FollowTick._dbgCount % 200 == 0 then
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

    -- Méthode B : ModData — persiste dans la sauvegarde, survit aux reloads et déchargements de chunk.
    -- Le serveur écrit md.PHNPC_IsNPC = true lors du spawn. Cette valeur est sérialisée
    -- avec l'entité et rechargée depuis le disque à chaque reload de partie.
    -- ⚠️ PZ peut sérialiser Java Boolean true comme String "true" selon les builds
    --    → on teste les deux représentations pour garantir la détection post-reload.
    if not isNPC then
        local mdOk, md = pcall(function() return zombie:getModData() end)
        if mdOk and md then
            local v  = md.PHNPC_IsNPC
            local fv = md.PHNPC_IsFemale
            if v == true or v == "true" then
                isNPC    = true
                isFemale = (fv == true or fv == "true")
            end
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
        -- Marquer AVANT pour éviter une boucle infinie si convertToNPC lève une erreur
        _convertedNPCs[zombie] = true
        convertToNPC(zombie, isFemale)
        attachDataModel(zombie)
    end

    -- Enforce chaque tick
    enforceNPC(zombie)

    -- Dispatch comportemental :
    --   followMode = true  → NPC suit le joueur (commandé explicitement)
    --   followMode = false → NPC_Brain pilote le comportement (défaut)
    local npcData = PHNPC._activeNPCs and PHNPC._activeNPCs[zombie]
    if npcData and npcData.followMode then
        -- Mode suivi : NPC suit le joueur actif
        local player = getPlayer()
        if player then
            _wanderTargets[zombie] = nil  -- annuler toute cible de rôdage
            doFollow(zombie, player)
        end
    else
        -- Mode autonome : NPC_Brain décide (fsmState → action physique)
        doBrainAction(zombie, npcData)
    end
end

-- ============================================================
-- Nettoyage du registre (entités mortes ou déchargées)
-- ============================================================

Events.OnTick.Add(function()
    _wanderTick = _wanderTick + 1   -- incrémenté chaque tick pour horodatage des cibles de rôdage
    PHNPC_FollowTick._cleanTick = (PHNPC_FollowTick._cleanTick or 0) + 1
    if PHNPC_FollowTick._cleanTick < 300 then return end
    PHNPC_FollowTick._cleanTick = 0

    -- Nettoyer les entrées mortes/déchargées des trois tables
    local toRemove = {}
    for isoObj, _ in pairs(PHNPC._activeNPCs) do
        local ok, dead = pcall(function() return isoObj:isDead() end)
        if not ok or dead then toRemove[#toRemove + 1] = isoObj end
    end
    for _, isoObj in ipairs(toRemove) do
        -- Désenregistrer du cerveau IA avant de supprimer le npcData
        local nd = PHNPC._activeNPCs[isoObj]
        if nd and nd.id then
            local Brain = PHNPC.getModule("NPC_Brain")
            if Brain then pcall(function() Brain.unregister(nd.id) end) end
        end
        PHNPC._activeNPCs[isoObj]  = nil
        _convertedNPCs[isoObj]     = nil
        _wanderTargets[isoObj]     = nil
    end
end)

-- ============================================================
-- Enregistrement
-- ============================================================

Events.OnZombieUpdate.Add(onZombieUpdate)

PHNPC.registerModule("PHNPC_FollowTick", PHNPC_FollowTick)
return PHNPC_FollowTick
