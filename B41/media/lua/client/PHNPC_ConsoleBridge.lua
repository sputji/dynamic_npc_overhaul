--[[
    Bridge commandes pour tests solo:
    - Permet d'executer les commandes PHNPC depuis Lua Command Line.
    - Exemple: PHNPC.run('/phnpc status')
]]

PHNPC = PHNPC or {}


local okLogger, PHNPC_Logger = pcall(require, "PHNPC_Logger")
if not okLogger then
    PHNPC_Logger = _G.PHNPC_Logger
end

local okLocator, PHNPC_ClientNPCLocator = pcall(require, "PHNPC_ClientNPCLocator")
if not okLocator then
    PHNPC_ClientNPCLocator = _G.PHNPC_ClientNPCLocator
end

local function normalizeLine(line)
    if type(line) ~= "string" then
        return nil
    end

    local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed == "" then
        return nil
    end

    if string.sub(string.lower(trimmed), 1, 6) ~= "/phnpc" then
        return "/phnpc " .. trimmed
    end

    return trimmed
end

function PHNPC.run(line)
    local cmd = normalizeLine(line)
    if not cmd then
        print("[PHNPC] Commande vide. Exemple: PHNPC.run('/phnpc status')")
        return false
    end

    if not sendClientCommand then
        if NPCSpawner and NPCSpawner.tryHandleChatCommand then
            local player = getSpecificPlayer and getSpecificPlayer(0) or nil
            local ok = pcall(function()
                NPCSpawner:tryHandleChatCommand(player, cmd)
            end)
            if ok then
                print("[PHNPC] Commande executee localement: " .. cmd)
                return true
            end
        end

        print("[PHNPC] sendClientCommand indisponible")
        return false
    end

    sendClientCommand("PH_NPC", "ConsoleCommand", {
        text = cmd,
        source = "LuaCommandLine"
    })

    print("[PHNPC] Commande envoyee: " .. cmd)
    return true
end

function PHNPC.help()
    print("[PHNPC] Utilisation:")
    print("[PHNPC] PHNPC.run('/phnpc status')")
    print("[PHNPC] PHNPC.run('/phnpc diag')")
    print("[PHNPC] PHNPC.run('/phnpc spawn 5')")
    print("[PHNPC] PHNPC.run('/phnpc mark on')")
    print("[PHNPC] PHNPC.dialogueOpenNearest(4)")
    print("[PHNPC] PHNPC.dialogueSendNearest('Salut, ca va?', 4)")
    print("[PHNPC] PHNPC.tradeOpenNearest(4)")
    print("[PHNPC] PHNPC.tradeBuyNearest('Base.CannedSardines', 1, 12, 4)")
    print("[PHNPC] PHNPC.tradeSellNearest('Base.Bandage', 1, 8, 4)")
    print("[PHNPC] PHNPC.questJournalOpen()")
    print("[PHNPC] PHNPC.questJournalRefresh()")
    print("[PHNPC] PHNPC.questJournalReset()")
    print("[PHNPC] PHNPC.testSuiteQuick()")
    print("[PHNPC] PHNPC.logLevel('DEBUG')")
    print("[PHNPC] PHNPC.logRecent(80)")
    print("[PHNPC] PHNPC.logOn() / PHNPC.logOff()")
    print("[PHNPC] PHNPC.run('/phnpc clear')")
    print("[PHNPC] PHNPC.run('/phnpc respawn 5')")
end

function PHNPC.logOn()
    if PHNPC_Logger and PHNPC_Logger.setEnabled then
        PHNPC_Logger:setEnabled(true)
        print("[PHNPC] Logger active")
        return true
    end
    print("[PHNPC] Logger indisponible")
    return false
end

function PHNPC.logOff()
    if PHNPC_Logger and PHNPC_Logger.setEnabled then
        PHNPC_Logger:setEnabled(false)
        print("[PHNPC] Logger desactive")
        return true
    end
    print("[PHNPC] Logger indisponible")
    return false
end

function PHNPC.logLevel(level)
    local v = string.upper(tostring(level or "DEBUG"))
    if PHNPC_Logger and PHNPC_Logger.setMinLevel then
        PHNPC_Logger:setMinLevel(v)
        print("[PHNPC] Niveau logger=" .. v)
        return true
    end
    print("[PHNPC] Logger indisponible")
    return false
end

function PHNPC.logRecent(limit)
    local wanted = math.max(1, tonumber(limit) or 50)
    if not PHNPC_Logger or not PHNPC_Logger.getRecent then
        print("[PHNPC] Logger indisponible")
        return false
    end

    local rows = PHNPC_Logger:getRecent(wanted)
    print("[PHNPC] Logs recents: " .. tostring(#rows))
    for i = 1, #rows do
        local row = rows[i]
        print((row and row.line) or "[PHNPC] <ligne invalide>")
    end
    return true
end

function PHNPC.mark(enabled)
    local okMarkers, PHNPC_DebugMarkers = pcall(require, "PHNPC_DebugMarkers")
    if not okMarkers then
        PHNPC_DebugMarkers = _G.PHNPC_DebugMarkers
    end

    if PHNPC_DebugMarkers and PHNPC_DebugMarkers.setEnabled then
        PHNPC_DebugMarkers:setEnabled(enabled == true)
        return true
    end

    print("[PHNPC] Markers indisponibles: PHNPC_DebugMarkers non charge")
    return false
end

function PHNPC.map(enabled)
    local okMarkers, PHNPC_DebugMarkers = pcall(require, "PHNPC_DebugMarkers")
    if not okMarkers then
        PHNPC_DebugMarkers = _G.PHNPC_DebugMarkers
    end

    if PHNPC_DebugMarkers and PHNPC_DebugMarkers.setMapEnabled then
        PHNPC_DebugMarkers:setMapEnabled(enabled == true)
        return true
    end

    print("[PHNPC] Map markers indisponibles: PHNPC_DebugMarkers non charge")
    return false
end

local function findNearestDynamicNpc(maxDistance)
    local player = getSpecificPlayer and getSpecificPlayer(0) or nil
    if not player then
        return nil
    end

    if PHNPC_ClientNPCLocator and PHNPC_ClientNPCLocator.findNearest then
        local nearest = PHNPC_ClientNPCLocator.findNearest(player, tonumber(maxDistance) or 4)
        return nearest
    end

    local cell = getCell and getCell() or nil
    if not cell then
        return nil
    end

    local px = player:getX()
    local py = player:getY()
    local pz = math.floor(player.getZ and player:getZ() or 0)
    local maxDist = tonumber(maxDistance) or 4
    local maxDistSq = maxDist * maxDist

    local nearest = nil
    local nearestDistSq = maxDistSq

    local function testEntity(entity)
        if not entity or not entity.getModData then
            return
        end
        local md = entity:getModData()
        if not md or md.PH_IsDynamicNPC ~= true then
            return
        end

        local ez = math.floor(entity.getZ and entity:getZ() or 0)
        if ez ~= pz then
            return
        end

        local ex = entity.getX and entity:getX() or nil
        local ey = entity.getY and entity:getY() or nil
        if not ex or not ey then
            return
        end

        local dx = ex - px
        local dy = ey - py
        local d2 = (dx * dx) + (dy * dy)
        if d2 <= nearestDistSq then
            nearestDistSq = d2
            nearest = entity
        end
    end

    local zlist = cell.getZombieList and cell:getZombieList() or nil
    if zlist and zlist.size then
        for i = 0, zlist:size() - 1 do
            testEntity(zlist:get(i))
        end
    end

    local objects = cell.getObjectList and cell:getObjectList() or nil
    if objects and objects.size then
        for i = 0, objects:size() - 1 do
            local obj = objects:get(i)
            if obj then
                local okName, objectName = pcall(function()
                    return obj:getObjectName()
                end)
                if okName and objectName == "IsoPlayer" then
                    testEntity(obj)
                end
            end
        end
    end

    return nearest
end

function PHNPC.dialogueOpenNearest(maxDistance)
    local npc = findNearestDynamicNpc(maxDistance)
    if not npc or not npc.getModData then
        print("[PHNPC] Aucun PNJ dynamique proche pour ouvrir le dialogue")
        return false
    end

    local md = npc:getModData()
    local npcId = md and md.PH_NPCId or nil
    if not npcId then
        print("[PHNPC] PNJ proche sans NPCId")
        return false
    end

    local okUI, OllamaChatUI = pcall(require, "OllamaChatUI")
    if not okUI or not OllamaChatUI or not OllamaChatUI.openChatWindow then
        print("[PHNPC] OllamaChatUI indisponible")
        return false
    end

    OllamaChatUI:openChatWindow(npcId)
    print("[PHNPC] Fenetre dialogue ouverte pour NPC=" .. tostring(npcId))
    return true
end

function PHNPC.dialogueSendNearest(message, maxDistance)
    local text = tostring(message or "")
    if text == "" then
        print("[PHNPC] Usage: PHNPC.dialogueSendNearest('message', 4)")
        return false
    end

    local npc = findNearestDynamicNpc(maxDistance)
    if not npc or not npc.getModData then
        print("[PHNPC] Aucun PNJ dynamique proche pour envoyer un message")
        return false
    end

    local md = npc:getModData()
    local npcId = md and md.PH_NPCId or nil
    if not npcId then
        print("[PHNPC] PNJ proche sans NPCId")
        return false
    end

    if not NPC_NetworkClient or not NPC_NetworkClient.requestDialogue then
        print("[PHNPC] NPC_NetworkClient indisponible")
        return false
    end

    NPC_NetworkClient:requestDialogue(npcId, text, function(response, isError)
        if isError then
            print("[PHNPC] Dialogue erreur: " .. tostring(response))
        else
            print("[PHNPC] Dialogue reponse: " .. tostring(response))
        end
    end)

    print("[PHNPC] Dialogue envoye a NPC=" .. tostring(npcId))
    return true
end

function PHNPC.tradeOpenNearest(maxDistance)
    local npc = findNearestDynamicNpc(maxDistance)
    if not npc or not npc.getModData then
        print("[PHNPC] Aucun PNJ dynamique proche pour ouvrir le commerce")
        return false
    end

    local md = npc:getModData()
    local npcId = md and md.PH_NPCId or nil
    if not npcId then
        print("[PHNPC] PNJ proche sans NPCId")
        return false
    end

    local okTrade, TradeUI = pcall(require, "PHNPC_TradeWindow")
    if not okTrade then
        TradeUI = _G.PHNPCTradeWindow
    end

    if not TradeUI or not TradeUI.open then
        print("[PHNPC] Fenetre commerce indisponible")
        return false
    end

    TradeUI.open(npcId)
    print("[PHNPC] Fenetre commerce ouverte pour NPC=" .. tostring(npcId))
    return true
end

local function sendTradeNearest(mode, itemType, quantity, price, maxDistance)
    local npc = findNearestDynamicNpc(maxDistance)
    if not npc or not npc.getModData then
        print("[PHNPC] Aucun PNJ dynamique proche pour transaction")
        return false
    end

    local md = npc:getModData()
    local npcId = md and md.PH_NPCId or nil
    if not npcId then
        print("[PHNPC] PNJ proche sans NPCId")
        return false
    end

    local okInteraction, interaction = pcall(require, "NPCInteractionClient")
    if not okInteraction then
        interaction = _G.PHNPCInteractionClient
    end

    if not interaction or not interaction.sendTradeEvent then
        print("[PHNPC] NPCInteractionClient indisponible")
        return false
    end

    local qty = math.max(1, math.floor(tonumber(quantity) or 1))
    local unitPrice = math.max(1, math.floor(tonumber(price) or 10))
    local total = qty * unitPrice

    interaction:sendTradeEvent(npcId, mode, {
        itemType = tostring(itemType or ""),
        quantity = qty,
        value = total,
        price = total,
        strictCapacity = true,
        requested = "lua_trade_bridge"
    })

    print("[PHNPC] Transaction envoyee mode=" .. tostring(mode) .. " npc=" .. tostring(npcId) .. " item=" .. tostring(itemType) .. " qty=" .. tostring(qty) .. " total=" .. tostring(total))
    return true
end

function PHNPC.tradeBuyNearest(itemType, quantity, totalPrice, maxDistance)
    if not itemType or tostring(itemType) == "" then
        print("[PHNPC] Usage: PHNPC.tradeBuyNearest('Base.CannedSardines', 1, 12, 4)")
        return false
    end
    return sendTradeNearest("buy", itemType, quantity, tonumber(totalPrice) and (tonumber(totalPrice) / math.max(1, tonumber(quantity) or 1)) or nil, maxDistance)
end

function PHNPC.tradeSellNearest(itemType, quantity, totalPrice, maxDistance)
    if not itemType or tostring(itemType) == "" then
        print("[PHNPC] Usage: PHNPC.tradeSellNearest('Base.Bandage', 1, 8, 4)")
        return false
    end
    return sendTradeNearest("sell", itemType, quantity, tonumber(totalPrice) and (tonumber(totalPrice) / math.max(1, tonumber(quantity) or 1)) or nil, maxDistance)
end

function PHNPC.questJournalOpen()
    local okQuest, questUI = pcall(require, "PHNPC_QuestJournalUI")
    if not okQuest then
        questUI = _G.PHNPCQuestJournalUI
    end

    if not questUI or not questUI.open then
        print("[PHNPC] Journal quetes indisponible")
        return false
    end

    questUI.open()
    local okInteraction, interaction = pcall(require, "NPCInteractionClient")
    if not okInteraction then
        interaction = _G.PHNPCInteractionClient
    end
    if interaction and interaction.requestQuestJournal then
        interaction:requestQuestJournal()
    end
    print("[PHNPC] Journal quetes ouvert")
    return true
end

function PHNPC.questJournalRefresh()
    local okInteraction, interaction = pcall(require, "NPCInteractionClient")
    if not okInteraction then
        interaction = _G.PHNPCInteractionClient
    end

    if not interaction or not interaction.requestQuestJournal then
        print("[PHNPC] NPCInteractionClient indisponible")
        return false
    end

    interaction:requestQuestJournal()
    print("[PHNPC] Requete journal quetes envoyee")
    return true
end

function PHNPC.questJournalReset()
    local okInteraction, interaction = pcall(require, "NPCInteractionClient")
    if not okInteraction then
        interaction = _G.PHNPCInteractionClient
    end

    if not interaction or not interaction.resetQuestJournal then
        print("[PHNPC] NPCInteractionClient indisponible")
        return false
    end

    interaction:resetQuestJournal()
    print("[PHNPC] Requete reset journal quetes envoyee")
    return true
end

function PHNPC.testSuiteQuick()
    print("[PHNPC] TestSuiteQuick: lancement sequence de verification")
    PHNPC.run('/phnpc status')
    PHNPC.run('/phnpc diag 20')
    PHNPC.run('/phnpc respawn 10')
    PHNPC.questJournalRefresh()
    print("[PHNPC] TestSuiteQuick: surveiller console pour status/diag/spawnFail")
    return true
end

local function onServerCommand(module, command, args)
    if module ~= "PH_NPC_CONSOLE" or command ~= "Result" then
        return
    end

    local payload = args or {}
    local message = tostring(payload.message or "(sans message)")
    print("[PHNPC] " .. message)
end

if Events and Events.OnServerCommand then
    Events.OnServerCommand.Add(onServerCommand)
end

print("[PHNPC] Lua bridge pret. Utilise PHNPC.run('/phnpc status') ou PHNPC.help()")

if PHNPC_Logger and PHNPC_Logger.setEnabled then
    PHNPC_Logger:setEnabled(true)
end
