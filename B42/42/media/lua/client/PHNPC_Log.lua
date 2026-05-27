--[[
    PHNPC_Log.lua  v0.0.9f  (client)
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
-- v0.0.9f FIX KAHLUA UPVALUE : meme bug que _flushTick/_buffer en v0.0.9e.
-- En Kahlua B42, les 'local function' dans un module deviennent nil
-- dans les closures des fonctions globales (PHNPC.Log.*) si le module
-- est recharge ou dans certains contextes d'execution.
-- SOLUTION : tout dans PHNPC.Log.* (champs de table globale), jamais de local.
-- ============================================================
PHNPC.Log.LEVEL_INT = { DBG=0, INF=1, WRN=2, ERR=3 }

function PHNPC.Log._fmt(level, module, msg)
    local t = ""
    if getGameTime then
        pcall(function()
            local gt = getGameTime()
            if gt then t = string.format("[h%.1f]", gt:getWorldAgeHours()) end
        end)
    end
    return string.format("[PHNPC][%s]%s[%s] %s",
        tostring(level), t, tostring(module), tostring(msg))
end

function PHNPC.Log._log(level, module, msg)
    local lvlInt = (PHNPC.Log.LEVEL_INT and PHNPC.Log.LEVEL_INT[level]) or 0
    local minLvl = (type(PHNPC.Log.LEVEL) == "number") and PHNPC.Log.LEVEL or 0
    if lvlInt < minLvl then return end
    local line = ""
    pcall(function() line = PHNPC.Log._fmt(level, module, msg) end)
    if line == "" then
        line = "[PHNPC]["..tostring(level).."]["
             ..tostring(module).."]	"..tostring(msg)
    end
    pcall(function() print(line) end)
    pcall(function() table.insert(PHNPC.Log._buffer, line) end)
end

-- ============================================================
-- API publique — wrappees dans pcall pour resister a tout contexte Kahlua
-- ============================================================
function PHNPC.Log.debug(module, msg) pcall(function() PHNPC.Log._log("DBG", module, msg) end) end
function PHNPC.Log.info (module, msg) pcall(function() PHNPC.Log._log("INF", module, msg) end) end
function PHNPC.Log.warn (module, msg) pcall(function() PHNPC.Log._log("WRN", module, msg) end) end
function PHNPC.Log.error(module, msg) pcall(function() PHNPC.Log._log("ERR", module, msg) end) end

function PHNPC.Log.npc(npc, level, msg)
    local name = "?"
    pcall(function() name = npc:getModData().PHNPC_Name or "NPC" end)
    pcall(function() PHNPC.Log._log(level or "INF", "NPC:"..name, msg) end)
end

function PHNPC.Log.npcState(npc)
    if PHNPC.Log.LEVEL > 0 then return end
    pcall(function()
        local md = npc:getModData()
        local x  = string.format("%.1f", npc:getX())
        local y  = string.format("%.1f", npc:getY())
        local hp = math.floor(md.PHNPC_Health or 0)
        local maxHp = math.floor(md.PHNPC_MaxHealth or 100)
        local state = tostring(md.PHNPC_State or "?")
        local mov   = tostring(md.PHNPC_Moving or false)
        PHNPC.Log._log("DBG", "NPC:"..tostring(md.PHNPC_Name or "?"),
            string.format("pos=(%s,%s) hp=%d/%d state=%s moving=%s",
                x, y, hp, maxHp, state, mov))
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
-- v0.0.9h FIX BUG 1 : Events.OnGameEnd n'existe PAS en B42.18 (etait B41 only).
-- Sans guard => attempted index: Add of non-table: null => ERROR au lancement.
local _onEndEvent = Events.OnGameStop or Events.OnPreSave or Events.OnGameEnd
if _onEndEvent and _onEndEvent.Add then
    _onEndEvent.Add(function()
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
    end)
end

PHNPC.Log.info("Log", "=== PHNPC_Log v0.0.9h initialise (LEVEL=" .. tostring(PHNPC.Log.LEVEL) .. ") ===")
print("[PHNPC] Log v0.0.9l loaded")
