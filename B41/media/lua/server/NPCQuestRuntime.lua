--[[
    Project Humain : Dynamic_NPC_Overhaul
    NPCQuestRuntime.lua

    Couche SSR minimale de quetes:
    - progression persistee dans le modData joueur
    - progression via intel, commerce et cadeaux
    - journal serialize pour UI client
]]

local NPCQuestRuntime = {
    module = "PH_NPC_INTERACT",
    command = "QuestJournal",
    storageKey = "PHNPC_QuestState"
}

local questDefs = {
    {
        id = "first_contact",
        title = "Premier contact",
        description = "Obtenir des renseignements de 2 PNJ differents.",
        goal = 2,
        kind = "intel"
    },
    {
        id = "market_runner",
        title = "Courier du marche",
        description = "Reussir 3 transactions commerciales.",
        goal = 3,
        kind = "trade"
    },
    {
        id = "goodwill",
        title = "Bonne volonte",
        description = "Offrir 2 cadeaux a des PNJ.",
        goal = 2,
        kind = "gift"
    }
}

local function clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

local function getPlayerId(player)
    if not player then
        return "unknown"
    end

    if player.getUsername then
        local ok, value = pcall(function()
            return player:getUsername()
        end)
        if ok and value and #tostring(value) > 0 then
            return tostring(value)
        end
    end

    return "unknown"
end

local function ensureStorage(player)
    if not player or not player.getModData then
        return nil
    end

    local md = player:getModData()
    if type(md[NPCQuestRuntime.storageKey]) ~= "table" then
        md[NPCQuestRuntime.storageKey] = {
            quests = {},
            intelNpcSeen = {},
            lastUpdate = 0
        }
    end

    local storage = md[NPCQuestRuntime.storageKey]
    storage.quests = storage.quests or {}
    storage.intelNpcSeen = storage.intelNpcSeen or {}

    for i = 1, #questDefs do
        local def = questDefs[i]
        if type(storage.quests[def.id]) ~= "table" then
            storage.quests[def.id] = {
                progress = 0,
                completed = false,
                completedAt = nil
            }
        end
    end

    return storage
end

local function getTick()
    if os and os.time then
        return os.time()
    end
    return 0
end

function NPCQuestRuntime:buildJournal(player)
    local storage = ensureStorage(player)
    if not storage then
        return {
            playerId = getPlayerId(player),
            quests = {}
        }
    end

    local out = {
        playerId = getPlayerId(player),
        updatedAt = storage.lastUpdate or 0,
        quests = {}
    }

    for i = 1, #questDefs do
        local def = questDefs[i]
        local state = storage.quests[def.id] or { progress = 0, completed = false }
        local progress = clamp(math.floor(tonumber(state.progress) or 0), 0, def.goal)
        out.quests[#out.quests + 1] = {
            id = def.id,
            title = def.title,
            description = def.description,
            goal = def.goal,
            progress = progress,
            completed = state.completed == true,
            completedAt = state.completedAt,
            status = (state.completed == true) and "terminee" or "active"
        }
    end

    return out
end

function NPCQuestRuntime:sendJournal(player, reason)
    if not player or not sendServerCommand then
        return
    end

    local journal = self:buildJournal(player)
    journal.reason = reason or "sync"
    sendServerCommand(player, self.module, self.command, journal)
end

function NPCQuestRuntime:increment(player, questId, amount)
    local storage = ensureStorage(player)
    if not storage then
        return false
    end

    local state = storage.quests[questId]
    if type(state) ~= "table" then
        return false
    end

    if state.completed == true then
        return false
    end

    local def = nil
    for i = 1, #questDefs do
        if questDefs[i].id == questId then
            def = questDefs[i]
            break
        end
    end
    if not def then
        return false
    end

    local delta = math.max(1, math.floor(tonumber(amount) or 1))
    state.progress = clamp((tonumber(state.progress) or 0) + delta, 0, def.goal)
    if state.progress >= def.goal then
        state.completed = true
        state.completedAt = getTick()
    end

    storage.lastUpdate = getTick()
    return true
end

function NPCQuestRuntime:onIntelSuccess(player, npcId)
    local storage = ensureStorage(player)
    if not storage then
        return false
    end

    local key = tostring(npcId or "unknown")
    if storage.intelNpcSeen[key] == true then
        return false
    end

    storage.intelNpcSeen[key] = true
    return self:increment(player, "first_contact", 1)
end

function NPCQuestRuntime:onTradeSuccess(player, mode)
    if tostring(mode or "") == "gift" then
        return false
    end
    return self:increment(player, "market_runner", 1)
end

function NPCQuestRuntime:onGiftSuccess(player, qty)
    return self:increment(player, "goodwill", math.max(1, math.floor(tonumber(qty) or 1)))
end

function NPCQuestRuntime:reset(player)
    local storage = ensureStorage(player)
    if not storage then
        return false
    end

    storage.quests = {}
    storage.intelNpcSeen = {}
    storage.lastUpdate = getTick()
    ensureStorage(player)
    return true
end

_G.NPCQuestRuntime = NPCQuestRuntime

return NPCQuestRuntime
