--[[
    Project Humain : Dynamic_NPC_Overhaul
    NPC_UI.lua

    HUD client complet PNJ:
    - Tooltip immersif au survol
    - HUD Joueur (dialogue/troc) avec inventaire reel et quantites
    - HUD Admin separe avec sliders stats/personnalite
    - Mise a jour temps reel via retours serveur
]]


local okInteraction, PHNPCInteractionClient = pcall(require, "NPCInteractionClient")
if not okInteraction then
    PHNPCInteractionClient = _G.PHNPCInteractionClient
end

local okLogger, PHNPC_Logger = pcall(require, "PHNPC_Logger")
if not okLogger then
    PHNPC_Logger = _G.PHNPC_Logger
end

-- Initialise reseau multijoueur client (sync positions, animations, dialogues)
local okNetClient, NPC_NetworkClient = pcall(require, "NPC_NetworkClient")
if not okNetClient then
    NPC_NetworkClient = _G.NPC_NetworkClient
else
    _G.NPC_NetworkClient = NPC_NetworkClient
end

-- Optionnel: page de configuration via Mod Options (Build 41)
pcall(require, "PHNPC_ModOptionsUI")

pcall(require, "ISUI/ISPanel")
pcall(require, "ISUI/ISButton")
pcall(require, "ISUI/ISLabel")
pcall(require, "ISUI/ISScrollingListBox")
pcall(require, "ISUI/ISTextEntryBox")
pcall(require, "ISUI/ISComboBox")
pcall(require, "ISUI/ISCollapsableWindow")

local okTradeWindow, PHNPCTradeWindow = pcall(require, "PHNPC_TradeWindow")
if not okTradeWindow then
    PHNPCTradeWindow = _G.PHNPCTradeWindow
end

local okQuestJournal, PHNPCQuestJournalUI = pcall(require, "PHNPC_QuestJournalUI")
if not okQuestJournal then
    PHNPCQuestJournalUI = _G.PHNPCQuestJournalUI
end

pcall(require, "PHNPC_SpeechBubbles")

local okLocator, PHNPC_ClientNPCLocator = pcall(require, "PHNPC_ClientNPCLocator")
if not okLocator then
    PHNPC_ClientNPCLocator = _G.PHNPC_ClientNPCLocator
end

local PHNPCUI = {
    enabled = true,
    scanRange = 16,
    hoverScreenThreshold = 26,
    tooltipPadding = 8,
    tooltipLineHeight = 14,
    tooltipMaxWidth = 340,
    playerWindow = nil,
    adminWindow = nil,
    tooltipPanel = nil
}

local function clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

local function safe(value, fallback)
    if value == nil then
        return fallback or "?"
    end
    return tostring(value)
end

local function getLocalPlayer()
    if type(getSpecificPlayer) == "function" then
        return getSpecificPlayer(0)
    end
    return nil
end

local function isAdminPlayer(player)
    if not player then
        return false
    end

    if player.isAccessLevel and player:getAccessLevel() then
        local level = tostring(player:getAccessLevel()):lower()
        if level == "admin" or level == "moderator" or level == "gm" then
            return true
        end
    end

    if player.isAdmin and player:isAdmin() then
        return true
    end

    return false
end

local function sqDistance2D(x1, y1, x2, y2)
    local dx = x1 - x2
    local dy = y1 - y2
    return math.sqrt(dx * dx + dy * dy)
end

local function worldToScreen(x, y, z)
    if type(isoToScreenX) == "function" and type(isoToScreenY) == "function" then
        local okX, sx = pcall(isoToScreenX, 0, x, y, z)
        local okY, sy = pcall(isoToScreenY, 0, x, y, z)
        if okX and okY then
            return sx, sy
        end
    end
    return nil, nil
end

local function getMoodFromSnapshot(snapshot)
    local relation = snapshot and snapshot.relation or nil
    local state = snapshot and snapshot.state or ""

    if relation and relation.isFeared then
        return "Effraye"
    end
    if relation and (relation.isDangerous or relation.isHostile) then
        return "Hostile"
    end
    if relation and relation.isTrusted then
        return "Amical"
    end

    if state == "Combat" then
        return "Hostile"
    elseif state == "Flee" then
        return "Effraye"
    end

    return "Neutre"
end

local function buildHintsFromSnapshot(snapshot)
    local hints = {}
    local state = snapshot and snapshot.state or nil

    if state == "Survive" then
        hints[#hints + 1] = "Semble affame ou deshydrate"
    elseif state == "Combat" then
        hints[#hints + 1] = "A l'air agressif et pret a se battre"
    elseif state == "Flee" then
        hints[#hints + 1] = "Semble sous pression"
    elseif state == "Wander" then
        hints[#hints + 1] = "Observe la zone avec prudence"
    end

    local relation = snapshot and snapshot.relation or nil
    if relation then
        if relation.isTrusted then
            hints[#hints + 1] = "A l'air confiant envers vous"
        elseif relation.isFeared then
            hints[#hints + 1] = "Evite votre presence"
        elseif relation.isDangerous then
            hints[#hints + 1] = "Semble vous considerer comme un danger"
        end
    end

    local infStatus = snapshot and snapshot.infectionStatus or nil
    local infProgress = tonumber(snapshot and snapshot.infectionProgress or 0) or 0
    if infStatus == "leave_discreetly" then
        hints[#hints + 1] = "Parait vouloir s'isoler"
    elseif infStatus == "sudden_attack" then
        hints[#hints + 1] = "Degage une tension dangereuse"
    elseif infProgress >= 55 then
        hints[#hints + 1] = "A l'air pale et fatigue"
    end

    if #hints == 0 then
        hints[#hints + 1] = "Comportement difficile a lire"
    end

    return hints
end

local function aggregateInventory(player)
    local map = {}
    local out = {}
    if not player or not player.getInventory then
        return out
    end

    local inv = player:getInventory()
    if not inv or not inv.getItems then
        return out
    end

    local items = inv:getItems()
    if not items or not items.size then
        return out
    end

    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it and it.getFullType then
            local fullType = it:getFullType()
            map[fullType] = (map[fullType] or 0) + 1
        end
    end

    for fullType, qty in pairs(map) do
        out[#out + 1] = {
            itemType = fullType,
            quantity = qty,
            label = fullType .. " x" .. tostring(qty)
        }
    end

    table.sort(out, function(a, b)
        return a.label < b.label
    end)

    return out
end

local function getNpcFromWorldObjects(worldobjects)
    if type(worldobjects) ~= "table" then
        return nil
    end

    for i = 1, #worldobjects do
        local obj = worldobjects[i]
        local sq = obj and obj.getSquare and obj:getSquare() or nil
        if sq and sq.getMovingObjects then
            local moving = sq:getMovingObjects()
            if moving and moving.size then
                for j = 0, moving:size() - 1 do
                    local mo = moving:get(j)
                    if mo and mo.getModData then
                        local md = mo:getModData()
                        if md and md.PH_IsDynamicNPC == true then
                            return mo
                        end
                    end
                end
            end
        end
    end

    return nil
end

local function getNearestTaggedNpcForPlayer(player, maxDistance)
    if not player then
        return nil
    end

    local cell = getCell and getCell() or nil
    if not cell then
        return nil
    end

    local px = player:getX()
    local py = player:getY()
    local pz = math.floor(player.getZ and player:getZ() or 0)
    local maxDist = tonumber(maxDistance) or 3.0
    local maxDistSq = maxDist * maxDist

    local nearest = nil
    local nearestDistSq = maxDistSq

    local function tryEntity(entity)
        -- IsoFallingClothing et autres IsoObject Java n'exposent pas getX/getY ;
        -- instanceof(entity, IsoGameCharacter) filtre aux seuls zombies/joueurs valides.
        if not entity or not instanceof(entity, IsoGameCharacter) then
            return
        end

        local md = entity:getModData()
        if not md or md.PH_IsDynamicNPC ~= true then
            return
        end

        local ez = math.floor(entity:getZ())
        if ez ~= pz then
            return
        end

        local ex = entity:getX()
        local ey = entity:getY()
        if not ex or not ey then
            return
        end

        local dx = ex - px
        local dy = ey - py
        local distSq = (dx * dx) + (dy * dy)
        if distSq <= nearestDistSq then
            nearestDistSq = distSq
            nearest = entity
        end
    end

    local zlist = cell.getZombieList and cell:getZombieList() or nil
    if zlist and zlist.size then
        for i = 0, zlist:size() - 1 do
            tryEntity(zlist:get(i))
        end
    end

    local objects = cell.getObjectList and cell:getObjectList() or nil
    if objects and objects.size then
        for i = 0, objects:size() - 1 do
            local obj = objects:get(i)
            if obj then
                local okName, objectName = pcall(function()
                    return obj:getObjectName()
                end)
                if okName and objectName == "IsoPlayer" then
                    tryEntity(obj)
                end
            end
        end
    end

    return nil
end

local function getNpcId(entity)
    local md = entity and entity.getModData and entity:getModData() or nil
    return md and md.PH_NPCId or nil
end

local function getRawSnapshotFromEntity(entity)
    local md = entity and entity.getModData and entity:getModData() or nil
    local fsm = md and md.PH_FSM or nil
    if not fsm then
        return nil
    end

    return {
        npcId = md and md.PH_NPCId,
        state = fsm.state,
        activeOrder = fsm.activeOrder,
        socialRole = fsm.socialRole,
        survivalScore = fsm.survivalScore,
        factionId = fsm.factionId,
        infectionStatus = fsm.infectionStatus,
        infectionProgress = fsm.infectionProgress,
        relation = fsm.observedPlayer and {
            trust = fsm.observedPlayer.trust,
            fear = fsm.observedPlayer.fear,
            respect = fsm.observedPlayer.respect,
            gratitude = fsm.observedPlayer.gratitude,
            resentment = fsm.observedPlayer.resentment,
            reputation = fsm.observedPlayer.reputation,
            isTrusted = fsm.observedPlayer.trusted,
            isFeared = fsm.observedPlayer.feared,
            isDangerous = fsm.observedPlayer.dangerous
        } or nil
    }
end

local function isAlliedSnapshot(snapshot)
    local r = snapshot and snapshot.relation or nil
    return r and r.isTrusted == true and (r.trust or 0) >= 35
end

local function formatAdminPathMetrics(snapshot)
    local metrics = snapshot and snapshot.environmentMetrics or nil
    local mGlobal = metrics and metrics.perMinute or nil
    local mNpc = metrics and metrics.perMinuteNpc or nil
    local window = tonumber(metrics and metrics.windowSeconds or 60) or 60

    local gDoor = tonumber(mGlobal and mGlobal.path_opened_door or 0) or 0
    local gBarricade = tonumber(mGlobal and mGlobal.path_blocked_barricade or 0) or 0
    local gContour = tonumber(mGlobal and mGlobal.path_contour_fallback or 0) or 0

    local nDoor = tonumber(mNpc and mNpc.path_opened_door or 0) or 0
    local nBarricade = tonumber(mNpc and mNpc.path_blocked_barricade or 0) or 0
    local nContour = tonumber(mNpc and mNpc.path_contour_fallback or 0) or 0

    return string.format(
        "Path/%ds Global[D:%d B:%d C:%d] | PNJ[D:%d B:%d C:%d]",
        window,
        gDoor,
        gBarricade,
        gContour,
        nDoor,
        nBarricade,
        nContour
    )
end

local NPCSimpleSlider = ISPanel:derive("NPCSimpleSlider")

function NPCSimpleSlider:new(x, y, w, h, title, value)
    local o = ISPanel.new(self, x, y, w, h)
    o.title = title or ""
    o.value = clamp(math.floor(value or 50), 0, 100)
    o.dragging = false
    o.onValueChanged = nil
    o.backgroundColor = { r = 0.06, g = 0.06, b = 0.06, a = 0.8 }
    o.borderColor = { r = 0.6, g = 0.6, b = 0.6, a = 0.9 }
    return o
end

function NPCSimpleSlider:prerender()
    self:drawRect(0, 0, self.width, self.height, self.backgroundColor.a, self.backgroundColor.r, self.backgroundColor.g, self.backgroundColor.b)
    self:drawRectBorder(0, 0, self.width, self.height, self.borderColor.a, self.borderColor.r, self.borderColor.g, self.borderColor.b)

    local label = self.title .. " : " .. tostring(math.floor(self.value))
    self:drawText(label, 6, 2, 1, 1, 1, 1, UIFont.Small)

    local trackX = 8
    local trackY = self.height - 10
    local trackW = self.width - 16
    self:drawRect(trackX, trackY, trackW, 3, 0.9, 0.2, 0.2, 0.2)

    local knobX = trackX + math.floor((self.value / 100) * trackW)
    self:drawRect(knobX - 3, trackY - 3, 6, 9, 1.0, 0.8, 0.8, 0.2)
end

function NPCSimpleSlider:setFromMouse(x)
    local trackX = 8
    local trackW = self.width - 16
    local localX = clamp(x - trackX, 0, trackW)
    local v = math.floor((localX / trackW) * 100)
    self.value = clamp(v, 0, 100)
    if self.onValueChanged then
        self.onValueChanged(self, self.value)
    end
end

function NPCSimpleSlider:onMouseDown(x, y)
    self.dragging = true
    self:setFromMouse(x)
    return true
end

function NPCSimpleSlider:onMouseMove(dx, dy)
    if self.dragging then
        local mx = self:getMouseX()
        self:setFromMouse(mx)
    end
end

function NPCSimpleSlider:onMouseUp(x, y)
    self.dragging = false
    return true
end

local NPCPlayerHUD = ISCollapsableWindow:derive("NPCPlayerHUD")

function NPCPlayerHUD:new(npcId)
    local o = ISCollapsableWindow.new(self, 110, 120, 560, 760)
    o.title = "HUD Commandes metier"
    o.npcId = npcId
    o.snapshot = nil
    o.statusText = ""
    o.inventoryRows = {}
    o.selectedItem = nil
    o.selectedTacticalProfile = "follow"
    o.strictCapacityCheck = true
    o.actionHistory = {}
    o.globalStartTick = os.time()
    o.lastSavedProfile = nil
    o.businessMode = "craft"
    o.pendingBusinessQuote = nil
    o.pendingBusinessRequest = nil
    o.businessTargetCategory = "materials"
    o.businessTargetItem = nil
    o.statusColor = { r = 0.8, g = 0.95, b = 0.85, a = 1.0 }
    o.backgroundColor = { r = 0.05, g = 0.06, b = 0.07, a = 0.92 }
    o.borderColor = { r = 0.36, g = 0.50, b = 0.62, a = 0.92 }
    o.resizable = true
    o.pin = true
    return o
end

function NPCPlayerHUD:prerender()
    ISCollapsableWindow.prerender(self)

    -- Sections visuelles claires: Dialogue, Troc, Ordres
    self:drawRect(8, 150, self.width - 16, 210, 0.12, 0.10, 0.12, 0.14)
    self:drawRectBorder(8, 150, self.width - 16, 210, 0.45, 0.36, 0.50, 0.62)
    self:drawText("1) DIALOGUE", 14, 152, 0.78, 0.90, 1.0, 1.0, UIFont.Small)

    self:drawRect(8, 548, self.width - 16, 186, 0.12, 0.10, 0.12, 0.14)
    self:drawRectBorder(8, 548, self.width - 16, 186, 0.45, 0.36, 0.50, 0.62)
    self:drawText("2) TROC / METIER", 14, 550, 0.78, 0.90, 1.0, 1.0, UIFont.Small)

    self:drawRect(8, 376, self.width - 16, 168, 0.12, 0.10, 0.12, 0.14)
    self:drawRectBorder(8, 376, self.width - 16, 168, 0.45, 0.36, 0.50, 0.62)
    self:drawText("3) ORDRES", 14, 378, 0.78, 0.90, 1.0, 1.0, UIFont.Small)
end

function NPCPlayerHUD:initialise()
    ISCollapsableWindow.initialise(self)

    self.lblNpc = ISLabel:new(12, 28, 18, "PNJ: " .. safe(self.npcId), 1, 1, 1, 1, UIFont.Small, true)
    self:addChild(self.lblNpc)

    self.lblFaction = ISLabel:new(12, 48, 18, "Faction: ?", 0.9, 0.9, 0.9, 1, UIFont.Small, true)
    self:addChild(self.lblFaction)

    self.lblMood = ISLabel:new(12, 66, 18, "Humeur: ?", 0.9, 0.9, 0.9, 1, UIFont.Small, true)
    self:addChild(self.lblMood)

    self.lblRelation = ISLabel:new(12, 84, 18, "Relation: ?", 0.85, 0.85, 0.85, 1, UIFont.Small, true)
    self:addChild(self.lblRelation)

    self.lblHints = ISLabel:new(12, 104, 18, "Indices:", 0.95, 0.95, 0.75, 1, UIFont.Small, true)
    self:addChild(self.lblHints)

    self.lblHelp = ISLabel:new(12, 120, 18, "Workflow metier: 1) Type  2) Devis  3) Validation", 0.70, 0.86, 1.0, 1, UIFont.Small, true)
    self:addChild(self.lblHelp)

    self.lblProfession = ISLabel:new(12, 136, 18, "Metier: inconnu", 0.88, 0.92, 0.72, 1, UIFont.Small, true)
    self:addChild(self.lblProfession)

    self.list = ISScrollingListBox:new(12, 166, self.width - 24, 156)
    self.list:initialise()
    self.list:instantiate()
    self.list.itemheight = 20
    self.list.font = UIFont.Small
    self.list.drawBorder = true
    self.list.doDrawItem = function(list, y, item, alt)
        local a = alt and 0.15 or 0.08
        list:drawRect(0, y, list:getWidth(), list.itemheight, a, 0.2, 0.2, 0.2)
        list:drawText(item.text, 8, y + 2, 0.96, 0.96, 0.96, 1, UIFont.Small)
        return y + list.itemheight
    end
    self:addChild(self.list)

    self.qtyEntry = ISTextEntryBox:new("1", 12, 330, 50, 22)
    self.qtyEntry:initialise()
    self.qtyEntry:instantiate()
    self:addChild(self.qtyEntry)

    self.btnTalk = ISButton:new(70, 330, 140, 22, "Parler (chat)", self, NPCPlayerHUD.onTalk)
    self.btnTalk:initialise()
    self.btnTalk:instantiate()
    self:addChild(self.btnTalk)

    self.btnChatAI = ISButton:new(216, 330, 110, 22, "Infos PNJ", self, NPCPlayerHUD.onChatAI)
    self.btnChatAI:initialise()
    self.btnChatAI:instantiate()
    self:addChild(self.btnChatAI)

    self.btnGift = ISButton:new(332, 330, 96, 22, "Don", self, NPCPlayerHUD.onGift)
    self.btnGift:initialise()
    self.btnGift:instantiate()
    self:addChild(self.btnGift)

    self.btnOrder = ISButton:new(432, 330, 102, 22, "Ordre", self, NPCPlayerHUD.onOrder)
    self.btnOrder:initialise()
    self.btnOrder:instantiate()
    self:addChild(self.btnOrder)

    self.btnRefresh = ISButton:new(486, 330, 50, 22, "MAJ", self, NPCPlayerHUD.onRefresh)
    self.btnRefresh:initialise()
    self.btnRefresh:instantiate()
    self:addChild(self.btnRefresh)

    self.btnTradeAdvanced = ISButton:new(12, 356, 160, 22, "Commerce avance", self, NPCPlayerHUD.onOpenAdvancedTrade)
    self.btnTradeAdvanced:initialise()
    self.btnTradeAdvanced:instantiate()
    self:addChild(self.btnTradeAdvanced)

    self.lblStatus = ISLabel:new(12, 360, 18, "", 0.8, 0.95, 0.85, 1, UIFont.Small, true)
    self:addChild(self.lblStatus)

    self.btnStrictCapacity = ISButton:new(354, 356, 152, 22, "Capacite stricte: ON", self, NPCPlayerHUD.onToggleStrictCapacity)
    self.btnStrictCapacity:initialise()
    self.btnStrictCapacity:instantiate()
    self:addChild(self.btnStrictCapacity)

    self.lblTactic = ISLabel:new(12, 382, 18, "Profil tactique: Suivre", 0.85, 0.9, 1.0, 1, UIFont.Small, true)
    self:addChild(self.lblTactic)

    self.btnTacticFollow = ISButton:new(12, 402, 118, 22, "Suivre", self, NPCPlayerHUD.onTacticFollow)
    self.btnTacticFollow:initialise()
    self.btnTacticFollow:instantiate()
    self:addChild(self.btnTacticFollow)

    self.btnTacticDistance = ISButton:new(136, 402, 118, 22, "Garder distance", self, NPCPlayerHUD.onTacticKeepDistance)
    self.btnTacticDistance:initialise()
    self.btnTacticDistance:instantiate()
    self:addChild(self.btnTacticDistance)

    self.btnTacticCover = ISButton:new(260, 402, 92, 22, "Couvrir", self, NPCPlayerHUD.onTacticCover)
    self.btnTacticCover:initialise()
    self.btnTacticCover:instantiate()
    self:addChild(self.btnTacticCover)

    self.targetHintEntry = ISTextEntryBox:new("food", 358, 402, 80, 22)
    self.targetHintEntry:initialise()
    self.targetHintEntry:instantiate()
    self:addChild(self.targetHintEntry)

    self.btnTacticLoot = ISButton:new(442, 402, 64, 22, "Loot cible", self, NPCPlayerHUD.onTacticLootTarget)
    self.btnTacticLoot:initialise()
    self.btnTacticLoot:instantiate()
    self:addChild(self.btnTacticLoot)

    self.btnPresetEscort = ISButton:new(12, 430, 160, 22, "Escort defensive", self, NPCPlayerHUD.onPresetDefensiveEscort)
    self.btnPresetEscort:initialise()
    self.btnPresetEscort:instantiate()
    self:addChild(self.btnPresetEscort)

    self.btnPresetLoot = ISButton:new(178, 430, 160, 22, "Pillage discret", self, NPCPlayerHUD.onPresetDiscreetLoot)
    self.btnPresetLoot:initialise()
    self.btnPresetLoot:instantiate()
    self:addChild(self.btnPresetLoot)

    self.btnPresetCover = ISButton:new(344, 430, 162, 22, "Couverture agressive", self, NPCPlayerHUD.onPresetAggressiveCover)
    self.btnPresetCover:initialise()
    self.btnPresetCover:instantiate()
    self:addChild(self.btnPresetCover)

    self.lblActionLog = ISLabel:new(12, 458, 18, "Journal actions (5):", 0.9, 0.9, 1.0, 1, UIFont.Small, true)
    self:addChild(self.lblActionLog)

    self.logList = ISScrollingListBox:new(12, 478, self.width - 24, 72)
    self.logList:initialise()
    self.logList:instantiate()
    self.logList.itemheight = 16
    self.logList.font = UIFont.Small
    self.logList.drawBorder = true
    self.logList.doDrawItem = function(list, y, item, alt)
        local it = item.item or {}
        local a = alt and 0.15 or 0.08
        list:drawRect(0, y, list:getWidth(), list.itemheight, a, 0.2, 0.2, 0.2)

        local r, g, b = 0.85, 0.9, 1.0
        if it.kind == "error" then
            r, g, b = 1.0, 0.45, 0.45
        elseif it.kind == "success" then
            r, g, b = 0.45, 1.0, 0.45
        elseif it.kind == "warn" then
            r, g, b = 1.0, 0.85, 0.35
        end

        list:drawText(item.text, 8, y + 1, r, g, b, 1, UIFont.Small)
        return y + list.itemheight
    end
    self:addChild(self.logList)

    self.lblBusiness = ISLabel:new(12, 558, 18, "Etape 1 - Type de commande: Fabrication", 0.95, 0.9, 0.8, 1, UIFont.Small, true)
    self:addChild(self.lblBusiness)

    self.btnBusinessCraft = ISButton:new(12, 580, 76, 22, "Fabriquer", self, NPCPlayerHUD.onBusinessCraft)
    self.btnBusinessCraft:initialise()
    self.btnBusinessCraft:instantiate()
    self:addChild(self.btnBusinessCraft)

    self.btnBusinessBuild = ISButton:new(94, 580, 80, 22, "Construire", self, NPCPlayerHUD.onBusinessBuild)
    self.btnBusinessBuild:initialise()
    self.btnBusinessBuild:instantiate()
    self:addChild(self.btnBusinessBuild)

    self.btnBusinessBuy = ISButton:new(180, 580, 64, 22, "Acheter", self, NPCPlayerHUD.onBusinessBuy)
    self.btnBusinessBuy:initialise()
    self.btnBusinessBuy:instantiate()
    self:addChild(self.btnBusinessBuy)

    self.btnBusinessQuote = ISButton:new(250, 580, 120, 22, "2) Demander devis", self, NPCPlayerHUD.onBusinessQuote)
    self.btnBusinessQuote:initialise()
    self.btnBusinessQuote:instantiate()
    self:addChild(self.btnBusinessQuote)

    self.btnBusinessConfirm = ISButton:new(376, 580, 132, 22, "3) Valider", self, NPCPlayerHUD.onBusinessConfirm)
    self.btnBusinessConfirm:initialise()
    self.btnBusinessConfirm:instantiate()
    self:addChild(self.btnBusinessConfirm)

    self.lblBusinessTarget = ISLabel:new(12, 610, 18, "Selection metier: cible", 0.9, 0.9, 1.0, 1, UIFont.Small, true)
    self:addChild(self.lblBusinessTarget)

    self.businessTargetList = ISScrollingListBox:new(12, 632, self.width - 24, 84)
    self.businessTargetList:initialise()
    self.businessTargetList:instantiate()
    self.businessTargetList.itemheight = 20
    self.businessTargetList.font = UIFont.Small
    self.businessTargetList.drawBorder = true
    self.businessTargetList.doDrawItem = function(list, y, item, alt)
        local a = alt and 0.15 or 0.08
        list:drawRect(0, y, list:getWidth(), list.itemheight, a, 0.2, 0.2, 0.2)
        list:drawText(item.text, 8, y + 2, 0.95, 0.95, 0.95, 1, UIFont.Small)
        return y + list.itemheight
    end
    self:addChild(self.businessTargetList)

    self.lblBusinessQuote = ISLabel:new(12, 724, 18, "Prix: -- | attente du devis", 0.85, 1.0, 0.85, 1, UIFont.Small, true)
    self:addChild(self.lblBusinessQuote)

    self:refreshBusinessTargets()

    self:refreshPlayerInventory()
    if PHNPCInteractionClient then
        PHNPCInteractionClient:requestNpcSnapshot(self.npcId)
    end
    
    if self.lastSavedProfile then
        self:setTacticalProfile(self.lastSavedProfile, self:getTacticalProfileLabel(self.lastSavedProfile))
    end
end

function NPCPlayerHUD:onResize()
    ISCollapsableWindow.onResize(self)
    if self.list then
        self.list:setWidth(self.width - 24)
    end
    if self.logList then
        self.logList:setWidth(self.width - 24)
    end
    if self.businessTargetList then
        self.businessTargetList:setWidth(self.width - 24)
    end
end

function NPCPlayerHUD:getElapsedTimeLabel()
    local elapsed = os.time() - self.globalStartTick
    if elapsed < 60 then
        return "T+" .. tostring(elapsed) .. "s"
    end
    local mins = math.floor(elapsed / 60)
    local secs = elapsed % 60
    return "T+" .. tostring(mins) .. "m" .. tostring(secs) .. "s"
end

function NPCPlayerHUD:setStatus(message, kind)
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

    self.lblStatus:setName(message or "")
    if self.lblStatus.setColor then
        self.lblStatus:setColor(r, g, b, 1.0)
    end
end

function NPCPlayerHUD:pushActionLog(text, kind)
    local timeLabel = self:getElapsedTimeLabel()
    local entry = {
        text = "[" .. timeLabel .. "] " .. tostring(text or ""),
        kind = kind or "info"
    }

    table.insert(self.actionHistory, 1, entry)
    while #self.actionHistory > 5 do
        table.remove(self.actionHistory, #self.actionHistory)
    end

    if not self.logList then
        return
    end

    self.logList:clear()
    for i = 1, #self.actionHistory do
        local row = self.actionHistory[i]
        self.logList:addItem(row.text, row)
    end
end

function NPCPlayerHUD:refreshBusinessTargets()
    if not self.businessTargetList then
        return
    end

    local selectedText = nil
    local selectedCategory = nil
    local selectedItem = nil
    if self.businessTargetList.items and self.businessTargetList.selected and self.businessTargetList.items[self.businessTargetList.selected] then
        local current = self.businessTargetList.items[self.businessTargetList.selected].item
        selectedText = current and current.text or nil
        selectedCategory = current and current.category or nil
        selectedItem = current and current.itemType or nil
    end

    self.businessTargetList:clear()

    local options = {
        { text = "Categorie: materiaux", category = "materials", itemType = nil },
        { text = "Categorie: outils", category = "tools", itemType = nil },
        { text = "Categorie: nourriture", category = "food", itemType = nil },
        { text = "Categorie: eau", category = "water", itemType = nil },
        { text = "Categorie: soins", category = "medicine", itemType = nil },
        { text = "Categorie: objets generaux", category = "general_goods", itemType = nil }
    }

    local seen = {}
    for i = 1, #options do
        local row = options[i]
        self.businessTargetList:addItem(row.text, row)
        seen[row.category .. ":" .. (row.itemType or "")] = true
    end

    for i = 1, #self.inventoryRows do
        local row = self.inventoryRows[i]
        local fullType = row.itemType
        if fullType and not seen["item:" .. fullType] then
            local entry = { text = "Objet: " .. tostring(fullType) .. " x" .. tostring(row.quantity or 1), category = nil, itemType = fullType }
            self.businessTargetList:addItem(entry.text, entry)
            seen["item:" .. fullType] = true
        end
    end

    if self.businessTargetList.items and #self.businessTargetList.items > 0 then
        self.businessTargetList.selected = 1
        if selectedText then
            for i = 1, #self.businessTargetList.items do
                local current = self.businessTargetList.items[i].item
                if current and current.text == selectedText then
                    self.businessTargetList.selected = i
                    break
                end
            end
        end
    end

    local selected = self:getBusinessTargetSelection()
    self.businessTargetCategory = selected and selected.category or selectedCategory or "materials"
    self.businessTargetItem = selected and selected.itemType or selectedItem or nil
end

function NPCPlayerHUD:getBusinessTargetSelection()
    if not self.businessTargetList or not self.businessTargetList.items or not self.businessTargetList.selected then
        return nil
    end

    local row = self.businessTargetList.items[self.businessTargetList.selected]
    return row and row.item or nil
end

function NPCPlayerHUD:getElapsedTimeLabel()
    local elapsed = os.time() - self.globalStartTick
    if elapsed < 60 then
        return "T+" .. tostring(elapsed) .. "s"
    end
    local mins = math.floor(elapsed / 60)
    local secs = elapsed % 60
    return "T+" .. tostring(mins) .. "m" .. tostring(secs) .. "s"
end

function NPCPlayerHUD:pushActionLog(text, kind)
    local timeLabel = self:getElapsedTimeLabel()
    local entry = {
        text = "[" .. timeLabel .. "] " .. tostring(text or ""),
        kind = kind or "info"
    }

    table.insert(self.actionHistory, 1, entry)
    while #self.actionHistory > 5 do
        table.remove(self.actionHistory, #self.actionHistory)
    end

    if not self.logList then
        return
    end

    self.logList:clear()
    for i = 1, #self.actionHistory do
        local row = self.actionHistory[i]
        self.logList:addItem(row.text, row)
    end
end

function NPCPlayerHUD:refreshPlayerInventory()
    self.list:clear()
    self.inventoryRows = aggregateInventory(getLocalPlayer())
    for i = 1, #self.inventoryRows do
        local row = self.inventoryRows[i]
        self.list:addItem(row.label, row)
    end
    self:refreshBusinessTargets()
end

function NPCPlayerHUD:updateFromSnapshot(snapshot)
    if not snapshot or snapshot.npcId ~= self.npcId then
        return
    end

    self.snapshot = snapshot

    if self.lblNpc then
        self.lblNpc:setName("PNJ: " .. safe(snapshot.displayName or snapshot.npcId))
    end

    self.lblFaction:setName("Faction: " .. safe(snapshot.factionId, "Solo"))
    self.lblMood:setName("Humeur: " .. getMoodFromSnapshot(snapshot))

    local rel = snapshot.relation or {}
    local relText = "Relation tr=" .. safe(rel.trust, "?")
        .. " fr=" .. safe(rel.fear, "?")
        .. " rep=" .. safe(rel.reputation, "?")
    self.lblRelation:setName(relText)

    local prof = snapshot.profession or {}
    local hasProfession = prof.hasProfession == true
    local role = tostring(prof.label or prof.role or "sans metier")
    local lvl = tonumber(prof.level or 0) or 0
    local maxLvl = tonumber(prof.maxLevel or 10) or 10
    local unlockText = (prof.unlocked == true) and "debloque" or "verrouille"
    if self.lblProfession then
        if hasProfession then
            self.lblProfession:setName(string.format("Metier: %s (%d/%d, %s)", role, lvl, maxLvl, unlockText))
        else
            self.lblProfession:setName("Metier: aucun")
        end
    end

    local hints = buildHintsFromSnapshot(snapshot)
    self.lblHints:setName("Indices: " .. table.concat(hints, " | "))

    self.btnOrder:setEnable(isAlliedSnapshot(snapshot) == true)
    
    if snapshot.lastTacticalProfile then
        local label = self:getTacticalProfileLabel(snapshot.lastTacticalProfile)
        self:setTacticalProfile(snapshot.lastTacticalProfile, label)
    end
end

function NPCPlayerHUD:onTalk()
    local okChatUI, OllamaChatUI = pcall(require, "OllamaChatUI")
    if okChatUI and OllamaChatUI and OllamaChatUI.openChatWindow then
        OllamaChatUI:openChatWindow(self.npcId)
        self:setStatus("Petit chat ouvert", "success")
    else
        self:setStatus("Chat indisponible", "error")
    end
end

function NPCPlayerHUD:onChatAI()
    if PHNPCInteractionClient and type(PHNPCInteractionClient.requestIntel) == "function" then
        PHNPCInteractionClient:requestIntel(self.npcId)
        self:setStatus("Demande d'informations envoyee", "info")
    else
        self:setStatus("Client interaction indisponible", "error")
    end
end

function NPCPlayerHUD:onGift()
    if not PHNPCInteractionClient then
        return
    end

    local item = self.list.selected and self.list.items[self.list.selected] and self.list.items[self.list.selected].item or nil
    if not item or not item.itemType then
        self:setStatus("Selectionnez un objet a donner", "warn")
        return
    end

    local qty = tonumber(self.qtyEntry:getText()) or 1
    qty = clamp(math.floor(qty), 1, item.quantity or 1)

    PHNPCInteractionClient:sendTradeEvent(self.npcId, "gift", {
        value = qty * 8,
        itemType = item.itemType,
        quantity = qty,
        strictCapacity = self.strictCapacityCheck == true,
        requested = "hud_gift"
    })

    self:setStatus("Don envoye: " .. item.itemType .. " x" .. tostring(qty), "info")
end

function NPCPlayerHUD:setBusinessMode(mode, label)
    self.businessMode = mode or "craft"
    if self.lblBusiness then
        self.lblBusiness:setName("Etape 1 - Type de commande: " .. tostring(label or self.businessMode))
    end
    self.pendingBusinessQuote = nil
    self.pendingBusinessRequest = nil
    if self.lblBusinessQuote then
        self.lblBusinessQuote:setName("Prix: -- | attente du devis")
    end
end

function NPCPlayerHUD:onBusinessCraft()
    self:setBusinessMode("craft", "Fabrication")
end

function NPCPlayerHUD:onBusinessBuild()
    self:setBusinessMode("build", "Construction")
end

function NPCPlayerHUD:onBusinessBuy()
    self:setBusinessMode("buy", "Achat")
end

function NPCPlayerHUD:getBusinessContext()
    local qty = tonumber(self.qtyEntry and self.qtyEntry:getText() or "1") or 1
    qty = clamp(math.floor(qty), 1, 999)
    local targetSelection = self:getBusinessTargetSelection() or {}
    local target = targetSelection.itemType or targetSelection.category or self.businessTargetCategory or "materials"
    return {
        serviceType = self.businessMode or "craft",
        itemType = target,
        quantity = qty,
        targetHint = targetSelection.text or target,
        marketCategory = targetSelection.category or self.businessTargetCategory or "materials",
        buildSiteId = self.pendingBusinessQuote and self.pendingBusinessQuote.buildSiteId or nil,
        baseId = self.pendingBusinessQuote and self.pendingBusinessQuote.baseId or nil,
        marketCategory = self.pendingBusinessQuote and self.pendingBusinessQuote.marketCategory or targetSelection.category or self.businessTargetCategory,
        price = self.pendingBusinessQuote and self.pendingBusinessQuote.cost or nil,
        quote = self.pendingBusinessQuote
    }
end

function NPCPlayerHUD:requestBusinessQuote()
    if not PHNPCInteractionClient or type(PHNPCInteractionClient.requestBusinessQuote) ~= "function" then
        if PHNPC_Logger and PHNPC_Logger.error then
            PHNPC_Logger:error("NPC_UI", "requestBusinessQuote", "PHNPCInteractionClient missing", {
                npcId = self.npcId
            })
        end
        return
    end

    local ctx = self:getBusinessContext()
    self.pendingBusinessRequest = ctx

    if PHNPC_Logger and PHNPC_Logger.info then
        PHNPC_Logger:info("NPC_UI", "requestBusinessQuote", "Requesting business quote", {
            npcId = self.npcId,
            serviceType = ctx and ctx.serviceType,
            itemType = ctx and ctx.itemType,
            quantity = ctx and ctx.quantity
        })
    end

    local okCall, err = pcall(function()
        PHNPCInteractionClient:requestBusinessQuote(self.npcId, ctx.serviceType, ctx)
    end)
    if not okCall then
        if PHNPC_Logger and PHNPC_Logger.error then
            PHNPC_Logger:error("NPC_UI", "requestBusinessQuote", "requestBusinessQuote call failed", {
                npcId = self.npcId,
                error = tostring(err)
            })
        end
        self:setStatus("Erreur devis: voir logs", "error")
        return
    end

    self:setStatus("Devis demande pour " .. tostring(ctx.serviceType), "info")
end

function NPCPlayerHUD:onBusinessQuote()
    self:requestBusinessQuote()
end

function NPCPlayerHUD:confirmBusinessOrder()
    if not PHNPCInteractionClient or type(PHNPCInteractionClient.sendBusinessOrder) ~= "function" then
        self:setStatus("Client interaction indisponible", "error")
        return
    end

    local quote = self.pendingBusinessQuote
    if not quote then
        self:setStatus("Demandez d'abord un devis", "warn")
        return
    end

    local ctx = self.pendingBusinessRequest or self:getBusinessContext()
    ctx.quote = quote
    PHNPCInteractionClient:sendBusinessOrder(self.npcId, ctx.serviceType, ctx)
    self:setStatus("Commande metier envoyee", "info")
end

function NPCPlayerHUD:onBusinessConfirm()
    self:confirmBusinessOrder()
end

function NPCPlayerHUD:onOrder()
    if not PHNPCInteractionClient then
        return
    end

    if self.selectedTacticalProfile == "keep_distance" then
        PHNPCInteractionClient:sendOrderAction(self.npcId, "tactical_keep_distance", {
            desiredDistance = 7,
            maxDistance = 12
        })
        self:setStatus("Ordre tactique: garder distance", "info")
    elseif self.selectedTacticalProfile == "cover" then
        PHNPCInteractionClient:sendOrderAction(self.npcId, "tactical_cover", {
            coverRadius = 6
        })
        self:setStatus("Ordre tactique: couvrir", "info")
    elseif self.selectedTacticalProfile == "loot_target" then
        local hint = self.targetHintEntry and self.targetHintEntry:getText() or ""
        PHNPCInteractionClient:sendOrderAction(self.npcId, "tactical_loot_target", {
            targetItemHint = hint
        })
        self:setStatus("Ordre tactique: loot cible (" .. tostring(hint) .. ")", "info")
    elseif self.selectedTacticalProfile == "preset_defensive_escort" then
        PHNPCInteractionClient:sendOrderAction(self.npcId, "tactical_preset_defensive_escort", {})
        self:setStatus("Preset: escort defensive", "info")
    elseif self.selectedTacticalProfile == "preset_discreet_loot" then
        local hint = self.targetHintEntry and self.targetHintEntry:getText() or "food"
        PHNPCInteractionClient:sendOrderAction(self.npcId, "tactical_preset_discreet_loot", {
            targetItemHint = hint
        })
        self:setStatus("Preset: pillage discret", "info")
    elseif self.selectedTacticalProfile == "preset_aggressive_cover" then
        PHNPCInteractionClient:sendOrderAction(self.npcId, "tactical_preset_aggressive_cover", {})
        self:setStatus("Preset: couverture agressive", "info")
    else
        PHNPCInteractionClient:sendOrderAction(self.npcId, "follow", {})
        self:setStatus("Ordre: suivre", "info")
    end
end

function NPCPlayerHUD:onRefresh()
    self:refreshPlayerInventory()
    if PHNPCInteractionClient then
        PHNPCInteractionClient:requestNpcSnapshot(self.npcId)
    end
end

function NPCPlayerHUD:onOpenAdvancedTrade()
    if PHNPCTradeWindow and PHNPCTradeWindow.open then
        PHNPCTradeWindow.open(self.npcId)
        self:setStatus("Fenetre commerce avance ouverte", "info")
    else
        self:setStatus("Commerce avance indisponible", "error")
    end
end

function NPCPlayerHUD:onToggleStrictCapacity()
    self.strictCapacityCheck = not (self.strictCapacityCheck == true)
    if self.btnStrictCapacity and self.btnStrictCapacity.setTitle then
        self.btnStrictCapacity:setTitle(self.strictCapacityCheck and "Capacite stricte: ON" or "Capacite stricte: OFF")
    end
    self:setStatus("Verification capacite: " .. (self.strictCapacityCheck and "activee" or "desactivee"), "info")
end

function NPCPlayerHUD:setTacticalProfile(profile, label)
    self.selectedTacticalProfile = profile
    self.lblTactic:setName("Profil tactique: " .. tostring(label))
    self.lastSavedProfile = profile
end

function NPCPlayerHUD:onTacticFollow()
    self:setTacticalProfile("follow", "Suivre")
end

function NPCPlayerHUD:onTacticKeepDistance()
    self:setTacticalProfile("keep_distance", "Garder distance")
end

function NPCPlayerHUD:onTacticCover()
    self:setTacticalProfile("cover", "Couvrir")
end

function NPCPlayerHUD:onTacticLootTarget()
    self:setTacticalProfile("loot_target", "Loot cible")
end

function NPCPlayerHUD:onPresetDefensiveEscort()
    self:setTacticalProfile("preset_defensive_escort", "Escort defensive")
end

function NPCPlayerHUD:onPresetDiscreetLoot()
    self:setTacticalProfile("preset_discreet_loot", "Pillage discret")
end

function NPCPlayerHUD:onPresetAggressiveCover()
    self:setTacticalProfile("preset_aggressive_cover", "Couverture agressive")
end

function NPCPlayerHUD:getTacticalProfileLabel(profile)
    if profile == "follow" then return "Suivre"
    elseif profile == "keep_distance" then return "Garder distance"
    elseif profile == "cover" then return "Couvrir"
    elseif profile == "loot_target" then return "Loot cible"
    elseif profile == "preset_defensive_escort" then return "Escort defensive"
    elseif profile == "preset_discreet_loot" then return "Pillage discret"
    elseif profile == "preset_aggressive_cover" then return "Couverture agressive"
    end
    return "Suivre"
end

local NPCAdminHUD = ISCollapsableWindow:derive("NPCAdminHUD")

function NPCAdminHUD:new(npcId)
    local o = ISCollapsableWindow.new(self, 660, 90, 460, 700)
    o.title = "HUD ADMIN PNJ"
    o.npcId = npcId
    o.snapshot = nil
    o.statsSliders = {}
    o.personalitySliders = {}
    o.resizable = true
    o.pin = true
    return o
end

function NPCAdminHUD:addSliderBlock(title, y)
    local lbl = ISLabel:new(12, y, 18, title, 1, 0.9, 0.7, 1, UIFont.Medium, true)
    self:addChild(lbl)
    return y + 22
end

function NPCAdminHUD:addSlider(name, y, list)
    local s = NPCSimpleSlider:new(12, y, self.width - 24, 36, name, 50)
    s:initialise()
    s:instantiate()
    self:addChild(s)
    list[name] = s
    return y + 40
end

function NPCAdminHUD:initialise()
    ISCollapsableWindow.initialise(self)

    self.lblNpc = ISLabel:new(12, 28, 18, "PNJ: " .. safe(self.npcId), 1, 1, 1, 1, UIFont.Small, true)
    self:addChild(self.lblNpc)

    self.lblState = ISLabel:new(12, 46, 18, "Etat: ?", 0.9, 0.9, 0.9, 1, UIFont.Small, true)
    self:addChild(self.lblState)

    self.lblPathMetrics = ISLabel:new(12, 64, 18, "Path/60s Global[D:0 B:0 C:0] | PNJ[D:0 B:0 C:0]", 0.85, 0.9, 1.0, 1, UIFont.Small, true)
    self:addChild(self.lblPathMetrics)

    self.lblPsychology = ISLabel:new(12, 82, 18, "Psy: trauma=0 rage=0 freeze=0", 0.95, 0.85, 0.85, 1, UIFont.Small, true)
    self:addChild(self.lblPsychology)

    self.lblWeather = ISLabel:new(12, 100, 18, "Meteo: wet=0 cold=0 sick=0", 0.82, 0.95, 0.9, 1, UIFont.Small, true)
    self:addChild(self.lblWeather)

    self.lblInjuries = ISLabel:new(12, 118, 18, "Blessures: mob=0 aim=0 force=0 charge=0", 0.95, 0.9, 0.75, 1, UIFont.Small, true)
    self:addChild(self.lblInjuries)

    self.lblExpedition = ISLabel:new(12, 136, 18, "Expedition: inactive", 0.85, 0.85, 1.0, 1, UIFont.Small, true)
    self:addChild(self.lblExpedition)

    self.lblGameplayProfile = ISLabel:new(12, 154, 18, "Profil gameplay: realistic", 0.9, 0.95, 0.75, 1, UIFont.Small, true)
    self:addChild(self.lblGameplayProfile)

    self.lblMsg = ISLabel:new(12, 172, 18, "", 0.8, 1.0, 0.8, 1, UIFont.Small, true)
    self:addChild(self.lblMsg)

    local y = 196
    y = self:addSliderBlock("Stats", y)
    y = self:addSlider("courage", y, self.statsSliders)
    y = self:addSlider("intelligence", y, self.statsSliders)
    y = self:addSlider("strength", y, self.statsSliders)
    y = self:addSlider("hunger", y, self.statsSliders)
    y = self:addSlider("thirst", y, self.statsSliders)

    y = y + 6
    y = self:addSliderBlock("Personnalite", y)
    y = self:addSlider("socialDrive", y, self.personalitySliders)
    y = self:addSlider("loneWolf", y, self.personalitySliders)
    y = self:addSlider("adaptability", y, self.personalitySliders)
    y = self:addSlider("brutality", y, self.personalitySliders)
    y = self:addSlider("opportunism", y, self.personalitySliders)

    self.btnApplyStats = ISButton:new(12, y + 4, 100, 24, "Appliquer stats", self, NPCAdminHUD.onApplyStats)
    self.btnApplyStats:initialise()
    self.btnApplyStats:instantiate()
    self:addChild(self.btnApplyStats)

    self.btnApplyPers = ISButton:new(118, y + 4, 130, 24, "Appliquer perso", self, NPCAdminHUD.onApplyPersonality)
    self.btnApplyPers:initialise()
    self.btnApplyPers:instantiate()
    self:addChild(self.btnApplyPers)

    self.btnFriendly = ISButton:new(254, y + 4, 62, 24, "Amical", self, NPCAdminHUD.onPresetFriendly)
    self.btnFriendly:initialise()
    self.btnFriendly:instantiate()
    self:addChild(self.btnFriendly)

    self.btnHostile = ISButton:new(320, y + 4, 62, 24, "Hostile", self, NPCAdminHUD.onPresetHostile)
    self.btnHostile:initialise()
    self.btnHostile:instantiate()
    self:addChild(self.btnHostile)

    self.btnSurvivor = ISButton:new(386, y + 4, 62, 24, "Survivant", self, NPCAdminHUD.onPresetSurvivor)
    self.btnSurvivor:initialise()
    self.btnSurvivor:instantiate()
    self:addChild(self.btnSurvivor)

    y = y + 34

    self.btnAddFood = ISButton:new(12, y, 108, 24, "Ajouter nourriture", self, NPCAdminHUD.onAddFood)
    self.btnAddFood:initialise()
    self.btnAddFood:instantiate()
    self:addChild(self.btnAddFood)

    self.btnAddWater = ISButton:new(126, y, 90, 24, "Ajouter eau", self, NPCAdminHUD.onAddWater)
    self.btnAddWater:initialise()
    self.btnAddWater:instantiate()
    self:addChild(self.btnAddWater)

    self.btnClearInv = ISButton:new(222, y, 104, 24, "Vider inventaire", self, NPCAdminHUD.onClearInventory)
    self.btnClearInv:initialise()
    self.btnClearInv:instantiate()
    self:addChild(self.btnClearInv)

    self.btnHeal = ISButton:new(332, y, 54, 24, "Soigner", self, NPCAdminHUD.onHeal)
    self.btnHeal:initialise()
    self.btnHeal:instantiate()
    self:addChild(self.btnHeal)

    self.btnBitten = ISButton:new(390, y, 58, 24, "Morsure", self, NPCAdminHUD.onToggleBitten)
    self.btnBitten:initialise()
    self.btnBitten:instantiate()
    self:addChild(self.btnBitten)

    y = y + 32
    self.btnProfileRealistic = ISButton:new(12, y, 86, 24, "Realiste", self, NPCAdminHUD.onProfileRealistic)
    self.btnProfileRealistic:initialise()
    self.btnProfileRealistic:instantiate()
    self:addChild(self.btnProfileRealistic)

    self.btnProfileHardcore = ISButton:new(102, y, 86, 24, "Hardcore", self, NPCAdminHUD.onProfileHardcore)
    self.btnProfileHardcore:initialise()
    self.btnProfileHardcore:instantiate()
    self:addChild(self.btnProfileHardcore)

    self.btnProfileNarrative = ISButton:new(192, y, 86, 24, "Narratif", self, NPCAdminHUD.onProfileNarrative)
    self.btnProfileNarrative:initialise()
    self.btnProfileNarrative:instantiate()
    self:addChild(self.btnProfileNarrative)

    self.btnProfileUltraHardcore = ISButton:new(282, y, 84, 24, "Ultra HC", self, NPCAdminHUD.onProfileUltraHardcore)
    self.btnProfileUltraHardcore:initialise()
    self.btnProfileUltraHardcore:instantiate()
    self:addChild(self.btnProfileUltraHardcore)

    self.btnProfileRpSoft = ISButton:new(370, y, 78, 24, "RP Soft", self, NPCAdminHUD.onProfileRpSoft)
    self.btnProfileRpSoft:initialise()
    self.btnProfileRpSoft:instantiate()
    self:addChild(self.btnProfileRpSoft)

    if PHNPCInteractionClient then
        PHNPCInteractionClient:requestNpcSnapshot(self.npcId)
    end
end

function NPCAdminHUD:updateFromSnapshot(snapshot)
    if not snapshot or snapshot.npcId ~= self.npcId then
        return
    end

    self.snapshot = snapshot
    self.npcData = snapshot
    self.lblState:setName("Etat: " .. safe(snapshot.state, "?") .. " | role=" .. safe(snapshot.socialRole, "?") .. " | survie=" .. safe(snapshot.survivalScore, "?"))
    if self.lblPathMetrics then
        self.lblPathMetrics:setName(formatAdminPathMetrics(snapshot))
    end

    local psych = snapshot.psychologyState or {}
    local weather = snapshot.weatherState or {}
    local penalties = snapshot.runtimePenalties or {}
    local expedition = snapshot.expeditionState or {}
    if self.lblPsychology then
        self.lblPsychology:setName(string.format("Psy: trauma=%d rage=%d freeze=%d", tonumber(psych.trauma) or 0, tonumber(psych.rage) or 0, tonumber(psych.freezeUntilTick) or 0))
    end
    if self.lblWeather then
        self.lblWeather:setName(string.format("Meteo: wet=%d cold=%d sick=%d", tonumber(weather.wetness) or 0, tonumber(weather.coldStress) or 0, tonumber(weather.sickness) or 0))
    end
    if self.lblInjuries then
        self.lblInjuries:setName(string.format("Blessures: mob=%d aim=%d force=%d charge=%d", tonumber(penalties.mobility) or 0, tonumber(penalties.aim) or 0, tonumber(penalties.strength) or 0, tonumber(penalties.carry) or 0))
    end
    if self.lblExpedition then
        if expedition.active == true then
            self.lblExpedition:setName(string.format("Expedition: active dist=%d retour=%d", tonumber(expedition.distance) or 0, tonumber(expedition.returnTick) or 0))
        else
            self.lblExpedition:setName("Expedition: inactive")
        end
    end
    if self.lblGameplayProfile then
        self.lblGameplayProfile:setName("Profil gameplay: " .. safe(snapshot.gameplayProfile, "realistic"))
    end

    local stats = {}
    if self.npcData and self.npcData.stats then
        stats = self.npcData.stats
    end
    local p = snapshot.personality or {}

    if self.statsSliders.courage then self.statsSliders.courage.value = clamp(tonumber(stats.courage or self.statsSliders.courage.value) or 50, 0, 100) end
    if self.statsSliders.intelligence then self.statsSliders.intelligence.value = clamp(tonumber(stats.intelligence or self.statsSliders.intelligence.value) or 50, 0, 100) end
    if self.statsSliders.strength then self.statsSliders.strength.value = clamp(tonumber(stats.strength or self.statsSliders.strength.value) or 50, 0, 100) end
    if self.statsSliders.hunger then self.statsSliders.hunger.value = clamp(tonumber(stats.hunger or self.statsSliders.hunger.value) or 50, 0, 100) end
    if self.statsSliders.thirst then self.statsSliders.thirst.value = clamp(tonumber(stats.thirst or self.statsSliders.thirst.value) or 50, 0, 100) end

    if self.personalitySliders.socialDrive then self.personalitySliders.socialDrive.value = clamp(tonumber(p.socialDrive or self.personalitySliders.socialDrive.value) or 50, 0, 100) end
    if self.personalitySliders.loneWolf then self.personalitySliders.loneWolf.value = clamp(tonumber(p.loneWolf or self.personalitySliders.loneWolf.value) or 50, 0, 100) end
    if self.personalitySliders.adaptability then self.personalitySliders.adaptability.value = clamp(tonumber(p.adaptability or self.personalitySliders.adaptability.value) or 50, 0, 100) end
    if self.personalitySliders.brutality then self.personalitySliders.brutality.value = clamp(tonumber(p.brutality or self.personalitySliders.brutality.value) or 50, 0, 100) end
    if self.personalitySliders.opportunism then self.personalitySliders.opportunism.value = clamp(tonumber(p.opportunism or self.personalitySliders.opportunism.value) or 50, 0, 100) end
end

function NPCAdminHUD:setStatus(message, kind)
    local r, g, b = 0.8, 1.0, 0.8
    if kind == "error" then
        r, g, b = 1.0, 0.45, 0.45
    elseif kind == "success" then
        r, g, b = 0.45, 1.0, 0.45
    elseif kind == "warn" then
        r, g, b = 1.0, 0.85, 0.35
    elseif kind == "info" then
        r, g, b = 0.65, 0.85, 1.0
    end

    self.lblMsg:setName(message or "")
    if self.lblMsg.setColor then
        self.lblMsg:setColor(r, g, b, 1.0)
    end
end

function NPCAdminHUD:sendAdmin(action, payload)
    if PHNPCInteractionClient then
        PHNPCInteractionClient:sendAdminAction(self.npcId, action, payload or {})
    end
end

function NPCAdminHUD:onApplyStats()
    for key, slider in pairs(self.statsSliders) do
        self:sendAdmin("setStat", {
            statName = key,
            value = math.floor(slider.value)
        })
    end
    self:setStatus("Stats envoyees", "info")
end

function NPCAdminHUD:onApplyPersonality()
    self:sendAdmin("setPersonality", {
        socialDrive = math.floor(self.personalitySliders.socialDrive.value),
        loneWolf = math.floor(self.personalitySliders.loneWolf.value),
        adaptability = math.floor(self.personalitySliders.adaptability.value),
        brutality = math.floor(self.personalitySliders.brutality.value),
        opportunism = math.floor(self.personalitySliders.opportunism.value)
    })
    self:setStatus("Personnalite envoyee", "info")
end

function NPCAdminHUD:onPresetFriendly() self:sendAdmin("setBehavior", { preset = "friendly" }) end
function NPCAdminHUD:onPresetHostile() self:sendAdmin("setBehavior", { preset = "hostile" }) end
function NPCAdminHUD:onPresetSurvivor() self:sendAdmin("setBehavior", { preset = "survivor" }) end
function NPCAdminHUD:onAddFood() self:sendAdmin("addItem", { itemType = "Base.CannedSardines", quantity = 2 }) end
function NPCAdminHUD:onAddWater() self:sendAdmin("addItem", { itemType = "Base.WaterBottleFull", quantity = 1 }) end
function NPCAdminHUD:onClearInventory() self:sendAdmin("clearInventory", {}) end
function NPCAdminHUD:onHeal() self:sendAdmin("heal", {}) end
function NPCAdminHUD:onToggleBitten() self:sendAdmin("toggleBitten", {}) end
function NPCAdminHUD:onProfileRealistic() self:sendAdmin("setGameplayProfile", { profile = "realistic" }) if PHNPCInteractionClient then PHNPCInteractionClient:requestNpcSnapshot(self.npcId) end end
function NPCAdminHUD:onProfileHardcore() self:sendAdmin("setGameplayProfile", { profile = "hardcore" }) if PHNPCInteractionClient then PHNPCInteractionClient:requestNpcSnapshot(self.npcId) end end
function NPCAdminHUD:onProfileNarrative() self:sendAdmin("setGameplayProfile", { profile = "narrative" }) if PHNPCInteractionClient then PHNPCInteractionClient:requestNpcSnapshot(self.npcId) end end
function NPCAdminHUD:onProfileUltraHardcore() self:sendAdmin("setGameplayProfile", { profile = "ultra_hardcore" }) if PHNPCInteractionClient then PHNPCInteractionClient:requestNpcSnapshot(self.npcId) end end
function NPCAdminHUD:onProfileRpSoft() self:sendAdmin("setGameplayProfile", { profile = "rp_soft" }) if PHNPCInteractionClient then PHNPCInteractionClient:requestNpcSnapshot(self.npcId) end end

local NPCTooltipPanel = ISPanel:derive("NPCTooltipPanel")

function NPCTooltipPanel:new()
    local o = ISPanel.new(self, 0, 0, 10, 10)
    o.backgroundColor = { r = 0.08, g = 0.08, b = 0.08, a = 0.88 }
    o.borderColor = { r = 0.7, g = 0.7, b = 0.7, a = 0.95 }
    o.lines = {}
    o:initialise()
    o:instantiate()
    o:setVisible(false)
    return o
end

function NPCTooltipPanel:setLines(lines)
    self.lines = lines or {}

    local tm = getTextManager and getTextManager() or nil
    if not tm then
        return
    end

    local maxWidth = 20
    for i = 1, #self.lines do
        local w = tm:MeasureStringX(UIFont.Small, self.lines[i])
        if w > maxWidth then
            maxWidth = w
        end
    end

    self:setWidth(math.min(PHNPCUI.tooltipMaxWidth, maxWidth + (PHNPCUI.tooltipPadding * 2)))
    self:setHeight((#self.lines * PHNPCUI.tooltipLineHeight) + (PHNPCUI.tooltipPadding * 2))
end

function NPCTooltipPanel:prerender()
    self:drawRect(0, 0, self.width, self.height, self.backgroundColor.a, self.backgroundColor.r, self.backgroundColor.g, self.backgroundColor.b)
    self:drawRectBorder(0, 0, self.width, self.height, self.borderColor.a, self.borderColor.r, self.borderColor.g, self.borderColor.b)

    for i = 1, #self.lines do
        self:drawText(self.lines[i], PHNPCUI.tooltipPadding, PHNPCUI.tooltipPadding + ((i - 1) * PHNPCUI.tooltipLineHeight), 0.95, 0.95, 0.95, 1.0, UIFont.Small)
    end
end

function PHNPCUI:getNearbyDynamicNpcs(player)
    local out = {}
    if not player then
        return out
    end

    if PHNPC_ClientNPCLocator and PHNPC_ClientNPCLocator.collectNearby then
        local nearby = PHNPC_ClientNPCLocator.collectNearby(player, self.scanRange)
        for i = 1, #nearby do
            local e = nearby[i] and nearby[i].entity or nil
            if e then
                out[#out + 1] = e
            end
        end
    end

    return out
end

function PHNPCUI:findHoveredNpc()
    local player = getLocalPlayer()
    if not player then
        return nil
    end

    local mx = getMouseX and getMouseX() or nil
    local my = getMouseY and getMouseY() or nil
    if not mx or not my then
        return nil
    end

    local candidates = self:getNearbyDynamicNpcs(player)
    local best = nil
    local bestScore = 999999

    for i = 1, #candidates do
        local entity = candidates[i]
        -- Garder nil-guard: getX()/getY()/getZ() peut retourner nil si entité invalide
        -- worldToScreen(nil,nil,nil) => MethodArguments.assertValid (non-catchable)
        local ex, ey, ez = entity:getX(), entity:getY(), entity:getZ()
        if ex and ey and ez then
        local sx, sy = worldToScreen(ex, ey, ez)
        if sx and sy then
            local d2 = sqDistance2D(mx, my, sx, sy)
            if d2 < bestScore and d2 <= self.hoverScreenThreshold then
                best = entity
                bestScore = d2
            end
        end
        end -- nil-guard ex/ey/ez
    end

    return best
end

function PHNPCUI:updateTooltip()
    -- Build 41: tooltip desactive. isoToScreenX(int,float,float,float) produit
    -- MethodArguments.assertValid (RuntimeException non-catchable par pcall Lua)
    -- ce qui genere 50 MB d'erreurs par session. Le panel n'est pas dans UIManager
    -- de toute facon (addToUIManager retire). Desactive jusqu'a refactoring complet.
    if true then return end  -- Lua 5.1 : return doit etre dernier statement du bloc

    local hovered = self:findHoveredNpc()
    if not hovered then
        if self.tooltipPanel and self._tooltipVisible then
            local ok = pcall(function() self.tooltipPanel:setVisible(false) end)
            if ok then self._tooltipVisible = false end
        end
        return
    end

    local npcId = getNpcId(hovered)
    local snapshot = getRawSnapshotFromEntity(hovered)
    local mood = getMoodFromSnapshot(snapshot)
    local hints = buildHintsFromSnapshot(snapshot)

    local lines = {
        "Nom: " .. safe(snapshot and snapshot.displayName, "PNJ " .. safe(npcId)),
        "Faction: " .. safe(snapshot and snapshot.factionId, "Solo"),
        "Humeur: " .. mood
    }

    for i = 1, #hints do
        lines[#lines + 1] = "- " .. hints[i]
    end

    self.tooltipPanel:setLines(lines)
    self.tooltipPanel:setX((getMouseX and getMouseX() or 0) + 16)
    self.tooltipPanel:setY((getMouseY and getMouseY() or 0) + 16)
    if not self._tooltipVisible then
        pcall(function() self.tooltipPanel:setVisible(true) end)
        self._tooltipVisible = true
    end
end

function PHNPCUI:openPlayerHUD(npcId)
    if not npcId then
        return
    end

    if self.playerWindow and self.playerWindow:getIsVisible() and self.playerWindow.npcId == npcId then
        self.playerWindow:bringToTop()
        return
    end

    if self.playerWindow then
        self.playerWindow:removeFromUIManager()
    end

    self.playerWindow = NPCPlayerHUD:new(npcId)
    self.playerWindow:initialise()
    self.playerWindow:addToUIManager()
    self.playerWindow:setVisible(true)
end

function PHNPCUI:openAdminHUD(npcId)
    if not npcId then
        return
    end

    local player = getLocalPlayer()
    if not isAdminPlayer(player) then
        return
    end

    if self.adminWindow and self.adminWindow:getIsVisible() and self.adminWindow.npcId == npcId then
        self.adminWindow:bringToTop()
        return
    end

    if self.adminWindow then
        self.adminWindow:removeFromUIManager()
    end

    self.adminWindow = NPCAdminHUD:new(npcId)
    self.adminWindow:initialise()
    self.adminWindow:addToUIManager()
    self.adminWindow:setVisible(true)
end

function PHNPCUI:onContextMenu(playerIndex, context, worldobjects, test)
    if test then
        return
    end

    local player = getSpecificPlayer and getSpecificPlayer(playerIndex) or nil
    local npc = getNpcFromWorldObjects(worldobjects)
    if not npc and player then
        npc = getNearestTaggedNpcForPlayer(player, 3.5)
    end
    if not player or not npc then
        return
    end

    local npcId = getNpcId(npc)
    if not npcId then
        return
    end

    context:addOption("Ouvrir HUD Commandes metier", nil, function()
        PHNPCUI:openPlayerHUD(npcId)
    end)

    context:addOption("Ouvrir Commerce avance", nil, function()
        if PHNPCTradeWindow and PHNPCTradeWindow.open then
            PHNPCTradeWindow.open(npcId)
        else
            PHNPCUI:openPlayerHUD(npcId)
        end
    end)

    context:addOption("Commande metier: fabrication", nil, function()
        PHNPCUI:openPlayerHUD(npcId)
        if PHNPCUI.playerWindow then
            PHNPCUI.playerWindow:onBusinessCraft()
            PHNPCUI.playerWindow:requestBusinessQuote()
        end
    end)

    context:addOption("Commande metier: construction", nil, function()
        PHNPCUI:openPlayerHUD(npcId)
        if PHNPCUI.playerWindow then
            PHNPCUI.playerWindow:onBusinessBuild()
            PHNPCUI.playerWindow:requestBusinessQuote()
        end
    end)

    context:addOption("Commande metier: achat", nil, function()
        PHNPCUI:openPlayerHUD(npcId)
        if PHNPCUI.playerWindow then
            PHNPCUI.playerWindow:onBusinessBuy()
            PHNPCUI.playerWindow:requestBusinessQuote()
        end
    end)

    context:addOption("Journal quetes SSR", nil, function()
        if PHNPCQuestJournalUI and PHNPCQuestJournalUI.open then
            PHNPCQuestJournalUI.open()
        end
    end)

    if PHNPCInteractionClient then
        context:addOption("Parler", nil, function()
            local okChatUI, OllamaChatUI = pcall(require, "OllamaChatUI")
            if okChatUI and OllamaChatUI and OllamaChatUI.openChatWindow then
                OllamaChatUI:openChatWindow(npcId)
            else
                PHNPCInteractionClient:requestIntel(npcId)
                PHNPCUI:openPlayerHUD(npcId)
            end
        end)
    end

    if isAdminPlayer(player) then
        context:addOption("Ouvrir HUD ADMIN", nil, function()
            PHNPCUI:openAdminHUD(npcId)
        end)
    end
end

function PHNPCUI:onRealtimeEvent(eventName, payload)
    if eventName == "ActionResult" and payload then
        local snapshot = payload.snapshot
        local msg = payload.message or ""
        local kind = payload.ok and "success" or "error"
        local actionLabel = tostring(payload.actionType or "Action")

        if actionLabel == "MemoryEvent" then
            actionLabel = "interaction"
        elseif actionLabel == "TradeEvent" then
            actionLabel = "echange"
        elseif actionLabel == "RequestIntel" then
            actionLabel = "information"
        elseif actionLabel == "OrderAction" then
            actionLabel = "commande"
        elseif actionLabel == "BusinessOrder" then
            actionLabel = "commande metier"
        elseif actionLabel == "AdminAction" then
            actionLabel = "admin"
        end

        if self.playerWindow and self.playerWindow:getIsVisible() then
            if snapshot then
                self.playerWindow:updateFromSnapshot(snapshot)
            end
            self.playerWindow:setStatus(msg, kind)
            self.playerWindow:pushActionLog(actionLabel .. " - " .. msg, kind)
            if payload.ok and payload.actionType == "TradeEvent" then
                self.playerWindow:refreshPlayerInventory()
            end
        end

        if self.adminWindow and self.adminWindow:getIsVisible() and snapshot then
            self.adminWindow:updateFromSnapshot(snapshot)
            self.adminWindow:setStatus(msg, kind)
        end
    elseif eventName == "NpcSnapshot" and payload and payload.snapshot then
        local snapshot = payload.snapshot
        if self.playerWindow and self.playerWindow:getIsVisible() then
            self.playerWindow:updateFromSnapshot(snapshot)
        end
        if self.adminWindow and self.adminWindow:getIsVisible() then
            self.adminWindow:updateFromSnapshot(snapshot)
        end
    elseif eventName == "BusinessQuoteResponse" and payload then
        local quote = payload.quote or nil
        if self.playerWindow and self.playerWindow:getIsVisible() then
            self.playerWindow.pendingBusinessQuote = quote
            if payload.request then
                self.playerWindow.pendingBusinessRequest = payload.request
            end
            local quoteText = "Prix: -- | attente du devis"
            if quote then
                quoteText = string.format("Prix: %d | marche=%s | %s", tonumber(quote.cost) or 0, tostring(quote.priceState or "neutre"), tostring(quote.label or quote.serviceType or "service"))
            end
            if self.playerWindow.lblBusinessQuote then
                self.playerWindow.lblBusinessQuote:setName(quoteText)
            end
            self.playerWindow:setStatus(quote and "Devis disponible" or "Devis indisponible", quote and "success" or "error")
            self.playerWindow:pushActionLog("Devis - " .. quoteText, quote and "success" or "error")
        end
    elseif eventName == "IntelResponse" and payload then
        if self.playerWindow and self.playerWindow:getIsVisible() then
            if payload.intel then
                self.playerWindow:setStatus("Le PNJ partage des informations", "success")
                self.playerWindow:pushActionLog("IntelResponse - partage", "success")
            else
                self.playerWindow:setStatus("Le PNJ refuse de partager", "error")
                self.playerWindow:pushActionLog("IntelResponse - refus", "error")
            end
        end
    elseif eventName == "NetworkTimeout" and payload then
        local msg = payload.message or "Timeout reseau (5s)"
        if self.playerWindow and self.playerWindow:getIsVisible() then
            self.playerWindow:setStatus("Serveur indisponible", "error")
            self.playerWindow:pushActionLog("Reseau - " .. msg, "error")
        end
    elseif eventName == "NPCFx" and payload then
        local fxLabel = tostring(payload.fxType or "npc_fx")
        local pretty = fxLabel:gsub("^npc_", "")
        pretty = pretty:gsub("_", " ")
        if self.playerWindow and self.playerWindow:getIsVisible() then
            if fxLabel == "npc_eat" then
                pretty = "mange"
            elseif fxLabel == "npc_drink" then
                pretty = "boit"
            elseif fxLabel == "npc_patrol" then
                pretty = "patrouille"
            elseif fxLabel == "npc_watch" then
                pretty = "veille"
            elseif fxLabel == "npc_social_talk" then
                pretty = "interaction sociale"
            elseif fxLabel == "npc_social_trade" then
                pretty = "echange social"
            elseif fxLabel == "npc_social_threat" then
                pretty = "tension sociale"
            elseif fxLabel == "npc_sleep" then
                pretty = "dort"
            elseif fxLabel == "npc_wake" then
                pretty = "se reveille"
            elseif fxLabel == "npc_fatigue" then
                pretty = "fatigue"
            elseif fxLabel == "npc_medical" then
                pretty = "soin"
            end
            self.playerWindow:setStatus("PNJ: " .. pretty, "info")
            self.playerWindow:pushActionLog("FX - " .. pretty, "info")
        end
    end
end

function PHNPCUI:start()
    self._tooltipVisible = false
    self.tooltipPanel = NPCTooltipPanel:new()
    -- Build 41: NE PAS appeler addToUIManager() sur le tooltip.
    -- UIManager appelle prerender() chaque frame ce qui provoque des MethodArguments.assertValid
    -- non-catchables par pcall (Java RuntimeException).
    -- self.tooltipPanel:addToUIManager()
    pcall(function() self.tooltipPanel:setVisible(false) end)

    if PHNPCInteractionClient and PHNPCInteractionClient.addListener then
        PHNPCInteractionClient:addListener("PHNPCUI", function(eventName, payload)
            PHNPCUI:onRealtimeEvent(eventName, payload)
        end)
    end

    if Events and Events.OnPostUIDraw then
        Events.OnPostUIDraw.Add(function()
            pcall(function() PHNPCUI:updateTooltip() end)
        end)
    end

    if Events and Events.OnFillWorldObjectContextMenu then
        Events.OnFillWorldObjectContextMenu.Add(function(playerIndex, context, worldobjects, test)
            PHNPCUI:onContextMenu(playerIndex, context, worldobjects, test)
        end)
    end
end

PHNPCUI:start()

_G.PHNPCUI = PHNPCUI

return PHNPCUI
