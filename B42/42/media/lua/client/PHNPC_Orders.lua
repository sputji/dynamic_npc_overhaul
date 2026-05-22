--[[
    PHNPC_Orders.lua  v0.0.9b  (client)
    Ordres adresses aux NPCs : recruter, suivre, rester, congedier, supprimer,
    attaquer, fuir, aller la-bas (goTo).

    v0.0.9b : Ajout goToLocation + PHGoToCursor (ISBuildingObject)
      - enterGoToMode(npc)  : active le curseur tuile verte vanilla
      - goToLocation(npc,x,y,z) : demarre le deplacement, etat "goingto"

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

print("[PHNPC] Orders v0.0.9b loaded")

-- ============================================================
-- "VA LA-BAS" : CURSOR TILE VERTE + ORDRE DE DEPLACEMENT
-- Pattern GCCompanionPanelGoTo.lua (NPC_Helper_Mod B42.18)
-- ============================================================

-- Curseur "tuile verte" de selection de destination
-- Lazy-init : ISBuildingObject peut ne pas etre pret au chargement
local PHGoToCursor = nil

local function initGoToCursor()
    if PHGoToCursor then return true end
    if not ISBuildingObject then return false end
    PHGoToCursor = ISBuildingObject:derive("PHGoToCursor")

    -- Appele quand le joueur clique sur une tuile valide
    function PHGoToCursor:create(x, y, z, north, sprite)
        local npc = self.targetNPC
        if not npc then return end
        PHNPC.goToLocation(npc, x + 0.5, y + 0.5, z)
    end

    function PHGoToCursor:isValid(square)
        if not square then return false end
        local ok, result = pcall(function()
            return square:TreatAsSolidFloor() and not square:isSolid() and not square:isSolidTrans()
        end)
        return ok and result == true
    end

    function PHGoToCursor:render(x, y, z, square)
        local hc
        if self:isValid(square) then
            hc = getCore():getGoodHighlitedColor()
        else
            hc = getCore():getBadHighlitedColor()
        end
        pcall(function()
            self:getFloorCursorSprite():RenderGhostTileColor(x, y, z, hc:getR(), hc:getG(), hc:getB(), 0.8)
        end)
    end

    function PHGoToCursor:new(character, npc)
        local o = {}
        setmetatable(o, self)
        self.__index = self
        o:init()
        o:setSprite("")
        o:setNorthSprite("")
        o.character    = character
        o.player       = character:getPlayerNum()
        o.noNeedHammer = true
        o.skipBuildAction = true
        o.targetNPC    = npc
        return o
    end

    print("[PHNPC] PHGoToCursor initialise")
    return true
end

-- Tenter l'init a la premiere occasion
initGoToCursor()

-- enterGoToMode : active le curseur de selection de tuile pour l'ordre "Va la-bas"
function PHNPC.enterGoToMode(npc)
    local player = getPlayer()
    if not player then return end
    if not initGoToCursor() then
        print("[PHNPC][GoTo] ISBuildingObject non disponible")
        return
    end
    local cursor = PHGoToCursor:new(player, npc)
    pcall(function() getCell():setDrag(cursor, player:getPlayerNum()) end)
    local md = npc:getModData()
    print("[PHNPC][GoTo] Curseur actif pour : " .. tostring(md.PHNPC_Name))
end

-- goToLocation : envoyer le NPC vers une coordonnee precise
function PHNPC.goToLocation(npc, x, y, z)
    local md = npc:getModData()
    md.PHNPC_State = "goingto"
    md.PHNPC_GoToX = x
    md.PHNPC_GoToY = y
    md.PHNPC_GoToZ = z or npc:getZ()
    PHNPC.startMovingTo(npc, x, y, md.PHNPC_GoToZ)
    pcall(function()
        npc:addLineChatElement(string.format(getText("UI_PHNPC_BarkGoTo"), md.PHNPC_Name or "?"), 0.9, 0.9, 0.2)
    end)
    print("[PHNPC][GoTo] " .. tostring(md.PHNPC_Name) .. " -> " .. tostring(x) .. "," .. tostring(y))
end
