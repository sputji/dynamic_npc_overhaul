--[[
    Project Humain : Dynamic_NPC_Overhaul
    NPC_NetworkClient.lua

    Client reseau pour sync multijoueur des PNJ.
    - Recoit positions/animations/attaques du serveur
    - Demande dialogues au serveur (Ollama centralise)
    - Applique ordres d'affichage optimises
    - N'execute AUCUN calcul lourd d'IA cote client
]]

local NPC_NetworkClient = {
    module = "PH_NPC_NETWORK",
    syncCommand = "NPCSyncState",
    dialogueRequestCommand = "DialogueRequest",
    dialogueResponseCommand = "DialogueResponse",
    dialoguePendingCommand = "DialoguePending",
    fxCommand = "NPCFx",
    
    -- Cache etats PNJ recus du serveur
    npcStates = {},
    
    -- Callbacks pour dialogue responses
    dialogueCallbacks = {},
    lastRequestByNpc = {},

    -- Entites IsoPlayer locales creees par le client (coop/multi)
    localNPCEntities = {}
}


local function emitRealtimeEvent(payload)
    if type(payload) ~= "table" then
        return
    end

    if type(triggerEvent) == "function" then
        pcall(function()
            triggerEvent("OnRealtimeEvent", payload)
        end)
        return
    end

    if Events and Events.OnRealtimeEvent and Events.OnRealtimeEvent.trigger then
        pcall(function()
            Events.OnRealtimeEvent:trigger(payload)
        end)
    end
end

local function getLocalPlayerSafe()
    if type(getSpecificPlayer) == "function" then
        return getSpecificPlayer(0)
    end
    return nil
end

local function tryPlayEmitterSound(soundName)
    local player = getLocalPlayerSafe()
    if not player or not player.getEmitter then
        return false
    end

    local emitter = player:getEmitter()
    if not emitter or type(emitter.playSound) ~= "function" then
        return false
    end

    local ok, result = pcall(function()
        return emitter:playSound(soundName)
    end)
    return ok and result ~= nil
end

local function playNativeFx(fxType)
    local candidates = nil
    if fxType == "npc_cough" then
        candidates = { "MaleZombieAttack", "FemaleZombieAttack", "ZombieBite", "MaleZombieGroan", "FemaleZombieGroan" }
    elseif fxType == "npc_hurt" then
        candidates = { "MaleZombieHurt", "FemaleZombieHurt", "ZombieHit", "ZombieGroan", "Bite" }
    elseif fxType == "npc_build" then
        candidates = { "HammerHit", "PZ_Hammer", "CarpentryHammer", "Hammer", "Saw", "ChopWood" }
    elseif fxType == "npc_eat" then
        candidates = { "Eat", "OpenCan", "Bag", "EatFood" }
    elseif fxType == "npc_drink" then
        candidates = { "Drink", "SipWater", "PourWater", "Bottle" }
    elseif fxType == "npc_trade" then
        candidates = { "Paper", "BookFlip", "Coin", "InventoryItem" }
    elseif fxType == "npc_cook" then
        candidates = { "Stove", "Pan", "Cook", "PourWater" }
    elseif fxType == "npc_scavenge" then
        candidates = { "FootstepGrass", "FootstepConcrete", "Rummage", "ItemPickup" }
    elseif fxType == "npc_study" then
        candidates = { "BookFlip", "Paper", "Pencil" }
    elseif fxType == "npc_guard" or fxType == "npc_defend" then
        candidates = { "ZombieAlert", "MaleZombieAttack", "FemaleZombieAttack", "BatSwing" }
    elseif fxType == "npc_follow" then
        candidates = { "FootstepGrass", "FootstepConcrete", "FootstepRunGrass" }
    elseif fxType == "npc_patrol" then
        candidates = { "FootstepGrass", "FootstepConcrete", "FootstepRunGrass", "WalkieTalkieStatic" }
    elseif fxType == "npc_watch" then
        candidates = { "BreathOut", "BreathIn", "FootstepConcrete", "FootstepGrass" }
    elseif fxType == "npc_recover" or fxType == "npc_sleep" then
        candidates = { "Sleeping", "BreathIn", "BreathOut" }
    elseif fxType == "npc_wake" then
        candidates = { "BreathIn", "BreathOut", "FootstepGrass", "FootstepConcrete" }
    elseif fxType == "npc_fatigue" then
        candidates = { "BreathIn", "BreathOut", "HeartBeat", "Tired" }
    elseif fxType == "npc_flee" or fxType == "npc_run" then
        candidates = { "FootstepRunGrass", "FootstepRunConcrete", "BreathIn", "BreathOut" }
    elseif fxType == "npc_walk" or fxType == "npc_idle" then
        candidates = { "FootstepGrass", "FootstepConcrete", "BreathOut" }
    elseif fxType == "npc_combat" then
        candidates = { "ZombieAttack", "ZombieHurt", "BatSwing", "AxeSwing", "Crowbar", "PipeSwing" }
    elseif fxType == "npc_medical" then
        candidates = { "Bandage", "Pill", "Pain", "Heartbeat" }
    elseif fxType == "npc_social_talk" then
        candidates = { "Paper", "BookFlip", "BreathOut" }
    elseif fxType == "npc_social_trade" then
        candidates = { "Paper", "Coin", "InventoryItem", "BookFlip" }
    elseif fxType == "npc_social_threat" then
        candidates = { "ZombieAlert", "ZombieGroan", "MaleZombieAttack", "FemaleZombieAttack" }
    end

    if type(candidates) ~= "table" then
        return
    end

    for i = 1, #candidates do
        if tryPlayEmitterSound(candidates[i]) then
            return
        end
    end
end

local function resolveCurrentLanguageCode()
    local defaultCode = "EN"

    if not Translator or not Translator.getLanguage then
        return defaultCode
    end

    local ok, langObj = pcall(function()
        return Translator.getLanguage()
    end)
    if not ok or not langObj then
        return defaultCode
    end

    local langCode = tostring(langObj)
    if langObj.toString then
        local okToString, asString = pcall(function()
            return langObj:toString()
        end)
        if okToString and asString and #tostring(asString) > 0 then
            langCode = tostring(asString)
        end
    end

    langCode = string.upper(tostring(langCode or defaultCode))
    langCode = langCode:gsub("[^A-Z]", "")
    if #langCode >= 2 then
        return langCode:sub(1, 2)
    end

    return defaultCode
end

-- ==============================================================================
-- RECOIT SYNC depuis le serveur
-- ==============================================================================

function NPC_NetworkClient:onNPCSyncState(args)
    -- Recoit mise a jour position/animation/health d'un PNJ
    
    if not args or not args.npcId then
        return
    end

    -- Stocke l'etat
    self.npcStates[args.npcId] = args

    -- Applique visuellement (si on avait l'entite locale)
    self:applyNPCVisuals(args)
end

function NPC_NetworkClient:applyNPCVisuals(state)
    -- Applique les changements visuels recus du serveur
    -- (Dans une vraie implementation, chercher l'entite et la mettre a jour)
    
    if not state then
        return
    end

    -- Debug log
    if state.moving then
        print(string.format("[NPC_Sync] PNJ %s se deplace vers (%.1f, %.1f, %.1f)", 
            state.npcId, state.x, state.y, state.z))
    end

    if state.attacking then
        print(string.format("[NPC_Sync] PNJ %s attaque!", state.npcId))
    end

    if state.health < 50 and state.health > 0 then
        print(string.format("[NPC_Sync] PNJ %s est blesse (sante: %.0f%%)", state.npcId, state.health))
    end

    -- TODO: Appliquer animation reelle si entite trouvee
    -- TODO: Mettre a jour sprite/position dans scene si multijoueur
end

-- ==============================================================================
-- DEMANDE DIALOGUES: Envoie au serveur
-- ==============================================================================

function NPC_NetworkClient:requestDialogue(npcId, userMessage, callback)
    -- Demande dialogue au serveur (sera traite par Ollama ou fallback serveur)
    
    if not npcId or not userMessage or not callback then
        return false
    end

    if not sendClientCommand then
        callback("Erreur reseau", true)
        return false
    end

    -- Genere ID unique pour tracker callback
    local requestId = npcId .. "_" .. os.time() .. "_" .. math.random(10000)
    self.dialogueCallbacks[requestId] = callback
    self.lastRequestByNpc[npcId] = requestId

    -- Envoie requete serveur
    sendClientCommand(self.module, self.dialogueRequestCommand, {
        npcId = npcId,
        userMessage = userMessage,
        requestId = requestId,
        playerLanguage = resolveCurrentLanguageCode()
    })

    return true
end

-- ==============================================================================
-- RECOIT RESPONSES depuis le serveur
-- ==============================================================================

function NPC_NetworkClient:onDialogueResponse(args)
    -- Recoit reponse dialogue du serveur
    
    if not args or not args.npcId then
        return
    end

    local npcId = args.npcId
    local requestId = args.requestId or self.lastRequestByNpc[npcId]
    local response = args.response or "..."
    local isError = args.isError == true

    if requestId and self.dialogueCallbacks[requestId] then
        local cb = self.dialogueCallbacks[requestId]
        self.dialogueCallbacks[requestId] = nil
        if type(cb) == "function" then
            pcall(cb, response, isError)
        end
    end

    -- Appelle callback enregistre (UI ou autre)
    -- Broadcast event real-time pour OllamaChatUI
    emitRealtimeEvent({
        eventType = "DialogueResponse",
        npcId = npcId,
        requestId = requestId,
        response = response,
        isError = isError
    })

    print(string.format("[NPC_Dialogue] Reponse PNJ %s: %s", npcId, response))
end

function NPC_NetworkClient:onDialoguePending(args)
    if not args or not args.npcId then
        return
    end

    emitRealtimeEvent({
        eventType = "DialoguePending",
        npcId = args.npcId,
        requestId = args.requestId,
        pending = args.pending == true
    })
end

function NPC_NetworkClient:onNPCFx(args)
    if not args or not args.fxType then
        return
    end

    playNativeFx(args.fxType)

    emitRealtimeEvent({
        eventType = "NPCFx",
        npcId = args.npcId,
        fxType = args.fxType,
        x = args.x,
        y = args.y,
        z = args.z
    })
end

-- ==============================================================================
-- INTEGRATION UI: Hook OllamaChatUI
-- ==============================================================================

function NPC_NetworkClient:sendMessage(npcId, userMessage)
    -- Appele depuis OllamaChatUI quand l'utilisateur envoie un message
    
    self:requestDialogue(npcId, userMessage, function(response, isError)
        -- Callback: response recue via onDialogueResponse
        print("[NPC_NetworkClient] Dialogue callback recu")
    end)
end

-- ==============================================================================
-- EVENT REGISTRATION
-- ==============================================================================

-- ==============================================================================
-- COOP/MULTI: Gestion entites IsoPlayer locales (PH_NPC_SYNC)
-- ==============================================================================

local function onPHNPCSyncCommand(module, command, args)
    if module ~= "PH_NPC_SYNC" then return end
    if not args then return end

    if command == "NPCSpawn" then
        if not args.npcId then return end
        -- Ne pas creer deux fois la meme entite
        if NPC_NetworkClient.localNPCEntities[args.npcId] then return end

        local world = getWorld and getWorld() or nil
        if not world or not IsoPlayer or not IsoPlayer.new or not SurvivorFactory then return end

        local isFemale = args.isFemale == true
        local descriptor = SurvivorFactory.CreateSurvivor(SurvivorType.Neutral, isFemale)
        if not descriptor then return end

        local ok, npc = pcall(function()
            return IsoPlayer.new(world:getCell(), descriptor, args.x or 0, args.y or 0, args.z or 0)
        end)
        if not ok or not npc then return end

        if npc.setNPC then pcall(function() npc:setNPC(true) end) end
        if npc.setGodMod then pcall(function() npc:setGodMod(false) end) end
        if npc.setSceneCulled then pcall(function() npc:setSceneCulled(false) end) end
        if npc.setInvisible then pcall(function() npc:setInvisible(false) end) end
        if npc.setCanBeZombie then pcall(function() npc:setCanBeZombie(false) end) end
        if npc.setBlockMovement then pcall(function() npc:setBlockMovement(false) end) end
        if args.outfit and npc.dressInNamedOutfit then
            pcall(function() npc:dressInNamedOutfit(tostring(args.outfit)) end)
        end
        if args.name and npc.setDisplayName then
            pcall(function() npc:setDisplayName(tostring(args.name)) end)
        end

        NPC_NetworkClient.localNPCEntities[args.npcId] = npc
        print(string.format("[NPC_SYNC] PNJ cree localement: %s", tostring(args.npcId)))

    elseif command == "NPCUpdate" then
        if not args.npcId then return end
        local npc = NPC_NetworkClient.localNPCEntities[args.npcId]
        if not npc then return end

        if args.x and args.y then
            if npc.getPathFindBehavior2 then
                pcall(function()
                    local pfb = npc:getPathFindBehavior2()
                    if pfb and pfb.pathToLocation then
                        pfb:pathToLocation(args.x, args.y, args.z or 0)
                    end
                end)
            end
        end
        if npc.NPCSetRunning then
            pcall(function() npc:NPCSetRunning(args.isRunning == true) end)
        end
        if not args.isRunning and npc.NPCSetWalking then
            pcall(function() npc:NPCSetWalking(true) end)
        end

    elseif command == "NPCDespawn" then
        if not args.npcId then return end
        local npc = NPC_NetworkClient.localNPCEntities[args.npcId]
        if npc then
            if npc.removeFromWorld then pcall(function() npc:removeFromWorld() end) end
            if npc.removeFromSquare then pcall(function() npc:removeFromSquare() end) end
            NPC_NetworkClient.localNPCEntities[args.npcId] = nil
            print(string.format("[NPC_SYNC] PNJ supprime localement: %s", tostring(args.npcId)))
        end
    end
end

function NPC_NetworkClient:registerListeners()
    print("[NPC_NetworkClient] Enregistrement des listeners multijoueur")
    
    if Events and Events.OnServerCommand then
        Events.OnServerCommand.Add(function(module, command, args)
            if module == self.module then
                if command == self.syncCommand then
                    NPC_NetworkClient:onNPCSyncState(args)
                elseif command == self.dialogueResponseCommand then
                    NPC_NetworkClient:onDialogueResponse(args)
                elseif command == self.dialoguePendingCommand then
                    NPC_NetworkClient:onDialoguePending(args)
                elseif command == self.fxCommand then
                    NPC_NetworkClient:onNPCFx(args)
                end
            end
        end)
        -- Sync spawn/update/despawn IsoPlayer depuis le serveur MULTI
        Events.OnServerCommand.Add(onPHNPCSyncCommand)
    end
end

function NPC_NetworkClient:init()
    self:registerListeners()
    print("[NPC_NetworkClient] Reseau multijoueur actif (client)")
end

-- Initialise client
if not isServer then
    NPC_NetworkClient:init()
end

_G.NPC_NetworkClient = NPC_NetworkClient

return NPC_NetworkClient
