--[[
    Project Humain : Dynamic_NPC_Overhaul
    NPCInteractionClient.lua

    Helper client pour envoyer des interactions explicites vers le serveur.
    Sert de base a une future UI de dialogue, troc, intimidation ou vol.
]]

local PHNPCInteractionClient = {
    module = "PH_NPC_INTERACT",
    lastIntelResponse = nil,
    lastActionResult = nil,
    lastNpcSnapshot = nil,
    lastQuestJournal = nil,
    _listeners = {},
    networkTimeoutSec = 5,
    _pendingNetwork = {}
}


local hasLogger, PHNPC_Logger = pcall(require, "PHNPC_Logger")
if not hasLogger then
    PHNPC_Logger = _G.PHNPC_Logger
end

local function send(command, payload)
    if sendClientCommand then
        sendClientCommand(PHNPCInteractionClient.module, command, payload or {})
    end
end

local function resolveCurrentLanguageCode()
    if not Translator or not Translator.getLanguage then
        return "EN"
    end

    local ok, langObj = pcall(function()
        return Translator.getLanguage()
    end)
    if not ok or not langObj then
        return "EN"
    end

    local langCode = tostring(langObj)
    if langObj.toString then
        local okToString, asString = pcall(function()
            return langObj:toString()
        end)
        if okToString and asString and #tostring(asString) > 0 then
            langCode = tostring(asString)
        end
    end

    langCode = string.upper(langCode or "EN"):gsub("[^A-Z]", "")
    if #langCode >= 2 then
        return langCode:sub(1, 2)
    end

    return "EN"
end

function PHNPCInteractionClient:sendMemoryEvent(targetNpcId, actionType, opts)
    opts = opts or {}
    send("MemoryEvent", {
        sourceType = opts.sourceType or "player",
        sourceId = opts.sourceId,
        targetType = opts.targetType or "npc",
        targetId = targetNpcId,
        actionType = actionType,
        tick = opts.tick,
        value = opts.value,
        itemType = opts.itemType,
        reason = opts.reason,
        zombieCount = opts.zombieCount,
        strengthScore = opts.strengthScore,
        hostilityType = opts.hostilityType
    })
end

function PHNPCInteractionClient:sendTradeEvent(targetNpcId, mode, opts)
    opts = opts or {}
    send("TradeEvent", {
        sourceType = opts.sourceType or "player",
        sourceId = opts.sourceId,
        targetType = opts.targetType or "npc",
        targetId = targetNpcId,
        mode = mode,
        tick = opts.tick,
        value = opts.value,
        itemType = opts.itemType,
        quantity = opts.quantity,
        strictCapacity = opts.strictCapacity,
        requested = opts.requested
    })
end

function PHNPCInteractionClient:requestIntel(npcId)
    send("RequestIntel", {
        npcId = npcId
    })
end

function PHNPCInteractionClient:requestNpcSnapshot(npcId)
    send("RequestNpcSnapshot", {
        npcId = npcId
    })
end

function PHNPCInteractionClient:sendOrderAction(npcId, orderType, params)
    send("OrderAction", {
        npcId = npcId,
        orderType = orderType,
        params = params or {}
    })
end

function PHNPCInteractionClient:requestQuestJournal()
    send("QuestJournalRequest", {})
end

function PHNPCInteractionClient:resetQuestJournal()
    send("QuestResetRequest", {})
end

function PHNPCInteractionClient:requestBusinessQuote(npcId, serviceType, opts)
    opts = opts or {}
    local requestId = "quote_" .. tostring(npcId or "unknown") .. "_" .. tostring(os.time()) .. "_" .. tostring(math.random(10000))
    self._pendingNetwork[requestId] = {
        requestType = "BusinessQuoteRequest",
        startedAt = os.time(),
        npcId = npcId
    }

    send("BusinessQuoteRequest", {
        requestId = requestId,
        npcId = npcId,
        serviceType = serviceType,
        itemType = opts.itemType,
        quantity = opts.quantity,
        marketCategory = opts.marketCategory,
        targetHint = opts.targetHint,
        buildSiteId = opts.buildSiteId,
        baseId = opts.baseId,
        price = opts.price,
        clanNeed = opts.clanNeed,
        personalNeed = opts.personalNeed
    })

    if PHNPC_Logger and PHNPC_Logger.info then
        PHNPC_Logger:info("NPCInteractionClient", "requestBusinessQuote", "Business quote requested", {
            requestId = requestId,
            npcId = npcId,
            serviceType = serviceType,
            itemType = opts.itemType,
            quantity = opts.quantity
        })
    end
end

function PHNPCInteractionClient:sendBusinessOrder(npcId, serviceType, opts)
    opts = opts or {}
    local requestId = "order_" .. tostring(npcId or "unknown") .. "_" .. tostring(os.time()) .. "_" .. tostring(math.random(10000))
    self._pendingNetwork[requestId] = {
        requestType = "BusinessOrderRequest",
        startedAt = os.time(),
        npcId = npcId
    }

    send("BusinessOrderRequest", {
        requestId = requestId,
        npcId = npcId,
        serviceType = serviceType,
        itemType = opts.itemType,
        quantity = opts.quantity,
        marketCategory = opts.marketCategory,
        targetHint = opts.targetHint,
        buildSiteId = opts.buildSiteId,
        baseId = opts.baseId,
        price = opts.price,
        quote = opts.quote,
        clanNeed = opts.clanNeed,
        personalNeed = opts.personalNeed
    })

    if PHNPC_Logger and PHNPC_Logger.info then
        PHNPC_Logger:info("NPCInteractionClient", "sendBusinessOrder", "Business order requested", {
            requestId = requestId,
            npcId = npcId,
            serviceType = serviceType,
            itemType = opts.itemType,
            quantity = opts.quantity
        })
    end
end

function PHNPCInteractionClient:sendAdminAction(npcId, action, payload)
    payload = payload or {}
    payload.npcId = npcId
    payload.action = action
    send("AdminAction", payload)
end

function PHNPCInteractionClient:gift(npcId, value, itemType, quantity)
    self:sendTradeEvent(npcId, "gift", {
        value = value,
        itemType = itemType,
        quantity = quantity
    })
end

function PHNPCInteractionClient:theft(npcId, value, itemType)
    self:sendMemoryEvent(npcId, "theft", {
        value = value,
        itemType = itemType
    })
end

function PHNPCInteractionClient:hostile(npcId, hostilityType, value)
    self:sendMemoryEvent(npcId, "hostile", {
        hostilityType = hostilityType,
        value = value
    })
end

function PHNPCInteractionClient:sendOllamaRequest(npcId, userMessage)
    send("OllamaRequest", {
        npcId = npcId,
        userMessage = userMessage,
        playerLanguage = resolveCurrentLanguageCode()
    })
end

function PHNPCInteractionClient:onServerCommand(module, command, args)
    if module ~= self.module then
        return
    end

    if command == "IntelResponse" then
        self.lastIntelResponse = args or nil
        self:_notify("IntelResponse", args)
    elseif command == "ActionResult" then
        self.lastActionResult = args or nil
        if args and args.snapshot then
            self.lastNpcSnapshot = args.snapshot
        end
        self:_notify("ActionResult", args)
    elseif command == "NpcSnapshot" then
        self.lastNpcSnapshot = args and args.snapshot or nil
        self:_notify("NpcSnapshot", args)
    elseif command == "BusinessQuoteResponse" then
        local req = args and args.request or nil
        local requestId = req and req.requestId or nil
        if requestId and self._pendingNetwork[requestId] then
            self._pendingNetwork[requestId] = nil
        end
        if PHNPC_Logger and PHNPC_Logger.ok then
            PHNPC_Logger:ok("NPCInteractionClient", "BusinessQuoteResponse", "Business quote response received", {
                requestId = requestId,
                npcId = req and req.npcId or (args and args.npcId),
                accepted = args and args.ok
            })
        end
        self:_notify("BusinessQuoteResponse", args)
    elseif command == "QuestJournal" then
        self.lastQuestJournal = args or nil
        self:_notify("QuestJournal", args)
    elseif command == "OllamaResponse" then
        self:_notify("OllamaResponse", args)
    end

    if command == "ActionResult" and args and args.actionType == "BusinessOrder" and args.requestId and self._pendingNetwork[args.requestId] then
        self._pendingNetwork[args.requestId] = nil
    end
end

function PHNPCInteractionClient:updateTimeouts()
    local now = os.time()
    for requestId, pending in pairs(self._pendingNetwork) do
        if type(pending) == "table" and (now - (pending.startedAt or now)) >= self.networkTimeoutSec then
            self._pendingNetwork[requestId] = nil
            if PHNPC_Logger and PHNPC_Logger.warn then
                PHNPC_Logger:warn("NPCInteractionClient", "NetworkTimeout", "Pending network request timed out", {
                    requestId = requestId,
                    requestType = pending.requestType,
                    npcId = pending.npcId,
                    timeoutSec = self.networkTimeoutSec
                })
            end
            self:_notify("NetworkTimeout", {
                requestId = requestId,
                requestType = pending.requestType,
                npcId = pending.npcId,
                message = "Timeout reseau (5s): " .. tostring(pending.requestType or "request")
            })
        end
    end
end

function PHNPCInteractionClient:addListener(id, callback)
    if not id or type(callback) ~= "function" then
        return
    end
    self._listeners[id] = callback
end

function PHNPCInteractionClient:removeListener(id)
    if id then
        self._listeners[id] = nil
    end
end

function PHNPCInteractionClient:_notify(eventName, payload)
    for _, callback in pairs(self._listeners) do
        if type(callback) == "function" then
            pcall(callback, eventName, payload)
        end
    end
end

if Events and Events.OnServerCommand then
    Events.OnServerCommand.Add(function(module, command, args)
        PHNPCInteractionClient:onServerCommand(module, command, args)
    end)
end

if Events and Events.OnTick then
    Events.OnTick.Add(function()
        PHNPCInteractionClient:updateTimeouts()
    end)
end

_G.PHNPCInteractionClient = PHNPCInteractionClient

return PHNPCInteractionClient
