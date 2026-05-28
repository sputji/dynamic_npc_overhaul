--[[
    PHNPC_Combat.lua  v0.0.9c  (client)
    IA Combat NPC : attaquer les zombies proches (npcCombatStep)
    IA Fuite NPC  : fuir si HP < 30% (npcFlightStep)

    v0.0.9c :
      - npcCombatStep : utilise les armes de l'inventaire NPC (weapon type check)
        + NoiseTimer pour signaler le bruit des attaques a PHNPC_Danger.lua
      - npcFlightStep : utilise findEscapeDirection (PHNPC_Pathfind.lua) pour
        trouver une direction de fuite libre en 8 angles. Si zone degagee disponible
        (findClearAreaNear), fuir vers cette zone ; sinon se replier vers le joueur.

    Pattern : NHM GCCombatActionsAttack.lua + GCHelpersEscape.lua simplifies
    Necessite :
      PHNPC_Actions.lua  (PHNPC.startMovingTo, PHNPC.stopMoving, PHNPC.findNearestZombie)
      PHNPC_Barks.lua    (PHNPC.sayBark)
      PHNPC_Pathfind.lua (PHNPC.findEscapeDirection, PHNPC.findClearAreaNear)
]]

-- ============================================================
-- Helpers internes : detecter et utiliser les armes de l'inventaire
-- ============================================================

-- Retourne l'arme la plus adaptee dans l'inventaire NPC
-- v0.0.12 : durcissement Kahlua B42
--   - Evite item:isWeapon() (non fiable selon type d'item expose Lua)
--   - Utilise instanceof(item, "HandWeapon") + garde-fous methodes
--   - Plus de crash en boucle sur scoreWeapon/getNPCWeapon
local function scoreWeapon(item)
    if not item then return 0 end

    local isHandWeapon = false
    pcall(function() isHandWeapon = instanceof(item, "HandWeapon") end)
    if not isHandWeapon then return 0 end

    local isRanged = false
    pcall(function() isRanged = item:isRanged() end)
    if isRanged then return 0 end  -- pas d'armes a feu en combat melee NPC pour l'instant

    local dmg = 1.0
    pcall(function()
        local maxD = item.getMaxDamage and item:getMaxDamage() or nil
        local minD = item.getMinDamage and item:getMinDamage() or nil
        dmg = maxD or minD or 1.0
    end)

    local cond, condMax = 1, 1
    pcall(function() cond = item:getCondition() or 1 end)
    pcall(function() condMax = item:getConditionMax() or 1 end)
    local condRatio = (condMax > 0) and (cond / condMax) or 0.5
    return (dmg * 10) + (condRatio * 1)
end

local function getNPCWeapon(npc)
    local primary
    pcall(function() primary = npc:getPrimaryHandItem() end)
    local bestItem = primary
    local bestScore = scoreWeapon(primary)

    local inv
    pcall(function() inv = npc:getInventory() end)
    if not inv then return bestItem end

    -- Scan complet et selection du meilleur score
    local items
    pcall(function() items = inv:getItems() end)
    if not items then return bestItem end
    local n = 0
    pcall(function() n = items:size() end)
    for i = 0, n - 1 do
        local it
        pcall(function() it = items:get(i) end)
        local s = scoreWeapon(it)
        if s > bestScore then
            bestScore = s
            bestItem = it
        end
    end
    return bestItem
end

-- Variantes d'attaque selon le type d'arme
local function getAttackAnim(weapon)
    if not weapon then
        -- A mains nues
        local punches = {"Shove", "FrontKick", "HighKick", "Shove"}
        return punches[(ZombRand(#punches) + 1)]
    end
    local typeName = ""
    pcall(function() typeName = weapon:getType() or "" end)
    if typeName:find("Axe") or typeName:find("Shovel") then
        return "HitLeft"
    elseif typeName:find("Bat") or typeName:find("Baton") or typeName:find("Crowbar") then
        return "HitLeft"
    elseif typeName:find("Knife") then
        return "Shove"
    end
    return "HitLeft"
end

-- ============================================================
-- COMBAT NPC : chercher et attaquer les zombies proches
-- Pattern GCCombatActionsAttack.lua (NPC_Helper_Mod) simplifie
-- ============================================================
function PHNPC.npcCombatStep(npc)
    local md = npc:getModData()
    if not md.PHNPC_Recruited then return end
    if md.PHNPC_CombatMode == "off" then return end
    -- Pas de combat si en fuite
    if md.PHNPC_State == "fleeing" then return end
    -- v0.0.9i FIX BUG 2/4/5 : ordres explicites du joueur prioritaires.
    -- Combat ne doit JAMAIS interrompre "Va la-bas" / "Mets-toi a l'abri".
    -- Le NPC n'engage le combat que s'il est en mode neutre (following/staying/free).
    if md.PHNPC_State == "goingto" or md.PHNPC_State == "shelter" then return end

    -- Decrementer cooldown attaque
    if (md.PHNPC_AttackCooldown or 0) > 0 then
        md.PHNPC_AttackCooldown = md.PHNPC_AttackCooldown - 1
        return
    end

    -- Timer : ne pas evaluer chaque tick
    PHNPC._combatTimers[npc] = (PHNPC._combatTimers[npc] or 0) + 1
    if PHNPC._combatTimers[npc] < (PHNPC.COMBAT_TICK_RATE or 30) then return end
    PHNPC._combatTimers[npc] = 0

    -- Chercher zombie dans le rayon de combat
    local target, dist = PHNPC.findNearestZombie(npc, PHNPC.COMBAT_RANGE or 8)

    if not target then
        -- Plus de cible : quitter l'etat "defending" si on y etait
        if md.PHNPC_State == "defending" then
            md.PHNPC_State = md.PHNPC_PrevState or "following"
            md.PHNPC_PrevState = nil
            -- v0.0.10 FIX BUG #4 : forcer un nouveau pathfind apres sortie du combat.
            -- Pendant defending, pathToLocationF a ete appele sur les coords du
            -- zombie => PathX/PathY pointe maintenant n'importe ou. Si on ne
            -- reset pas, Update.lua "goingto" voit needNewPath=false et reste
            -- planté (effet "allez-retour bizarre" rapporte au test joueur).
            md.PHNPC_PathX = nil
            md.PHNPC_PathY = nil
            md.PHNPC_PathZ = nil
            md.PHNPC_Moving = false
        end
        if md.PHNPC_Moving then
            PHNPC.stopMoving(npc)
        end
        return
    end

    -- Entrer en mode defense si pas deja dedans
    if md.PHNPC_State ~= "defending" then
        md.PHNPC_PrevState = md.PHNPC_State
        md.PHNPC_State     = "defending"
        PHNPC.sayBark(npc, "defending", 0.9, 0.2, 0.2)
        -- Signaler bruit de combat (attire zombies via PHNPC_Danger.lua)
        md.PHNPC_NoiseTimer = 200
    end

    if dist <= (PHNPC.COMBAT_ATTACK_RANGE or 1.5) then
        -- Assez proche : attaquer
        local targetDead = false
        pcall(function() targetDead = target:isDead() end)
        if targetDead then return end

        pcall(function() npc:faceLocationF(target:getX(), target:getY()) end)

        -- Equiper l'arme si disponible
        -- v0.0.10 FIX BUG #3 : setEquippedItem N'EXISTE PAS en B42.18 sur IsoZombie.
        -- Depuis v0.0.7a, l'appel etait masque silencieusement par pcall =>
        -- les NPCs n'equipaient JAMAIS leur arme et frappaient toujours a mains
        -- nues. La bonne methode est setPrimaryHandItem (verifie : utilise dans
        -- PHNPC_Convert.lua:47 et PHNPC_Loot.lua:105).
        local weapon = getNPCWeapon(npc)
        if weapon then
            pcall(function() npc:setPrimaryHandItem(weapon) end)
        end

        local anim = getAttackAnim(weapon)
        pcall(function() npc:setBumpType(anim) end)
        -- Endommager le zombie (knockDown + setHealth pour le tuer proprement)
        pcall(function()
            target:knockDown(true)
            local tmd = target:getModData()
            -- Ne pas endommager nos propres NPCs
            if not tmd.PHNPC_IsNPC then
                local zh = target:getHealth() - 25
                if zh <= 0 then zh = 0 end
                target:setHealth(zh)
            end
        end)

        md.PHNPC_AttackCooldown = 60
        -- Bruit de l'attaque
        md.PHNPC_NoiseTimer = (md.PHNPC_NoiseTimer or 0) + 150

        print("[PHNPC][COMBAT] " .. tostring(md.PHNPC_Name) .. " : " .. anim
              .. " dist=" .. string.format("%.1f", dist))
    else
        -- Trop loin : se deplacer vers le zombie EN COURANT (v0.0.9k)
        PHNPC.startMovingTo(npc, target:getX(), target:getY(), target:getZ(), "Run")
    end
end

-- ============================================================
-- FUITE NPC : fuir si HP < 30%
-- v0.0.9c : utilise findEscapeDirection (8 angles) et findClearAreaNear
-- Pattern GCHelpersEscape.lua (NPC_Helper_Mod) adapte
-- ============================================================
function PHNPC.npcFlightStep(npc, player)
    local md = npc:getModData()
    if not md.PHNPC_Recruited then return end
    -- v0.0.9i FIX BUG 2/5 : ne pas interrompre les ordres explicites.
    -- Si HP critique le NPC peut quand meme fuir, mais sinon respecter goingto/shelter.
    local hpRatioOverride = (md.PHNPC_Health or 100) / (md.PHNPC_MaxHealth or 100)
    if (md.PHNPC_State == "goingto" or md.PHNPC_State == "shelter")
       and hpRatioOverride > 0.15 then
        return
    end

    local hp    = md.PHNPC_Health    or 100
    local maxHp = md.PHNPC_MaxHealth or 100
    local ratio = hp / maxHp

    if ratio < (PHNPC.FLEE_HP_RATIO or 0.30) then
        -- Passer en etat fuite
        if md.PHNPC_State ~= "fleeing" then
            md.PHNPC_PrevState = md.PHNPC_State
            md.PHNPC_State     = "fleeing"
            pcall(function()
                npc:addLineChatElement(string.format(getText("UI_PHNPC_FleeHurt"), md.PHNPC_Name or "?"), 0.9, 0.2, 0.2)
            end)
        end

        local enemy, eDist = PHNPC.findNearestZombie(npc, 25)

        if enemy and eDist < 25 then
            local tx, ty

            -- 1. Tenter de trouver une zone degagee (peu de zombies)
            if PHNPC.findClearAreaNear then
                tx, ty = PHNPC.findClearAreaNear(npc:getX(), npc:getY(), npc:getZ(), PHNPC.FLEE_DISTANCE or 15)
            end

            -- 2. Sinon utiliser findEscapeDirection (8 angles)
            if not tx then
                if PHNPC.findEscapeDirection then
                    tx, ty = PHNPC.findEscapeDirection(npc, enemy, PHNPC.FLEE_DISTANCE or 15)
                else
                    -- Fallback : direction opposee simple
                    local nx2, ny2 = npc:getX(), npc:getY()
                    local ex, ey   = enemy:getX(), enemy:getY()
                    local dx, dy   = nx2 - ex, ny2 - ey
                    local d = math.sqrt(dx * dx + dy * dy)
                    if d > 0 then dx, dy = dx / d, dy / d end
                    tx = nx2 + dx * (PHNPC.FLEE_DISTANCE or 15)
                    ty = ny2 + dy * (PHNPC.FLEE_DISTANCE or 15)
                end
            end

            -- 3. Si la destination est trop loin du joueur, se rapprocher du joueur
            local target = player or getPlayer()
            if target then
                local pdx = tx - target:getX()
                local pdy = ty - target:getY()
                if (pdx * pdx + pdy * pdy) > 30 * 30 then
                    tx = target:getX() + (npc:getX() - target:getX()) * 0.3
                    ty = target:getY() + (npc:getY() - target:getY()) * 0.3
                end
            end

            PHNPC.startMovingTo(npc, tx, ty, npc:getZ())
        else
            -- Pas de zombie proche : se replier vers le joueur
            local target = player or getPlayer()
            if target then
                PHNPC.startMovingTo(npc, target:getX(), target:getY(), target:getZ())
            end
            md.PHNPC_State = md.PHNPC_PrevState or "following"
            md.PHNPC_PrevState = nil
        end
    else
        -- HP OK : sortir de l'etat fuite
        if md.PHNPC_State == "fleeing" then
            md.PHNPC_State     = md.PHNPC_PrevState or "following"
            md.PHNPC_PrevState = nil
            pcall(function()
                npc:addLineChatElement(string.format(getText("UI_PHNPC_FleeOk"), md.PHNPC_Name or "?"), 0.2, 0.9, 0.2)
            end)
        end
    end
end

print("[PHNPC] Combat v0.0.9l loaded")
