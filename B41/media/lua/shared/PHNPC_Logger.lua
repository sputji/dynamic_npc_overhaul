--[[
    Project Humain : Dynamic_NPC_Overhaul
    PHNPC_Logger.lua

    Logger structure pour debug mod <-> jeu.
    Objectif: tracer ce qui fonctionne et ce qui echoue avec:
    - timestamp lisible
    - suffixes de statut (OK/ERR/WARN/...)
    - contexte cle/valeur
    - traceId pour relier les etapes
]]

local PHNPC_Logger = {
    enabled = true,
    minLevel = "DEBUG",
    maxEntries = 4000,
    sessionStartedAt = 0,
    entries = {}
}

local LEVEL_RANK = {
    TRACE = 10,
    DEBUG = 20,
    INFO = 30,
    OK = 35,
    WARN = 40,
    ERROR = 50,
    FAIL = 55
}

local function safeString(value)
    if value == nil then
        return "nil"
    end
    local t = type(value)
    if t == "string" then
        return value
    end
    if t == "number" or t == "boolean" then
        return tostring(value)
    end
    if t == "table" then
        return "<table>"
    end
    return "<" .. t .. ">"
end

local function envTag()
    if isServer and isServer() then
        return "SV"
    end
    if isClient and isClient() then
        return "CL"
    end
    return "SH"
end

local function nowStamp()
    local base = "0000-00-00 00:00:00"
    local ms = 0

    if os and os.date then
        local okDate, dateValue = pcall(function()
            return os.date("%Y-%m-%d %H:%M:%S")
        end)
        if okDate and type(dateValue) == "string" and #dateValue > 0 then
            base = dateValue
        end
    end

    if os and os.clock then
        local okClock, clockValue = pcall(function()
            return os.clock()
        end)
        if okClock and type(clockValue) == "number" then
            ms = math.max(0, math.floor((clockValue % 1) * 1000))
        end
    end

    return string.format("%s.%03d", base, ms)
end

local function gameTickStamp()
    if getGameTime and getGameTime() and getGameTime().getWorldAgeHours then
        local ok, h = pcall(function()
            return getGameTime():getWorldAgeHours()
        end)
        if ok and h then
            return string.format("T+%.2fh", tonumber(h) or 0)
        end
    end
    return "T+na"
end

local function contextToString(ctx)
    if type(ctx) ~= "table" then
        return ""
    end

    local keys = {}
    for k, _ in pairs(ctx) do
        keys[#keys + 1] = tostring(k)
    end
    table.sort(keys)

    local parts = {}
    for i = 1, #keys do
        local k = keys[i]
        local v = ctx[k]
        parts[#parts + 1] = tostring(k) .. "=" .. safeString(v)
    end

    if #parts == 0 then
        return ""
    end
    return " | " .. table.concat(parts, " ")
end

local function levelAllowed(level)
    local wanted = LEVEL_RANK[tostring(PHNPC_Logger.minLevel or "DEBUG")] or LEVEL_RANK.DEBUG
    local got = LEVEL_RANK[tostring(level or "DEBUG")] or LEVEL_RANK.DEBUG
    return got >= wanted
end

function PHNPC_Logger:setEnabled(value)
    self.enabled = value == true
end

function PHNPC_Logger:setMinLevel(level)
    if LEVEL_RANK[level] then
        self.minLevel = level
    end
end

function PHNPC_Logger:makeTraceId(prefix)
    local p = tostring(prefix or "trace")
    local rnd = math.random(1000, 9999)
    local t = 0
    if os and os.time then
        local okTime, timeValue = pcall(function()
            return os.time()
        end)
        if okTime and type(timeValue) == "number" then
            t = timeValue
        end
    end
    return string.format("%s_%d_%d", p, t, rnd)
end

function PHNPC_Logger:log(level, moduleName, action, message, ctx)
    if self.enabled ~= true then
        return
    end
    if not levelAllowed(level) then
        return
    end

    local levelTag = tostring(level or "DEBUG")
    local mod = tostring(moduleName or "UnknownModule")
    local act = tostring(action or "event")
    local msg = tostring(message or "")

    local okStamp, stamp = pcall(nowStamp)
    if not okStamp then
        stamp = "0000-00-00 00:00:00.000"
    end

    local okTick, tickStamp = pcall(gameTickStamp)
    if not okTick then
        tickStamp = "T+na"
    end

    local okCtx, ctxText = pcall(contextToString, ctx)
    if not okCtx then
        ctxText = ""
    end

    local line = string.format(
        "[PHNPC][%s][%s][%s][%s.%s][%s] %s%s",
        stamp,
        tickStamp,
        envTag(),
        mod,
        act,
        levelTag,
        msg,
        ctxText
    )

    print(line)

    self.entries[#self.entries + 1] = {
        ts = os.time(),
        level = levelTag,
        moduleName = mod,
        action = act,
        message = msg,
        context = ctx,
        line = line
    }

    if #self.entries > self.maxEntries then
        table.remove(self.entries, 1)
    end

    _G.PHNPC_DebugJournal = self.entries
    _G.PHNPC_LastLogLine = line
end

function PHNPC_Logger:trace(moduleName, action, message, ctx)
    self:log("TRACE", moduleName, action, message, ctx)
end

function PHNPC_Logger:debug(moduleName, action, message, ctx)
    self:log("DEBUG", moduleName, action, message, ctx)
end

function PHNPC_Logger:info(moduleName, action, message, ctx)
    self:log("INFO", moduleName, action, message, ctx)
end

function PHNPC_Logger:ok(moduleName, action, message, ctx)
    self:log("OK", moduleName, action, message, ctx)
end

function PHNPC_Logger:warn(moduleName, action, message, ctx)
    self:log("WARN", moduleName, action, message, ctx)
end

function PHNPC_Logger:error(moduleName, action, message, ctx)
    self:log("ERROR", moduleName, action, message, ctx)
end

function PHNPC_Logger:fail(moduleName, action, message, ctx)
    self:log("FAIL", moduleName, action, message, ctx)
end

function PHNPC_Logger:getRecent(limit)
    local wanted = math.max(1, tonumber(limit) or 50)
    local out = {}
    local startIdx = math.max(1, #self.entries - wanted + 1)
    for i = startIdx, #self.entries do
        out[#out + 1] = self.entries[i]
    end
    return out
end

if not _G.PHNPC_Logger then
    _G.PHNPC_Logger = PHNPC_Logger
end

do
    local t = 0
    if os and os.time then
        local okTime, timeValue = pcall(function()
            return os.time()
        end)
        if okTime and type(timeValue) == "number" then
            t = timeValue
        end
    end
    PHNPC_Logger.sessionStartedAt = t
end

return PHNPC_Logger
