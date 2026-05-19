--[[
    Project Humain : Dynamic_NPC_Overhaul
    PHNPC_TradeWindow.lua

    Fenetre de commerce dediee inspiree des patterns tradeHunter (liste vendeur/acheteur)
    mais branchee sur le pipeline reseau existant (PHNPCInteractionClient).
]]


pcall(require, "ISUI/ISPanel")
pcall(require, "ISUI/ISButton")
pcall(require, "ISUI/ISLabel")
pcall(require, "ISUI/ISScrollingListBox")
pcall(require, "ISUI/ISTextEntryBox")
pcall(require, "ISUI/ISCollapsableWindow")

local okInteraction, PHNPCInteractionClient = pcall(require, "NPCInteractionClient")
if not okInteraction then
    PHNPCInteractionClient = _G.PHNPCInteractionClient
end

local PHNPCTradeWindow = ISCollapsableWindow:derive("PHNPCTradeWindow")

local TradeController = {
    windows = {},
    listenerRegistered = false
}

local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function getLocalPlayer()
    if type(getSpecificPlayer) == "function" then
        return getSpecificPlayer(0)
    end
    return nil
end

local function aggregatePlayerInventory(player)
    local rows = {}
    if not player or not player.getInventory then
        return rows
    end

    local inv = player:getInventory()
    local items = inv and inv.getItems and inv:getItems() or nil
    if not items or not items.size then
        return rows
    end

    local map = {}
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it and it.getFullType then
            local fullType = it:getFullType()
            map[fullType] = (map[fullType] or 0) + 1
        end
    end

    for fullType, qty in pairs(map) do
        rows[#rows + 1] = {
            itemType = fullType,
            quantity = qty,
            label = fullType .. " x" .. tostring(qty)
        }
    end

    table.sort(rows, function(a, b)
        return tostring(a.itemType or "") < tostring(b.itemType or "")
    end)

    return rows
end

function PHNPCTradeWindow:new(npcId)
    local o = ISCollapsableWindow.new(self, 240, 120, 700, 520)
    o.title = "Commerce PNJ"
    o.npcId = npcId
    o.snapshot = nil
    o.pendingQuote = nil
    o.playerRows = {}
    o.npcRows = {}
    o.backgroundColor = { r = 0.05, g = 0.06, b = 0.07, a = 0.92 }
    o.borderColor = { r = 0.36, g = 0.50, b = 0.62, a = 0.92 }
    o.resizable = true
    o.pin = true
    return o
end

function PHNPCTradeWindow:initialise()
    ISCollapsableWindow.initialise(self)

    self.lblNpc = ISLabel:new(12, 28, 18, "PNJ: " .. tostring(self.npcId or "?"), 1, 1, 1, 1, UIFont.Small, true)
    self:addChild(self.lblNpc)

    self.lblCash = ISLabel:new(12, 46, 18, "Caisse PNJ: ?", 0.92, 0.9, 0.75, 1, UIFont.Small, true)
    self:addChild(self.lblCash)

    self.lblStatus = ISLabel:new(12, 64, 18, "Pret", 0.8, 0.95, 0.85, 1, UIFont.Small, true)
    self:addChild(self.lblStatus)

    self.lblSteps = ISLabel:new(12, 78, 18, "Etapes: 1) Selection  2) Demander devis  3) Acheter/Vendre", 0.68, 0.85, 1.0, 1, UIFont.Small, true)
    self:addChild(self.lblSteps)

    self.lblQuote = ISLabel:new(360, 46, 18, "Prix estime: --", 0.7, 0.85, 1.0, 1, UIFont.Small, true)
    self:addChild(self.lblQuote)

    self.npcList = ISScrollingListBox:new(12, 102, 330, 318)
    self.npcList:initialise()
    self.npcList:instantiate()
    self.npcList.itemheight = 20
    self.npcList.font = UIFont.Small
    self.npcList.drawBorder = true
    self.npcList.doDrawItem = function(list, y, item, alt)
        local a = alt and 0.15 or 0.08
        list:drawRect(0, y, list:getWidth(), list.itemheight, a, 0.2, 0.2, 0.2)
        list:drawText(item.text, 8, y + 2, 0.95, 0.95, 0.95, 1, UIFont.Small)
        return y + list.itemheight
    end
    self.npcList.onMouseDown = function(list, x, y)
        ISScrollingListBox.onMouseDown(list, x, y)
        self:onNpcSelectionChanged()
    end
    self:addChild(self.npcList)

    self.playerList = ISScrollingListBox:new(358, 102, 330, 318)
    self.playerList:initialise()
    self.playerList:instantiate()
    self.playerList.itemheight = 20
    self.playerList.font = UIFont.Small
    self.playerList.drawBorder = true
    self.playerList.doDrawItem = function(list, y, item, alt)
        local a = alt and 0.15 or 0.08
        list:drawRect(0, y, list:getWidth(), list.itemheight, a, 0.2, 0.2, 0.2)
        list:drawText(item.text, 8, y + 2, 0.95, 0.95, 0.95, 1, UIFont.Small)
        return y + list.itemheight
    end
    self.playerList.onMouseDown = function(list, x, y)
        ISScrollingListBox.onMouseDown(list, x, y)
        self:onPlayerSelectionChanged()
    end
    self:addChild(self.playerList)

    self.lblNpcStock = ISLabel:new(12, 424, 18, "Stock du PNJ", 0.95, 0.95, 0.75, 1, UIFont.Small, true)
    self:addChild(self.lblNpcStock)

    self.lblPlayerStock = ISLabel:new(358, 424, 18, "Inventaire joueur", 0.95, 0.95, 0.75, 1, UIFont.Small, true)
    self:addChild(self.lblPlayerStock)

    self.qtyEntry = ISTextEntryBox:new("1", 12, 448, 52, 24)
    self.qtyEntry:initialise()
    self.qtyEntry:instantiate()
    self:addChild(self.qtyEntry)

    self.btnQuote = ISButton:new(70, 448, 130, 24, "2) Demander devis", self, PHNPCTradeWindow.onRequestQuote)
    self.btnQuote:initialise()
    self.btnQuote:instantiate()
    self:addChild(self.btnQuote)

    self.btnBuy = ISButton:new(206, 448, 124, 24, "3) Acheter", self, PHNPCTradeWindow.onBuy)
    self.btnBuy:initialise()
    self.btnBuy:instantiate()
    self:addChild(self.btnBuy)

    self.btnSell = ISButton:new(336, 448, 124, 24, "3) Vendre", self, PHNPCTradeWindow.onSell)
    self.btnSell:initialise()
    self.btnSell:instantiate()
    self:addChild(self.btnSell)

    self.btnRefresh = ISButton:new(468, 448, 98, 24, "Actualiser", self, PHNPCTradeWindow.onRefresh)
    self.btnRefresh:initialise()
    self.btnRefresh:instantiate()
    self:addChild(self.btnRefresh)

    self.btnClose = ISButton:new(572, 448, 116, 24, "Fermer", self, PHNPCTradeWindow.onCloseClick)
    self.btnClose:initialise()
    self.btnClose:instantiate()
    self:addChild(self.btnClose)

    self:refreshPlayerInventory()
    self:requestSnapshot()
end

function PHNPCTradeWindow:setStatus(message, kind)
    local r, g, b = 0.8, 0.95, 0.85
    if kind == "error" then
        r, g, b = 1.0, 0.45, 0.45
    elseif kind == "success" then
        r, g, b = 0.45, 1.0, 0.45
    elseif kind == "warn" then
        r, g, b = 1.0, 0.85, 0.35
    elseif kind == "info" then
        r, g, b = 0.65, 0.85, 1.0
    end

    self.lblStatus:setName(tostring(message or ""))
    if self.lblStatus.setColor then
        self.lblStatus:setColor(r, g, b, 1.0)
    end
end

function PHNPCTradeWindow:getSelectedNpcItem()
    if not self.npcList or not self.npcList.items or not self.npcList.selected then
        return nil
    end
    local row = self.npcList.items[self.npcList.selected]
    return row and row.item or nil
end

function PHNPCTradeWindow:getSelectedPlayerItem()
    if not self.playerList or not self.playerList.items or not self.playerList.selected then
        return nil
    end
    local row = self.playerList.items[self.playerList.selected]
    return row and row.item or nil
end

function PHNPCTradeWindow:getQuantity(defaultQty)
    local qty = tonumber(self.qtyEntry and self.qtyEntry:getText() or tostring(defaultQty or 1)) or (defaultQty or 1)
    return clamp(math.floor(qty), 1, 999)
end

function PHNPCTradeWindow:requestSnapshot()
    if PHNPCInteractionClient and PHNPCInteractionClient.requestNpcSnapshot then
        PHNPCInteractionClient:requestNpcSnapshot(self.npcId)
    end
end

function PHNPCTradeWindow:refreshPlayerInventory()
    self.playerRows = aggregatePlayerInventory(getLocalPlayer())

    if not self.playerList then
        return
    end

    self.playerList:clear()
    for i = 1, #self.playerRows do
        local row = self.playerRows[i]
        self.playerList:addItem(row.label, row)
    end
end

function PHNPCTradeWindow:refreshNpcInventory()
    if not self.npcList then
        return
    end

    self.npcList:clear()
    self.npcRows = {}

    local inv = self.snapshot and self.snapshot.inventory or nil
    local items = inv and inv.items or nil
    if type(items) ~= "table" then
        return
    end

    for i = 1, #items do
        local it = items[i]
        if it and it.type then
            local qty = math.max(1, tonumber(it.quantity) or 1)
            local row = {
                itemType = tostring(it.type),
                quantity = qty,
                label = tostring(it.type) .. " x" .. tostring(qty)
            }
            self.npcRows[#self.npcRows + 1] = row
        end
    end

    table.sort(self.npcRows, function(a, b)
        return tostring(a.itemType or "") < tostring(b.itemType or "")
    end)

    for i = 1, #self.npcRows do
        local row = self.npcRows[i]
        self.npcList:addItem(row.label, row)
    end
end

function PHNPCTradeWindow:updateFromSnapshot(snapshot)
    if not snapshot or snapshot.npcId ~= self.npcId then
        return
    end

    self.snapshot = snapshot
    local cash = snapshot.economy and snapshot.economy.cash or nil
    self.lblCash:setName("Caisse PNJ: " .. tostring(cash ~= nil and cash or "?"))
    self:refreshNpcInventory()
end

function PHNPCTradeWindow:onNpcSelectionChanged()
    local row = self:getSelectedNpcItem()
    if not row then
        return
    end
    self:setStatus("Selection PNJ: " .. tostring(row.itemType), "info")
end

function PHNPCTradeWindow:onPlayerSelectionChanged()
    local row = self:getSelectedPlayerItem()
    if not row then
        return
    end
    self:setStatus("Selection joueur: " .. tostring(row.itemType), "info")
end

function PHNPCTradeWindow:onRequestQuote()
    if not PHNPCInteractionClient or type(PHNPCInteractionClient.requestBusinessQuote) ~= "function" then
        self:setStatus("Client interaction indisponible", "error")
        return
    end

    local row = self:getSelectedNpcItem() or self:getSelectedPlayerItem()
    if not row or not row.itemType then
        self:setStatus("Selectionnez un objet", "warn")
        return
    end

    local qty = self:getQuantity(row.quantity or 1)
    self.pendingQuote = nil

    PHNPCInteractionClient:requestBusinessQuote(self.npcId, "buy", {
        serviceType = "buy",
        itemType = row.itemType,
        quantity = qty,
        marketCategory = "general_goods",
        targetHint = row.itemType
    })

    self:setStatus("Devis demande pour " .. tostring(row.itemType), "info")
end

function PHNPCTradeWindow:onBuy()
    if not PHNPCInteractionClient or type(PHNPCInteractionClient.sendTradeEvent) ~= "function" then
        self:setStatus("Client interaction indisponible", "error")
        return
    end

    local row = self:getSelectedNpcItem()
    if not row or not row.itemType then
        self:setStatus("Selectionnez un objet du stock PNJ", "warn")
        return
    end

    local qty = self:getQuantity(row.quantity or 1)
    qty = clamp(qty, 1, row.quantity or qty)

    PHNPCInteractionClient:sendTradeEvent(self.npcId, "buy", {
        itemType = row.itemType,
        quantity = qty,
        value = (self.pendingQuote and self.pendingQuote.cost) or (qty * 10),
        price = (self.pendingQuote and self.pendingQuote.cost) or (qty * 10),
        strictCapacity = true,
        requested = "trade_window_buy"
    })

    self:setStatus("Achat envoye: " .. tostring(row.itemType) .. " x" .. tostring(qty), "info")
end

function PHNPCTradeWindow:onSell()
    if not PHNPCInteractionClient or type(PHNPCInteractionClient.sendTradeEvent) ~= "function" then
        self:setStatus("Client interaction indisponible", "error")
        return
    end

    local row = self:getSelectedPlayerItem()
    if not row or not row.itemType then
        self:setStatus("Selectionnez un objet joueur", "warn")
        return
    end

    local qty = self:getQuantity(row.quantity or 1)
    qty = clamp(qty, 1, row.quantity or qty)

    PHNPCInteractionClient:sendTradeEvent(self.npcId, "sell", {
        itemType = row.itemType,
        quantity = qty,
        value = (self.pendingQuote and self.pendingQuote.cost) or (qty * 8),
        price = (self.pendingQuote and self.pendingQuote.cost) or (qty * 8),
        strictCapacity = true,
        requested = "trade_window_sell"
    })

    self:setStatus("Vente envoyee: " .. tostring(row.itemType) .. " x" .. tostring(qty), "info")
end

function PHNPCTradeWindow:onRefresh()
    self:refreshPlayerInventory()
    self:requestSnapshot()
    self:setStatus("Actualisation demandee", "info")
end

function PHNPCTradeWindow:onCloseClick()
    self:close()
end

function PHNPCTradeWindow:close()
    if self.setVisible then
        self:setVisible(false)
    end
    if self.removeFromUIManager then
        self:removeFromUIManager()
    end
    TradeController.windows[self.npcId] = nil
end

function TradeController.open(npcId)
    if not npcId then
        return nil
    end

    local existing = TradeController.windows[npcId]
    if existing and existing.getIsVisible and existing:getIsVisible() then
        existing:bringToTop()
        existing:refreshPlayerInventory()
        existing:requestSnapshot()
        return existing
    end

    local win = PHNPCTradeWindow:new(npcId)
    win:initialise()
    win:addToUIManager()
    win:setVisible(true)
    TradeController.windows[npcId] = win
    return win
end

function TradeController.onInteractionEvent(eventName, payload)
    if eventName == "NpcSnapshot" and payload and payload.snapshot then
        local npcId = payload.snapshot.npcId
        local win = TradeController.windows[npcId]
        if win and win.getIsVisible and win:getIsVisible() then
            win:updateFromSnapshot(payload.snapshot)
        end
    elseif eventName == "ActionResult" and payload and payload.actionType == "TradeEvent" then
        local npcId = payload.npcId
        local win = TradeController.windows[npcId]
        if win and win.getIsVisible and win:getIsVisible() then
            local ok = payload.ok == true
            win:setStatus(payload.message or "TradeEvent", ok and "success" or "error")
            win:refreshPlayerInventory()
            win:requestSnapshot()
        end
    elseif eventName == "BusinessQuoteResponse" and payload then
        local req = payload.request or nil
        local npcId = req and req.npcId or nil
        if not npcId then
            return
        end

        local win = TradeController.windows[npcId]
        if win and win.getIsVisible and win:getIsVisible() then
            win.pendingQuote = payload.quote
            if win.pendingQuote then
                local c = tonumber(win.pendingQuote.cost) or 0
                win.lblQuote:setName("Prix estime: " .. tostring(c) .. " | " .. tostring(win.pendingQuote.priceState or "neutre"))
                win:setStatus("Devis recu", "success")
            else
                win.lblQuote:setName("Prix estime: --")
                win:setStatus("Devis indisponible", "warn")
            end
        end
    end
end

function TradeController.start()
    if TradeController.listenerRegistered then
        return
    end

    if PHNPCInteractionClient and PHNPCInteractionClient.addListener then
        PHNPCInteractionClient:addListener("PHNPCTradeWindow", function(eventName, payload)
            TradeController.onInteractionEvent(eventName, payload)
        end)
        TradeController.listenerRegistered = true
    end
end

TradeController.start()

_G.PHNPCTradeWindow = TradeController

return TradeController
