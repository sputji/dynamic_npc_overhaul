-- ?? GameModeDetector.lua
-- Dynamic NPC Overhaul v2.1 - Detect SOLO vs MULTIJOUEUR
-- Fichier: media/lua/shared/GameModeDetector.lua
-- Purpose: Provide centralized game mode detection for SOLO vs MULTI branching
-- Auteur: Dynamic NPC Overhaul Maintainers
-- Version: v1.0.5 (12 mai 2026)

local GameModeDetector = {}

-- ============================================================================
-- PUBLIC API
-- ============================================================================

--- Detect current game mode
-- @return "SOLO" | "MULTI_SERVER" | "MULTI_CLIENT"
function GameModeDetector:detectMode()
    -- isServer() = LUA SERVER (dedicated or host)
    -- isClient() = LUA CLIENT (player connected to server)
    
    local hasServer = isServer ~= nil and isServer()
    local hasClient = isClient ~= nil and isClient()
    
    if hasServer and not hasClient then
        -- Dedicated server or host-only authority
        return "MULTI_SERVER"
    elseif hasClient and not hasServer then
        -- Pure client connecting to remote server
        return "MULTI_CLIENT"
    elseif hasServer and hasClient then
        -- Single-player mode: both server and client in same process
        return "SOLO"
    else
        -- Fallback: unknown state, assume SOLO
        return "SOLO"
    end
end

--- Check if current game is SOLO
-- @return boolean true if SOLO mode
function GameModeDetector:isSolo()
    return self:detectMode() == "SOLO"
end

--- Check if current game is MULTIJOUEUR (server authority)
-- @return boolean true if server
function GameModeDetector:isMultiServer()
    return self:detectMode() == "MULTI_SERVER"
end

--- Check if current game is MULTIJOUEUR (client)
-- @return boolean true if client
function GameModeDetector:isMultiClient()
    return self:detectMode() == "MULTI_CLIENT"
end

--- Check if running any MULTI mode (server or client)
-- @return boolean true if MULTI (not SOLO)
function GameModeDetector:isMulti()
    local mode = self:detectMode()
    return mode == "MULTI_SERVER" or mode == "MULTI_CLIENT"
end

--- Get descriptive string for logging
-- @return string "SOLO", "MULTI (server)", or "MULTI (client)"
function GameModeDetector:getModeString()
    local mode = self:detectMode()
    if mode == "SOLO" then
        return "SOLO"
    elseif mode == "MULTI_SERVER" then
        return "MULTI (server)"
    elseif mode == "MULTI_CLIENT" then
        return "MULTI (client)"
    else
        return "UNKNOWN"
    end
end

-- ============================================================================
-- DEBUG UTILITIES
-- ============================================================================

--- Log current mode (for debug)
function GameModeDetector:logMode()
    if PHNPC_Logger then
        PHNPC_Logger:info("[GameModeDetector] Current mode: " .. self:getModeString())
        PHNPC_Logger:debug("[GameModeDetector] isServer=" .. tostring(isServer()) .. ", isClient=" .. tostring(isClient()))
    else
        print("[GameModeDetector] Current mode: " .. self:getModeString())
    end
end

--- Get debug info
-- @return table with detection details
function GameModeDetector:getDebugInfo()
    return {
        mode = self:detectMode(),
        isSolo = self:isSolo(),
        isMulti = self:isMulti(),
        isServer = isServer ~= nil and isServer() or false,
        isClient = isClient ~= nil and isClient() or false,
        modeString = self:getModeString(),
    }
end

-- ============================================================================
-- EXPORTS
-- ============================================================================

-- OnGameBoot n'existe pas en Build 41 ; on utilise OnGameStart avec un garde pcall
if type(Events) ~= "nil" and Events.OnGameStart then
    local ok = pcall(function()
        Events.OnGameStart.Add(function()
            if PHNPC_Logger then
                PHNPC_Logger:debug("[GameModeDetector] Boot mode detection: " .. GameModeDetector:getModeString())
            end
        end)
    end)
    if not ok then
        print("[GameModeDetector] Warning: could not subscribe to OnGameStart")
    end
end

return GameModeDetector
