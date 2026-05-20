-- Project Humain: Dynamic NPC Overhaul - B42
-- client/UI/NPC_DialogueWindow.lua
-- Simple NPC dialogue ISPanel.
-- Called from NPC_FollowTick.lua: NPC_DialogueWindow.open(npc, npcData)
-- npc = IsoPlayer entity, npcData = { forename, surname, fullname, followMode, ... }

NPC_DialogueWindow = NPC_DialogueWindow or {}

-- ============================================================
-- DIALOGUE LINES (ASCII only)
-- ============================================================

local LINES = {
    "Je suis heureux d'etre en vie.",
    "Restez pres de moi, s'il vous plait.",
    "Je peux vous aider a survivre.",
    "Merci de m'avoir trouve.",
    "On est plus forts ensemble.",
    "Avez-vous vu d'autres survivants ?",
    "Je cherche de la nourriture.",
    "Il faut rester prudent.",
    "Je connais un abri pas loin d'ici.",
    "Vous savez manier une arme ?",
}

-- ============================================================
-- WINDOW CLASS
-- ============================================================

local DlgWin = ISPanel:derive("PHNPC_DlgWin")

local PANEL_W = 320
local PANEL_H = 130

function DlgWin:new(npc, npcData)
    local sx = math.floor(getCore():getScreenWidth()  / 2 - PANEL_W / 2)
    local sy = math.floor(getCore():getScreenHeight() * 0.60)
    local o  = ISPanel.new(self, sx, sy, PANEL_W, PANEL_H)
    setmetatable(o, self)
    self.__index    = self
    o.npc           = npc
    o.npcData       = npcData or {}
    o.dialogueLine  = LINES[ZombRand(#LINES) + 1]
    o.moveWithMouse = true
    return o
end

function DlgWin:initialise()
    ISPanel.initialise(self)
    self:createChildren()
end

function DlgWin:createChildren()
    local name = self.npcData.fullname or "NPC"

    -- NPC name (title)
    local lblName = ISLabel:new(10, 8, 20, name, 1, 0.85, 0.2, 1, UIFont.Medium, false)
    lblName:initialise()
    self:addChild(lblName)

    -- Dialogue line
    local line = '"' .. self.dialogueLine .. '"'
    local lblLine = ISLabel:new(10, 35, 20, line, 0.85, 0.85, 0.85, 1, UIFont.Small, false)
    lblLine:initialise()
    self:addChild(lblLine)

    -- [Suis-moi] button
    local btnFollow = ISButton:new(10, 90, 90, 25, "Suis-moi", self, DlgWin.onFollow)
    btnFollow:initialise()
    self:addChild(btnFollow)

    -- [Reste ici] button
    local btnStay = ISButton:new(110, 90, 90, 25, "Reste ici", self, DlgWin.onStay)
    btnStay:initialise()
    self:addChild(btnStay)

    -- [Fermer] button
    local btnClose = ISButton:new(220, 90, 80, 25, "Fermer", self, DlgWin.close)
    btnClose:initialise()
    self:addChild(btnClose)
end

function DlgWin:onFollow(btn)
    if self.npcData then
        self.npcData.followMode = true
    end
    self:close()
end

function DlgWin:onStay(btn)
    if self.npcData then
        self.npcData.followMode = false
        if self.npc then
            pcall(function()
                self.npc:getPathFindBehavior2():cancel()
                self.npc:setPath2(nil)
            end)
        end
    end
    self:close()
end

function DlgWin:close()
    NPC_DialogueWindow._instance = nil
    self:removeFromUIManager()
end

-- ============================================================
-- PUBLIC API
-- ============================================================

--- Open dialogue window for an NPC.
-- @param npc     IsoPlayer entity
-- @param npcData table from PHNPC.npcs registry
function NPC_DialogueWindow.open(npc, npcData)
    -- Close existing window if open
    if NPC_DialogueWindow._instance then
        pcall(function() NPC_DialogueWindow._instance:close() end)
    end
    local win = DlgWin:new(npc, npcData)
    win:initialise()
    win:addToUIManager()
    NPC_DialogueWindow._instance = win
end

print("[PHNPC] NPC_DialogueWindow loaded")