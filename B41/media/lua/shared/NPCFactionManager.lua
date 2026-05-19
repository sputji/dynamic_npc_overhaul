--[[
    Project Humain : Dynamic_NPC_Overhaul
    NPCFactionManager.lua

    Systeme de societe/factions pour PNJ dynamiques.
    - Factions globales (alliance, guerre, neutre)
    - Recrutement joueur <-> PNJ et PNJ <-> PNJ
    - Ordres unifies (joueur et PNJ utilisent les memes actions)
    - Sedentarisation des bases NPC avec rotations de garde de nuit automatiques
]]

local hasSpawner, NPCSpawner = pcall(require, "NPCSpawner")
if not hasSpawner then
    NPCSpawner = nil
end

local hasMemory, NPCMemory = pcall(require, "NPCMemory")
if not hasMemory then
    NPCMemory = nil
end

local NPCFactionManager = {
    factions = {},
    npcToFaction = {},
    playerToFaction = {},
    npcToBase = {},
    npcOrders = {},
    bases = {},

    tickCounter = 0,
    updateEveryTicks = 20,
    autoRecruitEveryTicks = 320,
    autoSocietyEveryTicks = 180,
    autoAffiliationEveryTicks = 240,

    relation = {
        ALLY = "ally",
        WAR = "war",
        NEUTRAL = "neutral",
        TRUCE = "truce"
    },

    orderType = {
        FOLLOW = "follow",
        STAY = "stay",
        GUARD = "guard",
        DEFEND = "defend",
        RECOVER = "recover",
        STUDY = "study",
        COOK = "cook",
        BUILD = "build",
        SLEEP = "sleep",
        PATROL = "patrol",
        SCAVENGE = "scavenge"
    },

    _factionCounter = 0,
    _baseCounter = 0
}

local function randInt(minValue, maxValue)
    if type(ZombRand) == "function" then
        return minValue + ZombRand((maxValue - minValue) + 1)
    end
    return math.random(minValue, maxValue)
end

local function clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

local function makeId(prefix, counter)
    local stamp = (os and os.time and os.time()) or 0
    return string.format("%s_%d_%d", prefix, stamp, counter)
end

local function isServerRuntime()
    if type(isServer) == "function" then
        return isServer() == true
    end
    return true
end

local function makeDefaultPerimeterPoints(center, radius)
    local points = {}
    local r = math.max(4, math.floor(radius or 12))
    local offsets = {
        { 0, -r },
        { r, 0 },
        { 0, r },
        { -r, 0 },
        { math.floor(r * 0.7), -math.floor(r * 0.7) },
        { math.floor(r * 0.7), math.floor(r * 0.7) },
        { -math.floor(r * 0.7), math.floor(r * 0.7) },
        { -math.floor(r * 0.7), -math.floor(r * 0.7) }
    }

    for i = 1, #offsets do
        local o = offsets[i]
        points[#points + 1] = {
            x = math.floor((center.x or 0) + o[1]),
            y = math.floor((center.y or 0) + o[2]),
            z = center.z or 0
        }
    end

    return points
end

local function sqDistance2D(x1, y1, x2, y2)
    local dx = x1 - x2
    local dy = y1 - y2
    return math.sqrt(dx * dx + dy * dy)
end

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end

    local out = {}
    for k, v in pairs(value) do
        out[k] = deepCopy(v)
    end
    return out
end

local function classifyTradeCategory(itemType)
    local value = tostring(itemType or ""):lower()
    if value == "" then
        return "general_goods"
    end

    if value:find("water", 1, true) or value:find("bottle", 1, true) or value:find("juice", 1, true) or value:find("soda", 1, true) or value:find("pop", 1, true) then
        return "water"
    end
    if value:find("canned", 1, true) or value:find("food", 1, true) or value:find("crisps", 1, true) or value:find("beans", 1, true) or value:find("soup", 1, true) or value:find("sardines", 1, true) or value:find("tuna", 1, true) or value:find("bread", 1, true) or value:find("meat", 1, true) or value:find("fruit", 1, true) then
        return "food"
    end
    if value:find("bandage", 1, true) or value:find("pill", 1, true) or value:find("alcohol", 1, true) or value:find("medical", 1, true) or value:find("antibiotic", 1, true) then
        return "medicine"
    end
    if value:find("hammer", 1, true) or value:find("screwdriver", 1, true) or value:find("saw", 1, true) or value:find("wrench", 1, true) or value:find("tool", 1, true) then
        return "tools"
    end
    if value:find("sheet", 1, true) or value:find("nail", 1, true) or value:find("plank", 1, true) or value:find("rope", 1, true) or value:find("glue", 1, true) or value:find("wood", 1, true) then
        return "materials"
    end
    if value:find("ammo", 1, true) or value:find("bullet", 1, true) or value:find("shell", 1, true) then
        return "ammo"
    end
    if value:find("weapon", 1, true) or value:find("gun", 1, true) or value:find("pistol", 1, true) or value:find("rifle", 1, true) then
        return "weapons"
    end
    if value:find("thread", 1, true) or value:find("needle", 1, true) or value:find("book", 1, true) or value:find("magazine", 1, true) or value:find("recipe", 1, true) then
        return "crafts"
    end

    return "general_goods"
end

local function countInventoryStockByCategory(npcData, bucket)
    local inventory = npcData and npcData.inventory or nil
    local items = inventory and inventory.items or nil
    if type(items) ~= "table" then
        return
    end

    for i = 1, #items do
        local item = items[i]
        if item and item.type and (item.quantity or 0) > 0 then
            local category = classifyTradeCategory(item.type)
            bucket[category] = (bucket[category] or 0) + math.max(1, tonumber(item.quantity) or 1)
        end
    end
end

local function defaultBuildStages()
    return {
        { name = "foundation", required = 40 },
        { name = "frame", required = 55 },
        { name = "walls", required = 70 },
        { name = "roof", required = 85 },
        { name = "fortify", required = 100 }
    }
end

local function makeDefaultBuildSites(center, radius)
    local r = math.max(5, math.floor((radius or 15) * 0.65))
    local offsets = {
        { -r, -r },
        { r, -r },
        { r, r },
        { -r, r },
        { 0, -r },
        { r, 0 },
        { 0, r },
        { -r, 0 }
    }

    local sites = {}
    for i = 1, #offsets do
        local off = offsets[i]
        sites[#sites + 1] = {
            id = "site_" .. tostring(i),
            x = math.floor((center.x or 0) + off[1]),
            y = math.floor((center.y or 0) + off[2]),
            z = center.z or 0,
            reservedBy = nil,
            stageIndex = 1,
            stageProgress = 0,
            completed = false,
            stages = defaultBuildStages()
        }
    end

    return sites
end

function NPCFactionManager:getActiveNPCEntries()
    if not NPCSpawner or type(NPCSpawner.activeNPCs) ~= "table" then
        return {}
    end
    return NPCSpawner.activeNPCs
end

function NPCFactionManager:getNPCData(npcId)
    local active = self:getActiveNPCEntries()
    local entry = active[npcId]
    if not entry then
        return nil
    end
    return entry.data, entry
end

function NPCFactionManager:getAllActiveNPCIds()
    local ids = {}
    local active = self:getActiveNPCEntries()
    for npcId in pairs(active) do
        ids[#ids + 1] = npcId
    end
    return ids
end

function NPCFactionManager:getOrderCatalog()
    return self.orderType
end

function NPCFactionManager:_nextFactionId()
    self._factionCounter = self._factionCounter + 1
    return makeId("faction", self._factionCounter)
end

function NPCFactionManager:_nextBaseId()
    self._baseCounter = self._baseCounter + 1
    return makeId("base", self._baseCounter)
end

function NPCFactionManager:getFaction(factionId)
    return self.factions[factionId]
end

function NPCFactionManager:getFactionOfNPC(npcId)
    return self.npcToFaction[npcId]
end

function NPCFactionManager:getFactionOfPlayer(playerId)
    return self.playerToFaction[playerId]
end

function NPCFactionManager:createFaction(name, founderNpcId, opts)
    opts = opts or {}

    local factionId = opts.id or self:_nextFactionId()
    self.factions[factionId] = {
        id = factionId,
        name = name or ("Faction_" .. tostring(self._factionCounter)),
        founderNpcId = founderNpcId,
        leaderNpcId = founderNpcId,
        membersNPC = {},
        membersPlayers = {},
        relations = {},
        meta = {
            createdTick = self.tickCounter,
            doctrine = opts.doctrine or "survival"
        }
    }

    if founderNpcId then
        self:addNPCToFaction(founderNpcId, factionId)
    end

    return factionId
end

function NPCFactionManager:createClan(leaderNpcId, npcIds, clanName)
    local factionId = self:createFaction(clanName or "NPC_Clan", leaderNpcId)
    npcIds = npcIds or {}

    for i = 1, #npcIds do
        local npcId = npcIds[i]
        if npcId ~= leaderNpcId then
            self:addNPCToFaction(npcId, factionId)
        end
    end

    return factionId
end

function NPCFactionManager:addNPCToFaction(npcId, factionId)
    local faction = self.factions[factionId]
    if not faction then
        return false
    end

    local oldFactionId = self.npcToFaction[npcId]
    if oldFactionId == factionId then
        return true
    end

    if oldFactionId and self.factions[oldFactionId] then
        local oldMembers = self.factions[oldFactionId].membersNPC
        oldMembers[npcId] = nil
    end

    self.npcToFaction[npcId] = factionId
    faction.membersNPC[npcId] = true

    return true
end

function NPCFactionManager:removeNPCFromFaction(npcId)
    local oldFactionId = self.npcToFaction[npcId]
    if not oldFactionId then
        return false
    end

    local oldFaction = self.factions[oldFactionId]
    if oldFaction and oldFaction.membersNPC then
        oldFaction.membersNPC[npcId] = nil
        if oldFaction.leaderNpcId == npcId then
            oldFaction.leaderNpcId = nil
            for otherId in pairs(oldFaction.membersNPC) do
                oldFaction.leaderNpcId = otherId
                break
            end
        end
    end

    self.npcToFaction[npcId] = nil
    return true
end

function NPCFactionManager:getOnlinePlayerList()
    local players = {}

    if type(getOnlinePlayers) == "function" then
        local online = getOnlinePlayers()
        if online and online.size then
            for i = 0, online:size() - 1 do
                players[#players + 1] = online:get(i)
            end
            return players
        end
    end

    if type(getNumActivePlayers) == "function" and type(getSpecificPlayer) == "function" then
        for i = 0, getNumActivePlayers() - 1 do
            local p = getSpecificPlayer(i)
            if p then
                players[#players + 1] = p
            end
        end
    end

    return players
end

function NPCFactionManager:getPersonalityProfile(npcData)
    npcData.traits = npcData.traits or {}
    npcData.traits.personality = npcData.traits.personality or {}
    local p = npcData.traits.personality

    local stats = npcData.stats or {}
    p.socialDrive = tonumber(p.socialDrive) or clamp(math.floor((stats.intelligence or 50) * 0.6 + randInt(0, 35)), 0, 100)
    p.loneWolf = tonumber(p.loneWolf) or clamp(100 - p.socialDrive + randInt(-12, 12), 0, 100)
    p.adaptability = tonumber(p.adaptability) or clamp(math.floor((stats.intelligence or 50) * 0.5 + randInt(0, 30)), 0, 100)
    p.brutality = tonumber(p.brutality) or clamp(math.floor((100 - (stats.intelligence or 50)) * 0.35 + randInt(0, 25)), 0, 100)
    p.opportunism = tonumber(p.opportunism) or clamp(math.floor((100 - (stats.courage or 50)) * 0.25 + randInt(10, 45)), 0, 100)

    return p
end

function NPCFactionManager:computeSurvivalScore(npcData)
    local stats = npcData and npcData.stats or {}
    local health = npcData and npcData.health or {}
    local hp = (health.current or 75)
    local hunger = (stats.hunger or 50)
    local thirst = (stats.thirst or 50)
    local courage = (stats.courage or 50)
    local intelligence = (stats.intelligence or 50)

    local base = (hp * 0.35) + (hunger * 0.2) + (thirst * 0.2) + (courage * 0.1) + (intelligence * 0.15)
    if health.isBitten then
        base = base - 25
    end
    return clamp(math.floor(base), 0, 100)
end

function NPCFactionManager:getBestTrustedPlayerId(npcData)
    if not NPCMemory then
        return nil, nil
    end

    local memory = NPCMemory.EnsureMemory(npcData)
    local bestPlayerId = nil
    local bestScore = -999999

    for actorKey, profile in pairs(memory.actorProfiles or {}) do
        if type(actorKey) == "string" and string.sub(actorKey, 1, 7) == "player:" then
            local score = (profile.trust or 0) + (profile.gratitude or 0) + math.floor((profile.respect or 0) * 0.5)
                - (profile.resentment or 0) - math.floor((profile.fear or 0) * 0.4)
            if score > bestScore then
                bestScore = score
                bestPlayerId = string.sub(actorKey, 8)
            end
        end
    end

    return bestPlayerId, bestScore
end

function NPCFactionManager:autoAffiliationPass()
    local ids = self:getAllActiveNPCIds()
    if #ids == 0 then
        return
    end

    for i = 1, #ids do
        local npcId = ids[i]
        local npcData = self:getNPCData(npcId)
        if npcData then
            local personality = self:getPersonalityProfile(npcData)
            local survival = self:computeSurvivalScore(npcData)
            local factionId = self:getFactionOfNPC(npcId)

            if factionId then
                local leaveDrive = personality.loneWolf + math.floor((survival - 55) * 0.6) - math.floor(personality.socialDrive * 0.45)
                if leaveDrive >= 62 and randInt(1, 100) <= 10 then
                    self:removeNPCFromFaction(npcId)
                end
            else
                local joinDrive = personality.socialDrive + math.floor((50 - survival) * 0.9) + math.floor(personality.adaptability * 0.2)

                if joinDrive >= 55 then
                    local trustedPlayerId, playerScore = self:getBestTrustedPlayerId(npcData)
                    if trustedPlayerId and playerScore and playerScore >= 28 then
                        local pf = self:getFactionOfPlayer(trustedPlayerId)
                        if not pf then
                            pf = self:createFaction("Band_of_" .. tostring(trustedPlayerId), nil, {
                                doctrine = "mixed"
                            })
                            self:addPlayerToFaction(trustedPlayerId, pf)
                        end
                        self:recruitNPCByPlayer(trustedPlayerId, npcId, pf)
                    else
                        local recruiterId = ids[randInt(1, #ids)]
                        if recruiterId and recruiterId ~= npcId and self:getFactionOfNPC(recruiterId) then
                            self:recruitNPCByNPC(recruiterId, npcId)
                        elseif randInt(1, 100) <= 6 then
                            local newFaction = self:createFaction("Clan_" .. tostring(npcId), npcId, {
                                doctrine = "survival"
                            })
                            self:addNPCToFaction(npcId, newFaction)
                        end
                    end
                end
            end
        end
    end
end

function NPCFactionManager:addPlayerToFaction(playerId, factionId)
    local faction = self.factions[factionId]
    if not faction then
        return false
    end

    local oldFactionId = self.playerToFaction[playerId]
    if oldFactionId and self.factions[oldFactionId] then
        self.factions[oldFactionId].membersPlayers[playerId] = nil
    end

    self.playerToFaction[playerId] = factionId
    faction.membersPlayers[playerId] = true

    return true
end

function NPCFactionManager:setRelation(factionAId, factionBId, relationState)
    local factionA = self.factions[factionAId]
    local factionB = self.factions[factionBId]
    if not factionA or not factionB or factionAId == factionBId then
        return false
    end

    local state = relationState or self.relation.NEUTRAL
    factionA.relations[factionBId] = state
    factionB.relations[factionAId] = state
    return true
end

function NPCFactionManager:getRelation(factionAId, factionBId)
    if not factionAId or not factionBId then
        return self.relation.NEUTRAL
    end
    if factionAId == factionBId then
        return self.relation.ALLY
    end

    local factionA = self.factions[factionAId]
    if not factionA then
        return self.relation.NEUTRAL
    end

    return factionA.relations[factionBId] or self.relation.NEUTRAL
end

function NPCFactionManager:isAlly(npcAId, npcBId)
    local fa = self:getFactionOfNPC(npcAId)
    local fb = self:getFactionOfNPC(npcBId)
    return self:getRelation(fa, fb) == self.relation.ALLY
end

function NPCFactionManager:canRecruitNPC(recruiterNPCId, targetNPCId)
    if recruiterNPCId == targetNPCId then
        return false
    end

    local recruiterData = self:getNPCData(recruiterNPCId)
    local targetData = self:getNPCData(targetNPCId)
    if not recruiterData or not targetData then
        return false
    end

    local recruiterFaction = self:getFactionOfNPC(recruiterNPCId)
    if not recruiterFaction then
        return false
    end

    local targetFaction = self:getFactionOfNPC(targetNPCId)
    if targetFaction and targetFaction ~= recruiterFaction then
        local rel = self:getRelation(recruiterFaction, targetFaction)
        if rel == self.relation.WAR then
            return false
        end
    end

    local courage = targetData.stats and targetData.stats.courage or 50
    local intelligence = targetData.stats and targetData.stats.intelligence or 50
    local willingness = clamp((intelligence * 0.5) + (100 - courage) * 0.5, 0, 100)

    if NPCMemory then
        local recruiterMemory = NPCMemory.EnsureMemory(recruiterData)
        local targetMemory = NPCMemory.EnsureMemory(targetData)
        local disposition = NPCMemory.GetDispositionTowardNPC(targetData, recruiterNPCId)

        willingness = clamp(
            willingness + disposition.trust + math.floor(disposition.respect * 0.4)
                - disposition.fear - disposition.resentment - math.floor((disposition.aggression or 0) * 0.5),
            0,
            100
        )

        if targetMemory.trustedNPCs[recruiterNPCId] then
            willingness = clamp(willingness + 18, 0, 100)
        end

        local recentHelp = 0
        for i = 1, #targetMemory.recentEvents do
            local event = targetMemory.recentEvents[i]
            if event and event.payload and event.payload.fromNpcId == recruiterNPCId then
                if event.eventType == "shared_memory_in" then
                    recentHelp = recentHelp + 8
                end
            end
        end
        willingness = clamp(willingness + recentHelp, 0, 100)

        if recruiterMemory and recruiterMemory.infection and recruiterMemory.infection.berserkTriggered then
            willingness = clamp(willingness - 40, 0, 100)
        end
    end

    if targetData.memory and targetData.memory.reputationByActor then
        local repMap = targetData.memory.reputationByActor
        local socialSignal = 0
        for _, rep in pairs(repMap) do
            socialSignal = socialSignal + (tonumber(rep) or 0)
        end
        willingness = clamp(willingness + (socialSignal * 0.02), 0, 100)
    end

    return willingness >= randInt(35, 75)
end

function NPCFactionManager:recruitNPCByNPC(recruiterNPCId, targetNPCId)
    local recruiterFaction = self:getFactionOfNPC(recruiterNPCId)
    if not recruiterFaction then
        return false
    end

    if not self:canRecruitNPC(recruiterNPCId, targetNPCId) then
        return false
    end

    local ok = self:addNPCToFaction(targetNPCId, recruiterFaction)
    if ok and NPCMemory then
        local recruiterData = self:getNPCData(recruiterNPCId)
        local targetData = self:getNPCData(targetNPCId)
        if recruiterData and targetData then
            NPCMemory.ShareMemory(recruiterData, targetData, { tick = self.tickCounter })
        end
    end
    return ok
end

function NPCFactionManager:recruitNPCByPlayer(playerId, targetNPCId, factionId)
    if not playerId or not targetNPCId then
        return false
    end

    local wantedFaction = factionId or self:getFactionOfPlayer(playerId)
    if not wantedFaction then
        return false
    end

    local targetData = self:getNPCData(targetNPCId)
    if not targetData then
        return false
    end

    local dispositionScore = 0
    if NPCMemory then
        local disposition = NPCMemory.GetDispositionTowardPlayer(targetData, playerId)
        dispositionScore = (disposition.reputation or 0) + disposition.trust + disposition.gratitude + math.floor(disposition.respect * 0.5)
            - disposition.fear - disposition.resentment
    else
        if targetData.memory and targetData.memory.reputationByPlayer then
            dispositionScore = tonumber(targetData.memory.reputationByPlayer[playerId]) or 0
        end
    end

    local threshold = randInt(-10, 35)
    if dispositionScore < threshold then
        return false
    end

    return self:addNPCToFaction(targetNPCId, wantedFaction)
end

function NPCFactionManager:invitePlayerByNPC(recruiterNPCId, playerId)
    local recruiterFaction = self:getFactionOfNPC(recruiterNPCId)
    if not recruiterFaction then
        return false
    end

    local npcData = self:getNPCData(recruiterNPCId)
    if not npcData then
        return false
    end

    local score = 0
    if NPCMemory then
        local disposition = NPCMemory.GetDispositionTowardPlayer(npcData, playerId)
        score = (disposition.reputation or 0) + disposition.trust + disposition.gratitude + disposition.respect
            - disposition.resentment - math.floor(disposition.fear * 0.5)
    elseif npcData.memory and npcData.memory.reputationByPlayer then
        score = tonumber(npcData.memory.reputationByPlayer[playerId]) or 0
    end

    if score < randInt(5, 40) then
        return false
    end

    return self:addPlayerToFaction(playerId, recruiterFaction)
end

function NPCFactionManager:issueOrder(issuerType, issuerId, targetNPCIds, orderType, params)
    params = params or {}
    targetNPCIds = targetNPCIds or {}

    local validOrder = false
    for _, v in pairs(self.orderType) do
        if v == orderType then
            validOrder = true
            break
        end
    end
    if not validOrder then
        return false
    end

    for i = 1, #targetNPCIds do
        local npcId = targetNPCIds[i]
        self.npcOrders[npcId] = {
            issuerType = issuerType,
            issuerId = issuerId,
            orderType = orderType,
            params = params,
            createdTick = self.tickCounter,
            expiresTick = params.expiresTick,
            automatic = params.automatic == true
        }
    end

    return true
end

function NPCFactionManager:getOrder(npcId)
    local order = self.npcOrders[npcId]
    if not order then
        return nil
    end

    if order.expiresTick and self.tickCounter > order.expiresTick then
        self.npcOrders[npcId] = nil
        return nil
    end

    return order
end

function NPCFactionManager:clearOrder(npcId)
    self.npcOrders[npcId] = nil
end

function NPCFactionManager:ShareMemoryBetweenNPCs(npcAId, npcBId, context)
    if not NPCMemory then
        return false
    end

    local npcA = self:getNPCData(npcAId)
    local npcB = self:getNPCData(npcBId)
    if not npcA or not npcB then
        return false
    end

    return NPCMemory.ShareMemory(npcA, npcB, {
        tick = self.tickCounter,
        context = context
    })
end

function NPCFactionManager:BuildNPCPlayerExchange(npcId, playerId, context)
    if not NPCMemory then
        return nil
    end

    local npcData = self:getNPCData(npcId)
    if not npcData then
        return nil
    end

    return NPCMemory.BuildTradeOffer(npcData, "player", playerId, {
        tick = self.tickCounter,
        baseId = context and context.baseId
    })
end

function NPCFactionManager:BuildNPCtoNPCExchange(npcAId, npcBId, context)
    if not NPCMemory then
        return nil
    end

    local npcA = self:getNPCData(npcAId)
    local npcB = self:getNPCData(npcBId)
    if not npcA or not npcB then
        return nil
    end

    local offerA = NPCMemory.BuildTradeOffer(npcA, "npc", npcBId, {
        tick = self.tickCounter,
        baseId = context and context.baseId
    })
    local offerB = NPCMemory.BuildTradeOffer(npcB, "npc", npcAId, {
        tick = self.tickCounter,
        baseId = context and context.baseId
    })

    return {
        fromA = offerA,
        fromB = offerB
    }
end

function NPCFactionManager:OfferIntelToNPC(npcId, otherNpcId)
    if not NPCMemory then
        return nil
    end

    local npcData = self:getNPCData(npcId)
    if not npcData then
        return nil
    end

    return NPCMemory.BuildIntelForActor(npcData, "npc", otherNpcId)
end

function NPCFactionManager:OfferIntelToPlayer(npcId, playerId)
    if not NPCMemory then
        return nil
    end

    local npcData = self:getNPCData(npcId)
    if not npcData then
        return nil
    end

    return NPCMemory.BuildIntelForPlayer(npcData, playerId)
end

function NPCFactionManager:getBase(baseId)
    return self.bases[baseId]
end

function NPCFactionManager:getBaseOfNPC(npcId)
    local baseId = self.npcToBase[npcId]
    if not baseId then
        return nil
    end
    return self.bases[baseId], baseId
end

function NPCFactionManager:BuildLocalMarketState(npcId)
    if not NPCMemory then
        return {
            localSupply = {},
            localDemand = {},
            merchantCount = 0,
            stockBias = 0,
            totalMembers = 0
        }
    end

    local base, baseId = self:getBaseOfNPC(npcId)
    local factionId = self:getFactionOfNPC(npcId)
    local market = {
        baseId = baseId,
        factionId = factionId or (base and base.factionId) or nil,
        localSupply = {},
        localDemand = {},
        merchantCount = 0,
        merchantStock = 0,
        stockBias = 0,
        totalMembers = 0,
        priceTrend = "neutral"
    }

    local npcIds = {}
    if base and type(base.assignedNPCs) == "table" then
        for id in pairs(base.assignedNPCs) do
            npcIds[#npcIds + 1] = id
        end
    elseif factionId and type(self.factions[factionId]) == "table" then
        for id in pairs(self.factions[factionId].membersNPC or {}) do
            npcIds[#npcIds + 1] = id
        end
    else
        npcIds = self:getAllActiveNPCIds()
    end

    local totalSupply = 0
    local totalDemand = 0

    for i = 1, #npcIds do
        local id = npcIds[i]
        local npcData = self:getNPCData(id)
        if npcData then
            market.totalMembers = market.totalMembers + 1
            local profession = NPCMemory.GetProfessionProfile(npcData)
            local demandProfile = NPCMemory.BuildEconomicDemand(npcData, {
                isInClan = factionId ~= nil,
                clanNeed = base and (base.pressure and base.pressure.resources or 0) or 0,
                allowRoleShift = false,
                reason = "market_scan"
            })

            if profession and profession.isMerchant then
                market.merchantCount = market.merchantCount + 1
                countInventoryStockByCategory(npcData, market.localSupply)
                market.merchantStock = market.merchantStock + math.max(1, #(npcData.inventory and npcData.inventory.items or {}))
            end

            for j = 1, #demandProfile.demands do
                local demand = demandProfile.demands[j]
                local category = tostring(demand.category or "general_goods")
                local amount = math.max(1, tonumber(demand.priority) or 10)
                market.localDemand[category] = (market.localDemand[category] or 0) + amount
                totalDemand = totalDemand + amount
            end

            for _, category in ipairs(profession and profession.sells or {}) do
                market.localSupply[category] = (market.localSupply[category] or 0) + 5
                totalSupply = totalSupply + 5
            end
        end
    end

    market.stockBias = totalDemand - totalSupply + (market.merchantStock > 0 and -math.floor(market.merchantStock * 0.15) or 0)
    if market.stockBias > 25 then
        market.priceTrend = "baisse"
    elseif market.stockBias < -25 then
        market.priceTrend = "augmentation"
    end

    return market
end

function NPCFactionManager:createBase(factionId, centerX, centerY, z, radius, perimeterPoints, opts)
    opts = opts or {}

    local faction = nil
    if factionId then
        faction = self:getFaction(factionId)
        if not faction then
            return nil
        end
    end

    local baseId = self:_nextBaseId()
    local center = {
        x = centerX,
        y = centerY,
        z = z or 0
    }

    local perimeter = perimeterPoints
    if type(perimeter) ~= "table" or #perimeter == 0 then
        perimeter = makeDefaultPerimeterPoints(center, radius or 15)
    end

    self.bases[baseId] = {
        id = baseId,
        factionId = factionId,
        ownerType = opts.ownerType or (factionId and "npc" or "player"),
        ownerId = opts.ownerId,
        center = center,
        radius = radius or 15,
        perimeterPoints = perimeter,
        assignedNPCs = {},
        rotation = {
            guardIndex = 1,
            lastRotationTick = 0
        },
        rotationIntervalTicks = 420,
        nightStartHour = 21,
        nightEndHour = 6,
        buildSites = makeDefaultBuildSites(center, radius or 15),
        roleTargets = {
            guards = 1,
            cooks = 1,
            builders = 1,
            scavengers = 1,
            recover = 0,
            study = 0
        },
        pressure = {
            danger = 0,
            resources = 0,
            updatedTick = 0
        }
    }

    return baseId
end

function NPCFactionManager:getBuildSite(baseId, siteId)
    local base = self.bases[baseId]
    if not base or type(base.buildSites) ~= "table" then
        return nil
    end

    for i = 1, #base.buildSites do
        local site = base.buildSites[i]
        if site.id == siteId then
            return site
        end
    end
    return nil
end

function NPCFactionManager:getAssignedBuildSite(base, npcId)
    if not base or type(base.buildSites) ~= "table" then
        return nil
    end

    for i = 1, #base.buildSites do
        local site = base.buildSites[i]
        if site.reservedBy == npcId and not site.completed then
            return site
        end
    end
    return nil
end

function NPCFactionManager:reserveBuildSiteForNPC(base, npcId)
    if not base or type(base.buildSites) ~= "table" then
        return nil
    end

    local current = self:getAssignedBuildSite(base, npcId)
    if current then
        return current
    end

    local bestSite = nil
    local bestScore = -999999

    for i = 1, #base.buildSites do
        local site = base.buildSites[i]
        if not site.completed and (site.reservedBy == nil or site.reservedBy == npcId) then
            local stageWeight = (site.stageIndex or 1) * 100
            local progressWeight = site.stageProgress or 0
            local score = stageWeight + progressWeight
            if score > bestScore then
                bestScore = score
                bestSite = site
            end
        end
    end

    if bestSite then
        bestSite.reservedBy = npcId
    end

    return bestSite
end

function NPCFactionManager:recordBuildWork(baseId, npcId, workUnits)
    local base = self.bases[baseId]
    if not base then
        return false
    end

    local site = self:getAssignedBuildSite(base, npcId)
    if not site then
        site = self:reserveBuildSiteForNPC(base, npcId)
    end
    if not site then
        return false
    end

    local stages = site.stages or defaultBuildStages()
    local stage = stages[site.stageIndex]
    if not stage then
        site.completed = true
        site.reservedBy = nil
        return true
    end

    local gain = math.max(1, math.floor(workUnits or 1))
    site.stageProgress = (site.stageProgress or 0) + gain

    if site.stageProgress >= stage.required then
        site.stageProgress = 0
        site.stageIndex = (site.stageIndex or 1) + 1
        local nextStage = stages[site.stageIndex]
        if not nextStage then
            site.completed = true
            site.reservedBy = nil
        end
    end

    return true
end

function NPCFactionManager:getLocalDangerScore(base)
    local cell = getCell and getCell() or nil
    if not cell or not cell.getZombieList then
        return 0
    end

    local zombies = cell:getZombieList()
    if not zombies or not zombies.size then
        return 0
    end

    local radius = math.max(12, math.floor((base.radius or 15) * 2))
    local bx = base.center.x or 0
    local by = base.center.y or 0
    local bz = base.center.z or 0

    local nearCount = 0
    for i = 0, zombies:size() - 1 do
        local z = zombies:get(i)
        if z and z.getX and z.getY and z.getZ then
            if math.floor(z:getZ()) == bz then
                local d = sqDistance2D(bx, by, z:getX(), z:getY())
                if d <= radius then
                    nearCount = nearCount + 1
                end
            end
        end
    end

    return clamp(math.floor((nearCount / math.max(1, base.radius or 15)) * 100), 0, 100)
end

function NPCFactionManager:getBaseResourcePressure(base)
    local ids = self:getAssignedNPCList(base)
    if #ids == 0 then
        return 0
    end

    local hungerLow = 0
    local thirstLow = 0
    for i = 1, #ids do
        local npcId = ids[i]
        local data = self:getNPCData(npcId)
        local stats = data and data.stats or nil
        if stats then
            if (stats.hunger or 100) <= 35 then
                hungerLow = hungerLow + 1
            end
            if (stats.thirst or 100) <= 35 then
                thirstLow = thirstLow + 1
            end
        end
    end

    local ratio = (hungerLow + thirstLow) / (#ids * 2)
    return clamp(math.floor(ratio * 100), 0, 100)
end

function NPCFactionManager:computeDynamicRoleTargets(base)
    local ids = self:getAssignedNPCList(base)
    local total = #ids
    if total == 0 then
        return {
            guards = 0,
            cooks = 0,
            builders = 0,
            scavengers = 0,
            recover = 0,
            study = 0
        }
    end

    local incompleteSites = 0
    for i = 1, #(base.buildSites or {}) do
        if not base.buildSites[i].completed then
            incompleteSites = incompleteSites + 1
        end
    end

    local danger = self:getLocalDangerScore(base)
    local resources = self:getBaseResourcePressure(base)
    base.pressure = {
        danger = danger,
        resources = resources,
        updatedTick = self.tickCounter
    }

    local guards = 1
    local cooks = 1
    local builders = 1
    local scavengers = 1
    local recover = 0
    local study = 0

    if danger >= 65 then
        guards = math.max(2, math.floor(total * 0.5))
        scavengers = math.max(1, math.floor(total * 0.2))
        builders = math.max(1, math.floor(total * 0.15))
        cooks = math.max(1, math.floor(total * 0.15))
    elseif danger >= 35 then
        guards = math.max(1, math.floor(total * 0.35))
        scavengers = math.max(1, math.floor(total * 0.2))
        builders = math.max(1, math.floor(total * 0.25))
        cooks = math.max(1, math.floor(total * 0.2))
    else
        guards = math.max(1, math.floor(total * 0.2))
        builders = math.max(1, math.floor(total * 0.35))
        cooks = math.max(1, math.floor(total * 0.2))
        scavengers = math.max(1, math.floor(total * 0.15))
        study = math.max(0, total - (guards + builders + cooks + scavengers))
    end

    if resources >= 60 then
        scavengers = math.max(scavengers, math.floor(total * 0.35))
        cooks = math.max(cooks, math.floor(total * 0.3))
        builders = math.max(1, builders - 1)
    end

    if incompleteSites <= 0 then
        builders = 0
        study = math.max(study, 1)
    else
        builders = math.min(builders, incompleteSites)
    end

    local used = guards + cooks + builders + scavengers + recover + study
    while used > total do
        if builders > 0 then
            builders = builders - 1
        elseif study > 0 then
            study = study - 1
        elseif scavengers > 1 then
            scavengers = scavengers - 1
        elseif cooks > 1 then
            cooks = cooks - 1
        elseif guards > 1 then
            guards = guards - 1
        else
            break
        end
        used = guards + cooks + builders + scavengers + recover + study
    end

    local spare = total - used
    if spare > 0 then
        builders = builders + spare
    end

    local targets = {
        guards = guards,
        cooks = cooks,
        builders = builders,
        scavengers = scavengers,
        recover = recover,
        study = study
    }

    base.roleTargets = deepCopy(targets)
    return targets
end

function NPCFactionManager:assignNPCToBase(npcId, baseId)
    local base = self.bases[baseId]
    if not base then
        return false
    end

    base.assignedNPCs[npcId] = {
        joinedTick = self.tickCounter
    }

    self.npcToBase[npcId] = baseId

    if base.factionId and not self:getFactionOfNPC(npcId) then
        self:addNPCToFaction(npcId, base.factionId)
    end

    return true
end

function NPCFactionManager:getHour()
    if type(getGameTime) == "function" then
        local gt = getGameTime()
        if gt and gt.getHour then
            return gt:getHour()
        end
    end
    return 12
end

function NPCFactionManager:isNight(base)
    local hour = self:getHour()
    local startHour = base.nightStartHour
    local endHour = base.nightEndHour

    if startHour <= endHour then
        return hour >= startHour and hour < endHour
    end

    -- Cas classique 21 -> 6
    return hour >= startHour or hour < endHour
end

function NPCFactionManager:getAssignedNPCList(base)
    local ids = {}
    for npcId in pairs(base.assignedNPCs) do
        ids[#ids + 1] = npcId
    end
    table.sort(ids)
    return ids
end

function NPCFactionManager:getGuardSlot(base)
    local ids = self:getAssignedNPCList(base)
    if #ids == 0 then
        return nil, ids
    end

    if (self.tickCounter - base.rotation.lastRotationTick) >= base.rotationIntervalTicks then
        base.rotation.lastRotationTick = self.tickCounter
        base.rotation.guardIndex = (base.rotation.guardIndex % #ids) + 1
    end

    local guardId = ids[base.rotation.guardIndex]
    return guardId, ids
end

function NPCFactionManager:_buildGuardParams(base)
    return {
        automatic = true,
        baseId = base.id,
        center = base.center,
        radius = base.radius,
        waypointMode = "loop",
        waypoints = base.perimeterPoints,
        perimeter = base.perimeterPoints,
        expiresTick = self.tickCounter + base.rotationIntervalTicks
    }
end

function NPCFactionManager:runBaseNightRotation(base)
    local guardId, ids = self:getGuardSlot(base)
    if not guardId then
        return
    end

    local faction = self:getFaction(base.factionId)
    local issuerId = faction and faction.leaderNpcId or guardId

    for i = 1, #ids do
        local npcId = ids[i]
        if npcId == guardId then
            self:issueOrder("npc", issuerId, { npcId }, self.orderType.GUARD, self:_buildGuardParams(base))
        else
            self:issueOrder("npc", issuerId, { npcId }, self.orderType.SLEEP, {
                automatic = true,
                baseId = base.id,
                center = base.center,
                expiresTick = self.tickCounter + base.rotationIntervalTicks
            })
        end
    end
end

function NPCFactionManager:runBaseDayPlan(base)
    local ids = self:getAssignedNPCList(base)
    if #ids == 0 then
        return
    end

    local faction = self:getFaction(base.factionId)
    local issuerId = faction and faction.leaderNpcId or ids[1]
    local targets = self:computeDynamicRoleTargets(base)
    local assigned = {
        guards = 0,
        cooks = 0,
        builders = 0,
        scavengers = 0,
        recover = 0,
        study = 0
    }

    for i = 1, #ids do
        local npcId = ids[i]
        local data = self:getNPCData(npcId)
        local stats = data and data.stats or {}
        local ord = self.orderType.DEFEND
        local params = {
            automatic = true,
            baseId = base.id,
            center = base.center,
            radius = base.radius,
            waypointMode = "loop",
            waypoints = base.perimeterPoints,
            expiresTick = self.tickCounter + math.floor(base.rotationIntervalTicks * 0.6)
        }

        if assigned.guards < targets.guards and (stats.courage or 50) >= 40 then
            ord = self.orderType.DEFEND
            assigned.guards = assigned.guards + 1
        elseif assigned.cooks < targets.cooks and ((stats.intelligence or 50) >= 30) then
            ord = self.orderType.COOK
            assigned.cooks = assigned.cooks + 1
        elseif assigned.scavengers < targets.scavengers then
            ord = self.orderType.SCAVENGE
            assigned.scavengers = assigned.scavengers + 1
        elseif assigned.builders < targets.builders then
            ord = self.orderType.BUILD
            assigned.builders = assigned.builders + 1
            local site = self:reserveBuildSiteForNPC(base, npcId)
            if site then
                params.buildSiteId = site.id
                params.center = { x = site.x, y = site.y, z = site.z }
            end
        elseif assigned.study < targets.study then
            ord = self.orderType.STUDY
            assigned.study = assigned.study + 1
        else
            if (stats.hunger or 100) <= 25 or (stats.thirst or 100) <= 25 then
                ord = self.orderType.RECOVER
                assigned.recover = assigned.recover + 1
            else
                ord = self.orderType.DEFEND
                assigned.guards = assigned.guards + 1
            end
        end

        self:issueOrder("npc", issuerId, { npcId }, ord, params)
    end
end

function NPCFactionManager:getBaseNeedProfile(base)
    local ids = self:getAssignedNPCList(base)
    local profile = {
        total = #ids,
        guards = 0,
        cooks = 0,
        builders = 0,
        scholars = 0,
        recovers = 0
    }

    for i = 1, #ids do
        local npcId = ids[i]
        local ord = self:getOrder(npcId)
        local t = ord and ord.orderType or nil
        if t == self.orderType.GUARD or t == self.orderType.DEFEND or t == self.orderType.PATROL then
            profile.guards = profile.guards + 1
        elseif t == self.orderType.COOK then
            profile.cooks = profile.cooks + 1
        elseif t == self.orderType.BUILD then
            profile.builders = profile.builders + 1
        elseif t == self.orderType.STUDY then
            profile.scholars = profile.scholars + 1
        elseif t == self.orderType.RECOVER then
            profile.recovers = profile.recovers + 1
        end
    end

    return profile
end

function NPCFactionManager:suggestAutonomousOrder(npcId, npcData)
    if self:getOrder(npcId) then
        return nil
    end

    local stats = npcData and npcData.stats
    if not stats then
        return nil
    end

    local base, baseId = self:getBaseOfNPC(npcId)
    local needsFood = stats.hunger <= 30
    local needsWater = stats.thirst <= 30

    -- Besoins personnels prioritaires.
    if needsFood or needsWater then
        local orderType = self.orderType.COOK
        if stats.hunger <= 15 or stats.thirst <= 15 then
            orderType = self.orderType.RECOVER
        end

        return {
            issuerType = "npc",
            issuerId = npcId,
            orderType = orderType,
            params = {
                automatic = true,
                baseId = baseId,
                center = base and base.center or nil,
                radius = base and base.radius or 8,
                expiresTick = self.tickCounter + 160
            }
        }
    end

    -- Sinon, contribuer a l'amelioration de la base (joueur ou NPC).
    if base then
        local profile = self:getBaseNeedProfile(base)
        local targets = base.roleTargets
        local lastUpdate = (base.pressure and base.pressure.updatedTick) or 0
        if type(targets) ~= "table" or (self.tickCounter - lastUpdate) > math.max(60, self.autoSocietyEveryTicks) then
            targets = self:computeDynamicRoleTargets(base)
        end
        local isNightTime = self:isNight(base)

        if isNightTime and profile.guards < math.max(1, targets.guards) then
            return {
                issuerType = "npc",
                issuerId = npcId,
                orderType = self.orderType.GUARD,
                params = self:_buildGuardParams(base)
            }
        end

        if profile.cooks < math.max(1, targets.cooks) then
            return {
                issuerType = "npc",
                issuerId = npcId,
                orderType = self.orderType.COOK,
                params = {
                    automatic = true,
                    baseId = base.id,
                    center = base.center,
                    radius = base.radius,
                    expiresTick = self.tickCounter + 220
                }
            }
        end

        local craft = stats.craftSkill or 0
        local intel = stats.intelligence or 0
        if craft < 65 and profile.builders < math.max(1, targets.builders) then
            local site = self:reserveBuildSiteForNPC(base, npcId)
            return {
                issuerType = "npc",
                issuerId = npcId,
                orderType = self.orderType.BUILD,
                params = {
                    automatic = true,
                    baseId = base.id,
                    center = site and { x = site.x, y = site.y, z = site.z } or base.center,
                    radius = base.radius,
                    waypointMode = "loop",
                    waypoints = base.perimeterPoints,
                    buildSiteId = site and site.id or nil,
                    expiresTick = self.tickCounter + 220
                }
            }
        end

        if intel < 70 and profile.scholars < math.max(0, targets.study) then
            return {
                issuerType = "npc",
                issuerId = npcId,
                orderType = self.orderType.STUDY,
                params = {
                    automatic = true,
                    baseId = base.id,
                    center = base.center,
                    expiresTick = self.tickCounter + 200
                }
            }
        end

        return {
            issuerType = "npc",
            issuerId = npcId,
            orderType = self.orderType.DEFEND,
            params = {
                automatic = true,
                baseId = base.id,
                center = base.center,
                radius = base.radius,
                waypointMode = "loop",
                waypoints = base.perimeterPoints,
                expiresTick = self.tickCounter + 180
            }
        }
    end

    -- Sans base: progression autonome de survie.
    local roll = randInt(1, 100)
    if roll <= 35 then
        return {
            issuerType = "npc",
            issuerId = npcId,
            orderType = self.orderType.SCAVENGE,
            params = { automatic = true, expiresTick = self.tickCounter + 140 }
        }
    elseif roll <= 70 then
        return {
            issuerType = "npc",
            issuerId = npcId,
            orderType = self.orderType.RECOVER,
            params = { automatic = true, expiresTick = self.tickCounter + 140 }
        }
    end

    return {
        issuerType = "npc",
        issuerId = npcId,
        orderType = self.orderType.STUDY,
        params = { automatic = true, expiresTick = self.tickCounter + 140 }
    }
end

function NPCFactionManager:updateSedentarization()
    for _, base in pairs(self.bases) do
        if self:isNight(base) then
            self:runBaseNightRotation(base)
        else
            self:runBaseDayPlan(base)
        end
    end
end

function NPCFactionManager:autoRecruitmentPass()
    local ids = self:getAllActiveNPCIds()
    if #ids < 2 then
        return
    end

    for i = 1, #ids do
        local recruiterId = ids[i]
        local recruiterFaction = self:getFactionOfNPC(recruiterId)
        if recruiterFaction then
            local targetId = ids[randInt(1, #ids)]
            if targetId ~= recruiterId then
                self:recruitNPCByNPC(recruiterId, targetId)
            end
        end
    end
end

function NPCFactionManager:autoSocietyOrdersPass()
    for factionId, faction in pairs(self.factions) do
        local leaderId = faction.leaderNpcId
        if not leaderId then
            for npcId in pairs(faction.membersNPC) do
                leaderId = npcId
                faction.leaderNpcId = npcId
                break
            end
        end

        if leaderId then
            local shareBudget = 0
            for npcId in pairs(faction.membersNPC) do
                if NPCMemory and npcId ~= leaderId and shareBudget < 3 then
                    local ok = self:ShareMemoryBetweenNPCs(leaderId, npcId, "faction_sync")
                    if ok then
                        shareBudget = shareBudget + 1
                    end
                end

                if npcId ~= leaderId then
                    local current = self:getOrder(npcId)
                    if not current then
                        local dice = randInt(1, 100)
                        local action = self.orderType.PATROL
                        if dice <= 18 then
                            action = self.orderType.RECOVER
                        elseif dice <= 34 then
                            action = self.orderType.STUDY
                        elseif dice <= 50 then
                            action = self.orderType.COOK
                        elseif dice <= 66 then
                            action = self.orderType.BUILD
                        elseif dice <= 82 then
                            action = self.orderType.DEFEND
                        end

                        self:issueOrder("npc", leaderId, { npcId }, action, {
                            automatic = true,
                            expiresTick = self.tickCounter + 240
                        })
                    end
                end
            end
        end

        -- Les relations inter-factions peuvent evoluer automatiquement.
        for otherFactionId in pairs(self.factions) do
            if otherFactionId ~= factionId then
                local rel = self:getRelation(factionId, otherFactionId)
                local roll = randInt(1, 1000)
                if rel == self.relation.NEUTRAL and roll <= 2 then
                    self:setRelation(factionId, otherFactionId, self.relation.ALLY)
                elseif rel == self.relation.NEUTRAL and roll >= 998 then
                    self:setRelation(factionId, otherFactionId, self.relation.WAR)
                elseif rel == self.relation.WAR and roll <= 2 then
                    self:setRelation(factionId, otherFactionId, self.relation.TRUCE)
                end
            end
        end
    end
end

function NPCFactionManager:update()
    if not isServerRuntime() then
        return
    end

    self.tickCounter = self.tickCounter + 1
    if (self.tickCounter % self.updateEveryTicks) ~= 0 then
        return
    end

    if (self.tickCounter % self.autoRecruitEveryTicks) == 0 then
        self:autoRecruitmentPass()
    end

    if (self.tickCounter % self.autoAffiliationEveryTicks) == 0 then
        self:autoAffiliationPass()
    end

    if (self.tickCounter % self.autoSocietyEveryTicks) == 0 then
        self:autoSocietyOrdersPass()
    end

    self:updateSedentarization()
end

function NPCFactionManager:start()
    if Events and Events.OnTick then
        Events.OnTick.Add(function()
            NPCFactionManager:update()
        end)
    end
end

NPCFactionManager:start()

return NPCFactionManager
