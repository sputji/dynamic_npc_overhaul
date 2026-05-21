--[[
    PHNPC_Health.lua  v0.1  (client)
    Systeme de sante NPC : degats, animations de douleur, mort
    Project Humain : Dynamic NPC Overhaul

    Hook Events.OnHitZombie pour intercepter les coups sur nos NPCs.
    La sante vanilla est maintenue a 10000 (via enforceNPC) pour
    empecher PZ de les tuer ; on gere nous-memes la mort via md.PHNPC_Health.

    Pattern: NPC_Helper_Mod GCUpdateHit.lua
    Necessite: PHNPC_Core.lua + PHNPC_Manager.lua charges avant ce fichier.
]]

-- ============================================================
-- CONSTANTES
-- ============================================================
local PAIN_ANIMS  = { "PainHead", "PainTorso" }   -- animations de douleur (bumped/)
local MIN_DAMAGE  = 5    -- degats minimum par coup
local CRIT_MULT   = 2    -- multiplicateur critique (headshot, crits)

-- ============================================================
-- HOOK : OnHitZombie
-- Signature PZ : (zombie, character, bodyPart, handWeapon)
-- ============================================================

Events.OnHitZombie.Add(function(zombie, character, bodyPart, handWeapon)
    -- Verifier que c'est bien un de nos NPCs
    if not PHNPC or not PHNPC.isNPC(zombie) then return end

    local md = zombie:getModData()
    local hp = md.PHNPC_Health or 0

    -- NPC deja mort : ignorer
    if hp <= 0 then return end

    -- ---- Calcul des degats ----
    local damage = MIN_DAMAGE

    if handWeapon then
        local ok, maxDmg = pcall(function() return handWeapon:getMaxDamage() end)
        if ok and maxDmg and maxDmg > 0 then
            damage = math.max(MIN_DAMAGE, math.floor(maxDmg * 15))
        end
    end

    -- Critique sur la tete (bodyPart == "Head")
    local partName = ""
    pcall(function() partName = tostring(bodyPart) end)
    if partName:lower():find("head") then
        damage = math.floor(damage * CRIT_MULT)
    end

    -- ---- Application des degats ----
    hp = math.max(0, hp - damage)
    md.PHNPC_Health = hp

    -- Empecher la mort vanilla (enforceNPC le fait aussi, double securite ici)
    pcall(function() zombie:setHealth(10000) end)
    pcall(function() zombie:setFakeDead(false) end)

    print(string.format("[PHNPC][HIT] %s dmg=%d HP=%d/%d",
        tostring(md.PHNPC_Name or "?"), damage, hp, md.PHNPC_MaxHealth or 100))

    -- ---- Reaction ----
    if hp > 0 then
        -- Animation de douleur aleatoire
        pcall(function()
            zombie:setUseless(false)
            local anim = PAIN_ANIMS[(ZombRand(#PAIN_ANIMS)) + 1]
            zombie:setBumpType(anim)
        end)
    else
        -- ---- MORT NPC ----
        print("[PHNPC][MORT] " .. tostring(md.PHNPC_Name or "?"))

        -- Derniere parole
        pcall(function()
            zombie:Say(tostring(md.PHNPC_Name or "?") .. " : Argh...")
        end)

        -- Retirer des registres PHNPC (plus traite par enforceNPC/follow)
        PHNPC.allNPCs[zombie]   = nil
        PHNPC.recruited[zombie] = nil

        -- Laisser PZ gerer la mort naturellement
        pcall(function()
            zombie:setHealth(1)
            zombie:setFakeDead(false)
        end)
    end
end)

print("[PHNPC] Health v0.1 loaded")
