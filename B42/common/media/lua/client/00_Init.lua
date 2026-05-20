--[[
    Project Humain : Dynamic NPC Overhaul — B42
    client/00_Init.lua

    Bootstrap du côté client.
    Chargé en premier par ordre alphabétique ("00_").

    Responsabilités :
      • Déclare PHNPC._activeNPCs (registre des PNJs vivants sur ce client)
      • Log du démarrage
      • Enregistre le handler de la commande réseau PHNPC_SpawnConfirm
        (réponse du serveur après un spawn réussi en mode multijoueur)
]]

-- Registre { [isoZombie] = NPCDataModel } partagé par tous les modules client.
PHNPC._activeNPCs = PHNPC._activeNPCs or {}

-- File d'attente client des PNJs spawned côté serveur, non encore détectés
-- par Events.OnZombieUpdate. Chaque entrée : { x, y, isFemale, outfit, name }
-- Utilisée par NPC_FollowTick comme méthode C de détection cross-VM.
PHNPC._pendingNPCs = PHNPC._pendingNPCs or {}

-- ============================================================
-- Démarrage
-- ============================================================

local function disableTieredUpdates()
    -- CRITIQUE (cf. Bandits BanditZombie.lua) :
    -- En B42, "tiered zombie updates" empêche Events.OnZombieUpdate de firer
    -- pour les zombies hors de la zone d'attention du joueur.
    -- On le désactive pour garantir que nos NPCs reçoivent le hook chaque tick.
    local ok, err = pcall(function()
        getCore():setOptionTieredZombieUpdates(false)
    end)
    if not ok then
        print("[PHNPC][WARN] setOptionTieredZombieUpdates échoué : " .. tostring(err))
    end
end

Events.OnGameStart.Add(function()
    disableTieredUpdates()
    local Log = PHNPC.getModule("NPC_Logger")
    if Log then
        Log.info("Client/Init", "Corps client B42 prêt",
            { version = PHNPC.VERSION, env = PHNPC.env() })
    end
end)

-- Maintenir la désactivation toutes les minutes (le jeu peut la réactiver)
Events.EveryOneMinute.Add(disableTieredUpdates)

-- ============================================================
-- Handler commande serveur → client : PHNPC_SpawnConfirm
-- Reçu quand le serveur confirme (ou refuse) un spawn en multi.
-- En solo, ce handler n'est jamais déclenché (spawn direct côté serveur).
-- ============================================================

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= PHNPC.MOD_ID then return end
    if command ~= "PHNPC_SpawnConfirm" then return end

    local Log = PHNPC.getModule("NPC_Logger")

    if args and args.success then
        -- Stocker le PNJ en attente : NPC_FollowTick.onZombieUpdate
        -- l'identifiera par proximité de position (méthode C cross-VM).
        table.insert(PHNPC._pendingNPCs, {
            x        = tonumber(args.x)   or 0,
            y        = tonumber(args.y)   or 0,
            isFemale = args.isFemale      or false,
            outfit   = args.outfit        or "Survivor",
            name     = args.name          or "Survivant",
        })
        if Log then
            Log.ok("Client/Init", "PNJ en attente de conversion",
                { name = tostring(args.name), x = tostring(args.x), y = tostring(args.y),
                  pending = tostring(#PHNPC._pendingNPCs) })
        end
    else
        if Log then Log.warn("Client/Init", "Spawn refusé par le serveur") end
    end
end)
