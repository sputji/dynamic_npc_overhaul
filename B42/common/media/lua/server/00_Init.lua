--[[
    Project Humain : Dynamic NPC Overhaul — B42
    server/00_Init.lua

    Bootstrap côté serveur.
    Chargé en premier par ordre alphabétique ("00_").

    En solo, ce fichier est chargé dans le même état Lua que le client.
    En multijoueur dédié, il tourne exclusivement sur le serveur.

    Rôle : log du démarrage serveur. La logique de spawn est dans
    server/NPC_SpawnManager.lua.
]]

Events.OnServerStarted.Add(function()
    local Log = PHNPC.getModule("NPC_Logger")
    if Log then
        Log.info("Server/Init", "Module serveur B42 démarré",
            { version = PHNPC.VERSION, env = PHNPC.env() })
    end
end)
