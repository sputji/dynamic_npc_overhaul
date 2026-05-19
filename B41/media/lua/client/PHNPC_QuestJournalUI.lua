--[[
    Project Humain : Dynamic_NPC_Overhaul
    PHNPC_QuestJournalUI.lua

    Fenetre minimale de journal de quetes SSR.
]]

pcall(require, "ISUI/ISCollapsableWindow")
pcall(require, "ISUI/ISScrollingListBox")
pcall(require, "ISUI/ISButton")
pcall(require, "ISUI/ISLabel")

local okInteraction, PHNPCInteractionClient = pcall(require, "NPCInteractionClient")
if not okInteraction then
    PHNPCInteractionClient = _G.PHNPCInteractionClient
end

PHNPCQuestJournalWindow = ISCollapsableWindow:derive("PHNPCQuestJournalWindow")

local function fmtQuestLine(q)
    local progress = math.max(0, tonumber(q and q.progress) or 0)
    local goal = math.max(1, tonumber(q and q.goal) or 1)
    local prefix = (q and q.completed == true) and "[OK] " or "[..] "
    return prefix .. tostring(q and q.title or "Quete") .. " - " .. tostring(progress) .. "/" .. tostring(goal)
end

function PHNPCQuestJournalWindow:new(x, y, width, height)
    local o = ISCollapsableWindow.new(self, x, y, width, height)
    o.title = "PHNPC - Journal de quetes"
    o.resizable = true
    o.moveWithMouse = true
    o.currentJournal = nil
    return o
end

function PHNPCQuestJournalWindow:initialise()
    ISCollapsableWindow.initialise(self)

    self.lblHint = ISLabel:new(12, 24, 18, "Journal SSR minimal", 0.9, 0.95, 1.0, 1, UIFont.Small, true)
    self.lblHint:initialise()
    self.lblHint:instantiate()
    self:addChild(self.lblHint)

    self.questList = ISScrollingListBox:new(10, 44, self.width - 20, self.height - 94)
    self.questList:initialise()
    self.questList:instantiate()
    self.questList.itemheight = 20
    self.questList.font = UIFont.Small
    self.questList.doDrawItem = function(list, y, item, alt)
        local bg = alt and 0.12 or 0.08
        list:drawRect(0, y, list:getWidth(), list.itemheight - 1, bg, 0.08, 0.08, 0.08)
        list:drawText(item.text, 8, y + 2, 0.92, 0.95, 1.0, 1.0, UIFont.Small)
        return y + list.itemheight
    end
    self:addChild(self.questList)

    self.btnRefresh = ISButton:new(10, self.height - 44, 100, 24, "Rafraichir", self, PHNPCQuestJournalWindow.onRefresh)
    self.btnRefresh:initialise()
    self.btnRefresh:instantiate()
    self:addChild(self.btnRefresh)

    self.btnReset = ISButton:new(118, self.height - 44, 100, 24, "Reset", self, PHNPCQuestJournalWindow.onReset)
    self.btnReset:initialise()
    self.btnReset:instantiate()
    self:addChild(self.btnReset)
end

function PHNPCQuestJournalWindow:onResize()
    ISCollapsableWindow.onResize(self)
    if self.questList then
        self.questList:setWidth(self.width - 20)
        self.questList:setHeight(self.height - 94)
    end
    if self.btnRefresh then
        self.btnRefresh:setY(self.height - 44)
    end
    if self.btnReset then
        self.btnReset:setY(self.height - 44)
    end
end

function PHNPCQuestJournalWindow:onRefresh()
    if PHNPCInteractionClient and PHNPCInteractionClient.requestQuestJournal then
        PHNPCInteractionClient:requestQuestJournal()
    end
end

function PHNPCQuestJournalWindow:onReset()
    if PHNPCInteractionClient and PHNPCInteractionClient.resetQuestJournal then
        PHNPCInteractionClient:resetQuestJournal()
    end
end

function PHNPCQuestJournalWindow:applyJournal(journal)
    self.currentJournal = journal or nil
    self.questList:clear()

    local quests = journal and journal.quests or {}
    if type(quests) ~= "table" or #quests == 0 then
        self.questList:addItem("Aucune quete disponible", { text = "Aucune quete disponible" })
        return
    end

    for i = 1, #quests do
        local q = quests[i]
        local line = fmtQuestLine(q)
        self.questList:addItem(line, { text = line, quest = q })
        if q and q.description then
            self.questList:addItem("  " .. tostring(q.description), { text = "  " .. tostring(q.description), quest = q })
        end
    end
end

local PHNPCQuestJournalUI = {
    window = nil
}

function PHNPCQuestJournalUI.open()
    if PHNPCQuestJournalUI.window and PHNPCQuestJournalUI.window:getIsVisible() then
        PHNPCQuestJournalUI.window:bringToTop()
    else
        local w = PHNPCQuestJournalWindow:new(160, 120, 420, 360)
        w:initialise()
        w:addToUIManager()
        w:setVisible(true)
        PHNPCQuestJournalUI.window = w
    end

    if PHNPCInteractionClient and PHNPCInteractionClient.lastQuestJournal then
        PHNPCQuestJournalUI.window:applyJournal(PHNPCInteractionClient.lastQuestJournal)
    end

    if PHNPCInteractionClient and PHNPCInteractionClient.requestQuestJournal then
        PHNPCInteractionClient:requestQuestJournal()
    end
end

if PHNPCInteractionClient and PHNPCInteractionClient.addListener then
    PHNPCInteractionClient:addListener("PHNPCQuestJournalUI", function(eventName, payload)
        if eventName ~= "QuestJournal" then
            return
        end
        if PHNPCQuestJournalUI.window and PHNPCQuestJournalUI.window:getIsVisible() then
            PHNPCQuestJournalUI.window:applyJournal(payload)
        end
    end)
end

_G.PHNPCQuestJournalUI = PHNPCQuestJournalUI

return PHNPCQuestJournalUI
