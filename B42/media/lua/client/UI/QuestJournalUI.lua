--[[
    Project Humain : Dynamic NPC Overhaul — B42
    client/UI/QuestJournalUI.lua

    Journal de quêtes : affiche les quêtes actives / terminées
    reçues des PNJ dynamiques.
    Hérite de ISPanel.
]]

if not isClient() then return end

local Log = PHNPC.getModule("NPC_Logger")

-- ============================================================
-- Registre des quêtes client
-- ============================================================
PHNPC.clientQuests = PHNPC.clientQuests or {}
-- { [questId] = { title, description, giverName, status="active"|"done"|"failed" } }

-- ============================================================
-- Classe QuestJournalUI
-- ============================================================

PHNPC_QuestJournalUI = ISPanel:derive("PHNPC_QuestJournalUI")

local WIN_W = 360
local WIN_H = 300
local PAD   = 8

function PHNPC_QuestJournalUI:new()
    local x = 20
    local y = 80
    local o = ISPanel.new(self, x, y, WIN_W, WIN_H)
    o.filter = "active"  -- "active" | "done" | "all"
    return o
end

function PHNPC_QuestJournalUI:initialise()
    ISPanel.initialise(self)

    -- Bouton fermer
    local btnClose = ISButton:new(WIN_W - 30, 4, 26, 22, "X", self, PHNPC_QuestJournalUI.close)
    btnClose:initialise() ; btnClose:instantiate()
    self:addChild(btnClose)

    -- Filtres
    local function addFilter(label, filter, bx)
        local btn = ISButton:new(bx, WIN_H - 34, 80, 26, label, self, function() self.filter = filter end)
        btn:initialise() ; btn:instantiate()
        self:addChild(btn)
    end
    addFilter("Actives", "active",  PAD)
    addFilter("Terminées","done",   PAD + 88)
    addFilter("Toutes",  "all",     PAD + 176)
end

function PHNPC_QuestJournalUI:render()
    ISPanel.render(self)
    self:drawRect(0, 0, WIN_W, 28, 0.85, 0.1, 0.1, 0.15)
    self:drawText("Journal de quêtes", PAD, 6, 1, 1, 0.6, 1, UIFont.Medium)

    local y = 36
    local count = 0
    for _, quest in pairs(PHNPC.clientQuests) do
        if self.filter == "all" or quest.status == self.filter then
            local color = { r=0.9, g=0.9, b=0.9 }
            if quest.status == "done"   then color = { r=0.4, g=0.9, b=0.4 } end
            if quest.status == "failed" then color = { r=0.9, g=0.4, b=0.4 } end
            self:drawText("■ " .. (quest.title or "?"), PAD, y, color.r, color.g, color.b, 1, UIFont.Small)
            y = y + 16
            self:drawText("  De : " .. (quest.giverName or "?"), PAD, y, 0.6, 0.6, 0.6, 1, UIFont.Small)
            y = y + 16
            if y > WIN_H - 50 then break end
            count = count + 1
        end
    end
    if count == 0 then
        self:drawText("Aucune quête.", PAD, y, 0.5, 0.5, 0.5, 1, UIFont.Small)
    end
end

function PHNPC_QuestJournalUI:close()
    self:setVisible(false)
    self:removeFromUIManager()
    _openJournal = nil
end

-- ============================================================
-- API module
-- ============================================================

local QuestJournalUI = {}
local _openJournal = nil

function QuestJournalUI.toggle()
    if _openJournal then
        _openJournal:close()
        _openJournal = nil
        return
    end
    local ui = PHNPC_QuestJournalUI:new()
    ui:initialise()
    ui:addToUIManager()
    _openJournal = ui
end

--- Ajoute ou met à jour une quête dans le registre client.
function QuestJournalUI.updateQuest(questData)
    if not questData or not questData.id then return end
    PHNPC.clientQuests[questData.id] = questData
end

-- Raccourci clavier : J pour ouvrir le journal
Events.OnKeyPressed.Add(function(key)
    if key == Keyboard.KEY_J then
        QuestJournalUI.toggle()
    end
end)

PHNPC.registerModule("QuestJournalUI", QuestJournalUI)
return QuestJournalUI
