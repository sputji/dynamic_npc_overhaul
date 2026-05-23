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
-- Priorite : arme equipee en main > arme corps a corps > baton/couteau > poings
local function getNPCWeapon(npc)
    -- Arme deja en main ?
    local ok1, primary = pcall(function() return npc:getPrimaryHandItem() end)
    if ok1 and primary then
        local ok2, isWeapon = pcall(function() return primary:isWeapon() end)
        if ok2 and isWeapon then return primary end
    end
    -- Chercher dans l'inventaire
    local inv = npc:getInventory()
    if not inv then return nil end
    -- Essayer arme corps a corps d'abord
    local function tryGet(typeName)
        local ok, item = pcall(function() return inv:getFirstTypeRecurse(typeName) end)
        return ok and item or nil
    end
    return tryGet("Base.Bat")
        or tryGet("Base.Axe")
        or tryGet("Base.Crowbar")
        or tryGet("Base.Knife")
        or tryGet("Base.PoliceBaton")
        or tryGet("Base.Shovel")
        or tryGet("Base.Hammer")
        or nil
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
        local weapon = getNPCWeapon(npc)
        if weapon then
            pcall(function() npc:setEquippedItem(weapon) end)
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
        -- Trop loin : se deplacer vers le zombie
        PHNPC.startMovingTo(npc, target:getX(), target:getY(), target:getZ())
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

print("[PHNPC] Combat v0.0.9i loaded")
