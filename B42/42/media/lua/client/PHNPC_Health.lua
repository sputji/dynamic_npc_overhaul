--[[
    PHNPC_Health.lua  v0.3  (client)
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

    print(string.format("[PHNPC][HIT] %s dmg=%d HP=%d/%d",
        tostring(md.PHNPC_Name or "?"), damage, hp, md.PHNPC_MaxHealth or 100))

    -- ---- Reaction ----
    if hp > 0 then
        -- NPC vivant : empecher la mort vanilla + animation douleur
        -- setHealth(10000) ICI SEULEMENT (pas quand hp==0, sinon overridera le setHealth(0) de mort)
        pcall(function() zombie:setHealth(10000) end)
        pcall(function() zombie:setFakeDead(false) end)
        -- Animation de douleur aleatoire
        pcall(function()
            zombie:setUseless(false)
            local anim = PAIN_ANIMS[(ZombRand(#PAIN_ANIMS)) + 1]
            zombie:setBumpType(anim)
        end)
    else
        -- ---- MORT NPC ----
        -- NE PAS appeler setHealth(10000) ici !
        -- (setHealth(10000) puis setHealth(0) dans le meme callback = setHealth(0) ignore par PZ)
        print("[PHNPC][MORT] " .. tostring(md.PHNPC_Name or "?"))

        -- Derniere parole (addLineChatElement = bulle visible en B42)
        pcall(function()
            zombie:addLineChatElement(string.format(getText("UI_PHNPC_BarkDeath"), tostring(md.PHNPC_Name or "?")), 0.9, 0.2, 0.2)
        end)

        -- Retirer des registres PHNPC (plus traite par enforceNPC/follow).
        -- On conserve PHNPC_IsNPC jusqu'au snapshot loot (OnZombieDead), sinon
        -- PHNPC_Loot ne reconnait pas ce NPC et les objets donnes sont perdus.
        md.PHNPC_DeadPendingLoot = true
        PHNPC.allNPCs[zombie]   = nil
        PHNPC.recruited[zombie] = nil

        -- Mort naturelle via setHealth(0) : PZ cree le corpse avec tout l'inventaire
        -- setHealth(1) ne tuait PAS le NPC -> pas de corpse -> items perdus
        pcall(function()
            zombie:setHealth(0)
        end)
    end
end)

print("[PHNPC] Health v0.0.14 loaded")
