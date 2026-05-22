--[[
    PHNPC_Menu.lua  v1.0  (client)
    Menu contextuel clic-droit pour les NPCs et callbacks de debug inline.

    Pattern : NHM GCMenuContext.onFillWorldObjectContextMenu
    Necessite :
      PHNPC_Actions.lua  (PHNPC.stopMoving)
      PHNPC_Barks.lua    (PHNPC.sayBark)
      PHNPC_Convert.lua  (PHNPC.spawnNPC)
      PHNPC_Inventory.lua (PHNPC.openNPCInventory)
      PHNPC_Orders.lua   (PHNPC.recruitNPC, followNPC, stayNPC, dismissNPC,
                           deleteNPC, orderAttackNPC, orderFleeNPC, toggleCombatNPC)
      PHNPC_Core.lua     (PHNPC.isNPC, PHNPC.INTERACTION_DIST)
]]

-- ============================================================
-- TALKNIC : bark immediat selon etat courant (option "Parler")
-- ============================================================
local function talkNPC(npc)
    if not npc then return end
    local md = npc:getModData()
    PHNPC.sayBark(npc, md.PHNPC_State or "idle", 0.9, 0.9, 0.2)
end

-- ============================================================
-- SHOW NPC INFO : affiche l'etat complet via addLineChatElement
-- ============================================================
local function showNPCInfo(npc)
    local md    = npc:getModData()
    local hp    = md.PHNPC_Health    or 0
    local maxHp = md.PHNPC_MaxHealth or 100
    local speed = string.format("%.0f%%", (md.PHNPC_SpeedMod or 0.8) * 100)
    local str   = tostring(md.PHNPC_Strength or "?")
    local outfit= tostring(md.PHNPC_Outfit or "?")
    local state = tostring(md.PHNPC_State or "idle")
    local genre = (md.PHNPC_Female and "F" or "M")
    -- Ligne 1 : identite
    pcall(function()
        npc:addLineChatElement(string.format(getText("UI_PHNPC_InfoLine1"), md.PHNPC_Name or "?", genre, outfit), 0.9, 0.9, 0.2)
    end)
    -- Ligne 2 : stats
    pcall(function()
        npc:addLineChatElement(string.format(getText("UI_PHNPC_InfoLine2"), math.floor(hp), math.floor(maxHp), speed, str, state), 0.9, 0.9, 0.2)
    end)
end

-- ============================================================
-- CALLBACKS DEBUG (sous-menu [DEBUG]..., disponibles en mode debug PZ)
-- ============================================================
local function dbgForceIdle(npc)
    npc:getModData().PHNPC_State = "idle"
    PHNPC.stopMoving(npc)
end
local function dbgForceDefending(npc)  npc:getModData().PHNPC_State = "defending" end
local function dbgForceFleeing(npc)
    local md = npc:getModData()
    md.PHNPC_State  = "fleeing"
    md.PHNPC_Health = 1
end
local function dbgHPFull(npc)
    local md = npc:getModData()
    md.PHNPC_Health = md.PHNPC_MaxHealth or 100
    pcall(function() npc:addLineChatElement(string.format(getText("UI_PHNPC_HpRestored"), md.PHNPC_Name or "?"), 0.2, 0.9, 0.2) end)
end
local function dbgDeleteAll(_)
    local toDelete = {}
    for npc, _ in pairs(PHNPC.allNPCs) do table.insert(toDelete, npc) end
    for _, npc in ipairs(toDelete) do PHNPC.deleteNPC(npc) end
    print("[PHNPC][DEBUG] Tous les NPCs supprimes")
end
local function dbgAnimShove(npc)       pcall(function() npc:setBumpType("Shove")       end) end
local function dbgAnimFrontKick(npc)   pcall(function() npc:setBumpType("FrontKick")   end) end
local function dbgAnimHighKick(npc)    pcall(function() npc:setBumpType("HighKick")    end) end
local function dbgAnimWaveHi(npc)      pcall(function() npc:setBumpType("WaveHi")      end) end
local function dbgAnimShrug(npc)       pcall(function() npc:setBumpType("Shrug")       end) end
local function dbgAnimStagger(npc)     pcall(function() npc:setBumpType("StaggerBack") end) end
local function dbgAnimYes(npc)         pcall(function() npc:setBumpType("Yes")         end) end
local function dbgAnimNo(npc)          pcall(function() npc:setBumpType("No")          end) end

-- ============================================================
-- MENU CONTEXTUEL (GCMenuContext.onFillWorldObjectContextMenu EXACT)
-- ============================================================
local function onFillContextMenu(playerIndex, context, worldObjects, test)
    if test then return end

    local player = getSpecificPlayer(playerIndex)
    if not player or not PHNPC then return end

    local px = player:getX()
    local py = player:getY()

    local cell = player:getCell()
    if not cell then return end

    -- Rechercher NPCs a portee (via zombieList de la cellule)
    local nearbyNPCs = {}
    local zlist = cell:getZombieList()
    local distSq = PHNPC.INTERACTION_DIST * PHNPC.INTERACTION_DIST

    for i = 0, zlist:size() - 1 do
        local z = zlist:get(i)
        if z and PHNPC.isNPC(z) then
            local dx = z:getX() - px
            local dy = z:getY() - py
            if (dx * dx + dy * dy) <= distSq then
                table.insert(nearbyNPCs, z)
            end
        end
    end

    if #nearbyNPCs == 0 then
        -- Aucun NPC a portee : proposer spawn sur la case cliquee
        local square = ISWorldObjectContextMenu.fetchVars.clickedSquare
        if square then
            context:addOption("[PHNPC] Appeler un survivant", square, PHNPC.spawnNPC)
        end
        -- Options debug globales — uniquement en mode debug PZ
        if isDebugEnabled and isDebugEnabled() then
            context:addOption("[DEBUG] Supprimer tous les NPCs", player, dbgDeleteAll)
        end
        return
    end

    -- Menu pour chaque NPC a portee
    for _, npc in ipairs(nearbyNPCs) do
        local md    = npc:getModData()
        local name  = md.PHNPC_Name or "Survivant"
        local genre = md.PHNPC_Female and "F" or "M"
        local hp    = md.PHNPC_Health    or 0
        local maxHp = md.PHNPC_MaxHealth or 100
        -- Label avec HP integre pour visibilite immediate
        local label = string.format("[%s (%s) — %s — HP:%d/%d]",
                        name, genre, md.PHNPC_Outfit or "?", hp, maxHp)

        local menuOpt = context:addOption(label)
        local subMenu = ISContextMenu:getNew(context)
        context:addSubMenu(menuOpt, subMenu)

        -- "Parler" : bark immediat selon etat (toujours disponible)
        subMenu:addOption("Parler",                npc, talkNPC)

        if not md.PHNPC_Recruited then
            -- NPC non recrute : recrutement
            subMenu:addOption("Rejoins-moi !",     npc, PHNPC.recruitNPC)
        else
            -- NPC recrute : echange d'objets + ordres
            subMenu:addOption("Echange d'objets...", npc, PHNPC.openNPCInventory)

            local ordreOpt = subMenu:addOption("Ordres...")
            local ordreSub = ISContextMenu:getNew(subMenu)
            subMenu:addSubMenu(ordreOpt, ordreSub)

            if md.PHNPC_State == "following" then
                ordreSub:addOption("Reste ici.",             npc, PHNPC.stayNPC)
            else
                ordreSub:addOption("Suis-moi !",             npc, PHNPC.followNPC)
            end
            ordreSub:addOption("Va la-bas...",               npc, PHNPC.enterGoToMode)
            ordreSub:addOption("Attaque les zombies !",      npc, PHNPC.orderAttackNPC)
            ordreSub:addOption("Mets-toi a l'abri !",        npc, PHNPC.orderFleeNPC)
            local combatLabel = "Mode combat : " .. (md.PHNPC_CombatMode == "off" and "OFF" or "AUTO")
            ordreSub:addOption(combatLabel,                  npc, PHNPC.toggleCombatNPC)
            ordreSub:addOption("Tu peux partir.",            npc, PHNPC.dismissNPC)
        end

        -- Section debug (uniquement si mode debug PZ)
        if isDebugEnabled and isDebugEnabled() then
            local dbgOpt = subMenu:addOption("[DEBUG]...")
            local dbgSub = ISContextMenu:getNew(subMenu)
            subMenu:addSubMenu(dbgOpt, dbgSub)

            dbgSub:addOption("Info NPC",             npc, showNPCInfo)
            -- Etats forces
            dbgSub:addOption("Forcer : idle",        npc, dbgForceIdle)
            dbgSub:addOption("Forcer : defending",   npc, dbgForceDefending)
            dbgSub:addOption("Forcer : fleeing",     npc, dbgForceFleeing)
            dbgSub:addOption("HP full reset",        npc, dbgHPFull)
            -- Animations de test
            dbgSub:addOption("Anim : Shove",         npc, dbgAnimShove)
            dbgSub:addOption("Anim : FrontKick",     npc, dbgAnimFrontKick)
            dbgSub:addOption("Anim : HighKick",      npc, dbgAnimHighKick)
            dbgSub:addOption("Anim : WaveHi",        npc, dbgAnimWaveHi)
            dbgSub:addOption("Anim : Shrug",         npc, dbgAnimShrug)
            dbgSub:addOption("Anim : StaggerBack",   npc, dbgAnimStagger)
            dbgSub:addOption("Anim : Yes",           npc, dbgAnimYes)
            dbgSub:addOption("Anim : No",            npc, dbgAnimNo)
        end

        subMenu:addOption("[Supprimer]",             npc, PHNPC.deleteNPC)
    end
end

-- Enregistrer le menu contextuel
Events.OnPreFillWorldObjectContextMenu.Add(onFillContextMenu)

print("[PHNPC] Menu v0.0.9b loaded")
