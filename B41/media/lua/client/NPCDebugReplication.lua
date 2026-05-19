--[[
    Project Humain : Dynamic_NPC_Overhaul
    NPCDebugReplication.lua

    Recoit la replication debug du serveur et affiche un overlay minimal
    pour visualiser les chunks actifs/dormants autour du joueur.
]]

PHNPCDebugReplication = PHNPCDebugReplication or {
    enabled = true,
    heatmapMode = false,
    fsmEnabled = true,
    fsmRange = 40,
    fsmLimit = 10,
    module = "PH_NPC",
    command = "ChunkDebugState",
    ackCommand = "AdminDebugAck",
    maxLines = 10,
    maxFSMLines = 8,
    lastPayload = nil
}

local function safeToString(v)
    if v == nil then
        return "nil"
    end
    return tostring(v)
end

local function clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

local function chunkDensity(chunk)
    local a = (chunk and chunk.active) or 0
    local d = (chunk and chunk.dormant) or 0
    return a + (d * 0.35)
end

local function colorForDensity(norm)
    norm = clamp(norm or 0, 0, 1)

    -- Gradient vert -> jaune -> orange -> rouge
    if norm < 0.33 then
        local t = norm / 0.33
        return 0.25 + (0.75 * t), 0.95, 0.25
    elseif norm < 0.66 then
        local t = (norm - 0.33) / 0.33
        return 1.0, 0.95 - (0.35 * t), 0.20
    else
        local t = (norm - 0.66) / 0.34
        return 1.0, 0.60 - (0.45 * t), 0.15
    end
end

local function barForDensity(norm, width)
    local barLen = math.floor(clamp(norm, 0, 1) * width)
    local bar = ""
    for i = 1, width do
        bar = bar .. (i <= barLen and "#" or "-")
    end
    return bar
end

function PHNPCDebugReplication:sendAdminCommand(args)
    if not sendClientCommand then
        print("[PH NPC DEBUG] sendClientCommand indisponible.")
        return
    end

    sendClientCommand(self.module, "AdminSetDebug", args or {})
end

function PHNPCDebugReplication:setOverlayEnabled(enabled)
    self:sendAdminCommand({ overlayEnabled = enabled == true })
end

function PHNPCDebugReplication:setHeatmapEnabled(enabled)
    self:sendAdminCommand({ heatmapEnabled = enabled == true })
end

function PHNPCDebugReplication:toggleOverlay()
    self:sendAdminCommand({ toggleOverlay = true })
end

function PHNPCDebugReplication:toggleHeatmap()
    self:sendAdminCommand({ toggleHeatmap = true })
end

function PHNPCDebugReplication:printStatus()
    print(
        "[PH NPC DEBUG] overlay=" .. tostring(self.enabled)
            .. " heatmap=" .. tostring(self.heatmapMode)
            .. " fsm=" .. tostring(self.fsmEnabled)
            .. " fsmRange=" .. tostring(self.fsmRange)
            .. " fsmLimit=" .. tostring(self.fsmLimit)
    )
end

function PHNPCDebugReplication:onServerCommand(module, command, args)
    if module ~= self.module then
        return
    end

    if command == self.ackCommand then
        if type(args) ~= "table" then
            print("[PH NPC DEBUG] Reponse admin invalide.")
            return
        end

        if args.ok ~= true then
            print("[PH NPC DEBUG] Refuse (admin requis).")
            return
        end

        self.enabled = args.overlayEnabled == true
        self.heatmapMode = args.heatmapEnabled == true
        self.fsmEnabled = args.fsmEnabled ~= false
        self.fsmRange = tonumber(args.fsmRange) or self.fsmRange
        self.fsmLimit = tonumber(args.fsmLimit) or self.fsmLimit

        self:printStatus()
        return
    end

    if command ~= self.command then
        return
    end

    self.lastPayload = args

    if type(args) == "table" and type(args.debug) == "table" then
        self.enabled = args.debug.overlayEnabled == true
        self.heatmapMode = args.debug.heatmapEnabled == true
        self.fsmEnabled = args.debug.fsmEnabled ~= false
        self.fsmRange = tonumber(args.debug.fsmRange) or self.fsmRange
        self.fsmLimit = tonumber(args.debug.fsmLimit) or self.fsmLimit
    end
end

function PHNPCDebugReplication:drawOverlay()
    if not self.enabled then
        return
    end

    local data = self.lastPayload
    if type(data) ~= "table" then
        return
    end

    local tm = getTextManager and getTextManager() or nil
    if not tm or not tm.DrawString then
        return
    end

    local x = 20
    local y = 260
    local line = 0

    local function draw(text, r, g, b, a)
        tm:DrawString(UIFont.Small, x, y + (line * 14), text, r or 0.9, g or 0.9, b or 0.9, a or 1.0)
        line = line + 1
    end

    draw("[PH NPC DEBUG] tick=" .. safeToString(data.tick), 0.5, 0.95, 1.0, 1.0)
    draw("Active=" .. safeToString(data.totalActive) .. " Dormant=" .. safeToString(data.totalDormant), 0.9, 0.9, 0.9, 1.0)

    local p = data.player or {}
    draw(
        "Player=" .. safeToString(p.username) .. " @ " .. safeToString(p.x) .. "," .. safeToString(p.y) .. "," .. safeToString(p.z),
        0.8,
        0.9,
        0.8,
        1.0
    )

    local chunks = data.chunks
    if type(chunks) ~= "table" then
        return
    end

    local ordered = {}
    local maxDensity = 0

    for i = 1, #chunks do
        local c = chunks[i]
        ordered[#ordered + 1] = c
        local density = chunkDensity(c)
        if density > maxDensity then
            maxDensity = density
        end
    end

    table.sort(ordered, function(a, b)
        return chunkDensity(a) > chunkDensity(b)
    end)

    local maxLines = math.min(#ordered, self.maxLines)
    if self.heatmapMode then
        draw("Mode HEATMAP (densite chunks)", 1.0, 0.75, 0.35, 1.0)
    end

    for i = 1, maxLines do
        local c = ordered[i]
        if c then
            local density = chunkDensity(c)
            local norm = (maxDensity > 0) and (density / maxDensity) or 0
            local r, g, b = colorForDensity(norm)

            if self.heatmapMode then
                draw(
                    "chunk " .. safeToString(c.key)
                        .. " | [" .. barForDensity(norm, 12) .. "]"
                        .. " d=" .. string.format("%.2f", density)
                        .. " A=" .. safeToString(c.active)
                        .. " D=" .. safeToString(c.dormant),
                    r,
                    g,
                    b,
                    1.0
                )
            else
                draw(
                    "chunk " .. safeToString(c.key) .. " | A=" .. safeToString(c.active) .. " D=" .. safeToString(c.dormant),
                    r,
                    g,
                    b,
                    1.0
                )
            end
        end
    end

    if not self.fsmEnabled then
        draw("FSM overlay OFF", 0.65, 0.65, 0.7, 1.0)
        return
    end

    local nearbyFSM = data.nearbyFSM
    if type(nearbyFSM) ~= "table" or #nearbyFSM == 0 then
        return
    end

    draw(
        "PNJ Proches (FSM) range=" .. safeToString(self.fsmRange) .. " limit=" .. safeToString(self.fsmLimit),
        0.55,
        0.85,
        1.0,
        1.0
    )
    local fsmLines = math.min(#nearbyFSM, self.maxFSMLines)

    for i = 1, fsmLines do
        local n = nearbyFSM[i]
        if n then
            local state = safeToString(n.state)
            local goal = safeToString(n.goal)
            local activeOrder = safeToString(n.activeOrder)
            local dist = tonumber(n.distance) or 0

            local colorR, colorG, colorB = 0.85, 0.9, 1.0
            if state == "Combat" then
                colorR, colorG, colorB = 1.0, 0.45, 0.35
            elseif state == "Flee" then
                colorR, colorG, colorB = 1.0, 0.75, 0.30
            elseif state == "Survive" then
                colorR, colorG, colorB = 0.80, 1.0, 0.55
            end

            local targetText = ""
            local t = n.target
            if type(t) == "table" and t.x ~= nil and t.y ~= nil then
                targetText = " -> T:" .. safeToString(t.x) .. "," .. safeToString(t.y)
            end

            local observedText = ""
            local observed = n.observedPlayer
            if type(observed) == "table" and observed.id ~= nil then
                observedText = " | P:" .. safeToString(observed.id)
                    .. " tr=" .. safeToString(observed.trust)
                    .. " fr=" .. safeToString(observed.fear)
                    .. " rs=" .. safeToString(observed.respect)
                    .. " rep=" .. safeToString(observed.reputation)
                    .. " ["
                    .. (observed.trusted and "T" or "-")
                    .. (observed.feared and "F" or "-")
                    .. (observed.dangerous and "D" or "-")
                    .. "]"
            end

            local infectionText = ""
            if n.infectionStatus ~= nil then
                infectionText = " | inf=" .. safeToString(n.infectionStatus)
                    .. ":" .. safeToString(n.infectionProgress)
            end

            draw(
                "#" .. safeToString(n.id)
                    .. " | " .. state
                    .. " / " .. goal
                    .. " / ord=" .. activeOrder
                    .. " | d=" .. string.format("%.1f", dist)
                    .. targetText
                    .. infectionText
                    .. observedText,
                colorR,
                colorG,
                colorB,
                1.0
            )
        end
    end
end

if Events and Events.OnServerCommand then
    Events.OnServerCommand.Add(function(module, command, args)
        PHNPCDebugReplication:onServerCommand(module, command, args)
    end)
end

if Events and Events.OnPostUIDraw then
    Events.OnPostUIDraw.Add(function()
        PHNPCDebugReplication:drawOverlay()
    end)
end

-- Commandes admin utilisables dans la console Lua client:
-- PHNPC_AdminOverlay(true/false)
-- PHNPC_AdminHeatmap(true/false)
-- PHNPC_AdminToggleOverlay()
-- PHNPC_AdminToggleHeatmap()
-- PHNPC_AdminDebugStatus()
function PHNPC_AdminOverlay(enabled)
    PHNPCDebugReplication:setOverlayEnabled(enabled)
end

function PHNPC_AdminHeatmap(enabled)
    PHNPCDebugReplication:setHeatmapEnabled(enabled)
end

function PHNPC_AdminToggleOverlay()
    PHNPCDebugReplication:toggleOverlay()
end

function PHNPC_AdminToggleHeatmap()
    PHNPCDebugReplication:toggleHeatmap()
end

function PHNPC_AdminDebugStatus()
    PHNPCDebugReplication:printStatus()
end

return PHNPCDebugReplication
