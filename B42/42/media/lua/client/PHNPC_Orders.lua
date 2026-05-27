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

--[[
    PHNPC_Orders.lua  v0.0.9d  (client)
    Ordres adresses aux NPCs.

    v0.0.9d : Refonte complete des ordres pour correspondre aux etats
      followNPC     : "following" — suit le joueur
      stayNPC       : "staying"   — reste dans une zone memorisee
      goToLocation  : "goingto"   — va a une destination, puis staying
      attackOrderNPC: "attacking" — attaque puis retour base
      shelterNPC    : "shelter"   — cherche zone safe, puis staying
      freeNPC       : "free"      — libre mais dans l'equipe
      quitTeamNPC   : dismissed   — quitte definitivement l'equipe
      toggleCombatNPC : AUTO/OFF

    Necessite :
      PHNPC_Actions.lua (PHNPC.stopMoving, PHNPC.startMovingTo)
      PHNPC_Core.lua    (PHNPC.recruited, PHNPC.allNPCs)
      PHNPC_Log.lua     (PHNPC.Log.*)
]]

-- ============================================================
-- RECRUTEMENT / EQUIPE
-- ============================================================

function PHNPC.recruitNPC(npc)
    if not npc then return end
    local md = npc:getModData()
    if not md then return end
    md.PHNPC_Recruited  = true
    md.PHNPC_State      = "following"
    md.PHNPC_Moving     = false
    md.PHNPC_IdleTick   = 0
    md.PHNPC_CombatMode = md.PHNPC_CombatMode or "auto"
    PHNPC.recruited[npc] = true
    pcall(function()
        npc:setUseless(false)
        npc:changeState(ZombieIdleState.instance())
        npc:setBumpType("Shrug")
    end)
    pcall(function()
        npc:addLineChatElement(string.format(getText("UI_PHNPC_BarkRecruit"), md.PHNPC_Name), 0.2, 0.9, 0.2)
    end)
    PHNPC.Log.info("Orders", "Recrute : " .. tostring(md.PHNPC_Name))
end

-- ============================================================
-- SUIVI JOUEUR
-- ============================================================

function PHNPC.followNPC(npc)
    if not npc then return end
    local md = npc:getModData()
    if not md then return end
    md.PHNPC_State  = "following"
    md.PHNPC_ZoneX  = nil  -- effacer la zone precedente
    md.PHNPC_ZoneY  = nil
    md.PHNPC_LastPX = nil  -- forcer un recalcul immediat
    md.PHNPC_LastPY = nil
    pcall(function()
        npc:addLineChatElement(string.format(getText("UI_PHNPC_BarkFollow"), md.PHNPC_Name or "?"), 0.2, 0.9, 0.2)
    end)
    PHNPC.Log.info("Orders", tostring(md.PHNPC_Name) .. " -> following")
end

-- ============================================================
-- RESTE ICI (zone libre autour de la position actuelle)
-- ============================================================

function PHNPC.stayNPC(npc)
    if not npc then return end
    local md = npc:getModData()
    if not md then return end
    md.PHNPC_State = "staying"
    md.PHNPC_ZoneX = npc:getX()
    md.PHNPC_ZoneY = npc:getY()
    md.PHNPC_ZoneZ = npc:getZ()
    md.PHNPC_ZoneR = PHNPC.STAY_RADIUS or 5
    PHNPC.stopMoving(npc)
    pcall(function()
        npc:addLineChatElement(string.format(getText("UI_PHNPC_BarkStay"), md.PHNPC_Name or "?"), 0.9, 0.9, 0.2)
    end)
    PHNPC.Log.info("Orders", tostring(md.PHNPC_Name) .. " -> staying at (" .. string.format("%.1f,%.1f", md.PHNPC_ZoneX, md.PHNPC_ZoneY) .. ")")
end

-- ============================================================
-- ATTAQUE LES ZOMBIES (combat actif + retour base)
-- ============================================================

function PHNPC.attackOrderNPC(npc)
    if not npc then return end
    local md = npc:getModData()
    if not md then return end
    md.PHNPC_CombatMode   = "auto"
    md.PHNPC_AttackReturn = true
    md.PHNPC_ZoneX        = npc:getX()
    md.PHNPC_ZoneY        = npc:getY()
    md.PHNPC_ZoneZ        = npc:getZ()
    md.PHNPC_ZoneR        = PHNPC.STAY_RADIUS or 5
    md.PHNPC_State        = "attacking"
    pcall(function()
        npc:addLineChatElement(string.format(getText("UI_PHNPC_BarkAttack"), md.PHNPC_Name or "?"), 0.9, 0.2, 0.2)
    end)
    PHNPC.Log.info("Orders", tostring(md.PHNPC_Name) .. " -> attacking")
end

-- ============================================================
-- METS-TOI A L'ABRI (zone safe via findClearAreaNear)
-- ============================================================

function PHNPC.shelterNPC(npc)
    if not npc then return end
    local md = npc:getModData()
    if not md then return end
    md.PHNPC_State = "shelter"
    md.PHNPC_ZoneX = nil  -- sera calcule par Update.lua
    md.PHNPC_ZoneY = nil
    pcall(function()
        npc:addLineChatElement(string.format(getText("UI_PHNPC_BarkShelter"), md.PHNPC_Name or "?"), 0.2, 0.9, 0.9)
    end)
    PHNPC.Log.info("Orders", tostring(md.PHNPC_Name) .. " -> shelter")
end

-- ============================================================
-- TU PEUX PARTIR (libre mais dans l'equipe)
-- ============================================================

function PHNPC.freeNPC(npc)
    if not npc then return end
    local md = npc:getModData()
    if not md then return end
    md.PHNPC_State = "free"
    md.PHNPC_ZoneX = nil
    md.PHNPC_ZoneY = nil
    pcall(function()
        npc:addLineChatElement(string.format(getText("UI_PHNPC_BarkFree"), md.PHNPC_Name or "?"), 0.9, 0.9, 0.2)
    end)
    PHNPC.Log.info("Orders", tostring(md.PHNPC_Name) .. " -> free (dans equipe)")
end

-- ============================================================
-- QUITTE MON EQUIPE (definitif : retire de recruited)
-- ============================================================

function PHNPC.quitTeamNPC(npc)
    if not npc then return end
    local md = npc:getModData()
    if not md then return end
    md.PHNPC_Recruited = false
    md.PHNPC_State     = "idle"
    md.PHNPC_ZoneX     = nil
    md.PHNPC_ZoneY     = nil
    PHNPC.recruited[npc]         = nil
    PHNPC._followTimers[npc]     = nil
    PHNPC._combatTimers[npc]     = nil
    PHNPC._attackCooldowns[npc]  = nil
    PHNPC.stopMoving(npc)
    pcall(function()
        npc:addLineChatElement(string.format(getText("UI_PHNPC_BarkQuitTeam"), md.PHNPC_Name or "?"), 0.9, 0.4, 0.1)
    end)
    PHNPC.Log.info("Orders", tostring(md.PHNPC_Name) .. " quitte l'equipe")
end

-- ============================================================
-- MODE COMBAT AUTO / OFF
-- ============================================================

function PHNPC.toggleCombatNPC(npc)
    if not npc then return end
    local md = npc:getModData()
    if not md then return end
    if md.PHNPC_CombatMode == "off" then
        md.PHNPC_CombatMode = "auto"
        pcall(function()
            npc:addLineChatElement(string.format(getText("UI_PHNPC_BarkCombatOn"), md.PHNPC_Name or "?"), 0.2, 0.9, 0.2)
        end)
    else
        md.PHNPC_CombatMode = "off"
        pcall(function()
            npc:addLineChatElement(string.format(getText("UI_PHNPC_BarkCombatOff"), md.PHNPC_Name or "?"), 0.9, 0.9, 0.2)
        end)
    end
    PHNPC.Log.info("Orders", tostring(md.PHNPC_Name) .. " combatMode -> " .. tostring(md.PHNPC_CombatMode))
end

-- ============================================================
-- SUPPRESSION DEFINITIVE
-- ============================================================

function PHNPC.deleteNPC(npc)
    if not npc then return end
    local md   = npc:getModData()
    if not md then return end
    local name = md.PHNPC_Name or "?"
    md.PHNPC_IsNPC = nil
    if PHNPC._openInventoryNPC == npc then PHNPC._openInventoryNPC = nil end
    PHNPC.allNPCs[npc]           = nil
    PHNPC.recruited[npc]         = nil
    PHNPC._followTimers[npc]     = nil
    PHNPC._combatTimers[npc]     = nil
    PHNPC._attackCooldowns[npc]  = nil
    pcall(function() npc:setHealth(0) end)
    PHNPC.Log.info("Orders", "Supprime : " .. name)
end

print("[PHNPC] Orders v0.0.9j loaded")

-- ============================================================
-- "VA LA-BAS" : CURSOR TILE VERTE + ORDRE DE DEPLACEMENT
-- Pattern GCCompanionPanelGoTo.lua (NPC_Helper_Mod B42.18)
-- ============================================================

-- v0.0.9f FIX KAHLUA UPVALUE : local PHGoToCursor et local initGoToCursor
-- devenaient nil dans enterGoToMode (meme bug que _log dans PHNPC_Log.lua).
-- Solution : utiliser des champs PHNPC.* au lieu de variables locales.
PHNPC._GoToCursor = PHNPC._GoToCursor or nil

PHNPC._initGoToCursor = function()
    if PHNPC._GoToCursor then return true end
    if not ISBuildingObject then return false end
    PHNPC._GoToCursor = ISBuildingObject:derive("PHGoToCursor")

    -- Appele quand le joueur clique sur une tuile valide
    function PHNPC._GoToCursor:create(x, y, z, north, sprite)
        -- Fermer le curseur IMMEDIATEMENT (sinon il reste a l'ecran)
        pcall(function() getCell():setDrag(nil, 0) end)
        local npc = self.targetNPC
        if not npc then return end
        pcall(function() PHNPC.goToLocation(npc, x + 0.5, y + 0.5, z) end)
    end

    function PHNPC._GoToCursor:isValid(square)
        if not square then return false end
        -- Pas de pcall ici : retour direct comme NPC_Helper_Mod
        local ok, res = pcall(function()
            return square:TreatAsSolidFloor() and not square:isSolid() and not square:isSolidTrans()
        end)
        if not ok then return false end
        return res and true or false
    end

    function PHNPC._GoToCursor:render(x, y, z, square)
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

    function PHNPC._GoToCursor:new(character, npc)
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
pcall(function() PHNPC._initGoToCursor() end)

-- enterGoToMode : active le curseur de selection de tuile pour l'ordre "Va la-bas"
function PHNPC.enterGoToMode(npc)
    if not npc then return end
    local player = getPlayer()
    if not player then return end
    -- v0.0.9f : utiliser PHNPC._initGoToCursor (champ table, pas upvalue locale)
    local ok = pcall(function() PHNPC._initGoToCursor() end)
    if not ok or not PHNPC._GoToCursor then
        print("[PHNPC][GoTo] ISBuildingObject non disponible")
        return
    end
    local cursor = PHNPC._GoToCursor:new(player, npc)
    pcall(function() getCell():setDrag(cursor, player:getPlayerNum()) end)
    local md = npc:getModData()
    print("[PHNPC][GoTo] Curseur actif pour : " .. tostring(md.PHNPC_Name))
end

-- goToLocation : envoyer le NPC vers une coordonnee precise
function PHNPC.goToLocation(npc, x, y, z)
    if not npc then return end
    local md = npc:getModData()
    if not md then return end
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
