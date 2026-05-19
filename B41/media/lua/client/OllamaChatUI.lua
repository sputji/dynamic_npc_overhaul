--[[
    Project Humain : Dynamic_NPC_Overhaul
    OllamaChatUI.lua

    Interface de chat en jeu pour dialogues IA via Ollama.
    - Fenetre chat collapsible
    - Historique des messages
    - Indicateur de saisie (...)
    - Integration temps reel avec serveur
]]


local okInteraction, PHNPCInteractionClient = pcall(require, "NPCInteractionClient")
if not okInteraction then
    PHNPCInteractionClient = _G.PHNPCInteractionClient
end

local okLogger, PHNPC_Logger = pcall(require, "PHNPC_Logger")
if not okLogger then
    PHNPC_Logger = _G.PHNPC_Logger
end

local function getNetworkClient()
    local net = _G and _G.NPC_NetworkClient or nil
    if type(net) == "table" and type(net.requestDialogue) == "function" then
        return net
    end
    return nil
end

pcall(require, "ISUI/ISPanel")
pcall(require, "ISUI/ISButton")
pcall(require, "ISUI/ISLabel")
pcall(require, "ISUI/ISScrollingListBox")
pcall(require, "ISUI/ISTextEntryBox")
pcall(require, "ISUI/ISCollapsableWindow")

local OllamaChatUI = {
    chatWindows = {},
    isWaitingForResponse = {}
}

local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function safe(value, fallback)
    if value == nil then return fallback or "?" end
    return tostring(value)
end

local NPCChatWindow = ISCollapsableWindow:derive("NPCChatWindow")

function NPCChatWindow:new(npcId)
    local o = ISCollapsableWindow.new(self, 260, 180, 360, 236)
    o.title = "Parler au PNJ"
    o.npcId = npcId
    o.messages = {}
    o.isWaiting = false
    o.waitingStartAt = 0
    o.waitingDotStep = 0
    o.resizable = true
    o.pin = true
    return o
end

function NPCChatWindow:initialise()
    ISCollapsableWindow.initialise(self)

    self.lblNpc = ISLabel:new(12, 28, 18, "Dialogue avec PNJ", 1, 1, 1, 1, UIFont.Small, true)
    self:addChild(self.lblNpc)

    self.messageList = ISScrollingListBox:new(12, 50, self.width - 24, 108)
    self.messageList:initialise()
    self.messageList:instantiate()
    self.messageList.itemheight = 20
    self.messageList.font = UIFont.Small
    self.messageList.drawBorder = true
    self.messageList.doDrawItem = function(list, y, item, alt)
        local msg = item.item or {}
        local a = alt and 0.15 or 0.08
        list:drawRect(0, y, list:getWidth(), list.itemheight, a, 0.15, 0.15, 0.15)

        local r, g, b = 0.85, 0.85, 0.85
        if msg.isPlayer == true then
            r, g, b = 0.65, 0.85, 1.0
        elseif msg.isError == true then
            r, g, b = 1.0, 0.45, 0.45
        elseif msg.isAI == true then
            r, g, b = 0.85, 1.0, 0.6
        end

        local prefix = (msg.isPlayer and "Vous: ") or (msg.isAI and "PNJ: ") or ">> "
        list:drawText(prefix .. (msg.text or ""), 6, y + 2, r, g, b, 1, UIFont.Small)
        return y + list.itemheight
    end
    self:addChild(self.messageList)

    self.inputEntry = ISTextEntryBox:new("", 12, 166, self.width - 24 - 74, 22)
    self.inputEntry:initialise()
    self.inputEntry:instantiate()
    self:addChild(self.inputEntry)

    self.btnSend = ISButton:new(self.width - 58, 166, 50, 22, "OK", self, NPCChatWindow.onSendMessage)
    self.btnSend:initialise()
    self.btnSend:instantiate()
    self:addChild(self.btnSend)

    self.lblStatus = ISLabel:new(12, 194, 18, "Pret", 0.8, 0.95, 0.85, 1, UIFont.Small, true)
    self:addChild(self.lblStatus)

    self.btnClose = ISButton:new(self.width - 88, 194, 80, 22, "Fermer", self, NPCChatWindow.onClose)
    self.btnClose:initialise()
    self.btnClose:instantiate()
    self:addChild(self.btnClose)

    self:addMessage("Dialogue ouvert. Tapez votre message et appuyez sur Envoyer.", nil)
end

function NPCChatWindow:onResize()
    ISCollapsableWindow.onResize(self)
    if self.messageList then
        self.messageList:setWidth(self.width - 24)
        self.messageList:setHeight(108)
    end
    if self.inputEntry then
        self.inputEntry:setY(166)
        self.inputEntry:setWidth(self.width - 24 - 74)
    end
    if self.btnSend then
        self.btnSend:setY(166)
        self.btnSend:setX(self.width - 58)
    end
    if self.lblStatus then
        self.lblStatus:setY(194)
    end
    if self.btnClose then
        self.btnClose:setY(194)
        self.btnClose:setX(self.width - 88)
    end
end

function NPCChatWindow:addMessage(text, isPlayer)
    if not text or #text == 0 then
        return
    end

    local wrappedLines = {}
    local maxLen = 60
    local currentLine = ""

    for i = 1, #text do
        local char = text:sub(i, i)
        if char == "\n" or #currentLine >= maxLen then
            wrappedLines[#wrappedLines + 1] = currentLine
            currentLine = ""
        else
            currentLine = currentLine .. char
        end
    end

    if #currentLine > 0 then
        wrappedLines[#wrappedLines + 1] = currentLine
    end

    for i = 1, #wrappedLines do
        local line = wrappedLines[i]
        if #line > 0 then
            self.messages[#self.messages + 1] = {
                text = line,
                isPlayer = isPlayer == true,
                isAI = isPlayer == false and isPlayer ~= nil,
                isError = isPlayer == "error"
            }
        end
    end

    self:refreshMessageList()
end

function NPCChatWindow:refreshMessageList()
    if not self.messageList then
        return
    end

    local okRefresh, err = pcall(function()
        self.messageList:clear()
        for i = 1, #self.messages do
            local msg = self.messages[i]
            self.messageList:addItem(msg and msg.text or "", msg)
        end

        if self.messageList:getItemCount() > 0 then
            self.messageList:setSelectedIndex(self.messageList:getItemCount())
        end
    end)

    if not okRefresh and PHNPC_Logger and PHNPC_Logger.error then
        PHNPC_Logger:error("OllamaChatUI", "refreshMessageList", "refreshMessageList failed", {
            npcId = self.npcId,
            error = tostring(err),
            messageCount = self.messages and #self.messages or 0
        })
    end
end

function NPCChatWindow:setStatus(message, kind)
    if not self.lblStatus then
        return
    end

    local r, g, b = 0.8, 0.95, 0.85
    if kind == "error" then
        r, g, b = 1.0, 0.45, 0.45
    elseif kind == "success" then
        r, g, b = 0.45, 1.0, 0.45
    elseif kind == "waiting" then
        r, g, b = 1.0, 0.85, 0.35
    elseif kind == "info" then
        r, g, b = 0.65, 0.85, 1.0
    end

    self.lblStatus:setName(message or "")
    if self.lblStatus.setColor then
        self.lblStatus:setColor(r, g, b, 1.0)
    end
end

function NPCChatWindow:updateWaitingIndicator()
    if not self.isWaiting then
        return
    end

    local now = os.time()
    if self.waitingStartAt <= 0 then
        self.waitingStartAt = now
    end

    local elapsed = now - self.waitingStartAt
    if elapsed < 2 then
        self:setStatus("Serveur interroge Ollama...", "waiting")
    else
        self.waitingDotStep = (self.waitingDotStep % 3) + 1
        local dots = string.rep(".", self.waitingDotStep)
        self:setStatus("Serveur interroge Ollama" .. dots, "waiting")
    end

    if elapsed >= 8 then
        self:setStatus("Traitement long cote serveur...", "info")
    end
end

function NPCChatWindow:onSendMessage()
    if self.isWaiting then
        self:setStatus("Veuillez attendre la reponse...", "waiting")
        return
    end

    local userInput = self.inputEntry and self.inputEntry:getText() or ""
    if not userInput or #userInput == 0 then
        self:setStatus("Entrez un message", "error")
        return
    end

    self:addMessage(userInput, true)
    self.inputEntry:setText("")

    self.isWaiting = true
    self.waitingStartAt = os.time()
    self.waitingDotStep = 0
    self:setStatus("Serveur traite...", "waiting")

    -- Utilise NPC_NetworkClient pour requete reseau (multijoueur)
    local networkClient = getNetworkClient()
    if networkClient then
        networkClient:requestDialogue(self.npcId, userInput, function(response, isError)
            -- Callback: reponse recue
            self.isWaiting = false
            self.waitingStartAt = 0
            if isError then
                self:setStatus("Erreur: " .. response, "error")
                self:addMessage("ERREUR: " .. response, nil)
            else
                self:setStatus("Reponse recue", "success")
                self:addMessage(response, false) -- isPlayer=false = c'est l'IA
            end
        end)
    else
        self:setStatus("Reseau indisponible", "error")
        self.isWaiting = false
        self.waitingStartAt = 0
    end
end

function NPCChatWindow:onClearHistory()
    self.messages = {}
    self:refreshMessageList()
    self:setStatus("Historique efface", "success")
    self:addMessage("Dialogue reinitialise.", nil)
end

function NPCChatWindow:onClose()
    self:setVisible(false)
    self:removeFromUIManager()
end

function OllamaChatUI:openChatWindow(npcId)
    if not npcId then
        return
    end

    if self.chatWindows[npcId] and self.chatWindows[npcId]:getIsVisible() then
        self.chatWindows[npcId]:bringToTop()
        return
    end

    if self.chatWindows[npcId] then
        self.chatWindows[npcId]:removeFromUIManager()
    end

    local chatWin = NPCChatWindow:new(npcId)
    chatWin:initialise()
    chatWin:addToUIManager()
    chatWin:setVisible(true)

    self.chatWindows[npcId] = chatWin
end

function OllamaChatUI:onOllamaResponse(npcId, response, isError)
    local chatWin = self.chatWindows[npcId]
    if not chatWin or not chatWin:getIsVisible() then
        return
    end

    if isError then
        chatWin:addMessage(response or "Erreur lors du traitement", "error")
        chatWin:setStatus("Erreur", "error")
    else
        chatWin:addMessage(response, false)
        chatWin:setStatus("Reponse recue", "success")
    end

    chatWin.isWaiting = false
    chatWin.waitingStartAt = 0
end

function OllamaChatUI:onRealtimeEvent(eventName, payload)
    if eventName == "OllamaResponse" and payload then
        self:onOllamaResponse(payload.npcId, payload.response, payload.isError)
    elseif eventName == "DialoguePending" and payload and payload.npcId then
        local chatWin = self.chatWindows[payload.npcId]
        if chatWin and chatWin:getIsVisible() then
            chatWin.isWaiting = payload.pending == true
            if chatWin.isWaiting then
                chatWin.waitingStartAt = os.time()
                chatWin.waitingDotStep = 0
                chatWin:setStatus("Serveur interroge Ollama...", "waiting")
            else
                chatWin.waitingStartAt = 0
            end
        end
    elseif eventName == "DialogueResponse" and payload and payload.npcId then
        local chatWin = self.chatWindows[payload.npcId]
        if chatWin and chatWin:getIsVisible() then
            chatWin.isWaiting = false
            chatWin.waitingStartAt = 0
        end
    end
end

function OllamaChatUI:start()
    if PHNPCInteractionClient and PHNPCInteractionClient.addListener then
        PHNPCInteractionClient:addListener("OllamaChatUI", function(eventName, payload)
            OllamaChatUI:onRealtimeEvent(eventName, payload)
        end)
    end

    if Events and Events.OnTick then
        Events.OnTick.Add(function()
            for _, win in pairs(OllamaChatUI.chatWindows) do
                if win and win.getIsVisible and win:getIsVisible() then
                    win:updateWaitingIndicator()
                end
            end
        end)
    end

    if Events and Events.OnRealtimeEvent then
        Events.OnRealtimeEvent.Add(function(evt)
            if type(evt) == "table" and evt.eventType then
                OllamaChatUI:onRealtimeEvent(evt.eventType, evt)
            end
        end)
    end
end

OllamaChatUI:start()

_G.OllamaChatUI = OllamaChatUI

return OllamaChatUI
