--[[
    Project Humain : Dynamic NPC Overhaul — B42
    shared/00_Core.lua

    Point d'entrée du namespace global PHNPC.
    Chargé en premier (préfixe "00_") par le moteur Lua de PZ.
    Toutes les valeurs de version sont ici — ne jamais les dupliquer.
]]

-- ============================================================
-- Namespace global
-- ============================================================
PHNPC = PHNPC or {}

PHNPC.VERSION       = "2.3.0"
PHNPC.BUILD         = "B42"
PHNPC.MOD_ID        = "PH_DynamicNPCOverhaul"

-- ============================================================
-- Registre des modules (auto-rempli par chaque module au chargement)
-- ============================================================
PHNPC._modules = {}

--- Enregistre un module dans le registre global.
-- @param name  string  Identifiant unique (ex: "NPC_Brain")
-- @param tbl   table   La table module à enregistrer
function PHNPC.registerModule(name, tbl)
    if PHNPC._modules[name] then
        print("[PHNPC][WARN] Module déjà enregistré : " .. tostring(name))
        return
    end
    PHNPC._modules[name] = tbl
end

--- Récupère un module enregistré (ou nil).
function PHNPC.getModule(name)
    return PHNPC._modules[name]
end

-- ============================================================
-- Utilitaires bas niveau (sans dépendance externe)
-- ============================================================

--- Clamp numérique.
function PHNPC.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

--- Entier aléatoire [lo, hi] — utilise ZombRand si disponible.
function PHNPC.randInt(lo, hi)
    if type(ZombRand) == "function" then
        return lo + ZombRand(hi - lo + 1)
    end
    return math.random(lo, hi)
end

--- Copie profonde d'une table.
function PHNPC.deepCopy(src)
    if type(src) ~= "table" then return src end
    local copy = {}
    for k, v in pairs(src) do copy[k] = PHNPC.deepCopy(v) end
    return copy
end

--- Retourne l'environnement courant ("SV" / "CL" / "SH").
function PHNPC.env()
    if type(isServer) == "function" and isServer() then return "SV" end
    if type(isClient) == "function" and isClient() then return "CL" end
    return "SH"
end

-- ============================================================
-- Vérification de version minimale du jeu
-- ============================================================
local function checkGameVersion()
    local ok, ver = pcall(function()
        return getCore and getCore():getGameVersion() or nil
    end)
    if ok and type(ver) == "string" then
        local major = tonumber(ver:match("^(%d+)")) or 0
        if major < 42 then
            print("[PHNPC][ERROR] Version du jeu incompatible : " .. ver .. " (minimum requis : 42)")
        end
    end
end

Events.OnGameBoot.Add(checkGameVersion)

print("[PHNPC] Core chargé — v" .. PHNPC.VERSION .. " (" .. PHNPC.BUILD .. ")")
