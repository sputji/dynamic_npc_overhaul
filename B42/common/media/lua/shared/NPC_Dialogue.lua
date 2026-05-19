--[[
    Project Humain : Dynamic NPC Overhaul — B42
    shared/NPC_Dialogue.lua

    Système de dialogues contextuels + localisation.
    Priorité : traduction via Translate/ → fallback intégré FR/EN.
    Supporte les tokens : {name}, {profession}, {faction}.
]]

local NPC_Dialogue = {
    _locale = "FR",   -- langue par défaut
}

-- ============================================================
-- Banque de dialogues de fallback (FR + EN)
-- ============================================================
local FALLBACK = {
    FR = {
        greeting      = { "Bonjour, étranger.", "Je te surveille.", "Qu'est-ce que tu veux ?" },
        trade         = { "Tu as quelque chose à vendre ?", "J'ai des provisions disponibles.", "Faisons affaire." },
        trade_accept  = { "Marché conclu.", "D'accord.", "Très bien." },
        trade_refuse  = { "Non, je ne suis pas intéressé.", "Pas pour toi.", "Reviens plus tard." },
        hostile       = { "Va-t'en !", "Tu n'aurais pas dû venir ici.", "Prépare-toi à te défendre !" },
        idle          = { "Hmm...", "Qu'est-ce qu'il se passe dehors ?", "Je dois rester vigilant." },
        help_request  = { "Tu peux m'aider ?", "J'ai besoin de provisions.", "Je cherche un médecin." },
        bitten_deny   = { "Ce n'est rien.", "J'ai juste glissé.", "Ça va, laisse-moi tranquille." },
        quest_give    = { "J'ai une mission pour toi.", "Tu pourrais faire quelque chose pour moi ?", "Écoute, j'ai besoin d'un service." },
        quest_complete = { "Excellent travail !", "Je savais que je pouvais compter sur toi.", "Merci, vraiment." },
        death         = { "Je... ne peux plus...", "Prends soin de toi...", "Évite les rues..." },
    },
    EN = {
        greeting      = { "Hello, stranger.", "I'm watching you.", "What do you want?" },
        trade         = { "Got anything to sell?", "I have supplies available.", "Let's do business." },
        trade_accept  = { "Deal.", "Alright.", "Very well." },
        trade_refuse  = { "No, I'm not interested.", "Not for you.", "Come back later." },
        hostile       = { "Get out!", "You shouldn't have come here.", "Prepare to defend yourself!" },
        idle          = { "Hmm...", "Wonder what's outside.", "Must stay alert." },
        help_request  = { "Can you help me?", "I need supplies.", "I'm looking for a medic." },
        bitten_deny   = { "It's nothing.", "I just slipped.", "I'm fine, leave me alone." },
        quest_give    = { "I have a mission for you.", "Could you do something for me?", "Listen, I need a favor." },
        quest_complete = { "Excellent work!", "I knew I could count on you.", "Thank you, truly." },
        death         = { "I... can't...", "Take care of yourself...", "Avoid the streets..." },
    },
}

-- ============================================================
-- API
-- ============================================================

--- Définit la locale active.
function NPC_Dialogue.setLocale(locale)
    NPC_Dialogue._locale = (locale == "EN") and "EN" or "FR"
end

--- Retourne une ligne de dialogue aléatoire pour un contexte.
-- @param context   string   Clé de contexte (greeting / trade / ...)
-- @param tokens    table?   { name=..., profession=..., faction=... }
-- @return string
function NPC_Dialogue.get(context, tokens)
    local locale  = NPC_Dialogue._locale
    local bank    = FALLBACK[locale] or FALLBACK.FR
    local lines   = bank[context] or bank.idle or { "..." }
    local line    = lines[PHNPC.randInt(1, #lines)]

    -- Substitution des tokens
    if type(tokens) == "table" then
        line = line:gsub("{(%w+)}", function(key)
            local v = tokens[key]
            return v and tostring(v) or ("{" .. key .. "}")
        end)
    end

    return line
end

--- Retourne une réponse Ollama de fallback si le pont HTTP échoue.
-- @param npcData  NPCDataModel
-- @param playerMsg  string
-- @return string
function NPC_Dialogue.ollamaFallback(npcData, playerMsg)
    local ctx = "idle"
    if playerMsg then
        local low = playerMsg:lower()
        if low:find("commerce") or low:find("vendre") or low:find("trade") or low:find("buy") then
            ctx = "trade"
        elseif low:find("aide") or low:find("help") or low:find("médecin") then
            ctx = "help_request"
        elseif low:find("mission") or low:find("quest") then
            ctx = "quest_give"
        end
    end
    return NPC_Dialogue.get(ctx, { name = npcData and npcData.firstName or "?" })
end

-- Détecter la langue du jeu (B42)
-- NOTE : on utilise des nil-guards et non pcall (pcall peut être nil en Kahlua)
Events.OnGameBoot.Add(function()
    if not getCore then return end
    local core = getCore()
    if not core then return end
    -- getLanguage() retourne un objet Java Language, on le convertit en string
    local lang = nil
    if core.getLanguage then
        local raw = core:getLanguage()
        if raw then lang = tostring(raw) end
    end
    if lang and type(lang) == "string" then
        NPC_Dialogue.setLocale(lang:upper():sub(1, 2))
    end
end)

PHNPC.registerModule("NPC_Dialogue", NPC_Dialogue)
return NPC_Dialogue
