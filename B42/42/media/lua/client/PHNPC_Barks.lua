--[[
    PHNPC_Barks.lua  v0.0.16  (client)
    Dialogues contextuels (barks) des NPCs.

    v0.0.16 :
      - Ajout des barks de reaction a la meteo (weather) :
        pluie, orage, neige, canicule, brouillard.
      - PHNPC.getWeatherState() : detecte la meteo courante via
        l'API native PZ (GameTime / WeatherPeriod).
      - PHNPC.sayWeatherBark(npc) : dit un bark contextuel selon
        la meteo actuelle (appele periodiquement depuis Update.lua).

    FIX v1.0 BUG getText() TIMING :
      Dans PZ B42, les fichiers client/ sont charges AVANT que le systeme de
      traduction soit completement initialise. Si on appelle getText() au niveau
      global (au chargement du fichier), la fonction retourne la cle brute
      ("UI_PHNPC_BarkIdle4") au lieu du texte traduit.
      SOLUTION : stocker uniquement les CLES de traduction (strings statiques),
      et appeler getText() uniquement a l'utilisation (PHNPC.getRandomBark).

    Pattern : PZ getText() lazy evaluation
    Necessite : PHNPC_Core.lua (shared) charge avant ce fichier.
]]

-- ============================================================
-- CLES DE TRADUCTION PAR ETAT
-- Uniquement des cles statiques — getText() est appele plus tard
-- ============================================================
local BARK_KEYS = {
    following = {
        "UI_PHNPC_BarkFollowing1",
        "UI_PHNPC_BarkFollowing2",
        "UI_PHNPC_BarkFollowing3",
        "UI_PHNPC_BarkFollowing4",
        "UI_PHNPC_BarkFollowing5",
        "UI_PHNPC_BarkFollowing6",
        "UI_PHNPC_BarkFollowing7",
    },
    staying = {
        "UI_PHNPC_BarkStaying1",
        "UI_PHNPC_BarkStaying2",
        "UI_PHNPC_BarkStaying3",
        "UI_PHNPC_BarkStaying4",
        "UI_PHNPC_BarkStaying5",
    },
    defending = {
        "UI_PHNPC_BarkDefending1",
        "UI_PHNPC_BarkDefending2",
        "UI_PHNPC_BarkDefending3",
        "UI_PHNPC_BarkDefending4",
        "UI_PHNPC_BarkDefending5",
    },
    fleeing = {
        "UI_PHNPC_BarkFleeing1",
        "UI_PHNPC_BarkFleeing2",
        "UI_PHNPC_BarkFleeing3",
        "UI_PHNPC_BarkFleeing4",
    },
    idle = {
        "UI_PHNPC_BarkIdle1",
        "UI_PHNPC_BarkIdle2",
        "UI_PHNPC_BarkIdle3",
        "UI_PHNPC_BarkIdle4",
    },
    -- v0.0.16 : barks meteo
    weather_rain = {
        "UI_PHNPC_BarkRain1",
        "UI_PHNPC_BarkRain2",
        "UI_PHNPC_BarkRain3",
    },
    weather_storm = {
        "UI_PHNPC_BarkStorm1",
        "UI_PHNPC_BarkStorm2",
        "UI_PHNPC_BarkStorm3",
    },
    weather_snow = {
        "UI_PHNPC_BarkSnow1",
        "UI_PHNPC_BarkSnow2",
        "UI_PHNPC_BarkSnow3",
    },
    weather_hot = {
        "UI_PHNPC_BarkHot1",
        "UI_PHNPC_BarkHot2",
    },
    weather_fog = {
        "UI_PHNPC_BarkFog1",
        "UI_PHNPC_BarkFog2",
    },
    levelup = {
        "UI_PHNPC_BarkLevelUp1",
        "UI_PHNPC_BarkLevelUp2",
    },
}

-- ============================================================
-- PHNPC.getRandomBark(state) : retourne un texte traduit
-- getText() est appele ici, au moment de l'utilisation, pas au chargement
-- => plus de probleme de timing
-- ============================================================
function PHNPC.getRandomBark(state)
    local pool = BARK_KEYS[state] or BARK_KEYS["idle"]
    local key  = pool[ZombRand(#pool) + 1]
    local text = nil
    pcall(function() text = getText(key) end)
    -- Fallback si getText renvoie la cle brute (pas encore initialise)
    if not text or text == key then
        return nil
    end
    return text
end

-- ============================================================
-- PHNPC.sayBark(npc, state, r, g, b)
-- Raccourci : le NPC dit un bark de l'etat donne avec la couleur specifiee
-- ============================================================
function PHNPC.sayBark(npc, state, r, g, b)
    local bark = PHNPC.getRandomBark(state or "idle")
    if not bark then return end  -- ne pas afficher la cle brute
    pcall(function() npc:addLineChatElement(bark, r or 0.9, g or 0.9, b or 0.2) end)
end

-- ============================================================
-- Seuils de detection meteo (v0.0.16) — extraits pour faciliter le reglage
-- ============================================================
local WEATHER_STORM_THRESHOLD  = 0.7   -- intensite pluie au-dessus = orage
local WEATHER_RAIN_THRESHOLD   = 0.1   -- intensite pluie au-dessus = pluie
local WEATHER_SNOW_RAIN_MIN    = 0.05  -- precipitation minimale pour neige
local WEATHER_HOT_TEMP         = 35    -- temperature (Celsius) au-dessus = canicule
local WEATHER_SNOW_TEMP        = 0     -- temperature (Celsius) en-dessous = neige possible
local WEATHER_FOG_THRESHOLD    = 0.3   -- intensite brouillard au-dessus = brouillard

-- ============================================================
-- PHNPC.getWeatherState() [NOUVEAU v0.0.16]
-- Detecte la meteo courante via l'API native PZ.
-- Retourne : "rain", "storm", "snow", "hot", "fog", "clear"
-- ============================================================
function PHNPC.getWeatherState()
    local state = "clear"
    pcall(function()
        local gt = GameTime.getInstance()
        if not gt then return end

        -- Verifier la pluie / orage
        local rainIntensity = 0
        pcall(function() rainIntensity = gt:getRainIntensity() end)
        if rainIntensity > WEATHER_STORM_THRESHOLD then
            state = "storm"
            return
        elseif rainIntensity > WEATHER_RAIN_THRESHOLD then
            state = "rain"
            return
        end

        -- Verifier la neige (temperature basse + precipitations)
        local temp = 20
        pcall(function() temp = gt:getTemperature() end)
        if temp < WEATHER_SNOW_TEMP and rainIntensity > WEATHER_SNOW_RAIN_MIN then
            state = "snow"
            return
        end

        -- Canicule
        if temp > WEATHER_HOT_TEMP then
            state = "hot"
            return
        end

        -- Brouillard
        local fog = 0
        pcall(function() fog = gt:getFogIntensity() end)
        if fog and fog > WEATHER_FOG_THRESHOLD then
            state = "fog"
            return
        end
    end)
    return state
end

-- ============================================================
-- PHNPC.sayWeatherBark(npc) [NOUVEAU v0.0.16]
-- Le NPC reagit a la meteo courante par un commentaire contextuel.
-- A appeler periodiquement depuis PHNPC_Update.lua (pas a chaque tick !).
-- ============================================================
function PHNPC.sayWeatherBark(npc)
    if not npc then return end
    local md = npc:getModData()
    if not md.PHNPC_Recruited then return end

    local weather = PHNPC.getWeatherState()
    if weather == "clear" then return end  -- Pas de bark par beau temps

    local barkState = "weather_" .. weather
    PHNPC.sayBark(npc, barkState, 0.6, 0.8, 1.0)
end

print("[PHNPC] Barks v0.0.16 loaded")
