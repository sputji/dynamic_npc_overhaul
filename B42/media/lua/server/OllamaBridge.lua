--[[
    Project Humain : Dynamic NPC Overhaul — B42
    server/OllamaBridge.lua

    Pont HTTP asynchrone vers l'API Ollama locale.
    Utilise HTTPRequest (API PZ B42) pour les appels non-bloquants.
    Si Ollama n'est pas disponible, le callback reçoit (nil, "timeout").
]]

if not isServer() then return end

local Log    = PHNPC.getModule("NPC_Logger")
local Config = PHNPC.getModule("NPC_Config")

local OllamaBridge = {
    _cache     = {},   -- { [hash] = reply }
    _cacheKeys = {},   -- ordre d'insertion pour LRU
}

-- ============================================================
-- Hash simple (clé de cache)
-- ============================================================

local function hash(npcId, msg)
    return npcId .. "|" .. (msg or "")
end

-- ============================================================
-- Cache LRU
-- ============================================================

local function cacheGet(key)
    return OllamaBridge._cache[key]
end

local function cachePut(key, value)
    local cfg      = Config.get()
    local maxSize  = cfg.OllamaCacheSize or 50
    if OllamaBridge._cache[key] then return end

    OllamaBridge._cache[key]               = value
    OllamaBridge._cacheKeys[#OllamaBridge._cacheKeys + 1] = key

    if #OllamaBridge._cacheKeys > maxSize then
        local oldest = table.remove(OllamaBridge._cacheKeys, 1)
        OllamaBridge._cache[oldest] = nil
    end
end

-- ============================================================
-- Construction du prompt
-- ============================================================

local function buildPrompt(npcData, playerMsg)
    local profs = PHNPC.getModule("NPC_Professions")
    local prof  = profs and profs.get(npcData.professionId)
    local profLabel = prof and prof.label or "Survivant"

    return string.format(
        "Tu joues un survivant PNJ dans un monde zombie nommé %s, %s. " ..
        "Santé : %d/100. Moral : %d/100. " ..
        "Réponds en moins de 2 phrases, en restant dans le personnage. " ..
        "Message joueur : %s",
        npcData.fullName or "Inconnu",
        profLabel,
        npcData.health or 100,
        npcData.morale or 50,
        playerMsg or "..."
    )
end

-- ============================================================
-- Requête HTTP (B42 HTTPRequest)
-- ============================================================

--- Envoie une question à Ollama et retourne la réponse via callback.
-- @param npcData    NPCDataModel
-- @param playerMsg  string
-- @param callback   function(reply: string|nil, err: string|nil)
function OllamaBridge.ask(npcData, playerMsg, callback)
    local cfg  = Config.get()
    if not cfg.EnableOllama then
        callback(nil, "disabled")
        return
    end

    local cacheKey = hash(npcData.id, playerMsg)
    local cached   = cacheGet(cacheKey)
    if cached then
        callback(cached, nil)
        return
    end

    local url     = (cfg.OllamaApiUrl or "http://localhost:11434") .. "/api/generate"
    local prompt  = buildPrompt(npcData, playerMsg)
    local payload = '{"model":"' .. (cfg.OllamaModel or "neural-chat") ..
                    '","prompt":' .. string.format("%q", prompt) ..
                    ',"stream":false}'

    local timeout = cfg.OllamaTimeoutMs or 8000

    -- B42 HTTPRequest API
    local ok, err = pcall(function()
        local req = HTTPRequest.new(url, "POST", payload, "application/json")
        req:setTimeout(timeout)
        req:setCallback(function(response)
            if not response or response:getCode() ~= 200 then
                callback(nil, "http_error")
                return
            end
            local body = response:getBody()
            -- Parser la réponse JSON minimalement
            local reply = body:match('"response"%s*:%s*"(.-[^\\])"') or
                          body:match('"response"%s*:%s*"()"')
            if not reply or #reply == 0 then
                callback(nil, "parse_error")
                return
            end
            -- Désescaper les \n et \"
            reply = reply:gsub("\\n", " "):gsub('\\"', '"')
            cachePut(cacheKey, reply)
            callback(reply, nil)
        end)
        req:send()
    end)

    if not ok then
        Log.error("OllamaBridge", "Erreur HTTP", { err = tostring(err) })
        callback(nil, tostring(err))
    end
end

PHNPC.registerModule("OllamaBridge", OllamaBridge)
return OllamaBridge
