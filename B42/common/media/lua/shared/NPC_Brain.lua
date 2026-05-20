--[[
    Project Humain : Dynamic NPC Overhaul — B42
    shared/NPC_Brain.lua

    Moteur IA / FSM (Finite State Machine) pour PNJ dynamiques.
    Cadence : ~33 ms (Events.OnTick, filtré toutes les N ticks).

    États FSM :
      idle     → wander / work / trade / guard
      wander   → idle / defend / flee
      work     → idle / trade
      trade    → idle / work
      defend   → flee / idle
      flee     → idle / wander
      guard    → defend / idle

    Ce fichier est SHARED : le serveur en est l'autorité,
    le client l'utilise pour l'interpolation visuelle locale.
]]

local Log         = PHNPC.getModule("NPC_Logger")
local NPC_Config  = PHNPC.getModule("NPC_Config")

local NPC_Brain = {
    -- Registre des contextes actifs { [npcId] = ctx }
    _contexts = {},

    -- Paramètres globaux (surchargés par NPC_Config au démarrage)
    updateEveryTicks   = 12,   -- cadence globale FSM
    thinkEveryTicks    = 30,   -- cadence de décision individuelle
    zombieVisionRange  = 14,
    playerVisionRange  = 12,
    hungerCritical     = 35,
    thirstCritical     = 35,
    cowardThreshold    = 38,   -- morale < X → fuite
    fleeDurationTicks  = 220,
    wanderMinDist      = 4,
    wanderMaxDist      = 10,
    hostileActionRange = 3.2,
    tradeActionRange   = 3.5,

    _tickCount = 0,
}

-- ============================================================
-- Helpers internes
-- ============================================================

local function cfg()
    return NPC_Config and NPC_Config.get() or {}
end

local function randInt(lo, hi)
    return PHNPC.randInt(lo, hi)
end

-- ============================================================
-- Gestion des contextes
-- ============================================================

--- Enregistre un PNJ dans le cerveau.
-- @param npcData  NPCDataModel
function NPC_Brain.register(npcData)
    if not npcData or not npcData.id then return end
    if NPC_Brain._contexts[npcData.id] then return end
    NPC_Brain._contexts[npcData.id] = {
        data          = npcData,
        state         = npcData.fsmState or "idle",
        target        = nil,
        lastThinkTick = 0,
        fleeTick      = 0,
        stuckTicks    = 0,
        lastPos       = nil,
    }
    if Log then Log.debug("NPC_Brain", "PNJ enregistré", { id = npcData.id, state = npcData.fsmState }) end
end

--- Supprime un PNJ du cerveau.
function NPC_Brain.unregister(npcId)
    NPC_Brain._contexts[npcId] = nil
end

--- Retourne le contexte d'un PNJ.
function NPC_Brain.getContext(npcId)
    return NPC_Brain._contexts[npcId]
end

-- ============================================================
-- Transitions FSM
-- ============================================================

local transitions = {
    idle    = { "wander", "work", "trade", "guard" },
    wander  = { "idle", "defend", "flee" },
    work    = { "idle", "trade" },
    trade   = { "idle", "work" },
    defend  = { "flee", "idle" },
    flee    = { "idle", "wander" },
    guard   = { "defend", "idle" },
}

local function canTransition(from, to)
    local t = transitions[from]
    if not t then return false end
    for _, s in ipairs(t) do
        if s == to then return true end
    end
    return false
end

local function setState(ctx, newState)
    if ctx.state == newState then return end
    if not canTransition(ctx.state, newState) then
        if Log then Log.warn("NPC_Brain", "Transition invalide", { from = ctx.state, to = newState }) end
        return
    end
    ctx.state      = newState
    ctx.data.fsmState = newState
end

-- ============================================================
-- Logique de décision (think)
-- ============================================================

local function evaluateNeeds(ctx)
    local d   = ctx.data
    local c   = cfg()
    -- Urgence : faim / soif
    if d.hunger < (c.hungerCritical or 35) or d.thirst < (c.thirstCritical or 35) then
        if ctx.state ~= "work" and ctx.state ~= "trade" then
            setState(ctx, "work")
        end
        return true
    end
    return false
end

local function evaluateThreat(ctx)
    local d = ctx.data
    -- PTSD / trauma
    if d.trauma >= 80 then
        if d.morale < NPC_Brain.cowardThreshold then
            -- Localiser le zombie hostile le plus proche pour stocker la source de menace.
            -- doBrainAction utilisera d.fsmTarget pour fuir dans la BONNE direction.
            if d.isoObject and instanceof(d.isoObject, "IsoZombie") then
                pcall(function()
                    local iso   = d.isoObject
                    local cell  = iso:getCell()
                    if not cell then return end
                    local zList = cell:getZombieList()
                    if not zList then return end
                    local bx, by      = iso:getX(), iso:getY()
                    local best, bestD = nil, 999
                    for i = 0, math.min(zList:size() - 1, 60) do
                        local z = zList:get(i)
                        if z and z ~= iso then
                            local isNPC = false
                            pcall(function() isNPC = z:getVariableBoolean("PHNPC_IsNPC") end)
                            if not isNPC then
                                local ddx, ddy = z:getX() - bx, z:getY() - by
                                local dist = ddx * ddx + ddy * ddy
                                if dist < bestD and dist < 225 then  -- 15 cases
                                    best, bestD = z, dist
                                end
                            end
                        end
                    end
                    if best then
                        d.fsmTarget = { x = best:getX(), y = best:getY() }
                    end
                end)
            end
            setState(ctx, "flee")
            ctx.fleeTick = NPC_Brain._tickCount
            return true
        else
            setState(ctx, "defend")
            return true
        end
    end
    return false
end

local function thinkIdle(ctx)
    local d = ctx.data
    -- Choisir une activité selon la profession
    local profs = PHNPC.getModule("NPC_Professions")
    local prof  = profs and profs.get(d.professionId)
    if not prof then
        setState(ctx, "wander")
        return
    end
    local priority = prof.fsm_priorities or {}
    if #priority > 0 then
        setState(ctx, priority[1])
    else
        setState(ctx, "wander")
    end
end

local function thinkFlee(ctx)
    local elapsed = NPC_Brain._tickCount - ctx.fleeTick
    if elapsed >= NPC_Brain.fleeDurationTicks then
        setState(ctx, "idle")
    end
end

local function think(ctx)
    -- Évaluation dans l'ordre de priorité décroissante
    if evaluateThreat(ctx)  then return end
    if evaluateNeeds(ctx)   then return end

    local state = ctx.state
    if state == "idle"  then thinkIdle(ctx)  return end
    if state == "flee"  then thinkFlee(ctx)  return end
    -- Autres états gérés par le serveur (actions réelles)
end

-- ============================================================
-- Boucle principale (OnTick)
-- ============================================================

local function onTick()
    NPC_Brain._tickCount = NPC_Brain._tickCount + 1
    if NPC_Brain._tickCount % NPC_Brain.updateEveryTicks ~= 0 then return end

    local cfgData = cfg()
    local range   = cfgData.FSMRange or 40

    for npcId, ctx in pairs(NPC_Brain._contexts) do
        -- Skip si l'objet iso est trop loin ou absent
        local iso = ctx.data.isoObject
        if iso then
            -- Vérifier la distance au joueur le plus proche (optionnel, perf guard)
            local ok, err = pcall(function()
                if NPC_Brain._tickCount % NPC_Brain.thinkEveryTicks == 0 then
                    think(ctx)
                end
                -- Décroissance des besoins (côté serveur uniquement)
                if type(isServer) == "function" and isServer() then
                    ctx.data:decayNeeds(NPC_Brain.updateEveryTicks * 0.033)
                end
            end)
            if not ok then
                if Log then Log.error("NPC_Brain", "Erreur tick NPC " .. npcId, { err = tostring(err) }) end
            end
        end
    end
end

-- Enregistrement de la boucle
Events.OnTick.Add(onTick)

PHNPC.registerModule("NPC_Brain", NPC_Brain)
return NPC_Brain
