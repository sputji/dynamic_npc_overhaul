--[[
    Project Humain : Dynamic NPC Overhaul — B42
    shared/NPC_Logger.lua

    Système de log unifié (client + serveur + shared).
    Niveaux : TRACE < DEBUG < INFO < OK < WARN < ERROR < FAIL
    Les entrées sont accumulées en mémoire (ring buffer) et
    imprimées dans la console PZ.
]]

local NPC_Logger = {
    enabled   = true,
    minLevel  = "DEBUG",   -- niveau minimum affiché
    maxEntries = 2000,     -- ring buffer
    _entries  = {},
}

-- --------------------------------------------------------
-- Rang des niveaux
-- --------------------------------------------------------
local RANK = {
    TRACE = 10, DEBUG = 20, INFO = 30,
    OK    = 35, WARN  = 40, ERROR = 50, FAIL = 55,
}

-- --------------------------------------------------------
-- Helpers internes
-- --------------------------------------------------------
local function safeStr(v)
    local t = type(v)
    if t == "string"  then return v end
    if t == "number" or t == "boolean" then return tostring(v) end
    if t == "table"  then return "<table>" end
    return "<" .. t .. ">"
end

local function envTag()
    if type(isServer) == "function" and isServer() then return "SV" end
    if type(isClient) == "function" and isClient() then return "CL" end
    return "SH"
end

local function stamp()
    local base = "00:00:00"
    if os and os.date then
        local ok, d = pcall(os.date, "%H:%M:%S")
        if ok and type(d) == "string" then base = d end
    end
    return base
end

-- --------------------------------------------------------
-- API publique
-- --------------------------------------------------------

--- Émet un message de log.
-- @param level   string  Niveau (TRACE/DEBUG/INFO/OK/WARN/ERROR/FAIL)
-- @param module  string  Nom du module émetteur
-- @param msg     string  Message principal
-- @param ctx     table?  Contexte clé/valeur optionnel
function NPC_Logger.log(level, module, msg, ctx)
    if not NPC_Logger.enabled then return end
    local rank = RANK[level] or RANK.DEBUG
    local minRank = RANK[NPC_Logger.minLevel] or RANK.DEBUG
    if rank < minRank then return end

    local env = envTag()
    local line = string.format("[PHNPC][%s][%s][%s] %s",
        stamp(), env, level, safeStr(msg))

    if type(ctx) == "table" then
        local parts = {}
        for k, v in pairs(ctx) do
            parts[#parts + 1] = safeStr(k) .. "=" .. safeStr(v)
        end
        if #parts > 0 then
            line = line .. " {" .. table.concat(parts, ", ") .. "}"
        end
    end

    print(line)

    -- Ring buffer
    local entries = NPC_Logger._entries
    entries[#entries + 1] = { ts = stamp(), env = env, level = level, module = module, msg = msg, ctx = ctx }
    if #entries > NPC_Logger.maxEntries then
        table.remove(entries, 1)
    end
end

-- Raccourcis par niveau
function NPC_Logger.trace(mod, msg, ctx)  NPC_Logger.log("TRACE", mod, msg, ctx) end
function NPC_Logger.debug(mod, msg, ctx)  NPC_Logger.log("DEBUG", mod, msg, ctx) end
function NPC_Logger.info(mod,  msg, ctx)  NPC_Logger.log("INFO",  mod, msg, ctx) end
function NPC_Logger.ok(mod,    msg, ctx)  NPC_Logger.log("OK",    mod, msg, ctx) end
function NPC_Logger.warn(mod,  msg, ctx)  NPC_Logger.log("WARN",  mod, msg, ctx) end
function NPC_Logger.error(mod, msg, ctx)  NPC_Logger.log("ERROR", mod, msg, ctx) end
function NPC_Logger.fail(mod,  msg, ctx)  NPC_Logger.log("FAIL",  mod, msg, ctx) end

--- Retourne les N dernières entrées (pour debug UI).
function NPC_Logger.tail(n)
    n = n or 20
    local entries = NPC_Logger._entries
    local result  = {}
    local start   = math.max(1, #entries - n + 1)
    for i = start, #entries do
        result[#result + 1] = entries[i]
    end
    return result
end

--- Vide le buffer.
function NPC_Logger.clear()
    NPC_Logger._entries = {}
end

PHNPC.registerModule("NPC_Logger", NPC_Logger)
return NPC_Logger
