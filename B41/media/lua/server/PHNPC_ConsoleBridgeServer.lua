--[[
    Bridge serveur pour Lua Command Line.
    Permet d'executer les commandes PHNPC meme si la console est cote serveur.
]]

PHNPC = PHNPC or {}


local function normalizeLine(line)
    if type(line) ~= "string" then
        return nil
    end

    local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed == "" then
        return nil
    end

    if string.sub(string.lower(trimmed), 1, 6) ~= "/phnpc" then
        return "/phnpc " .. trimmed
    end

    return trimmed
end

local function getFirstPlayer()
    if type(getOnlinePlayers) == "function" then
        local players = getOnlinePlayers()
        if players and players.size and players:size() > 0 then
            return players:get(0)
        end
    end

    if type(getNumActivePlayers) == "function" and type(getSpecificPlayer) == "function" then
        if getNumActivePlayers() > 0 then
            return getSpecificPlayer(0)
        end
    end

    return nil
end

local function runServer(line)
    local cmd = normalizeLine(line)
    if not cmd then
        print("[PHNPC][SERVER] Commande vide. Exemple: PHNPC.run('/phnpc status')")
        return false
    end

    if sendClientCommand then
        sendClientCommand("PH_NPC", "ConsoleCommand", {
            text = cmd,
            source = "LuaCommandLineServerFallback"
        })
        print("[PHNPC][SERVER] Commande redirigee vers client: " .. cmd)
        return true
    end

    if not (NPCSpawner and NPCSpawner.tryHandleChatCommand) then
        print("[PHNPC][SERVER] NPCSpawner indisponible")
        return false
    end

    local player = getFirstPlayer()
    local ok, err = pcall(function()
        NPCSpawner:tryHandleChatCommand(player, cmd)
    end)

    if ok then
        print("[PHNPC][SERVER] Commande executee: " .. cmd)
        return true
    end

    print("[PHNPC][SERVER] Erreur commande: " .. tostring(err))
    return false
end

PHNPC.runServer = runServer

if type(PHNPC.run) ~= "function" then
    PHNPC.run = runServer
end

function PHNPC.help()
    print("[PHNPC][SERVER] Utilisation:")
    print("[PHNPC][SERVER] PHNPC.run('/phnpc status')")
    print("[PHNPC][SERVER] PHNPC.run('/phnpc spawn 5')")
    print("[PHNPC][SERVER] PHNPC.run('/phnpc mark on')")
    print("[PHNPC][SERVER] PHNPC.run('/phnpc clear')")
    print("[PHNPC][SERVER] PHNPC.run('/phnpc respawn 5')")
end

print("[PHNPC][SERVER] Console bridge pret. Utilise PHNPC.run('/phnpc status')")
