--[[
    Project Humain : Dynamic NPC Overhaul — B42
    client/UI/NPC_UI.lua

    Interface principale : fiche info PNJ (nom, profession, besoins, faction).
    Hérite de ISPanel (B42 UI framework).
]]

if not isClient() then return end

local Log = PHNPC.getModule("NPC_Logger")

-- ============================================================
-- Classe NPC_UI (ISPanel)
-- ============================================================

NPC_UI = ISPanel:derive("NPC_UI")

local PANEL_W = 280
local PANEL_H = 220
local PAD     = 10

function NPC_UI:new(npcId)
    local x = getCore():getScreenWidth()  / 2 - PANEL_W / 2
    local y = getCore():getScreenHeight() / 2 - PANEL_H / 2
    local o = ISPanel.new(self, x, y, PANEL_W, PANEL_H)
    o.npcId = npcId
    o.data  = (PHNPC.clientNPCs or {})[npcId] or {}
    return o
end

function NPC_UI:initialise()
    ISPanel.initialise(self)

    -- Bouton fermer
    local btn = ISButton:new(PANEL_W - 30, 4, 26, 22, "X", self, NPC_UI.close)
    btn:initialise()
    btn:instantiate()
    self:addChild(btn)
end

function NPC_UI:render()
    ISPanel.render(self)

    local d    = self.data
    local name = d.fullName or "PNJ inconnu"
    local prof = d.professionId or "?"
    local hp   = d.health  or "?"
    local mor  = d.morale  or "?"
    local fac  = d.faction or "?"

    self:drawRect(0, 0, PANEL_W, 28, 0.85, 0.1, 0.1, 0.1)
    self:drawText(name, PAD, 6, 1, 1, 1, 1, UIFont.Medium)

    local y = 36
    local function row(label, value)
        self:drawText(label .. " : " .. tostring(value), PAD, y, 0.8, 0.8, 0.8, 1, UIFont.Small)
        y = y + 18
    end

    row("Profession", prof)
    row("Santé",      hp)
    row("Moral",      mor)
    row("Faction",    fac)

    -- Barre de santé
    y = y + 6
    local barW = PANEL_W - PAD * 2
    local hpPct = (type(d.health) == "number") and PHNPC.clamp(d.health / 100, 0, 1) or 0
    self:drawRect(PAD, y, barW, 10, 0.9, 0.3, 0.3, 0.3)
    self:drawRect(PAD, y, math.floor(barW * hpPct), 10, 0.9, 0.2, 0.8, 0.2)
    self:drawText("HP", PAD, y, 0.7, 1, 1, 1, UIFont.Small)
end

function NPC_UI:close()
    self:setVisible(false)
    self:removeFromUIManager()
end

-- ============================================================
-- API publique (module)
-- ============================================================

local NPC_UI_Module = {}

local _openPanel = nil

function NPC_UI_Module.showInfo(npcId)
    if _openPanel then
        _openPanel:close()
        _openPanel = nil
    end
    local panel = NPC_UI:new(npcId)
    panel:initialise()
    panel:addToUIManager()
    _openPanel = panel
    Log.debug("NPC_UI", "Panneau ouvert", { npcId = npcId })
end

PHNPC.registerModule("NPC_UI", NPC_UI_Module)
return NPC_UI_Module
