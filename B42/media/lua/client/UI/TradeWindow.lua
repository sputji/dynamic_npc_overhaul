--[[
    Project Humain : Dynamic NPC Overhaul — B42
    client/UI/TradeWindow.lua

    Fenêtre de commerce PNJ ↔ Joueur.
    Affiche l'inventaire du PNJ et permet d'initier un échange.
    Hérite de ISPanel.
]]

if not isClient() then return end

local Log        = PHNPC.getModule("NPC_Logger")
local Dispatcher = PHNPC.getModule("NPC_NetworkDispatcher")

-- ============================================================
-- Classe TradeWindow
-- ============================================================

NPC_TradeWindow = ISPanel:derive("NPC_TradeWindow")

local WIN_W = 380
local WIN_H = 320
local PAD   = 8

function NPC_TradeWindow:new(tradeData)
    local x = getCore():getScreenWidth()  / 2 - WIN_W / 2
    local y = getCore():getScreenHeight() / 2 - WIN_H / 2
    local o = ISPanel.new(self, x, y, WIN_W, WIN_H)
    o.tradeData  = tradeData or {}
    o.npcId      = tradeData.npcId
    o.npcName    = tradeData.name or "PNJ"
    o.inventory  = tradeData.inventory or {}
    o.npcGold    = tradeData.gold or 0
    o.selected   = {}   -- { [itemType] = qty }
    return o
end

function NPC_TradeWindow:initialise()
    ISPanel.initialise(self)

    -- Bouton fermer
    local btnClose = ISButton:new(WIN_W - 30, 4, 26, 22, "X", self, NPC_TradeWindow.close)
    btnClose:initialise()
    btnClose:instantiate()
    self:addChild(btnClose)

    -- Bouton Confirmer échange
    local btnOk = ISButton:new(PAD, WIN_H - 36, WIN_W - PAD * 2, 28, "Confirmer l'échange", self, NPC_TradeWindow.confirmTrade)
    btnOk:initialise()
    btnOk:instantiate()
    self:addChild(btnOk)
end

function NPC_TradeWindow:render()
    ISPanel.render(self)

    -- En-tête
    self:drawRect(0, 0, WIN_W, 28, 0.85, 0.1, 0.1, 0.1)
    self:drawText("Commerce : " .. self.npcName, PAD, 6, 1, 1, 1, 1, UIFont.Medium)

    -- Or du PNJ
    self:drawText("Or du PNJ : " .. tostring(self.npcGold), PAD, 32, 1, 0.9, 0.2, 1, UIFont.Small)

    -- Liste d'inventaire
    local y = 54
    self:drawText("Inventaire disponible :", PAD, y, 0.8, 0.8, 0.8, 1, UIFont.Small)
    y = y + 18

    local count = 0
    for itemType, qty in pairs(self.inventory) do
        if count > 8 then
            self:drawText("...", PAD, y, 0.6, 0.6, 0.6, 1, UIFont.Small)
            break
        end
        self:drawText(string.format("  %s  x%d", itemType, qty), PAD, y, 0.9, 0.9, 0.9, 1, UIFont.Small)
        y = y + 16
        count = count + 1
    end

    if count == 0 then
        self:drawText("  (inventaire vide)", PAD, y, 0.5, 0.5, 0.5, 1, UIFont.Small)
    end
end

function NPC_TradeWindow:confirmTrade()
    Dispatcher.send("server", "npc_trade_confirm", {
        npcId    = self.npcId,
        selected = self.selected,
    })
    Log.debug("NPC_TradeWindow", "Échange envoyé", { npcId = self.npcId })
end

function NPC_TradeWindow:onResult(result)
    if result and result.success then
        -- TODO : feedback positif (son, message)
        Log.ok("NPC_TradeWindow", "Échange réussi.")
    end
    self:close()
end

function NPC_TradeWindow:close()
    self:setVisible(false)
    self:removeFromUIManager()
end

-- ============================================================
-- API module
-- ============================================================

local NPC_TradeWindow_Module = {}
local _openWindow = nil

function NPC_TradeWindow_Module.open(data)
    if _openWindow then
        _openWindow:close()
        _openWindow = nil
    end
    local win = NPC_TradeWindow:new(data)
    win:initialise()
    win:addToUIManager()
    _openWindow = win
end

function NPC_TradeWindow_Module.onResult(data)
    if _openWindow then
        _openWindow:onResult(data)
        _openWindow = nil
    end
end

PHNPC.registerModule("NPC_TradeWindow", NPC_TradeWindow_Module)
return NPC_TradeWindow_Module
