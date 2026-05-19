--[[
    Project Humain : Dynamic NPC Overhaul — B42
    shared/NPC_NetworkDispatcher.lua

    Dispatcher réseau SOLO / MULTI.
    - SOLO  : zéro overhead réseau, appels directs en mémoire.
    MULTI : B42 API — CLIENT→SERVEUR : sendClientCommand(getPlayer(), mod, cmd, args)
             SERVEUR→CLIENT : sendServerCommand(player, mod, cmd, args).

    API unifiée : NPC_NetworkDispatcher.send(target, cmd, data)
      target = "server" | "client" | "all"
]]

local Log = PHNPC.getModule("NPC_Logger")

local NPC_NetworkDispatcher = {
    MOD_ID   = PHNPC.MOD_ID,
    _isSolo  = nil,  -- déterminé à OnGameStart
    _handlers = {},  -- { [cmd] = function(data, fromPlayer) }
}

-- ============================================================
-- Détection Solo / Multi
-- ============================================================

local function detectMode()
    local ok, solo = pcall(function()
        -- En B42, isCoopHost() indique un serveur hébergé par un joueur ;
        -- getNumActivePlayers() > 1 serait multi.
        if type(isCoopHost) == "function" and isCoopHost() then return false end
        if type(getServerOptions) == "function" then
            local opts = getServerOptions()
            if opts and opts:getOptionCount() > 0 then return false end
        end
        return true
    end)
    NPC_NetworkDispatcher._isSolo = (ok and solo == true) or false
    if Log then
        Log.info("NPC_NetworkDispatcher", "Mode détecté",
            { mode = NPC_NetworkDispatcher._isSolo and "SOLO" or "MULTI" })
    end
end

Events.OnGameStart.Add(detectMode)

-- ============================================================
-- Enregistrement des handlers (côté réception)
-- ============================================================

--- Enregistre un handler pour une commande.
-- @param cmd      string    Identifiant de commande
-- @param handler  function  fn(data, fromPlayer)
function NPC_NetworkDispatcher.on(cmd, handler)
    NPC_NetworkDispatcher._handlers[cmd] = handler
end

local function dispatch(cmd, data, fromPlayer)
    local h = NPC_NetworkDispatcher._handlers[cmd]
    if h then
        local ok, err = pcall(h, data, fromPlayer)
        if not ok and Log then
            Log.error("NPC_NetworkDispatcher", "Erreur handler " .. cmd, { err = tostring(err) })
        end
    end
end

-- ============================================================
-- Envoi
-- ============================================================

--- Envoie une commande.
-- @param target  "server" | "client" | "all"
-- @param cmd     string
-- @param data    table
-- @param player  IsoPlayer?  (cible spécifique en multi "client")
function NPC_NetworkDispatcher.send(target, cmd, data, player)
    if NPC_NetworkDispatcher._isSolo then
        -- Solo : appel direct
        dispatch(cmd, data, nil)
        return
    end

    -- Multi
    -- B42 : CLIENT→SERVEUR = sendClientCommand(player, mod, cmd, args)
    --        SERVEUR→CLIENT = sendServerCommand(player, mod, cmd, args)
    if target == "server" then
        -- Appelé depuis le client pour envoyer au serveur
        if type(sendClientCommand) == "function" then
            sendClientCommand(getPlayer(), NPC_NetworkDispatcher.MOD_ID, cmd, data or {})
        end
    elseif target == "client" then
        -- Appelé depuis le serveur pour envoyer à un client spécifique
        if type(sendServerCommand) == "function" then
            sendServerCommand(player, NPC_NetworkDispatcher.MOD_ID, cmd, data or {})
        end
    elseif target == "all" then
        -- Appelé depuis le serveur pour diffuser à tous les clients
        if type(sendServerCommand) == "function" then
            local players = getOnlinePlayers and getOnlinePlayers() or {}
            for i = 0, (players.size and players:size() or #players) - 1 do
                local p = players.get and players:get(i) or players[i + 1]
                if p then sendServerCommand(p, NPC_NetworkDispatcher.MOD_ID, cmd, data or {}) end
            end
        end
    end
end

-- ============================================================
-- Hooks PZ pour la réception
-- ============================================================

-- Côté serveur : reçoit les commandes des clients
Events.OnClientCommand.Add(function(modId, cmd, player, data)
    if modId ~= NPC_NetworkDispatcher.MOD_ID then return end
    dispatch(cmd, data, player)
end)

-- Côté client : reçoit les commandes du serveur
Events.OnServerCommand.Add(function(modId, cmd, data)
    if modId ~= NPC_NetworkDispatcher.MOD_ID then return end
    dispatch(cmd, data, nil)
end)

PHNPC.registerModule("NPC_NetworkDispatcher", NPC_NetworkDispatcher)
return NPC_NetworkDispatcher
