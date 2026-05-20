-- Project Humain: Dynamic NPC Overhaul - B42
-- client/00_Init.lua - Client bootstrap

-- Init NPC registry (shared with NPC_FollowTick.lua)
PHNPC.npcs = PHNPC.npcs or {}

-- Disable tiered zombie updates so NPC events fire correctly
local function disableTieredUpdates()
    pcall(function()
        getCore():setOptionTieredZombieUpdates(false)
    end)
end

Events.OnGameStart.Add(function()
    disableTieredUpdates()
    print("[PHNPC] Client B42 ready - v" .. (PHNPC.VERSION or "?"))
end)

-- Maintain the setting each minute (game may re-enable it)
Events.EveryOneMinute.Add(disableTieredUpdates)

print("[PHNPC] client/00_Init.lua loaded")