--[[
    PHNPC_Manager.lua  v0.14  (client)
    Module principal du Dynamic NPC Overhaul.
    La logique est repartie dans des fichiers specialises :
      PHNPC_Actions.lua    -- deplacement + fix proximity
      PHNPC_Barks.lua      -- barks (fix getText() timing)
      PHNPC_Combat.lua     -- IA combat / fuite
      PHNPC_Convert.lua    -- spawn NPC
      PHNPC_Debug.lua      -- menu debug [DEBUG_PHNPC] (existant)
      PHNPC_Enforce.lua    -- enforce comportement NPC (fix animation)
      PHNPC_Health.lua     -- sante NPC (existant)
      PHNPC_Inventory.lua  -- inventaire NPC
      PHNPC_Menu.lua       -- menu contextuel clic-droit
      PHNPC_Orders.lua     -- ordres recrut/follow/stay/dismiss/delete/attack/flee
      PHNPC_Update.lua     -- events OnZombieUpdate / OnTick / OnGameStart
    Necessite (shared) : PHNPC_Core.lua  PHNPC_Stats.lua
]]
print("[PHNPC] PHNPC_Manager v0.14 loaded")
