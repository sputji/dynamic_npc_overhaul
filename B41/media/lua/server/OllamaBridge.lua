--[[
    Project Humain : Dynamic_NPC_Overhaul
    OllamaBridge.lua

    Bridge pour integration Ollama locale (http://localhost:11434/api/generate).
    Requetes asynchrones sans bloquer le jeu.
    Cache des reponses pour eviter surcharge.
]]


local OllamaBridge = {
    enabled = true,
    baseUrl = "http://localhost:11434",
    model = "neural-chat",
    timeout = 8000,
    maxCacheSize = 50,
    responseCache = {},
    pendingRequests = {},
    pendingTickHandlers = {},
    requestCounter = 0,
    lastHealthCheck = 0,
    healthCheckInterval = 300
}

local okDialogueLocalization, NPCDialogueLocalization = pcall(require, "NPCDialogueLocalization")
if not okDialogueLocalization then
    NPCDialogueLocalization = _G.NPCDialogueLocalization
end

local function hashPrompt(systemPrompt, userMessage)
    local combined = (systemPrompt or "") .. "|" .. (userMessage or "")
    local hash = 0
    for i = 1, #combined do
        hash = (hash * 31 + string.byte(combined, i)) % 2147483647
    end
    return tostring(hash)
end

local function logOllama(level, message)
    if level == "error" then
        print("[OllamaBridge ERROR] " .. tostring(message))
    elseif level == "debug" then
        print("[OllamaBridge DEBUG] " .. tostring(message))
    elseif level == "info" then
        print("[OllamaBridge INFO] " .. tostring(message))
    end
end

local function normalizeLanguageCode(languageCode)
    local code = string.upper(tostring(languageCode or ""))
    code = code:gsub("[^A-Z]", "")
    if #code >= 2 then
        return code:sub(1, 2)
    end
    return "EN"
end

local function resolveLanguageCodeFromPZ()
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

local function resolveDialogueLanguageCode(npcData)
    if npcData and npcData._dialogueLanguage then
        return normalizeLanguageCode(npcData._dialogueLanguage)
    end
    return resolveLanguageCodeFromPZ()
end

local function localizeFallbackText(key, languageCode, fallbackFr, fallbackEn)
    if NPCDialogueLocalization and NPCDialogueLocalization.getText then
        return NPCDialogueLocalization:getText(key, languageCode, fallbackFr, fallbackEn)
    end

    if getText then
        local ok, translated = pcall(function()
            return getText(key)
        end)
        if ok and translated and translated ~= key and #tostring(translated) > 0 then
            return tostring(translated)
        end
    end

    if normalizeLanguageCode(languageCode) == "FR" then
        return fallbackFr or key
    end
    return fallbackEn or fallbackFr or key
end

local function isOllamaHealthy()
    if not OllamaBridge.enabled then
        return false
    end

    local now = os.time()
    if now - OllamaBridge.lastHealthCheck < OllamaBridge.healthCheckInterval then
        return OllamaBridge.lastHealthStatus == true
    end

    OllamaBridge.lastHealthCheck = now

    local hasHttpRequest = type(HttpRequest) == "userdata" or type(HttpRequest) == "table"
    if hasHttpRequest then
        OllamaBridge.lastHealthStatus = true
        return true
    end

    local hasCurl = false
    if os.execute then
        -- Linux/macOS
        hasCurl = (os.execute("command -v curl > /dev/null 2>&1") == 0)
        if not hasCurl then
            -- Windows
            hasCurl = (os.execute("where curl >nul 2>nul") == 0)
        end
    end

    if hasCurl then
        OllamaBridge.lastHealthStatus = true
        return true
    end

    OllamaBridge.lastHealthStatus = false
    return false
end

local function buildSystemPrompt(npcData, npcId)
    local languageCode = resolveDialogueLanguageCode(npcData)

    if not npcData then
        return "You are a survivor in a post-apocalyptic world. Be brief and realistic. "
            .. "ABSOLUTE RULE: Reply only in this language code: " .. languageCode .. "."
    end

    local name = npcData.name or ("NPC-" .. tostring(npcId):sub(1, 6))
    local stats = npcData.stats or {}
    local health = npcData.health or {}
    local traits = npcData.traits and npcData.traits.personality or {}

    local personality = "balanced"
    if (traits.loneWolf or 0) > (traits.socialDrive or 0) then
        personality = "suspicious and reserved"
    elseif (traits.brutality or 0) > 60 then
        personality = "aggressive and dangerous"
    elseif (traits.socialDrive or 0) > 70 then
        personality = "friendly and talkative"
    end

    local mentalState = "calm"
    if (stats.hunger or 0) < 35 then
        mentalState = "desperate and hungry"
    elseif (stats.courage or 0) < 40 then
        mentalState = "fearful and nervous"
    elseif (stats.courage or 0) > 80 then
        mentalState = "confident and bold"
    end

    local healthNote = ""
    if health.isBitten == true then
        healthNote = " You're secretly bitten and trying to hide it."
    elseif (health.current or 100) < 50 then
        healthNote = " You're wounded and in pain."
    end

    local additionalContext = npcData._dialogueContext or ""

    return string.format(
        "You are %s, a survivor in a post-apocalyptic world. Your personality is %s. You feel %s.%s "
        .. "Respond briefly (1-2 sentences) in a realistic, human way. Keep it conversational. "
        .. "ABSOLUTE RULE: You must reply only in this language code: %s.",
        name, personality, mentalState, healthNote, additionalContext, languageCode
    )
end

local function executeHttpRequestSync(url, payload, timeout_ms)
    local escapedPayload = tostring(payload or "")
        :gsub("\\", "\\\\")
        :gsub('"', '\\"')
        :gsub("\r", "")
        :gsub("\n", "\\n")

    local curlCmd = string.format(
        'curl -s -X POST "%s" -H "Content-Type: application/json" --max-time %d -d "%s"',
        url,
        math.ceil(timeout_ms / 1000),
        escapedPayload
    )

    local result = ""
    local ok = pcall(function()
        local handle = io.popen(curlCmd)
        if handle then
            result = handle:read("*a")
            handle:close()
        end
    end)

    if ok and result and #result > 0 then
        return result
    end

    return nil
end

local function parseOllamaResponse(responseBody)
    if not responseBody or #responseBody == 0 then
        return nil
    end

    local lines = {}
    for line in responseBody:gmatch("[^\n]+") do
        lines[#lines + 1] = line
    end

    local fullText = ""

    local function unescapeJsonString(value)
        if not value then
            return nil
        end
        local text = tostring(value)
        text = text:gsub('\\n', '\n')
        text = text:gsub('\\r', '\r')
        text = text:gsub('\\t', '\t')
        text = text:gsub('\\"', '"')
        text = text:gsub('\\\\', '\\')
        return text
    end

    for i = 1, #lines do
        local line = lines[i]

        local chunk = line:match('"response"%s*:%s*"(.-)"')
        if chunk then
            fullText = fullText .. unescapeJsonString(chunk)
        end

        if line:find('"done"%s*:%s*true') then
            break
        end
    end

    fullText = fullText:gsub("^%s+", ""):gsub("%s+$", "")
    if #fullText < 5 then
        return nil
    end

    return fullText
end

function OllamaBridge:generateDialogue(npcData, npcId, userMessage, callback)
    if not self.enabled or not isOllamaHealthy() then
        logOllama("debug", "Ollama not available, using fallback")
        if callback then
            callback(self:generateFallbackResponse(npcData, userMessage, resolveDialogueLanguageCode(npcData)))
        end
        return
    end

    local systemPrompt = buildSystemPrompt(npcData, npcId)
    local cacheKey = hashPrompt(systemPrompt, userMessage)

    if self.responseCache[cacheKey] then
        logOllama("debug", "Cache hit for prompt hash: " .. cacheKey)
        if callback then
            callback(self.responseCache[cacheKey])
        end
        return
    end

    self.requestCounter = self.requestCounter + 1
    local requestId = tostring(self.requestCounter)

    local payload = {
        model = self.model,
        prompt = systemPrompt .. "\n\nPlayer: " .. userMessage,
        stream = true,
        temperature = 0.7,
        top_p = 0.9,
        top_k = 40,
        num_predict = 60
    }

    local jsonPayload = self:tableToJson(payload)

    self.pendingRequests[requestId] = {
        npcId = npcId,
        npcData = npcData,
        userMessage = userMessage,
        languageCode = resolveDialogueLanguageCode(npcData),
        cacheKey = cacheKey,
        callback = callback,
        startTime = os.time()
    }

    logOllama("debug", "Queuing Ollama request " .. requestId .. " for NPC " .. tostring(npcId))

    if Events and Events.OnTick then
        local tickHandler = function()
            OllamaBridge:processRequest(requestId, jsonPayload)
        end
        self.pendingTickHandlers[requestId] = tickHandler
        Events.OnTick.Add(tickHandler)
    end
end

function OllamaBridge:cleanupRequest(requestId)
    local handler = self.pendingTickHandlers[requestId]
    if handler and Events and Events.OnTick then
        pcall(function()
            Events.OnTick.Remove(handler)
        end)
    end

    self.pendingTickHandlers[requestId] = nil
    self.pendingRequests[requestId] = nil
end

function OllamaBridge:processRequest(requestId, jsonPayload)
    local req = self.pendingRequests[requestId]
    if not req then
        self:cleanupRequest(requestId)
        return
    end

    if os.time() - req.startTime > math.ceil(self.timeout / 1000) then
        logOllama("error", "Request " .. requestId .. " timed out")
        if req.callback then
            req.callback(self:generateFallbackResponse(req.npcData, req.userMessage, req.languageCode))
        end
        self:cleanupRequest(requestId)
        return
    end

    local url = self.baseUrl .. "/api/generate"
    local response = executeHttpRequestSync(url, jsonPayload, self.timeout)

    local finalText = nil

    if response then
        local text = parseOllamaResponse(response)
        if text then
            finalText = text
            self.responseCache[req.cacheKey] = text

            local cacheCount = 0
            for _ in pairs(self.responseCache) do
                cacheCount = cacheCount + 1
            end

            if cacheCount > self.maxCacheSize then
                local firstKey = next(self.responseCache)
                if firstKey ~= nil then
                    self.responseCache[firstKey] = nil
                end
            end

            logOllama("info", "Received response for request " .. requestId)
        end
    end

    if not finalText then
        logOllama("error", "No valid Ollama response for request " .. requestId .. ", fallback used")
        finalText = self:generateFallbackResponse(req.npcData, req.userMessage, req.languageCode)
    end

    if req.callback then
        req.callback(finalText)
    end

    self:cleanupRequest(requestId)
end

function OllamaBridge:generateFallbackResponse(npcData, userMessage, languageCode)
    local langCode = normalizeLanguageCode(languageCode)
    local fallbacks = {
        localizeFallbackText("IGUI_PHNPC_FALLBACK_GENERIC_1", langCode),
        localizeFallbackText("IGUI_PHNPC_FALLBACK_GENERIC_2", langCode),
        localizeFallbackText("IGUI_PHNPC_FALLBACK_GENERIC_3", langCode),
        localizeFallbackText("IGUI_PHNPC_FALLBACK_GENERIC_4", langCode),
        localizeFallbackText("IGUI_PHNPC_FALLBACK_GENERIC_5", langCode),
        localizeFallbackText("IGUI_PHNPC_FALLBACK_GENERIC_6", langCode),
        localizeFallbackText("IGUI_PHNPC_FALLBACK_GENERIC_7", langCode),
        localizeFallbackText("IGUI_PHNPC_FALLBACK_GENERIC_8", langCode)
    }

    if npcData and npcData.traits and npcData.traits.personality then
        local brutality = npcData.traits.personality.brutality or 0
        if brutality > 70 then
            return localizeFallbackText(
                "IGUI_PHNPC_FALLBACK_BRUTAL",
                langCode
            )
        end
    end

    local idx = (os.time() + (userMessage and string.len(userMessage) or 0)) % #fallbacks + 1
    return fallbacks[idx]
end

function OllamaBridge:tableToJson(tbl)
    local function serialize(obj)
        if type(obj) == "string" then
            return '"' .. obj:gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r') .. '"'
        elseif type(obj) == "number" then
            return tostring(obj)
        elseif type(obj) == "boolean" then
            return obj and "true" or "false"
        elseif type(obj) == "table" then
            local pairs_list = {}
            for k, v in pairs(obj) do
                table.insert(pairs_list, '"' .. tostring(k) .. '":' .. serialize(v))
            end
            return "{" .. table.concat(pairs_list, ",") .. "}"
        end
        return "null"
    end

    return serialize(tbl)
end

logOllama("info", "OllamaBridge initialized. Model: " .. OllamaBridge.model .. ", URL: " .. OllamaBridge.baseUrl)

_G.OllamaBridge = OllamaBridge
return OllamaBridge
