--[[
    Project Humain : Dynamic NPC Overhaul — B42
    client/UI/NPC_SpeechBubble.lua

    Bulles de dialogue PNJ — deux niveaux :

      1. API PZ native (au-dessus de la tête du personnage)
         Tente zombie:setSpeakBubble(text) avec fallbacks.
         Si l'API existe dans cette version de PZ, la bulle
         s'affiche directement dans le monde 3D.

      2. Toast bas-écran (garanti fonctionnel)
         Panel fixe centré en bas de l'écran.
         Affiche  [Nom du NPC] : "ligne de dialogue"
         Disparaît progressivement après ~6 secondes.

    Usage :
        local Bubble = PHNPC.getModule("NPC_SpeechBubble")
        Bubble.show(npcData, zombie, texte)
]]

-- ============================================================
-- Panel toast bas de l'écran
-- ============================================================

local NPC_SpeechToastPanel = ISPanel:derive("NPC_SpeechToastPanel")

local TOAST_W       = 540
local TOAST_H       = 54
local DISPLAY_TICKS = 210   -- ~7 secondes à 30 fps
local FADE_TICKS    = 60    -- durée du fondu de sortie

function NPC_SpeechToastPanel:new()
    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    local x  = math.floor(sw / 2 - TOAST_W / 2)
    local y  = sh - TOAST_H - 82   -- juste au-dessus de la barre de statut PZ
    local o  = ISPanel.new(self, x, y, TOAST_W, TOAST_H)
    o._text  = ""
    o._name  = ""
    o._ticks = 0
    return o
end

function NPC_SpeechToastPanel:initialise()
    ISPanel.initialise(self)
end

--- Met à jour le texte et réinitialise le timer.
function NPC_SpeechToastPanel:show(name, text)
    self._name  = name or "PNJ"
    self._text  = text or "..."
    self._ticks = DISPLAY_TICKS
    -- Recentrer si la résolution a changé depuis la création
    local sw = getCore():getScreenWidth()
    self:setX(math.floor(sw / 2 - TOAST_W / 2))
    self:setVisible(true)
end

function NPC_SpeechToastPanel:update()
    ISPanel.update(self)
    if self._ticks > 0 then
        self._ticks = self._ticks - 1
        if self._ticks <= 0 then
            self:setVisible(false)
        end
    end
end

function NPC_SpeechToastPanel:render()
    -- Alpha : plein pendant DISPLAY_TICKS-FADE_TICKS, puis fondu
    local alpha = 1.0
    if self._ticks < FADE_TICKS then
        alpha = math.max(0.0, self._ticks / FADE_TICKS)
    end
    if alpha <= 0.01 then return end

    -- Fond sombre semi-opaque
    self:drawRect(0, 0, TOAST_W, TOAST_H, alpha * 0.88, 0.04, 0.04, 0.10)

    -- Bande bleue en haut (identifie la parole NPC)
    self:drawRect(0, 0, TOAST_W, 3, alpha,  0.25, 0.60, 0.95)

    -- Barre d'accent gauche
    self:drawRect(0, 0, 4, TOAST_H, alpha, 0.25, 0.60, 0.95)

    -- Bordure basse subtile
    self:drawRect(0, TOAST_H - 1, TOAST_W, 1, alpha * 0.5, 0.25, 0.60, 0.95)

    -- Nom du PNJ (couleur bleue)
    local nameStr = self._name .. "  :  "
    self:drawText(nameStr,
        12, 16,
        alpha,  0.40, 0.78, 1.00, UIFont.Small)

    -- Texte du dialogue (couleur chaude)
    local nw = getTextManager():MeasureStringX(UIFont.Small, nameStr)
    self:drawText('"' .. self._text .. '"',
        12 + nw, 16,
        alpha,  0.95, 0.92, 0.72, UIFont.Small)

    ISPanel.render(self)
end

-- ============================================================
-- Module NPC_SpeechBubble
-- ============================================================

local NPC_SpeechBubble = {}
NPC_SpeechBubble._toast = nil   -- instance unique du panel toast

--- Affiche une bulle de dialogue pour un PNJ.
-- Tente l'API PZ native (dessus-de-tête) ET affiche le toast bas-écran.
--
-- @param npcData  table  NPCDataModel ou {fullName, firstName}
-- @param zombie   IsoZombie associé (peut être nil)
-- @param text     string  Texte à afficher
function NPC_SpeechBubble.show(npcData, zombie, text)
    if not text or text == "" then return end

    local name = ""
    if npcData then
        name = npcData.fullName or npcData.firstName or "PNJ"
    end

    -- 1. API PZ native : bulle au-dessus de la tête du personnage dans le monde 3D.
    --    Plusieurs formes de l'API selon la version de PZ B42 — on essaie en cascade.
    if zombie and instanceof(zombie, "IsoZombie") then
        -- setSpeakBubble : méthode Java IsoGameCharacter → Lua binding (B42+)
        local ok = pcall(function() zombie:setSpeakBubble(text) end)
        -- setSayText : nom alternatif dans certaines versions
        if not ok then
            ok = pcall(function()
                zombie:setSayText(text)
                zombie:setSayTextTime(5000)
            end)
        end
        -- say : raccourci générique
        if not ok then
            pcall(function() zombie:say(text) end)
        end
    end

    -- 2. Toast bas-écran (toujours affiché, garanti fonctionnel).
    --    Crée le panel à la demande (lazy init) pour ne rien allouer au chargement.
    if not NPC_SpeechBubble._toast then
        local t = NPC_SpeechToastPanel:new()
        t:initialise()
        t:addToUIManager()
        t:setVisible(false)
        NPC_SpeechBubble._toast = t
    end

    NPC_SpeechBubble._toast:show(name, text)
end

--- Réinitialise le toast (appelé par OnGameStart pour éviter les références périmées).
function NPC_SpeechBubble.reset()
    if NPC_SpeechBubble._toast then
        pcall(function()
            NPC_SpeechBubble._toast:setVisible(false)
            NPC_SpeechBubble._toast:removeFromUIManager()
        end)
        NPC_SpeechBubble._toast = nil
    end
end

-- Nettoyage sur chargement de partie
Events.OnGameStart.Add(function()
    NPC_SpeechBubble.reset()
end)

-- ============================================================
-- Enregistrement
-- ============================================================

PHNPC.registerModule("NPC_SpeechBubble", NPC_SpeechBubble)
return NPC_SpeechBubble
