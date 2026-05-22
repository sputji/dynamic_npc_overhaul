--[[
    PHNPC_Log.lua  v0.0.9e  (client)
    Systeme de logging centralise pour PH_DynamicNPCOverhaul.

    USAGE (depuis n'importe quel module PHNPC) :
      PHNPC.Log.debug("Actions", "startFollowing appele")
      PHNPC.Log.info ("Update",  "NPC recrutés : 3")
      PHNPC.Log.warn ("Combat",  "findNearestZombie retourne nil")
      PHNPC.Log.error("Orders",  "npc est nil dans recruitNPC")

    NIVEAUX (definir PHNPC.Log.LEVEL pour filtrer) :
      0 = DEBUG  : tout loguer (dev)
      1 = INFO   : informations normales
      2 = WARN   : avertissements (par defaut en prod)
      3 = ERROR  : erreurs uniquement

    FICHIER : ecriture dans PHNPC_Debug.log (dossier Zomboid/)
    CONSOLE : toujours affiché dans console.txt via print()
    
    Ce fichier remplace PHNPC.Log (initialise dans PHNPC_Core.lua)
    avec les capacites d'ecriture fichier + filtrage par niveau.
]]

-- Niveau de log : 0=DEBUG, 1=INFO, 2=WARN, 3=ERROR
-- Changer en 2 pour la production (WARN+ERROR seulement)
PHNPC.Log.LEVEL = 0

-- Buffer d'ecriture fichier (vide toutes les ~5 secondes)
-- IMPORTANT v0.0.9e : stockes dans PHNPC.Log (table globale) et NON pas en variables
-- locales (upvalues de closure). En Kahlua B42, Events.OnTick passe un arg Java Long
-- en registre 0 de la callback, ce qui ecrase les upvalues locales => __add crash.
PHNPC.Log._buffer    = PHNPC.Log._buffer    or {}
PHNPC.Log._flushTick = PHNPC.Log._flushTick or 0

-- ============================================================
-- Formatage d'une ligne de log
-- ============================================================
local function _formatLine(level, module, msg)
    local t = ""
    if getGameTime then
        pcall(function()
            local gt = getGameTime()
            if gt then
                t = string.format("[h%.1f]", gt:getWorldAgeHours())
            end
        end)
    end
    return string.format("[PHNPC][%s]%s[%s] %s", level, t, tostring(module), tostring(msg))
end

-- ============================================================
-- Fonction centrale d'ecriture
-- ============================================================
local LEVEL_INT = { DEBUG=0, INFO=1, WARN=2, ERROR=3 }

local function _log(level, module, msg)
    if (LEVEL_INT[level] or 0) < (type(PHNPC.Log.LEVEL) == "number" and PHNPC.Log.LEVEL or 0) then return end
    local line = _formatLine(level, module, msg)
    print(line)
    pcall(function() table.insert(PHNPC.Log._buffer, line) end)
end

-- ============================================================
-- API publique
-- ============================================================
function PHNPC.Log.debug(module, msg) _log("DBG",  module, msg) end
function PHNPC.Log.info (module, msg) _log("INF",  module, msg) end
function PHNPC.Log.warn (module, msg) _log("WRN",  module, msg) end
function PHNPC.Log.error(module, msg) _log("ERR",  module, msg) end

-- Loguer une action NPC avec son nom (raccourci pratique)
function PHNPC.Log.npc(npc, level, msg)
    local name = "?"
    pcall(function()
        local md = npc:getModData()
        name = md.PHNPC_Name or "NPC"
    end)
    _log(level or "INF", "NPC:" .. name, msg)
end

-- Loguer l'état d'un NPC (état, position, HP)
function PHNPC.Log.npcState(npc)
    if PHNPC.Log.LEVEL > 0 then return end  -- seulement en DEBUG
    pcall(function()
        local md = npc:getModData()
        local x  = string.format("%.1f", npc:getX())
        local y  = string.format("%.1f", npc:getY())
        local hp = math.floor(md.PHNPC_Health or 0)
        local maxHp = math.floor(md.PHNPC_MaxHealth or 100)
        local state = tostring(md.PHNPC_State or "?")
        local mov   = tostring(md.PHNPC_Moving or false)
        _log("DBG", "NPC:" .. tostring(md.PHNPC_Name or "?"),
            string.format("pos=(%s,%s) hp=%d/%d state=%s moving=%s", x, y, hp, maxHp, state, mov))
    end)
end

-- ============================================================
-- Flush du buffer vers fichier toutes les ~5 secondes
-- ============================================================
Events.OnTick.Add(function()
    -- v0.0.9e : guard type obligatoire — Kahlua B42 peut passer un Long Java
    -- en arg 0 de la callback et corrompre les upvalues locales.
    -- Utiliser PHNPC.Log._flushTick (champ de table) evite le probleme.
    pcall(function()
        PHNPC.Log._flushTick = (type(PHNPC.Log._flushTick) == "number" and PHNPC.Log._flushTick or 0) + 1
        if PHNPC.Log._flushTick < 300 then return end
        PHNPC.Log._flushTick = 0
        if not PHNPC.Log._buffer or #PHNPC.Log._buffer == 0 then return end

        local toWrite = PHNPC.Log._buffer
        PHNPC.Log._buffer = {}

        local writer = getFileWriter("PHNPC_Debug.log", true, false)
        if writer then
            for _, line in ipairs(toWrite) do
                writer:write(line .. "\n")
            end
            writer:close()
        end
    end)
end)

-- Flush final a la fermeture du jeu
Events.OnGameEnd.Add(function()
    pcall(function()
        if not PHNPC.Log._buffer or #PHNPC.Log._buffer == 0 then return end
        local writer = getFileWriter("PHNPC_Debug.log", true, false)
        if writer then
            writer:write("[PHNPC][INF][Log] === Session terminee ===\n")
            for _, line in ipairs(PHNPC.Log._buffer) do
                writer:write(line .. "\n")
            end
            writer:close()
        end
    end)
    _logBuffer = {}
end)

PHNPC.Log.info("Log", "=== PHNPC_Log v0.0.9d initialise (LEVEL=" .. tostring(PHNPC.Log.LEVEL) .. ") ===")
print("[PHNPC] Log v0.0.9e loaded")
