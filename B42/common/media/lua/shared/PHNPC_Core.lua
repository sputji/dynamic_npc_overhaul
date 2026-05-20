-- Project Humain: Dynamic NPC Overhaul - B42
-- shared/PHNPC_Core.lua
-- Global namespace. Loaded first (shared), available to both client and server contexts.
-- NO BOM. ASCII only.

PHNPC = PHNPC or {}
PHNPC.VERSION = "3.0.0"
PHNPC.MOD_ID  = "PH_DynamicNPCOverhaul"

-- Active NPC table: [IsoPlayer reference] = { id, forename, surname, fullname, isFemale, followMode }
-- Populated and managed by PHNPC_Manager (client side).
PHNPC.npcs = PHNPC.npcs or {}

print("[PHNPC] Core v" .. PHNPC.VERSION .. " (B42) loaded")
