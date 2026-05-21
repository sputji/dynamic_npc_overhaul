--[[
    PHNPC_Orders.lua  v1.0  (client)
    Ordres adresses aux NPCs : recruter, suivre, rester, congedier, supprimer,
    attaquer, fuir.

    Toutes les fonctions sont dans PHNPC.xxx => accessibles depuis PHNPC_Menu.lua,
    PHNPC_Update.lua, etc.

    Necessite :
      PHNPC_Actions.lua (PHNPC.stopMoving, PHNPC.startMovingTo, PHNPC.findNearestZombie)
      PHNPC_Core.lua    (PHNPC.recruited, PHNPC.allNPCs)
]]

-- ============================================================
-- ORDRES : RECRUTER / SUIVRE / RESTER / CONGEDIER / SUPPRIMER
-- ============================================================

function PHNPC.recruitNPC(npc)
    local md = npc:getModData()
    md.PHNPC_Recruited = true
    md.PHNPC_State     = "following"
    md.PHNPC_Moving    = false
    md.PHNPC_IdleTick  = 0
    PHNPC.recruited[npc] = true
    -- Transition propre vers idle humain (evite bras tendus zombie au recrutement)
    pcall(function()
        npc:setUseless(false)
        npc:changeState(ZombieIdleState.instance())
        npc:setBumpType("Shrug")
    end)
    pcall(function() npc:addLineChatElement(string.format(getText("UI_PHNPC_BarkRecruit"), md.PHNPC_Name), 0.2, 0.9, 0.2) end)
    print("[PHNPC] Recrute : " .. tostring(md.PHNPC_Name))
end

function PHNPC.followNPC(npc)
    local md = npc:getModData()
    md.PHNPC_State = "following"
    pcall(function() npc:addLineChatElement(string.format(getText("UI_PHNPC_BarkFollow"), md.PHNPC_Name), 0.2, 0.9, 0.2) end)
    print("[PHNPC] Suis le joueur : " .. tostring(md.PHNPC_Name))
end

function PHNPC.stayNPC(npc)
    local md = npc:getModData()
    md.PHNPC_State = "staying"
    PHNPC.stopMoving(npc)
    pcall(function() npc:addLineChatElement(string.format(getText("UI_PHNPC_BarkStay"), md.PHNPC_Name), 0.9, 0.9, 0.2) end)
    print("[PHNPC] Reste ici : " .. tostring(md.PHNPC_Name))
end

function PHNPC.dismissNPC(npc)
    local md = npc:getModData()
    md.PHNPC_Recruited = false
    md.PHNPC_State     = "idle"
    PHNPC.recruited[npc] = nil
    PHNPC.stopMoving(npc)
    pcall(function() npc:addLineChatElement(string.format(getText("UI_PHNPC_BarkDismiss"), md.PHNPC_Name), 0.9, 0.9, 0.2) end)
    print("[PHNPC] Congedie : " .. tostring(md.PHNPC_Name))
end

function PHNPC.deleteNPC(npc)
    -- CRITIQUE : mettre PHNPC_IsNPC=nil AVANT setHealth(0)
    -- Sinon OnZombieUpdate (isNPC check) ressusciterait le NPC au tick suivant
    local md   = npc:getModData()
    local name = md.PHNPC_Name or "?"
    md.PHNPC_IsNPC = nil
    -- Fermer l'inventaire si c'est ce NPC qui est ouvert
    if PHNPC._openInventoryNPC == npc then PHNPC._openInventoryNPC = nil end
    -- Nettoyer toutes les references (enforceNPC ne traitera plus ce NPC)
    PHNPC.allNPCs[npc]           = nil
    PHNPC.recruited[npc]         = nil
    PHNPC._followTimers[npc]     = nil
    PHNPC._combatTimers[npc]     = nil
    PHNPC._attackCooldowns[npc]  = nil
    -- Mort naturelle via setHealth(0) : PZ cree un corpse lootable avec tout l'inventaire
    pcall(function()
        npc:setHealth(0)
    end)
    print("[PHNPC] Supprime : " .. name)
end

-- ============================================================
-- ORDRES COMBAT
-- ============================================================

function PHNPC.orderAttackNPC(npc)
    local md = npc:getModData()
    md.PHNPC_CombatMode = "auto"
    if md.PHNPC_State ~= "defending" then
        md.PHNPC_PrevState = md.PHNPC_State
        md.PHNPC_State     = "defending"
    end
    pcall(function() npc:addLineChatElement(string.format(getText("UI_PHNPC_BarkAttack"), md.PHNPC_Name or "?"), 0.9, 0.2, 0.2) end)
end

function PHNPC.orderFleeNPC(npc)
    local md = npc:getModData()
    md.PHNPC_State = "staying"   -- s'arrete apres la fuite (evite la boucle npcFlightStep)
    local enemy, eDist = PHNPC.findNearestZombie(npc, 20)
    local nx, ny, nz = npc:getX(), npc:getY(), npc:getZ()
    if enemy and eDist < 20 then
        local ex, ey = enemy:getX(), enemy:getY()
        local dx = nx - ex
        local dy = ny - ey
        local d = math.sqrt(dx * dx + dy * dy)
        if d > 0 then dx, dy = dx / d, dy / d end
        PHNPC.startMovingTo(npc, nx + dx * 15, ny + dy * 15, nz)
    else
        local player = getPlayer()
        if player then PHNPC.startMovingTo(npc, player:getX(), player:getY(), player:getZ()) end
    end
    pcall(function() npc:addLineChatElement(string.format(getText("UI_PHNPC_BarkFlee"), md.PHNPC_Name or "?"), 0.9, 0.4, 0.2) end)
end

function PHNPC.toggleCombatNPC(npc)
    local md = npc:getModData()
    if md.PHNPC_CombatMode == "off" then
        md.PHNPC_CombatMode = "auto"
        pcall(function() npc:addLineChatElement(string.format(getText("UI_PHNPC_BarkCombatOn"), md.PHNPC_Name or "?"), 0.2, 0.9, 0.2) end)
    else
        md.PHNPC_CombatMode = "off"
        pcall(function() npc:addLineChatElement(string.format(getText("UI_PHNPC_BarkCombatOff"), md.PHNPC_Name or "?"), 0.9, 0.9, 0.2) end)
    end
end

print("[PHNPC] Orders v1.0 loaded")
