--[[
    Project Humain : Dynamic NPC Overhaul — B42
    client/UI/NPC_DialogueWindow.lua

    Fenêtre de dialogue ISPanel — Phase 3.

    Ouverte par NPC_InteractionClient.onTalkClicked.
    Affiche nom / profession / santé du PNJ + une ligne de dialogue
    tirée de NPC_Dialogue (banque FR/EN).

    Boutons :
      [Parler encore] → cycle à travers les contextes de dialogue
      [Commerce]      → ligne "trade" (placeholder Phase 4)
      [Au revoir]     → ligne "trade_refuse" puis fermeture

    N'utilise PAS de réseau : tout est local client (DataModel déjà en mémoire).
]]

NPC_DialogueWindow = ISPanel:derive("NPC_DialogueWindow")

local PANEL_W = 440
local PANEL_H = 210

-- Cycle de contextes parcouru par "Parler encore"
local TALK_CYCLE = {
    "greeting", "idle", "help_request", "idle", "quest_give", "idle", "bitten_deny"
}

-- ============================================================
-- Point d'entrée statique
-- ============================================================

--- Ouvre (ou remplace) la fenêtre de dialogue pour un PNJ.
-- @param npcData  NPCDataModel (ou table partielle {fullName, ...})
-- @param zombie   IsoZombie associé
function NPC_DialogueWindow.open(npcData, zombie)
    if NPC_DialogueWindow._instance then
        pcall(function() NPC_DialogueWindow._instance:close() end)
    end
    local win = NPC_DialogueWindow:new(npcData, zombie)
    win:initialise()
    win:addToUIManager()
    NPC_DialogueWindow._instance = win
end

-- ============================================================
-- Constructeur
-- ============================================================

function NPC_DialogueWindow:new(npcData, zombie)
    local sx = math.floor(getCore():getScreenWidth()  / 2 - PANEL_W / 2)
    local sy = math.floor(getCore():getScreenHeight() * 0.60)
    local o  = ISPanel.new(self, sx, sy, PANEL_W, PANEL_H)
    o.npcData       = npcData or {}
    o.zombie        = zombie
    o._ctxIdx       = 1
    o._line         = "..."
    o.moveWithMouse = true
    return o
end

-- ============================================================
-- Mise à jour de la ligne de dialogue
-- ============================================================

function NPC_DialogueWindow:_refreshLine(ctxKey)
    local Dlg = PHNPC.getModule("NPC_Dialogue")
    if not Dlg then self._line = "..." return end
    self._line = Dlg.get(ctxKey or "greeting", {
        name       = self.npcData.firstName  or self.npcData.fullName or "?",
        profession = self.npcData.professionId or "",
    })
end

-- ============================================================
-- Initialisation (boutons)
-- ============================================================

function NPC_DialogueWindow:initialise()
    ISPanel.initialise(self)
    self:_refreshLine("greeting")

    local bw  = 128
    local bh  = 28
    local by  = PANEL_H - bh - 10
    local gap = 10

    -- [Parler encore]
    local b1 = ISButton:new(gap, by, bw, bh,
        "Parler encore", self, NPC_DialogueWindow.onTalkAgain)
    b1:initialise()
    self:addChild(b1)

    -- [Commerce]
    local b2 = ISButton:new(gap + bw + gap, by, bw, bh,
        "Commerce", self, NPC_DialogueWindow.onTrade)
    b2:initialise()
    self:addChild(b2)

    -- [Au revoir]
    local b3 = ISButton:new(PANEL_W - bw - gap, by, bw, bh,
        "Au revoir", self, NPC_DialogueWindow.onClose)
    b3:initialise()
    self:addChild(b3)
end

-- ============================================================
-- Callbacks boutons
-- ============================================================

function NPC_DialogueWindow:onTalkAgain()
    self._ctxIdx = (self._ctxIdx % #TALK_CYCLE) + 1
    self:_refreshLine(TALK_CYCLE[self._ctxIdx])
end

function NPC_DialogueWindow:onTrade()
    self:_refreshLine("trade")
end

function NPC_DialogueWindow:onClose()
    self:_refreshLine("trade_refuse")
    self:close()
end

-- ============================================================
-- Rendu
-- ============================================================

function NPC_DialogueWindow:render()
    -- Fond sombre semi-opaque
    self:drawRect(0, 0, PANEL_W, PANEL_H, 0.88, 0.04, 0.04, 0.04)

    -- Bordure chaude (or/marron)
    self:drawRect(0,          0,         PANEL_W, 2,       0.9, 0.65, 0.50, 0.25)
    self:drawRect(0,          PANEL_H-2, PANEL_W, 2,       0.9, 0.65, 0.50, 0.25)
    self:drawRect(0,          0,         2,       PANEL_H, 0.9, 0.65, 0.50, 0.25)
    self:drawRect(PANEL_W-2,  0,         2,       PANEL_H, 0.9, 0.65, 0.50, 0.25)

    -- En-tête : genre + nom + profession
    local gLabel = self.npcData.isFemale and "[F] " or "[H] "
    local name   = self.npcData.fullName    or "PNJ Inconnu"
    local prof   = self.npcData.professionId or ""
    self:drawText(gLabel .. name .. "  —  " .. prof, 12, 12, 1.0, 0.85, 0.40, 1.0, UIFont.Medium)

    -- Indicateur santé (coin haut droit)
    local hp = self.npcData.health or 100
    local hr, hg, hb
    if hp > 60 then hr, hg, hb = 0.30, 0.90, 0.30
    elseif hp > 30 then hr, hg, hb = 0.90, 0.90, 0.30
    else hr, hg, hb = 0.90, 0.30, 0.30 end
    self:drawText("Santé : " .. math.floor(hp) .. "%",
        PANEL_W - 110, 14, hr, hg, hb, 1.0, UIFont.Small)

    -- Séparateur horizontal
    self:drawRect(10, 40, PANEL_W - 20, 1, 0.7, 0.55, 0.45, 0.22)

    -- Ligne de dialogue (entre guillemets)
    local line = '"' .. (self._line or "...") .. '"'
    self:drawText(line, 14, 54, 0.95, 0.95, 0.82, 1.0, UIFont.Small)

    -- Appeler render enfants (boutons)
    ISPanel.render(self)
end

-- ============================================================
-- Fermeture
-- ============================================================

function NPC_DialogueWindow:close()
    self:setVisible(false)
    pcall(function() self:removeFromUIManager() end)
    NPC_DialogueWindow._instance = nil
end

-- ============================================================
-- Enregistrement
-- ============================================================

PHNPC.registerModule("NPC_DialogueWindow", NPC_DialogueWindow)
return NPC_DialogueWindow
