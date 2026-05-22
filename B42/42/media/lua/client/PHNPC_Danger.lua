--[[
    PHNPC_Danger.lua  v0.0.9c  (client)
    Gestion du danger autour des NPCs :
      1. Les NPCs generent des sons (bark, attaque, deplacement) qui attirent les zombies.
      2. Les zombies normaux proches d'un NPC actif recoivent une cible forcee vers ce NPC.
         => Les zombies attaquent les NPCs, pas uniquement le joueur.

    Mecanisme :
      - NoiseTimer : pose par Combat.lua ou Orders.lua apres une action bruyante
        (bark, attaque). Decremente chaque OnTick.
      - DANGER_TICK_RATE (80 ticks) : frequence du scan agro sur les zombies proches.
      - aggroZombiesOnNPC(npc, radius) : parcourt les tuiles du rayon et force
        zombie:setTarget(npc) + zombie:addAggro(npc, 1).

    Pattern : Bandits 42.16 BanditUpdate.lua (setTarget/setAttackedBy/addAggro)
    Necessite :
      PHNPC_Core.lua (PHNPC, PHNPC.allNPCs, PHNPC.recruited)
      PHNPC_Core.lua (PHNPC.AGGRO_RANGE, PHNPC.DANGER_TICK_RATE)
]]

-- ============================================================
-- aggroZombiesOnNPC : dirige les zombies normaux vers un NPC
-- Scan les tuiles du rayon, force setTarget(npc) sur ceux qui
-- n'ont pas deja une cible vivante.
-- Pattern Bandits 42.16 BanditUpdate.lua
-- ============================================================
function PHNPC.aggroZombiesOnNPC(npc, radius)
    radius = radius or (PHNPC.AGGRO_RANGE or 10)
    local cell = getCell()
    if not cell then return end

    local nx = math.floor(npc:getX())
    local ny = math.floor(npc:getY())
    local nz = math.floor(npc:getZ())
    local player = getPlayer()
    local count  = 0

    for dx = -radius, radius do
        for dy = -radius, radius do
            if dx * dx + dy * dy <= radius * radius then
                local ok, sq = pcall(function()
                    return cell:getGridSquare(nx + dx, ny + dy, nz)
                end)
                if ok and sq then
                    local movObjs = sq:getMovingObjects()
                    if movObjs then
                        for i = 0, movObjs:size() - 1 do
                            local obj = movObjs:get(i)
                            if obj and instanceof(obj, "IsoZombie") then
                                local objMd = obj:getModData()
                                -- Ne pas re-cibler nos propres NPCs
                                if not objMd.PHNPC_IsNPC then
                                    local alive = false
                                    pcall(function() alive = not obj:isDead() end)
                                    if alive then
                                        pcall(function()
                                            -- Reveiller le zombie (pattern Bandits 42.16)
                                            if player then
                                                obj:spottedNew(player, true)
                                            end
                                            -- Forcer la cible vers le NPC
                                            obj:addAggro(npc, 1)
                                            obj:setTarget(npc)
                                            obj:setAttackedBy(npc)
                                        end)
                                        count = count + 1
                                        -- Limiter : max 6 zombies re-cibles par appel
                                        if count >= 6 then return end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        if count >= 6 then break end
    end
end

-- ============================================================
-- OnTick : scan periodique des zombies autour des NPCs actifs
-- Frequence : DANGER_TICK_RATE ticks
-- ============================================================
local _dangerTick = 0

Events.OnTick.Add(function()
    if not PHNPC then return end

    _dangerTick = _dangerTick + 1
    if _dangerTick < (PHNPC.DANGER_TICK_RATE or 80) then return end
    _dangerTick = 0

    local player = getPlayer()
    if not player then return end

    -- Pour chaque NPC recrute actif (not staying immobile)
    for npc, _ in pairs(PHNPC.recruited) do
        local valid = false
        pcall(function() valid = not npc:isDead() end)
        if valid then
            local md = npc:getModData()
            -- Gerer le NoiseTimer : si le NPC vient de faire du bruit, agro maximal
            local noiseRadius = PHNPC.AGGRO_RANGE or 10
            if (md.PHNPC_NoiseTimer or 0) > 0 then
                md.PHNPC_NoiseTimer = md.PHNPC_NoiseTimer - (PHNPC.DANGER_TICK_RATE or 80)
                if md.PHNPC_NoiseTimer < 0 then md.PHNPC_NoiseTimer = 0 end
                -- Bruit recemment : agro dans un plus grand rayon
                noiseRadius = PHNPC.NOISE_RADIUS or 12
            end

            -- Ne pas agro si le NPC est en fuite (vulnerabilite trop elevee)
            if md.PHNPC_State ~= "fleeing" then
                pcall(function() PHNPC.aggroZombiesOnNPC(npc, noiseRadius) end)
            end
        end
    end

    -- NPCs non-recrutes actifs (en patrouille) : agro discret
    for npc, _ in pairs(PHNPC.allNPCs) do
        if not PHNPC.recruited[npc] then
            local valid = false
            pcall(function() valid = not npc:isDead() end)
            if valid then
                local md = npc:getModData()
                -- Seulement si en mouvement
                if md.PHNPC_Moving then
                    pcall(function() PHNPC.aggroZombiesOnNPC(npc, 5) end)
                end
            end
        end
    end
end)

print("[PHNPC] Danger v0.0.9c loaded")
