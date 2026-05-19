--[[
    Project Humain : Dynamic NPC Overhaul — B42
    client/UI/OllamaChatUI.lua

    Interface de chat IA avec un PNJ (pont Ollama).
    - Zone de saisie joueur
    - Historique de conversation
    - Réponses affichées dès réception (event "npc_talk_reply")
]]

if not isClient() then return end

local Log        = PHNPC.getModule("NPC_Logger")
local Dispatcher = PHNPC.getModule("NPC_NetworkDispatcher")

-- ============================================================
-- Classe OllamaChatUI
-- ============================================================

PHNPC_OllamaChatUI = ISPanel:derive("PHNPC_OllamaChatUI")

local WIN_W = 420
local WIN_H = 340
local PAD   = 8
local MAX_HISTORY = 20

function PHNPC_OllamaChatUI:new(npcId, npcName, player)
    local x = getCore():getScreenWidth()  / 2 - WIN_W / 2
    local y = getCore():getScreenHeight() / 2 - WIN_H / 2
    local o = ISPanel.new(self, x, y, WIN_W, WIN_H)
    o.npcId   = npcId
    o.npcName = npcName or "PNJ"
    o.player  = player
    o.history = {}   -- { { who="player"|"npc", text=... } }
    o._waiting = false
    return o
end

function PHNPC_OllamaChatUI:initialise()
    ISPanel.initialise(self)

    -- Zone de saisie
    self.inputField = ISTextEntryBox:new("", PAD, WIN_H - 64, WIN_W - PAD * 2 - 80, 28)
    self.inputField:initialise()
    self.inputField:instantiate()
    self:addChild(self.inputField)

    -- Bouton Envoyer
    local btnSend = ISButton:new(WIN_W - PAD - 74, WIN_H - 64, 70, 28, "Envoyer", self, PHNPC_OllamaChatUI.sendMessage)
    btnSend:initialise()
    btnSend:instantiate()
    self:addChild(btnSend)

    -- Bouton Fermer
    local btnClose = ISButton:new(WIN_W - 30, 4, 26, 22, "X", self, PHNPC_OllamaChatUI.close)
    btnClose:initialise()
    btnClose:instantiate()
    self:addChild(btnClose)
end

function PHNPC_OllamaChatUI:render()
    ISPanel.render(self)

    -- En-tête
    self:drawRect(0, 0, WIN_W, 28, 0.85, 0.1, 0.1, 0.15)
    self:drawText("Dialogue : " .. self.npcName, PAD, 6, 1, 1, 0.6, 1, UIFont.Medium)

    -- Historique
    local y     = 36
    local maxY  = WIN_H - 74
    local lines = self.history
    local start = math.max(1, #lines - 10)
    for i = start, #lines do
        local entry = lines[i]
        if y >= maxY then break end
        local who  = entry.who == "player" and "Vous" or self.npcName
        local r, g, b = 0.7, 0.9, 0.7
        if entry.who == "npc" then r, g, b = 0.9, 0.85, 0.5 end
        self:drawText("[" .. who .. "] " .. entry.text, PAD, y, r, g, b, 1, UIFont.Small)
        y = y + 16
    end

    -- Attente réponse
    if self._waiting then
        self:drawText("...", PAD, maxY - 4, 0.5, 0.5, 0.5, 1, UIFont.Small)
    end
end

function PHNPC_OllamaChatUI:sendMessage()
    if self._waiting then return end
    local msg = self.inputField:getText()
    if not msg or #msg:gsub("%s", "") == 0 then return end

    -- Ajouter à l'historique
    self:addMessage("player", msg)
    self.inputField:setText("")
    self._waiting = true

    -- Envoyer au serveur
    Dispatcher.send("server", "npc_talk", { npcId = self.npcId, message = msg })
end

function PHNPC_OllamaChatUI:addMessage(who, text)
    -- who = "player" | nom du PNJ
    local entryWho = (who == "player") and "player" or "npc"
    self.history[#self.history + 1] = { who = entryWho, text = text }
    if #self.history > MAX_HISTORY then
        table.remove(self.history, 1)
    end
    self._waiting = false
end

function PHNPC_OllamaChatUI:close()
    self:setVisible(false)
    self:removeFromUIManager()
    _openUI = nil
end

-- ============================================================
-- API module
-- ============================================================

local OllamaChatUI = {}
local _openUI = nil

function OllamaChatUI.open(npcId, npcName, player)
    if _openUI then
        _openUI:close()
        _openUI = nil
    end
    local ui = PHNPC_OllamaChatUI:new(npcId, npcName, player)
    ui:initialise()
    ui:addToUIManager()
    _openUI = ui
end

function OllamaChatUI.isOpen()
    return _openUI ~= nil and _openUI:isVisible()
end

function OllamaChatUI.addMessage(who, text)
    if _openUI then _openUI:addMessage(who, text) end
end

PHNPC.registerModule("OllamaChatUI", OllamaChatUI)
return OllamaChatUI
