--[[
    NPCSpawner.lua (DISPATCHER)
    Dynamic NPC Overhaul v2.1

    PURPOSE: Route vers NPCSpawner_SOLO (single-player) ou NPCSpawner_MULTI (placeholder).
    v1.0.5: Separation architecturale SOLO vs MULTI.
]]

-- Detection du mode de jeu
local hasDetector, GameModeDetector = pcall(require, "GameModeDetector")
local isMulti = hasDetector and GameModeDetector and GameModeDetector.isMulti and GameModeDetector:isMulti()

if isMulti then
    local okM, implM = pcall(require, "NPCSpawner_MULTI")
    if okM and type(implM) == "table" then
        print("[NPCSpawner] Mode MULTI detecte, chargement NPCSpawner_MULTI")
        return implM
    end
    print("[NPCSpawner] NPCSpawner_MULTI introuvable, repli sur SOLO")
end

local ok, impl = pcall(require, "NPCSpawner_SOLO")
if ok and type(impl) == "table" then
    return impl
end

-- Stub de securite si les deux echouent
return {
    activeNPCs  = {},
    dormantNPCs = {},
    despawnNPC      = function() return false end,
    spawnFromRecord = function() return false end,
}