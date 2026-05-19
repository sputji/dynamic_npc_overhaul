--[[
    Project Humain : Dynamic_NPC_Overhaul
    NPC_NetworkServer.lua

    Gestion reseau serveur pour sync multijoueur des PNJ.
    - Calculs centralises (IA, faim, soif, combat)
    - Sync positions/animations/attaques aux clients
    - Gestion dialogues (Ollama si dispo, fallback sinon)
    - Optimisation bande passante: clients recoivent ordres d'affichage seulement
]]


local PHNPC_DISABLE_OPTIONAL_RUNTIME_MODULES = false

local okBiteManager, NPC_BiteManagement = false, nil
if not PHNPC_DISABLE_OPTIONAL_RUNTIME_MODULES then
    okBiteManager, NPC_BiteManagement = pcall(require, "NPC_BiteManagement")
    if not okBiteManager then
        NPC_BiteManagement = nil
    end
end

local okLearning, NPC_ObservationLearning = false, nil
if not PHNPC_DISABLE_OPTIONAL_RUNTIME_MODULES then
    okLearning, NPC_ObservationLearning = pcall(require, "NPC_ObservationLearning")
    if not okLearning then
        NPC_ObservationLearning = nil
    end
end

local okMemory, NPCMemory = pcall(require, "NPCMemory")
if not okMemory then
    NPCMemory = nil
end

local okFactionMgr, NPCFactionManager = pcall(require, "NPCFactionManager")
if not okFactionMgr then
    NPCFactionManager = nil
end

local okDialogueLocalization, NPCDialogueLocalization = pcall(require, "NPCDialogueLocalization")
if not okDialogueLocalization then
    NPCDialogueLocalization = _G.NPCDialogueLocalization
end


local NPC_NetworkServer = {
    module = "PH_NPC_NETWORK",
    syncCommand = "NPCSyncState",
    dialogueRequestCommand = "DialogueRequest",
    dialogueResponseCommand = "DialogueResponse",
    dialoguePendingCommand = "DialoguePending",
    fxCommand = "NPCFx",
    
    -- Sync state de tous les PNJ: npcId -> {pos, anim, velocity, health, etc}
    npcSyncStates = {},
    
    -- Derniere sync timestamp pour throttle
    lastSyncTime = {},
    lastBuildFxTime = {},
    lastHurtFxTime = {},
    lastActionFxTime = {},
    syncInterval = 0.5, -- sync toutes les 500ms pour economiser bande passante
    
    -- Dialogues en cache par npcId
    cachedDialogues = {},
    recentFallbackByNpc = {},
    fallbackCounterByNpc = {},
    recentConversationByPair = {}
}

local function getOnlinePlayersSafe()
    local out = {}
    if type(getOnlinePlayers) == "function" then
        local ok, players = pcall(function()
            return getOnlinePlayers()
        end)
        if ok and players and players.size then
            for i = 0, players:size() - 1 do
                out[#out + 1] = players:get(i)
            end
        elseif ok and type(players) == "table" then
            for i = 1, #players do
                out[#out + 1] = players[i]
            end
        end
    end
    return out
end

function NPC_NetworkServer:broadcastNPCFx(npcId, fxType, npcData)
    if not sendServerCommand then
        return
    end

    local payload = {
        npcId = npcId,
        fxType = fxType,
        state = npcData and npcData.animState or nil,
        order = npcData and npcData.activeOrder or nil,
        x = npcData and (npcData.x or 0) or 0,
        y = npcData and (npcData.y or 0) or 0,
        z = npcData and (npcData.z or 0) or 0
    }

    local players = getOnlinePlayersSafe()
    for i = 1, #players do
        local p = players[i]
        if p then
            sendServerCommand(p, self.module, self.fxCommand, payload)
        end
    end
end

function NPC_NetworkServer:sendDialoguePending(player, npcId, requestId, pending)
    if not player or not sendServerCommand then
        return
    end

    sendServerCommand(player, self.module, self.dialoguePendingCommand, {
        npcId = npcId,
        requestId = requestId,
        pending = pending == true
    })
end

local function getOrderFxType(orderName, animState)
    local order = string.lower(tostring(orderName or ""))
    local anim = string.lower(tostring(animState or ""))

    if order == "build" then return "npc_build" end
    if order == "cook" then return "npc_cook" end
    if order == "trade" or order == "buy" then return "npc_trade" end
    if order == "scavenge" then return "npc_scavenge" end
    if order == "study" then return "npc_study" end
    if order == "guard" then return "npc_guard" end
    if order == "defend" then return "npc_defend" end
    if order == "follow" then return "npc_follow" end
    if order == "recover" then return "npc_recover" end
    if order == "sleep" then return "npc_sleep" end
    if order == "flee" then return "npc_flee" end
    if order == "wander" then return "npc_idle" end

    if anim == "attack" or anim == "attacking" or anim == "combat" then
        return "npc_combat"
    end
    if anim == "run" or anim == "running" then
        return "npc_run"
    end
    if anim == "walk" or anim == "moving" then
        return "npc_walk"
    end
    if anim == "idle" then
        return "npc_idle"
    end

    return nil
end

local function normalizeLanguageCode(languageCode)
    local code = string.upper(tostring(languageCode or ""))
    code = code:gsub("[^A-Z]", "")
    if #code >= 2 then
        return code:sub(1, 2)
    end
    return "EN"
end

local function getCurrentPZLanguageCode()
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

    return normalizeLanguageCode(langCode)
end

local function localizeFallback(key, languageCode)
    if NPCDialogueLocalization and NPCDialogueLocalization.getText then
        return NPCDialogueLocalization:getText(key, languageCode)
    end

    if getText then
        local ok, translated = pcall(function()
            return getText(key)
        end)
        if ok and translated and translated ~= key and #tostring(translated) > 0 then
            return tostring(translated)
        end
    end

    return "..."
end

local function addLocalizedLine(responses, key, languageCode, topic)
    if not key then
        return
    end
    local text = localizeFallback(key, languageCode)
    if text and #tostring(text) > 0 and text ~= "..." then
        table.insert(responses, {
            text = text,
            topic = topic or "general"
        })
    end
end

local function addLocalizedLines(responses, keys, languageCode, topic)
    if type(keys) ~= "table" then
        return
    end
    for i = 1, #keys do
        addLocalizedLine(responses, keys[i], languageCode, topic)
    end
end

local function humanizeFreeformLabel(value)
    local text = tostring(value or "")
    if #text == 0 then
        return ""
    end

    text = text:gsub("^.+%.", "")
    text = text:gsub("([a-z])([A-Z])", "%1 %2")
    text = text:gsub("[_%-]+", " ")
    text = text:gsub("%s+", " ")
    text = text:gsub("^%s+", "")
    text = text:gsub("%s+$", "")
    return string.lower(text)
end

local function resolveCardinalDirection(baseCenter, targetPoint, languageCode)
    if type(baseCenter) ~= "table" or type(targetPoint) ~= "table" then
        return ""
    end

    local dx = (tonumber(targetPoint.x) or 0) - (tonumber(baseCenter.x) or 0)
    local dy = (tonumber(targetPoint.y) or 0) - (tonumber(baseCenter.y) or 0)
    local adx = math.abs(dx)
    local ady = math.abs(dy)
    local lang = normalizeLanguageCode(languageCode)

    if adx < 3 and ady < 3 then
        return lang == "FR" and "centrale" or "central"
    end

    local ns = ""
    local ew = ""
    if dy <= -3 then
        ns = lang == "FR" and "nord" or "north"
    elseif dy >= 3 then
        ns = lang == "FR" and "sud" or "south"
    end

    if dx <= -3 then
        ew = lang == "FR" and "ouest" or "west"
    elseif dx >= 3 then
        ew = lang == "FR" and "est" or "east"
    end

    if #ns > 0 and #ew > 0 then
        return ns .. "-" .. ew
    end
    if #ns > 0 then
        return ns
    end
    return ew
end

local function resolveRuntimeBaseSiteContext(npcData, orderType, orderParams, languageCode)
    local context = {
        baseLabel = nil,
        siteLabel = nil
    }

    if not NPCFactionManager then
        return context
    end

    local params = type(orderParams) == "table" and orderParams or {}
    local npcId = npcData and (npcData.id or npcData.npcId or npcData.uuid) or nil
    local baseId = params.baseId
    local base = nil

    if baseId and NPCFactionManager.getBase then
        local okBase, foundBase = pcall(function()
            return NPCFactionManager:getBase(baseId)
        end)
        if okBase and foundBase then
            base = foundBase
        end
    end

    if (not base) and npcId and NPCFactionManager.getBaseOfNPC then
        local okBaseOfNpc, foundBase, foundBaseId = pcall(function()
            return NPCFactionManager:getBaseOfNPC(npcId)
        end)
        if okBaseOfNpc and foundBase then
            base = foundBase
            baseId = baseId or foundBaseId
        end
    end

    local direction = ""
    local site = nil
    if base and params.buildSiteId and NPCFactionManager.getBuildSite then
        local okSite, foundSite = pcall(function()
            return NPCFactionManager:getBuildSite(base.id or baseId, params.buildSiteId)
        end)
        if okSite and foundSite then
            site = foundSite
            direction = resolveCardinalDirection(base.center, site, languageCode)
        end
    end

    if #direction == 0 and base and type(params.center) == "table" then
        direction = resolveCardinalDirection(base.center, params.center, languageCode)
    end

    local lang = normalizeLanguageCode(languageCode)
    local order = tostring(orderType or "")
    local isDefensive = order == "guard" or order == "patrol" or order == "defend"
    local isWork = order == "build" or order == "cook" or order == "study"

    if base then
        if isDefensive then
            context.baseLabel = lang == "FR" and "la barricade exterieure" or "the outer barricade"
        elseif isWork then
            context.baseLabel = lang == "FR" and "l'atelier" or "the workshop"
        else
            context.baseLabel = lang == "FR" and "l'abri" or "the shelter"
        end
        if #direction > 0 then
            context.baseLabel = context.baseLabel .. " " .. direction
        end
    end

    if site or params.buildSiteId then
        if lang == "FR" then
            context.siteLabel = "le chantier"
        else
            context.siteLabel = "the work site"
        end
        if #direction > 0 then
            context.siteLabel = context.siteLabel .. " " .. direction
        end
    end

    return context
end

local function humanizeDialogueValue(value, valueType, languageCode, runtimeContext)
    local lang = normalizeLanguageCode(languageCode)
    local raw = tostring(value or "")
    local compact = string.lower(raw:gsub("%s+", ""))
    local label = humanizeFreeformLabel(raw)
    local spatial = type(runtimeContext) == "table" and runtimeContext or {}

    if #raw == 0 then
        if valueType == "base" then
            return lang == "FR" and "la base" or "the base"
        elseif valueType == "site" then
            return lang == "FR" and "le chantier" or "the work site"
        elseif valueType == "item" then
            return lang == "FR" and "du materiel utile" or "useful supplies"
        end
        return lang == "FR" and "quelque chose d'utile" or "something useful"
    end

    if valueType == "base" then
        if spatial.baseLabel and #tostring(spatial.baseLabel) > 0 then
            return tostring(spatial.baseLabel)
        end
        local baseNumber = raw:match("[Bb][Aa][Ss][Ee][_%-]?(%d+)")
        if baseNumber then
            return lang == "FR" and ("la base du secteur " .. baseNumber) or ("sector base " .. baseNumber)
        end
        if compact:find("base") then
            return lang == "FR" and "la base du groupe" or "the group base"
        end
    elseif valueType == "site" then
        if spatial.siteLabel and #tostring(spatial.siteLabel) > 0 then
            return tostring(spatial.siteLabel)
        end
        local siteNumber = raw:match("[Ss][Ii][Tt][Ee][_%-]?(%d+)")
        if siteNumber then
            return lang == "FR" and ("le chantier " .. siteNumber) or ("work site " .. siteNumber)
        end
        if compact:find("site") then
            return lang == "FR" and "le chantier assigne" or "the assigned work site"
        end
    elseif valueType == "item" then
        if compact:find("food") or compact:find("canned") or compact:find("beans") or compact:find("soup") then
            return lang == "FR" and "des provisions" or "food supplies"
        end
        if compact:find("water") or compact:find("bottle") or compact:find("soda") or compact:find("pop") then
            return lang == "FR" and "de l'eau" or "water"
        end
        if compact:find("med") or compact:find("bandage") or compact:find("pill") or compact:find("antibiotic") then
            return lang == "FR" and "du materiel medical" or "medical supplies"
        end
        if compact:find("tool") or compact:find("hammer") or compact:find("saw") or compact:find("wrench") then
            return lang == "FR" and "des outils" or "tools"
        end
        if compact:find("nail") or compact:find("plank") or compact:find("wood") or compact:find("rope") then
            return lang == "FR" and "des materiaux" or "building materials"
        end
        if compact:find("ammo") or compact:find("bullet") or compact:find("shell") then
            return lang == "FR" and "des munitions" or "ammunition"
        end
    elseif valueType == "player" or valueType == "npc" then
        if compact == "unknown" or compact == "unknownplayer" or compact == "unknownnpc" then
            return lang == "FR" and "quelqu'un" or "someone"
        end
    end

    if #label == 0 then
        return raw
    end

    return label
end

local function applyDialogueTemplate(text, replacements)
    local formatted = tostring(text or "")
    if type(replacements) ~= "table" then
        return formatted
    end

    for key, value in pairs(replacements) do
        formatted = formatted:gsub("{" .. tostring(key) .. "}", tostring(value or ""))
    end

    return formatted
end

local function addLocalizedTemplateLine(responses, key, languageCode, topic, replacements)
    if not key then
        return
    end
    local text = localizeFallback(key, languageCode)
    if text and #tostring(text) > 0 and text ~= "..." then
        table.insert(responses, {
            text = applyDialogueTemplate(text, replacements),
            topic = topic or "general"
        })
    end
end

local function buildConversationPairKey(npcId, player)
    local playerId = player and player.getUsername and player:getUsername() or "unknown_player"
    return tostring(npcId or "unknown_npc") .. "::" .. tostring(playerId)
end

local function inferDialogueIntent(userMessage)
    local msg = string.lower(tostring(userMessage or ""))
    if #msg == 0 then
        return "general"
    end

    if msg:find("trade") or msg:find("sell") or msg:find("buy") or msg:find("prix") or msg:find("price") or msg:find("deal") then
        return "trade"
    end
    if msg:find("build") or msg:find("construct") or msg:find("base") or msg:find("wall") or msg:find("fort") then
        return "build"
    end
    if msg:find("cook") or msg:find("food") or msg:find("hungry") or msg:find("faim") or msg:find("manger") then
        return "cook"
    end
    if msg:find("guard") or msg:find("defend") or msg:find("protect") or msg:find("defense") or msg:find("zombie") then
        return "defend"
    end
    if msg:find("scavenge") or msg:find("loot") or msg:find("search") or msg:find("fouille") then
        return "scavenge"
    end
    if msg:find("heal") or msg:find("medical") or msg:find("medic") or msg:find("soin") or msg:find("bless") then
        return "medical"
    end
    if msg:find("study") or msg:find("learn") or msg:find("appren") or msg:find("teach") then
        return "study"
    end
    if msg:find("faction") or msg:find("clan") or msg:find("alliance") or msg:find("hostile") then
        return "faction"
    end
    if msg:find("night") or msg:find("nuit") then
        return "night"
    end
    if msg:find("rain") or msg:find("pluie") or msg:find("storm") then
        return "rain"
    end
    if msg:find("cold") or msg:find("froid") or msg:find("snow") or msg:find("neige") or msg:find("temperature") then
        return "weather"
    end
    if msg:find("trauma") or msg:find("ptsd") or msg:find("stress") or msg:find("rage") then
        return "trauma"
    end
    if msg:find("injury") or msg:find("blessure") or msg:find("jambe") or msg:find("bras") or msg:find("head") or msg:find("tete") then
        return "injury"
    end
    if msg:find("story") or msg:find("histoire") or msg:find("rumeur") or msg:find("souvenir") then
        return "story"
    end
    if msg:find("expedition") or msg:find("mission") or msg:find("offscreen") or msg:find("voyage") then
        return "expedition"
    end

    return "general"
end

local function getRecentEvents(npcData, maxCount)
    local recent = npcData and npcData.memory and npcData.memory.recentEvents or nil
    if type(recent) ~= "table" or #recent == 0 then
        return {}
    end

    local results = {}
    local startIndex = math.max(1, #recent - (maxCount or 5) + 1)
    for i = #recent, startIndex, -1 do
        results[#results + 1] = recent[i]
    end
    return results
end

local function extractRuntimeTopics(npcData, playerName)
    local topics = {}
    local events = getRecentEvents(npcData, 6)
    for i = 1, #events do
        local event = events[i]
        local eventType = event and event.eventType or nil
        local payload = event and event.payload or {}
        local actorId = payload and payload.actorId or nil
        local counterpartId = payload and payload.counterpartId or nil
        local exchange = payload and payload.exchange or nil

        if eventType == "exchange_done" and (counterpartId == playerName or payload.counterpartType == "player") then
            if exchange and (exchange.mode == "gift" or exchange.mode == "free") then
                topics.help_trade = true
            else
                topics.trade_done = true
            end
        elseif eventType == "actor_hostile" and actorId == playerName then
            topics.player_hostile = true
        elseif eventType == "fsm_order_finished" then
            if not topics.last_finished_order then
                topics.last_finished_order = tostring(payload.orderType or "")
                topics.last_finished_params = payload.params or {}
            end
        elseif eventType == "fsm_order_active" then
            if not topics.last_active_order then
                topics.last_active_order = tostring(payload.orderType or "")
                topics.last_active_params = payload.params or {}
            end
        elseif eventType == "outgoing_action" then
            if payload.actionType == "trade" or payload.actionType == "gift" then
                topics.npc_outgoing_trade = true
            elseif payload.actionType == "hostile" or payload.actionType == "threat" or payload.actionType == "insult" then
                topics.npc_recent_conflict = true
            end
        elseif eventType == "weather_seek_shelter" then
            topics.weather_seek_shelter = true
        elseif eventType == "weather_seek_warmth" then
            topics.weather_seek_warmth = true
        elseif eventType == "weather_sick" then
            topics.weather_sick = true
        elseif eventType == "injury_leg_critical" then
            topics.injury_leg_critical = true
        elseif eventType == "trauma_freeze" then
            topics.trauma_freeze = true
        elseif eventType == "trauma_rage" then
            topics.trauma_rage = true
        elseif eventType == "ally_devoured" then
            topics.ally_devoured = true
        elseif eventType == "expedition_started" or eventType == "scavenge_offscreen_departure" then
            topics.expedition_started = true
        elseif eventType == "expedition_returned" then
            topics.expedition_returned = true
        elseif eventType == "social_dialogue_contact" then
            topics.social_dialogue = true
        elseif eventType == "social_trade_contact" then
            topics.social_trade = true
        elseif eventType == "shared_memory_in" or eventType == "shared_memory_out" then
            topics.story_shared = true
        elseif eventType == "path_blocked_barricade" then
            topics.path_blocked = true
        elseif eventType == "path_contour_fallback" then
            topics.path_contour = true
        end
    end

    if npcData and npcData.health and npcData.health.isBittenHidden == true then
        topics.hidden_bite = true
    end

    return topics
end

local function getOrderParamsForDialogue(npcData, runtimeTopics, preferFinished)
    if preferFinished and runtimeTopics and type(runtimeTopics.last_finished_params) == "table" then
        return runtimeTopics.last_finished_params
    end
    if not preferFinished and runtimeTopics and type(runtimeTopics.last_active_params) == "table" then
        return runtimeTopics.last_active_params
    end
    if preferFinished and type(npcData and npcData.lastExecutedOrderParams) == "table" then
        return npcData.lastExecutedOrderParams
    end
    if not preferFinished and type(npcData and npcData.activeOrderParams) == "table" then
        return npcData.activeOrderParams
    end
    return {}
end

local function classifyItemHint(targetItemHint)
    local hint = string.lower(tostring(targetItemHint or ""))
    if hint:find("food", 1, true) or hint:find("canned", 1, true) or hint:find("beans", 1, true) then
        return "food"
    end
    if hint:find("water", 1, true) or hint:find("bottle", 1, true) or hint:find("soda", 1, true) then
        return "water"
    end
    if hint:find("med", 1, true) or hint:find("bandage", 1, true) or hint:find("pill", 1, true) then
        return "medicine"
    end
    if hint:find("tool", 1, true) or hint:find("hammer", 1, true) or hint:find("saw", 1, true) then
        return "tools"
    end
    if hint:find("nail", 1, true) or hint:find("plank", 1, true) or hint:find("wood", 1, true) then
        return "materials"
    end
    if hint:find("ammo", 1, true) or hint:find("bullet", 1, true) then
        return "ammo"
    end
    return "general"
end

local function getPlayerDisposition(npcData, playerName)
    if not NPCMemory or not playerName then
        return nil
    end
    return NPCMemory.GetDispositionTowardPlayer(npcData, playerName)
end

local function shouldAllowHostileTone(disposition, runtimeTopics)
    if runtimeTopics and (runtimeTopics.player_hostile or runtimeTopics.npc_recent_conflict) then
        return true
    end
    if not disposition then
        return true
    end
    if disposition.isTrusted or (tonumber(disposition.trust) or 0) >= 35 then
        return false
    end
    if disposition.isHostile or disposition.isDangerous or (tonumber(disposition.resentment) or 0) >= 20 then
        return true
    end
    return false
end

local function resolveRelationshipVariant(disposition, runtimeTopics)
    if runtimeTopics and runtimeTopics.player_hostile then
        return "negative"
    end

    if not disposition then
        return "neutral"
    end

    local trust = tonumber(disposition.trust) or 0
    local fear = tonumber(disposition.fear) or 0
    local resentment = tonumber(disposition.resentment) or 0
    local gratitude = tonumber(disposition.gratitude) or 0
    local respect = tonumber(disposition.respect) or 0

    if disposition.isHostile or disposition.isDangerous or resentment >= 45 then
        return "hostile"
    end
    if disposition.isFeared or fear >= 45 then
        return "fearful"
    end
    if disposition.isTrusted or trust >= 55 or gratitude >= 20 then
        return "positive"
    end
    if resentment >= 15 or fear >= 25 then
        return "wary"
    end
    if trust >= 15 or respect >= 20 or gratitude >= 8 then
        return "warm"
    end

    return "neutral"
end

local function resolveRecentOrderVariant(npcData, runtimeTopics)
    if runtimeTopics and runtimeTopics.last_finished_order and #runtimeTopics.last_finished_order > 0 then
        return string.lower(runtimeTopics.last_finished_order)
    end
    local lastExecutedOrder = npcData and npcData.lastExecutedOrder or nil
    if lastExecutedOrder and #tostring(lastExecutedOrder) > 0 then
        return string.lower(tostring(lastExecutedOrder))
    end
    return nil
end

local function rememberFallback(npcId, response)
    if not npcId or not response then
        return
    end
    local recent = NPC_NetworkServer.recentFallbackByNpc[npcId] or {}
    table.insert(recent, response)
    while #recent > 4 do
        table.remove(recent, 1)
    end
    NPC_NetworkServer.recentFallbackByNpc[npcId] = recent
end

local function rememberConversationTopic(pairKey, topic)
    if not pairKey or not topic or #tostring(topic) == 0 then
        return
    end

    local recent = NPC_NetworkServer.recentConversationByPair[pairKey] or {}
    table.insert(recent, tostring(topic))
    while #recent > 3 do
        table.remove(recent, 1)
    end
    NPC_NetworkServer.recentConversationByPair[pairKey] = recent
end

local function isRecentConversationTopic(pairKey, topic)
    if not pairKey or not topic then
        return false
    end

    local recent = NPC_NetworkServer.recentConversationByPair[pairKey]
    if type(recent) ~= "table" then
        return false
    end

    for i = 1, #recent do
        if recent[i] == topic then
            return true
        end
    end

    return false
end

local function isRecentlyUsed(npcId, response)
    if not npcId or not response then
        return false
    end
    local recent = NPC_NetworkServer.recentFallbackByNpc[npcId]
    if type(recent) ~= "table" then
        return false
    end
    for i = 1, #recent do
        if recent[i] == response then
            return true
        end
    end
    return false
end

local function pickDialogueLine(pairKey, npcId, responses, userMessage)
    if type(responses) ~= "table" or #responses == 0 then
        return "..."
    end

    local filtered = {}
    for i = 1, #responses do
        local entry = responses[i]
        local line = entry and entry.text or nil
        local topic = entry and entry.topic or "general"
        if line and #line > 0 and not isRecentlyUsed(npcId, line) and not isRecentConversationTopic(pairKey, topic) then
            filtered[#filtered + 1] = entry
        end
    end

    if #filtered == 0 then
        for i = 1, #responses do
            local entry = responses[i]
            local line = entry and entry.text or nil
            if line and #line > 0 and not isRecentlyUsed(npcId, line) then
                filtered[#filtered + 1] = entry
            end
        end
    end

    if #filtered == 0 then
        filtered = responses
    end

    local msgLen = #(userMessage or "")
    local counter = (NPC_NetworkServer.fallbackCounterByNpc[npcId] or 0) + 1
    NPC_NetworkServer.fallbackCounterByNpc[npcId] = counter
    local idx = ((msgLen + counter * 7 + os.time()) % #filtered) + 1
    local chosen = filtered[idx]
    local chosenText = chosen and chosen.text or "..."
    local chosenTopic = chosen and chosen.topic or "general"

    rememberFallback(npcId, chosenText)
    rememberConversationTopic(pairKey, chosenTopic)
    return chosenText
end

-- ==============================================================================
-- FALLBACK DIALOGUES: Reponses sensees generees localement
-- ==============================================================================

local function buildFallbackDialogueSet(npcData, languageCode, userMessage, player)
    -- Construit un ensemble de reponses possibles basees sur le PNJ
    if not npcData then
        return {}
    end

    local personality = npcData.personality or {}
    local health = npcData.health or {}
    local economy = npcData.economy or {}
    local profession = npcData.profession or {}
    local hunger = tonumber(npcData.hunger) or 50
    local thirst = tonumber(npcData.thirst) or 50
    local morale = tonumber(npcData.morale) or 50
    local cash = tonumber(economy.cash) or 0
    local marketBias = tonumber(economy.marketBias) or 0
    local factionId = tostring(npcData.factionId or npcData.faction or "")
    local professionRole = tostring(profession.role or profession.type or "unknown"):lower()
    local intent = inferDialogueIntent(userMessage)
    local activeOrder = tostring(npcData.activeOrder or npcData.orderType or ""):lower()
    local inventory = npcData.inventory or {}
    local currentWeight = tonumber(inventory.currentWeight) or 0
    local maxWeight = tonumber(inventory.maxWeight) or 0
    local isInventoryFull = maxWeight > 0 and currentWeight >= (maxWeight * 0.9)
    local playerTrust = nil
    local playerName = player and player.getUsername and player:getUsername() or nil
    local disposition = getPlayerDisposition(npcData, playerName)
    if disposition then
        playerTrust = tonumber(disposition.trust)
    elseif npcData.memory and npcData.memory.reputationByActor and playerName then
        local relation = npcData.memory.reputationByActor[playerName]
        if type(relation) == "table" then
            playerTrust = tonumber(relation.trust)
        end
    end
    local runtimeTopics = extractRuntimeTopics(npcData, playerName)
    local allowHostileTone = shouldAllowHostileTone(disposition, runtimeTopics)
    local relationVariant = resolveRelationshipVariant(disposition, runtimeTopics)
    local recentOrderVariant = resolveRecentOrderVariant(npcData, runtimeTopics)
    local recentOrderParams = getOrderParamsForDialogue(npcData, runtimeTopics, true)
    local activeOrderParams = getOrderParamsForDialogue(npcData, runtimeTopics, false)
    local socialState = npcData.memory and npcData.memory.social or {}
    local psychologyState = npcData.memory and npcData.memory.psychology or {}
    local weatherState = npcData.memory and npcData.memory.environment or {}
    local expeditionState = npcData.memory and npcData.memory.expedition or {}
    local injuryPenalties = npcData.runtimePenalties or {}
    
    -- Determine tone base sur stats
    local isHungry = hunger < 35
    local isThirsty = thirst < 35
    local isLowMorale = morale < 40
    local isSeverelyWounded = health.health and health.health < 40
    local hasSevereInjuryPenalty = (tonumber(injuryPenalties.mobility) or 0) >= 45 or (tonumber(injuryPenalties.aim) or 0) >= 45
    local isTraumatized = (tonumber(psychologyState.trauma) or 0) >= 50
    local isInRage = (tonumber(psychologyState.rage) or 0) >= 38
    local wantsSocialSupport = (tonumber(socialState.loneliness) or 0) >= 52
    
    -- Determine personnalite type
    local isBrutal = (personality.brutality or 0) > 70
    local isFriendly = (personality.socialDrive or 0) > 70
    local isLoneWolf = (personality.loneWolf or 0) > 70
    local isCourageous = (personality.courage or 0) > 80
    local isFearful = (personality.courage or 0) < 40
    
    local responses = {}

    local function addLine(key, topic)
        addLocalizedLine(responses, key, languageCode, topic)
    end

    local function addLines(keys, topic)
        addLocalizedLines(responses, keys, languageCode, topic)
    end

    local function addTemplateLine(key, topic, replacements)
        addLocalizedTemplateLine(responses, key, languageCode, topic, replacements)
    end

    local function addOrderParamContext(orderType, orderParams, topicPrefix)
        if not orderType then
            return
        end

        local params = type(orderParams) == "table" and orderParams or {}
        local spatialContext = resolveRuntimeBaseSiteContext(npcData, orderType, params, languageCode)
        local baseId = humanizeDialogueValue(params.baseId, "base", languageCode, spatialContext)
        local buildSiteId = humanizeDialogueValue(params.buildSiteId, "site", languageCode, spatialContext)
        local hintLabel = humanizeDialogueValue(params.targetItemHint, "item", languageCode, spatialContext)
        local followPlayerId = humanizeDialogueValue(params.followPlayerId, "player", languageCode, spatialContext)
        local followNpcId = humanizeDialogueValue(params.followNpcId, "npc", languageCode, spatialContext)
        local coverPlayerId = humanizeDialogueValue(params.coverPlayerId, "player", languageCode, spatialContext)
        local radius = tostring(math.floor(tonumber(params.radius) or tonumber(params.coverRadius) or 0))
        local desiredDistance = tostring(math.floor(tonumber(params.desiredDistance) or 0))
        local hintCategory = classifyItemHint(params.targetItemHint)
        local replacements = {
            baseId = baseId,
            siteId = buildSiteId,
            hint = hintLabel,
            playerId = coverPlayerId ~= "unknown" and coverPlayerId or followPlayerId,
            npcId = followNpcId,
            radius = radius,
            distance = desiredDistance
        }
        local topic = topicPrefix or "order_detail"

        if orderType == "guard" then
            if params.baseId then
                addTemplateLine("IGUI_NPC_OrderParam_Guard_Base_1", topic, replacements)
            end
            if params.perimeter or params.waypointMode == "loop" then
                addTemplateLine("IGUI_NPC_OrderParam_Guard_Perimeter_1", topic, replacements)
            end
        elseif orderType == "patrol" then
            addTemplateLine("IGUI_NPC_OrderParam_Patrol_Perimeter_1", topic, replacements)
        elseif orderType == "defend" then
            if params.escortMode then
                addTemplateLine("IGUI_NPC_OrderParam_Defend_Escort_1", topic, replacements)
            elseif params.aggressiveCover == true then
                addTemplateLine("IGUI_NPC_OrderParam_Defend_Aggressive_1", topic, replacements)
            elseif params.coverPlayerId then
                addTemplateLine("IGUI_NPC_OrderParam_Defend_Player_1", topic, replacements)
            end
        elseif orderType == "build" then
            if params.baseId then
                addTemplateLine("IGUI_NPC_OrderParam_Build_Base_1", topic, replacements)
            end
            if params.buildSiteId then
                addTemplateLine("IGUI_NPC_OrderParam_Build_Site_1", topic, replacements)
            end
        elseif orderType == "scavenge" then
            if params.targetItemHint and #tostring(params.targetItemHint) > 0 then
                if hintCategory == "food" then
                    addTemplateLine("IGUI_NPC_OrderParam_Scavenge_Food_1", topic, replacements)
                elseif hintCategory == "water" then
                    addTemplateLine("IGUI_NPC_OrderParam_Scavenge_Water_1", topic, replacements)
                elseif hintCategory == "medicine" then
                    addTemplateLine("IGUI_NPC_OrderParam_Scavenge_Medicine_1", topic, replacements)
                elseif hintCategory == "tools" then
                    addTemplateLine("IGUI_NPC_OrderParam_Scavenge_Tools_1", topic, replacements)
                elseif hintCategory == "materials" then
                    addTemplateLine("IGUI_NPC_OrderParam_Scavenge_Materials_1", topic, replacements)
                elseif hintCategory == "ammo" then
                    addTemplateLine("IGUI_NPC_OrderParam_Scavenge_Ammo_1", topic, replacements)
                else
                    addTemplateLine("IGUI_NPC_OrderParam_Scavenge_Target_1", topic, replacements)
                end
            end
            if params.stealthScavenge == true then
                addTemplateLine("IGUI_NPC_OrderParam_Scavenge_Stealth_1", topic, replacements)
            end
        elseif orderType == "recover" then
            if params.baseId then
                addTemplateLine("IGUI_NPC_OrderParam_Recover_Base_1", topic, replacements)
            end
        elseif orderType == "study" then
            if params.businessService == "craft" then
                addTemplateLine("IGUI_NPC_OrderParam_Study_Craft_1", topic, replacements)
            elseif params.deliveryToPlayerId then
                replacements.playerId = humanizeDialogueValue(params.deliveryToPlayerId, "player", languageCode, spatialContext)
                addTemplateLine("IGUI_NPC_OrderParam_Study_Delivery_1", topic, replacements)
            elseif params.baseId then
                addTemplateLine("IGUI_NPC_OrderParam_Study_Base_1", topic, replacements)
            end
        elseif orderType == "cook" then
            if params.baseId then
                addTemplateLine("IGUI_NPC_OrderParam_Cook_Base_1", topic, replacements)
            end
        elseif orderType == "follow" then
            if params.followPlayerId then
                addTemplateLine("IGUI_NPC_OrderParam_Follow_Player_1", topic, replacements)
            elseif params.followNpcId then
                addTemplateLine("IGUI_NPC_OrderParam_Follow_NPC_1", topic, replacements)
            end
            if (tonumber(params.desiredDistance) or 0) > 0 then
                addTemplateLine("IGUI_NPC_OrderParam_Follow_Distance_1", topic, replacements)
            end
        elseif orderType == "stay" then
            if (tonumber(params.radius) or 0) > 0 then
                addTemplateLine("IGUI_NPC_OrderParam_Stay_Radius_1", topic, replacements)
            end
        elseif orderType == "sleep" then
            if params.baseId then
                addTemplateLine("IGUI_NPC_OrderParam_Sleep_Base_1", topic, replacements)
            end
        end
    end
    
    -- ===== GREETINGS =====
    if isFriendly then
        addLine("IGUI_NPC_Greeting_Friendly_1", "greeting")
        addLine("IGUI_NPC_Greeting_Friendly_2", "greeting")
        addLine("IGUI_NPC_Greeting_Friendly_3", "greeting")
    elseif isLoneWolf then
        addLine("IGUI_NPC_Greeting_LoneWolf_1", "greeting")
        addLine("IGUI_NPC_Greeting_LoneWolf_2", "greeting")
        addLine("IGUI_NPC_Greeting_LoneWolf_3", "greeting")
    else
        addLine("IGUI_NPC_Greeting_Neutral_1", "greeting")
        addLine("IGUI_NPC_Greeting_Neutral_2", "greeting")
        addLine("IGUI_NPC_Greeting_Neutral_3", "greeting")
    end

    -- ===== RELATIONSHIP CONTEXT =====
    if relationVariant == "positive" or relationVariant == "warm" then
        addLines({ "IGUI_NPC_Relation_Positive_1", "IGUI_NPC_Relation_Positive_2" }, "relationship")
    elseif relationVariant == "neutral" then
        addLines({ "IGUI_NPC_Relation_Neutral_1", "IGUI_NPC_Relation_Neutral_2" }, "relationship")
    elseif relationVariant == "wary" then
        addLines({ "IGUI_NPC_Relation_Wary_1", "IGUI_NPC_Relation_Wary_2" }, "relationship")
    elseif relationVariant == "fearful" then
        addLines({ "IGUI_NPC_Relation_Fearful_1", "IGUI_NPC_Relation_Fearful_2" }, "relationship")
    elseif relationVariant == "hostile" or relationVariant == "negative" then
        addLines({ "IGUI_NPC_Relation_Hostile_1", "IGUI_NPC_Relation_Hostile_2" }, "relationship")
    end
    
    -- ===== HUNGER/THIRST CONTEXT =====
    if isHungry and isThirsty then
        addLine("IGUI_NPC_HungryThirsty_1", "survival")
        addLine("IGUI_NPC_HungryThirsty_2", "survival")
    elseif isHungry then
        addLine("IGUI_NPC_Hungry", "survival")
        addLine("IGUI_NPC_Hungry_2", "survival")
    elseif isThirsty then
        addLine("IGUI_NPC_Thirsty", "survival")
        addLine("IGUI_NPC_Thirsty_2", "survival")
    end
    
    -- ===== HEALTH/WOUND CONTEXT =====
    if isSeverelyWounded then
        addLine("IGUI_NPC_Wounded_1", "medical")
        addLine("IGUI_NPC_Wounded_2", "medical")
        if isBrutal then
            addLine("IGUI_NPC_Wounded_Brutal", "medical")
        else
            addLine("IGUI_NPC_Wounded_Anxious", "medical")
        end
    end
    
    -- ===== HIDDEN BITE CONTEXT =====
    if health.isBittenHidden then
        addLine("IGUI_NPC_BittenHidden_1", "bite")
        addLine("IGUI_NPC_BittenHidden_2", "bite")
        addLine("IGUI_NPC_BittenHidden_3", "bite")
    end
    
    -- ===== ATTITUDE CONTEXT =====
    if isBrutal and allowHostileTone then
        addLine("IGUI_NPC_Attitude_Brutal_1", "attitude")
        addLine("IGUI_NPC_Attitude_Brutal_2", "attitude")
        addLine("IGUI_NPC_Attitude_Brutal_3", "attitude")
    elseif isCourageous then
        addLine("IGUI_NPC_Attitude_Courage_1", "attitude")
        addLine("IGUI_NPC_Attitude_Courage_2", "attitude")
        addLine("IGUI_NPC_Attitude_Courage_3", "attitude")
    elseif isFearful then
        addLine("IGUI_NPC_Attitude_Fear_1", "attitude")
        addLine("IGUI_NPC_Attitude_Fear_2", "attitude")
        addLine("IGUI_NPC_Attitude_Fear_3", "attitude")
    end
    
    -- ===== GENERAL CONTEXT =====
    if isLowMorale then
        addLine("IGUI_NPC_Morale_Low_1", "morale")
        addLine("IGUI_NPC_Morale_Low_2", "morale")
    else
        addLine("IGUI_NPC_Morale_Ok_1", "morale")
        addLine("IGUI_NPC_Morale_Ok_2", "morale")
    end
    
    -- ===== ALWAYS ADD GENERIC =====
    addLine("IGUI_NPC_Generic_1", "general")
    addLine("IGUI_NPC_Generic_2", "general")
    addLine("IGUI_NPC_Generic_3", "general")
    addLine("IGUI_NPC_Generic_4", "general")
    addLine("IGUI_NPC_Generic_5", "general")
    addLine("IGUI_NPC_Generic_6", "general")
    addLine("IGUI_NPC_Generic_7", "general")
    addLine("IGUI_NPC_Generic_8", "general")

    -- ===== COMMERCE CONTEXT =====
    addLines({ "IGUI_NPC_Trade_Offer_1", "IGUI_NPC_Trade_Offer_2", "IGUI_NPC_Trade_Offer_3", "IGUI_NPC_Trade_Offer_4", "IGUI_NPC_Trade_Offer_5", "IGUI_NPC_Trade_Offer_6" }, "trade")
    if cash < 20 then
        addLine("IGUI_NPC_Trade_NoCash", "trade")
    else
        addLine("IGUI_NPC_Trade_DealDone", "trade")
    end

    if marketBias > 20 then
        addLine("IGUI_NPC_Market_HighDemand", "market")
    elseif marketBias < -20 then
        addLine("IGUI_NPC_Market_Oversupply", "market")
    end

    if isInventoryFull then
        addLines({ "IGUI_NPC_Inventory_Full_1", "IGUI_NPC_Inventory_Full_2" }, "inventory")
    end

    -- ===== PROFESSION CONTEXT =====
    local professionKeys = {
        artisan = "IGUI_NPC_Profession_Artisan",
        cook = "IGUI_NPC_Profession_Cook",
        builder = "IGUI_NPC_Profession_Builder",
        merchant = "IGUI_NPC_Profession_Merchant",
        scout = "IGUI_NPC_Profession_Scout",
        warrior = "IGUI_NPC_Profession_Warrior",
        scholar = "IGUI_NPC_Profession_Scholar"
    }
    addLine(professionKeys[professionRole] or "IGUI_NPC_Profession_Unknown", "profession")
    if professionRole == "builder" then
        addLines({ "IGUI_NPC_Action_Build_1", "IGUI_NPC_Action_Build_2", "IGUI_NPC_Action_Build_3" }, "build")
    elseif professionRole == "cook" then
        addLines({ "IGUI_NPC_Action_Cook_1", "IGUI_NPC_Action_Cook_2", "IGUI_NPC_Action_Cook_3" }, "cook")
    elseif professionRole == "merchant" then
        addLines({ "IGUI_NPC_Action_Trade_1", "IGUI_NPC_Action_Trade_2", "IGUI_NPC_Action_Trade_3" }, "trade")
    elseif professionRole == "warrior" then
        addLines({ "IGUI_NPC_Action_Defend_1", "IGUI_NPC_Action_Defend_2" }, "defend")
    elseif professionRole == "scout" then
        addLines({ "IGUI_NPC_Action_Scavenge_1", "IGUI_NPC_Action_Scavenge_2", "IGUI_NPC_Action_Scavenge_3" }, "scavenge")
    elseif professionRole == "scholar" then
        addLines({ "IGUI_NPC_Action_Study_1", "IGUI_NPC_Action_Study_2" }, "study")
    end

    -- ===== FACTION CONTEXT =====
    if #factionId > 0 then
        if isBrutal and allowHostileTone then
            addLine("IGUI_NPC_Faction_Hostile", "faction")
        elseif isFriendly then
            addLine("IGUI_NPC_Faction_Allied", "faction")
        else
            addLine("IGUI_NPC_Faction_Neutral", "faction")
        end

        if morale < 35 then
            addLine("IGUI_NPC_Faction_EventNeedHelp", "faction")
        end
        if isFearful or health.isBittenHidden == true then
            addLine("IGUI_NPC_Faction_EventRaid", "faction")
        end
    end

    -- ===== RUNTIME EVENT CONTEXT =====
    if runtimeTopics.trade_done then
        addLines({ "IGUI_NPC_Event_TradeDone_1", "IGUI_NPC_Event_TradeDone_2" }, "event_trade")
    end
    if runtimeTopics.help_trade then
        addLines({ "IGUI_NPC_Event_Helped_1", "IGUI_NPC_Event_Helped_2" }, "event_help")
    end
    if runtimeTopics.player_hostile then
        addLines({ "IGUI_NPC_Event_PlayerHostile_1", "IGUI_NPC_Event_PlayerHostile_2" }, "event_conflict")
    end
    if runtimeTopics.hidden_bite then
        addLines({ "IGUI_NPC_Event_BiteSecret_1", "IGUI_NPC_Event_BiteSecret_2" }, "event_bite")
    end
    if runtimeTopics.npc_outgoing_trade then
        addLines({ "IGUI_NPC_Event_LastOrderTrade_1", "IGUI_NPC_Event_LastOrderTrade_2" }, "event_order")
    end
    if runtimeTopics.path_blocked then
        addLines({ "IGUI_NPC_Event_PathBlocked_1", "IGUI_NPC_Event_PathBlocked_2" }, "event_path")
    end
    if runtimeTopics.path_contour then
        addLines({ "IGUI_NPC_Event_PathContour_1", "IGUI_NPC_Event_PathContour_2" }, "event_path")
    end
    if runtimeTopics.weather_seek_shelter or weatherState.needsShelter then
        addLines({ "IGUI_NPC_Event_WeatherShelter_1", "IGUI_NPC_Event_WeatherShelter_2" }, "event_weather")
    end
    if runtimeTopics.weather_seek_warmth or weatherState.needsWarmth then
        addLines({ "IGUI_NPC_Event_WeatherWarmth_1", "IGUI_NPC_Event_WeatherWarmth_2" }, "event_weather")
    end
    if runtimeTopics.weather_sick or (tonumber(weatherState.sickness) or 0) >= 45 then
        addLines({ "IGUI_NPC_Event_WeatherSick_1", "IGUI_NPC_Event_WeatherSick_2" }, "event_weather")
    end
    if runtimeTopics.injury_leg_critical or hasSevereInjuryPenalty then
        addLines({ "IGUI_NPC_Event_InjuryLocalized_1", "IGUI_NPC_Event_InjuryLocalized_2" }, "event_injury")
    end
    if runtimeTopics.trauma_freeze or isTraumatized then
        addLines({ "IGUI_NPC_Event_TraumaFreeze_1", "IGUI_NPC_Event_TraumaFreeze_2" }, "event_trauma")
    end
    if runtimeTopics.trauma_rage or isInRage then
        addLines({ "IGUI_NPC_Event_TraumaRage_1", "IGUI_NPC_Event_TraumaRage_2" }, "event_trauma")
    end
    if runtimeTopics.expedition_started or expeditionState.active == true then
        addLines({ "IGUI_NPC_Event_ExpeditionStart_1", "IGUI_NPC_Event_ExpeditionStart_2" }, "event_expedition")
    end
    if runtimeTopics.expedition_returned then
        addLines({ "IGUI_NPC_Event_ExpeditionReturn_1", "IGUI_NPC_Event_ExpeditionReturn_2" }, "event_expedition")
    end
    if runtimeTopics.story_shared then
        addLines({ "IGUI_NPC_Event_StoryShared_1", "IGUI_NPC_Event_StoryShared_2" }, "event_story")
    end
    if runtimeTopics.social_dialogue or wantsSocialSupport then
        addLines({ "IGUI_NPC_Event_SocialTalk_1", "IGUI_NPC_Event_SocialTalk_2" }, "event_social")
    end
    if runtimeTopics.social_trade then
        addLines({ "IGUI_NPC_Event_SocialTrade_1", "IGUI_NPC_Event_SocialTrade_2" }, "event_social")
    end
    if recentOrderVariant == "guard" or recentOrderVariant == "patrol" then
        addLines({ "IGUI_NPC_Event_OrderFinished_Guard_1", "IGUI_NPC_Event_OrderFinished_Guard_2" }, "event_order")
    elseif recentOrderVariant == "recover" then
        addLines({ "IGUI_NPC_Event_OrderFinished_Recover_1", "IGUI_NPC_Event_OrderFinished_Recover_2" }, "event_order")
    elseif recentOrderVariant == "scavenge" then
        addLines({ "IGUI_NPC_Event_OrderFinished_Scavenge_1", "IGUI_NPC_Event_OrderFinished_Scavenge_2" }, "event_order")
    elseif recentOrderVariant == "build" then
        addLines({ "IGUI_NPC_Event_OrderFinished_Build_1", "IGUI_NPC_Event_OrderFinished_Build_2" }, "event_order")
    elseif recentOrderVariant == "cook" then
        addLines({ "IGUI_NPC_Event_OrderFinished_Cook_1", "IGUI_NPC_Event_OrderFinished_Cook_2" }, "event_order")
    elseif recentOrderVariant == "defend" then
        addLines({ "IGUI_NPC_Event_OrderFinished_Defend_1", "IGUI_NPC_Event_OrderFinished_Defend_2" }, "event_order")
    elseif recentOrderVariant == "follow" then
        addLines({ "IGUI_NPC_Event_OrderFinished_Follow_1", "IGUI_NPC_Event_OrderFinished_Follow_2" }, "event_order")
    elseif recentOrderVariant == "study" then
        addLines({ "IGUI_NPC_Event_OrderFinished_Study_1", "IGUI_NPC_Event_OrderFinished_Study_2" }, "event_order")
    elseif recentOrderVariant == "sleep" then
        addLines({ "IGUI_NPC_Event_OrderFinished_Sleep_1", "IGUI_NPC_Event_OrderFinished_Sleep_2" }, "event_order")
    elseif recentOrderVariant == "stay" then
        addLines({ "IGUI_NPC_Event_OrderFinished_Stay_1", "IGUI_NPC_Event_OrderFinished_Stay_2" }, "event_order")
    end
    addOrderParamContext(recentOrderVariant, recentOrderParams, "event_order_detail")

    -- ===== ORDER/INTENT CONTEXT =====
    if activeOrder == "build" then
        addLines({ "IGUI_NPC_Action_Build_1", "IGUI_NPC_Action_Build_2" }, "build")
    elseif activeOrder == "cook" then
        addLines({ "IGUI_NPC_Action_Cook_1", "IGUI_NPC_Action_Cook_2" }, "cook")
    elseif activeOrder == "guard" then
        addLines({ "IGUI_NPC_Action_Guard_1", "IGUI_NPC_Action_Guard_2", "IGUI_NPC_Action_Guard_3" }, "guard")
    elseif activeOrder == "scavenge" then
        addLines({ "IGUI_NPC_Action_Scavenge_1", "IGUI_NPC_Action_Scavenge_2" }, "scavenge")
    elseif activeOrder == "recover" then
        addLines({ "IGUI_NPC_Action_Recover_1", "IGUI_NPC_Action_Recover_2" }, "recover")
    elseif activeOrder == "defend" then
        addLines({ "IGUI_NPC_Action_Defend_1", "IGUI_NPC_Action_Defend_2" }, "defend")
    elseif activeOrder == "study" then
        addLines({ "IGUI_NPC_Action_Study_1", "IGUI_NPC_Action_Study_2" }, "study")
    end
    addOrderParamContext(activeOrder, activeOrderParams, "active_order_detail")

    if intent == "trade" then
        addLines({ "IGUI_NPC_Action_Trade_1", "IGUI_NPC_Action_Trade_2", "IGUI_NPC_Action_Trade_3" }, "trade")
    elseif intent == "build" then
        addLines({ "IGUI_NPC_Action_Build_1", "IGUI_NPC_Action_Build_2", "IGUI_NPC_Action_Build_3" }, "build")
    elseif intent == "cook" then
        addLines({ "IGUI_NPC_Action_Cook_1", "IGUI_NPC_Action_Cook_2", "IGUI_NPC_Action_Cook_3" }, "cook")
    elseif intent == "defend" then
        addLines({ "IGUI_NPC_Action_Defend_1", "IGUI_NPC_Action_Defend_2" }, "defend")
    elseif intent == "scavenge" then
        addLines({ "IGUI_NPC_Action_Scavenge_1", "IGUI_NPC_Action_Scavenge_2", "IGUI_NPC_Action_Scavenge_3" }, "scavenge")
    elseif intent == "medical" then
        addLines({ "IGUI_NPC_Action_Medical_1", "IGUI_NPC_Action_Medical_2" }, "medical")
    elseif intent == "study" then
        addLines({ "IGUI_NPC_Action_Study_1", "IGUI_NPC_Action_Study_2" }, "study")
    elseif intent == "faction" then
        if allowHostileTone then
            addLines({ "IGUI_NPC_Faction_Allied", "IGUI_NPC_Faction_Neutral", "IGUI_NPC_Faction_Hostile" }, "faction")
        else
            addLines({ "IGUI_NPC_Faction_Allied", "IGUI_NPC_Faction_Neutral" }, "faction")
        end
    elseif intent == "night" then
        addLines({ "IGUI_NPC_Condition_Night_1", "IGUI_NPC_Condition_Night_2" }, "night")
    elseif intent == "rain" then
        addLines({ "IGUI_NPC_Condition_Rain_1", "IGUI_NPC_Condition_Rain_2" }, "rain")
    elseif intent == "weather" then
        addLines({ "IGUI_NPC_Event_WeatherShelter_1", "IGUI_NPC_Event_WeatherWarmth_1", "IGUI_NPC_Event_WeatherSick_1" }, "weather")
    elseif intent == "trauma" then
        addLines({ "IGUI_NPC_Event_TraumaFreeze_1", "IGUI_NPC_Event_TraumaRage_1" }, "trauma")
    elseif intent == "injury" then
        addLines({ "IGUI_NPC_Event_InjuryLocalized_1", "IGUI_NPC_Event_InjuryLocalized_2" }, "injury")
    elseif intent == "story" then
        addLines({ "IGUI_NPC_Event_StoryShared_1", "IGUI_NPC_Event_SocialTalk_1" }, "story")
    elseif intent == "expedition" then
        addLines({ "IGUI_NPC_Event_ExpeditionStart_1", "IGUI_NPC_Event_ExpeditionReturn_1" }, "expedition")
    end

    if playerTrust ~= nil then
        if playerTrust >= 65 then
            addLines({ "IGUI_NPC_Trust_High_1", "IGUI_NPC_Trust_High_2" }, "trust")
        elseif playerTrust <= 25 then
            addLines({ "IGUI_NPC_Trust_Low_1", "IGUI_NPC_Trust_Low_2" }, "trust")
        end
    end

    if (relationVariant == "positive" or relationVariant == "warm") and not runtimeTopics.player_hostile then
        addLines({ "IGUI_NPC_Event_FriendlyStable_1", "IGUI_NPC_Event_FriendlyStable_2" }, "relationship")
    end

    if isFearful then
        addLines({ "IGUI_NPC_Condition_ZombiePressure_1", "IGUI_NPC_Condition_ZombiePressure_2" }, "pressure")
    end
    if isFriendly and morale > 60 then
        addLines({ "IGUI_NPC_Condition_BaseSafety_1", "IGUI_NPC_Condition_BaseSafety_2" }, "safety")
    end
    
        -- ===== LEARNING OBSERVATIONS =====
    if npcData.observationLog and #npcData.observationLog > 5 then
        addLine("IGUI_NPC_Learning_1", "learning")
        addLine("IGUI_NPC_Learning_2", "learning")
        addLine("IGUI_NPC_Learning_3", "learning")
    end
    
    return responses
end

local function generateFallbackDialogue(npcData, userMessage, languageCode, player)
    -- Genere une reponse fallback contextuelle
    local responses = buildFallbackDialogueSet(npcData, languageCode, userMessage, player)
    if #responses == 0 then
        return "..."
    end

    local npcId = npcData and (npcData.id or npcData.npcId or npcData.uuid) or "_generic"
    local pairKey = buildConversationPairKey(npcId, player)
    return pickDialogueLine(pairKey, tostring(npcId), responses, userMessage)
end

-- ==============================================================================
-- GESTION DIALOGUES: Ollama ou Fallback
-- ==============================================================================

function NPC_NetworkServer:getDialogueResponse(npcId, userMessage, player, callback, playerLanguage)
    -- Recupere dialogue Ollama si dispo, sinon fallback
    
    if not npcId or not userMessage or not callback then
        callback("Erreur communication", true)
        return
    end

    local okHooks, NPCInteractionHooks = pcall(require, "NPCInteractionHooks")
    if not okHooks or not NPCInteractionHooks then
        callback("Module NPC indisponible", true)
        return
    end

    local npcData = NPCInteractionHooks:getNPCData(npcId)
    if not npcData then
        callback("PNJ introuvable", true)
        return
    end

    local dialogueLanguage = normalizeLanguageCode(playerLanguage or getCurrentPZLanguageCode())

    -- ===== ENRICH CONTEXT POUR DIALOGUES =====
    local additionalContext = ""
    
    if NPC_BiteManagement then
        local bitePrompt = NPC_BiteManagement:buildBiteAnxietyPrompt(npcData)
        additionalContext = additionalContext .. bitePrompt
    end
    
    if NPC_ObservationLearning then
        local learningPrompt = NPC_ObservationLearning:buildLearningPrompt(npcData)
        additionalContext = additionalContext .. learningPrompt
    end
    
    -- Stocke pour Ollama (sera injecte dans systeme prompt)
    npcData._dialogueContext = additionalContext
    npcData._dialogueLanguage = dialogueLanguage

    -- Essaie Ollama d'abord
    local okOllama, OllamaBridge = pcall(require, "OllamaBridge")
    if okOllama and OllamaBridge then
        OllamaBridge:generateDialogue(npcData, npcId, userMessage, function(response)
            callback(response, false)
        end)
        return
    end

    -- Fallback: genere reponse intelligente localement
    local fallbackResponse = generateFallbackDialogue(npcData, userMessage, dialogueLanguage, player)
    callback(fallbackResponse, false)
end

-- ==============================================================================
-- SYNC POSITIONS/ANIMATIONS/ATTAQUES aux Clients
-- ==============================================================================

function NPC_NetworkServer:updateNPCState(npcId, npcData)
    -- Mets a jour l'etat du PNJ et l'envoie aux clients
    -- Appele regulierement par le game loop
    
    if not npcId or not npcData then
        return
    end

    -- Throttle pour economiser bande passante
    local now = os.time()
    if self.lastSyncTime[npcId] and (now - self.lastSyncTime[npcId]) < self.syncInterval then
        return
    end
    self.lastSyncTime[npcId] = now

    -- Construis state compact
    local state = {
        npcId = npcId,
        x = npcData.x or 0,
        y = npcData.y or 0,
        z = npcData.z or 0,
        direction = npcData.direction or 0,
        animState = npcData.animState or "idle",
        moving = npcData.moving or false,
        running = npcData.running or false,
        attacking = npcData.attacking or false,
        health = (npcData.health and (npcData.health.current or npcData.health.health)) or 100,
        isBitten = npcData.health and npcData.health.isBitten or false,
        weaponId = npcData.weaponId or nil,
        hunger = tonumber(npcData.hunger) or 50,
        thirst = tonumber(npcData.thirst) or 50,
        morale = tonumber(npcData.morale) or 50,
        order = npcData.activeOrder or nil
    }

    local previous = self.npcSyncStates[npcId]
    local orderFx = getOrderFxType(state.order, state.animState)
    local prevOrderFx = previous and getOrderFxType(previous.order, previous.animState) or nil
    if orderFx and orderFx ~= prevOrderFx then
        local lastAction = self.lastActionFxTime[npcId] or 0
        if (now - lastAction) >= 2 then
            self.lastActionFxTime[npcId] = now
            self:broadcastNPCFx(npcId, orderFx, npcData)
        end
    end

    if previous then
        local movingChanged = state.moving ~= previous.moving
        local runningChanged = state.running ~= previous.running
        local attackingChanged = state.attacking ~= previous.attacking
        local animChanged = state.animState ~= previous.animState

        if movingChanged or runningChanged or attackingChanged or animChanged then
            local stateFx = nil
            if state.attacking or state.animState == "combat" then
                stateFx = "npc_combat"
            elseif state.running then
                stateFx = "npc_run"
            elseif state.moving then
                stateFx = "npc_walk"
            elseif state.animState == "sleep" or state.order == "sleep" then
                stateFx = "npc_sleep"
            elseif state.animState == "recover" or state.order == "recover" then
                stateFx = "npc_recover"
            elseif state.order == "guard" then
                stateFx = "npc_guard"
            elseif state.order == "trade" or state.order == "buy" then
                stateFx = "npc_trade"
            elseif state.order == "scavenge" then
                stateFx = "npc_scavenge"
            elseif state.order == "cook" then
                stateFx = "npc_cook"
            elseif state.order == "study" then
                stateFx = "npc_study"
            elseif state.order == "follow" then
                stateFx = "npc_follow"
            elseif state.order == "flee" then
                stateFx = "npc_flee"
            elseif state.order == "build" then
                stateFx = "npc_build"
            elseif state.order == "idle" or state.animState == "idle" then
                stateFx = "npc_idle"
            end

            if stateFx then
                local lastAction = self.lastActionFxTime[npcId] or 0
                if (now - lastAction) >= 2 then
                    self.lastActionFxTime[npcId] = now
                    self:broadcastNPCFx(npcId, stateFx, npcData)
                end
            end
        end
    end
    if previous and tonumber(state.health) and tonumber(previous.health) and tonumber(state.health) < tonumber(previous.health) then
        local lastHurt = self.lastHurtFxTime[npcId] or 0
        if (now - lastHurt) >= 2 then
            self.lastHurtFxTime[npcId] = now
            self:broadcastNPCFx(npcId, "npc_hurt", npcData)
        end
    end

    if state.order == "build" then
        local lastBuild = self.lastBuildFxTime[npcId] or 0
        if (now - lastBuild) >= 4 then
            self.lastBuildFxTime[npcId] = now
            self:broadcastNPCFx(npcId, "npc_build", npcData)
        end
    end

    -- Envoie a tous les clients
    if sendServerCommand then
        local players = getOnlinePlayersSafe()
        for i = 1, #players do
            local player = players[i]
            sendServerCommand(player, self.module, self.syncCommand, state)
        end
    end

    self.npcSyncStates[npcId] = state
end

function NPC_NetworkServer:broadcastDialogueResponse(npcId, requestId, response, isError, targetPlayer)
    -- Envoie reponse dialogue au client
    
    if not targetPlayer or not sendServerCommand then
        return
    end

    sendServerCommand(targetPlayer, self.module, self.dialogueResponseCommand, {
        npcId = npcId,
        requestId = requestId,
        response = response,
        isError = isError == true
    })
end

-- ==============================================================================
-- ORCHESTRATION: Calculs centralises cote serveur
-- ==============================================================================

function NPC_NetworkServer:updateNPCStats(npcId, npcData)
    -- Calculs serveur: faim, soif, morale, sante
    -- Appele lors de ticks serveur
    
    if not npcData then
        return
    end

    local now = os.time()
    local lastUpdate = npcData._lastStatsUpdate or now
    local deltaTime = now - lastUpdate
    
    if deltaTime < 1 then
        return -- Mise a jour max 1x/sec
    end

    npcData._lastStatsUpdate = now

    -- Decremente faim/soif avec le temps (simplifie)
    local hunger = tonumber(npcData.hunger) or 50
    local thirst = tonumber(npcData.thirst) or 50
    local morale = tonumber(npcData.morale) or 50

    hunger = math.max(0, hunger - (deltaTime * 0.02)) -- Decroit lentement
    thirst = math.max(0, thirst - (deltaTime * 0.03)) -- Decroit plus vite
    
    -- Impact de la faim/soif sur le morale
    if hunger < 30 or thirst < 30 then
        morale = math.max(0, morale - (deltaTime * 0.05))
    end

    npcData.hunger = hunger
    npcData.thirst = thirst
    npcData.morale = morale

    -- ===== BITE MANAGEMENT =====
    if NPC_BiteManagement and type(NPC_BiteManagement.updateNPCBiteStates) == "function" then
        NPC_BiteManagement:updateNPCBiteStates(npcId, npcData)
    end

    -- ===== OBSERVATION LEARNING =====
    if NPC_ObservationLearning and type(NPC_ObservationLearning.checkNearbyPlayerActions) == "function" then
        -- Recupere tous les joueurs (simplifie, a adapter si besoin)
        local allPlayers = {} -- TODO: Implementer getAllPlayers()
        NPC_ObservationLearning:checkNearbyPlayerActions(npcId, npcData, allPlayers)
    end

    -- Sync etat mis a jour
    self:updateNPCState(npcId, npcData)
end

-- ==============================================================================
-- EVENT HANDLERS: Recoit commandes du client
-- ==============================================================================

function NPC_NetworkServer:onClientDialogueRequest(player, args)
    -- Client demande dialogue pour un PNJ
    
    if not player or not args or not args.npcId then
        return false
    end

    local npcId = args.npcId
    local userMessage = args.userMessage or ""
    local playerLanguage = args.playerLanguage
    local requestId = args.requestId

    self:sendDialoguePending(player, npcId, requestId, true)

    -- Appelle gestion dialogue (Ollama ou fallback)
    self:getDialogueResponse(npcId, userMessage, player, function(response, isError)
        self:sendDialoguePending(player, npcId, requestId, false)
        self:broadcastDialogueResponse(npcId, requestId, response, isError, player)
    end, playerLanguage)

    return true
end

-- ==============================================================================
-- INIT: Enregistre event listeners
-- ==============================================================================

function NPC_NetworkServer:init()
    print("[NPC_NetworkServer] Initialisation reseau multijoueur")
    
    if Events and Events.OnClientCommand then
        Events.OnClientCommand.Add(function(module, command, player, args)
            if module == self.module and command == self.dialogueRequestCommand then
                NPC_NetworkServer:onClientDialogueRequest(player, args)
            end
        end)
    end
end

-- Demarre si serveur
if isServer then
    NPC_NetworkServer:init()
end

return NPC_NetworkServer
