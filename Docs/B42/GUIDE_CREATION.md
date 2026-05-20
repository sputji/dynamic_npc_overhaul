# GUIDE DE CREATION - PH Dynamic NPC Overhaul B42
Version 1.1.0 - Pattern IsoZombie / Banditize (B42.18+)

## Principe

Tout PNJ est un IsoZombie cree via `addZombiesInOutfit()` puis "Banditize" : un ensemble
de variables et d'appels qui le transforment en entite humaine non-hostile.
L'approche IsoPlayer est INVALIDE en B42 (bugs de classe et pathfinding).
Sources de reference : NPC_Helper_Mod (GCCoreConvert.lua) + Bandits (BanditUpdate.lua).

---

## 1. Creer un NPC (code minimal)

    -- 1. Trouver la case sous le curseur
    local square = ISWorldObjectContextMenu.fetchVars.clickedSquare
    local x, y, z = square:getX(), square:getY(), square:getZ()

    -- 2. Spawn via addZombiesInOutfit
    local zombieList = addZombiesInOutfit(x, y, z, 1, "Farmer", 0)
    if not zombieList or zombieList:size() == 0 then return end
    local npc = zombieList:get(0)
    if not npc then return end

    -- 3. Banditize (transformer zombie -> NPC)
    npc:setNoTeeth(true)
    npc:setVariable("PHNPC_IsNPC", true)     -- active les AnimSets custom
    npc:setWalkType("Walk")
    npc:setVariable("zombieWalkType", "Walk")
    npc:setVariable("ZombieHitReaction", "Chainsaw")
    npc:setVariable("NoLungeTarget", true)
    npc:setVariable("LimpSpeed", 0.80)
    npc:setVariable("WalkSpeed", 1.04)
    npc:setVariable("RunSpeed", 0.75)
    npc:getEmitter():stopAll()
    npc:setPrimaryHandItem(nil)
    npc:setSecondaryHandItem(nil)
    npc:resetEquippedHandsModels()
    npc:clearAttachedItems()
    npc:setDressInRandomOutfit(false)
    npc:setTurnAlertedValues(-5, 5)
    npc:setBumpType("Shrug")

    -- CRUCIAL: effacer la cible et l'agression initiale
    npc:setTarget(nil)
    npc:clearAggroList()
    npc:setHealth(10000)

    -- 4. ModData (identifiant pour les loops)
    npc:getModData().PHNPC_ID = "mon_id_unique"

---

## 2. Faire bouger un NPC

    -- Demarrer le mouvement (pattern NPC_Helper_Mod GCCoreActions.lua)
    npc:setUseless(false)
    npc:setBumpType("IdleToWalk")   -- transition animation idle -> marche
    npc:pathToLocationF(x, y, z)

    -- Arreter le mouvement
    npc:setBumpType("WalkToIdle")   -- transition animation marche -> idle

    -- IMPORTANT: pathToLocationF doit etre rappele periodiquement (~15 ticks)
    --            car le zombie peut sortir du chemin ou stagner

---

## 3. Empecher le NPC d'attaquer (CRITIQUE — OnZombieUpdate)

    -- Ce pattern DOIT s'executer a chaque update engine (Events.OnZombieUpdate)
    -- pas seulement dans OnTick. Sans ca, le zombie AI reprend la main apres un hit.

    Events.OnZombieUpdate.Add(function(zombie)
        if not zombie then return end
        -- Verifier que c'est notre NPC
        local md = zombie:getModData()
        if not md or not md.PHNPC_ID then return end

        -- Maintenir la sante (PZ ne tue pas le zombie)
        pcall(function() zombie:setHealth(10000) end)
        pcall(function() zombie:setNoTeeth(true) end)
        pcall(function() zombie:setEatBodyTarget(nil, false) end)
        pcall(function() zombie:setVariable("PHNPC_IsNPC", true) end)
        pcall(function() zombie:setVariable("NoLungeTarget", true) end)

        -- Lire l'etat action courant
        local asn = ""
        pcall(function() asn = tostring(zombie:getActionStateName()) end)

        -- NE PAS appeler setTarget(nil) si pathfind actif (annulerait le deplacement!)
        if asn == "pathfind" then
            pcall(function() zombie:setUseless(false) end)
            return
        end

        -- Forcer reset si zombie attaque / lunge / mange
        if asn == "attack" or asn == "lunge" or asn == "eatBody" then
            pcall(function() zombie:changeState(ZombieIdleState.instance()) end)
            pcall(function() zombie:setTarget(nil) end)
            pcall(function() zombie:clearAggroList() end)
            pcall(function() zombie:setUseless(false) end)
            return
        end

        -- Etat normal: effacer cible et agression
        pcall(function() zombie:setTarget(nil) end)
        pcall(function() zombie:clearAggroList() end)
        pcall(function() zombie:setUseless(false) end)
    end)

---

## 4. AnimSets (ZSIdle.xml / ZSWalk.xml)

Les fichiers XML vont dans `42/media/AnimSets/zombie/idle/` et `walktoward/`.
La condition doit etre une variable posee via `zombie:setVariable(nom, valeur)`.

ZSIdle.xml minimal:

    <?xml version="1.0" encoding="utf-8"?>
    <animNode>
        <m_Name>ZSIdle</m_Name>
        <m_AnimName>Bob_Idle</m_AnimName>
        <m_Conditions>
            <m_Name>PHNPC_IsNPC</m_Name>
            <m_Type>BOOL</m_Type>
            <m_BoolValue>true</m_BoolValue>
        </m_Conditions>
    </animNode>

ZSWalk.xml minimal (PAS de x_extends — provoquerait un crash de parsing):

    <?xml version="1.0" encoding="utf-8"?>
    <animNode>
        <m_Name>ZSWalk</m_Name>
        <m_AnimName>Bob_Walk</m_AnimName>
        <m_Conditions>
            <m_Name>zombieWalkType</m_Name>
            <m_Type>STRING</m_Type>
            <m_StringValue>Walk</m_StringValue>
        </m_Conditions>
    </animNode>

---

## 5. Enregistrer les events

    -- Par entite a chaque frame (enforce anti-zombie-AI)
    Events.OnZombieUpdate.Add(maFonctionEnforce)

    -- Tick global (mouvement, IA)
    Events.OnTick.Add(maFonctionTick)

    -- Menu clic-droit
    Events.OnPreFillWorldObjectContextMenu.Add(maFonctionMenu)

    -- Reset a chaque nouvelle partie
    Events.OnGameStart.Add(function() monTable = {} end)

---

## 6. Pieges courants

| Piege | Solution |
|-------|----------|
| `x_extends` dans ZSWalk.xml | Supprimer: provoquerait un crash AnimNode.Parse si le fichier reference n'existe pas dans le mod |
| setTarget(nil) pendant pathfind | Ne jamais appeler si asn == "pathfind", ca annule le deplacement |
| NPC hostile apres hit | Manque Events.OnZombieUpdate avec clearAggroList() + setTarget(nil) |
| NPC gele apres hit | PZ met setUseless(true) apres un hit — enforcer setUseless(false) chaque frame |
| Erreur `goto`/`continue` en Lua | Kahlua (PZ) n'est pas Lua 5.2+, utiliser des if imbriques |
| BOM UTF-8 dans les .lua | Les fichiers doivent etre ASCII pur (pas de BOM) |


    -- Sauvegarde
    Events.OnSave.Add(maFonctionSave)

---

## 4. Menu clic-droit (pattern CnpcMenu)

    local function onContextMenu(playerIndex, context, worldobjects, test)
        if test then return end
        local square = ISWorldObjectContextMenu.fetchVars.clickedSquare
        if not square then return end
        context:addOption("Mon option", monObjet, maCallback)
    end
    Events.OnPreFillWorldObjectContextMenu.Add(onContextMenu)

---

## 5. Regles Kahlua (PZ B42)

INTERDIT               -> ALTERNATIVE
goto / continue        -> if + early return
next(table)            -> pairs(table) + break
obj:method and ...     -> obj.method and obj:method()
BOM UTF-8              -> Fichiers ASCII pur
getServerOptions()     -> getGameMode() ~= "Multiplayer"

---

## 6. Tester en jeu

1. Deployer : robocopy "B42" "C:\Users\Nicolas\Zomboid\mods\PH_DynamicNPCOverhaul" /MIR
2. Lancer PZ, activer le mod, charger une save
3. Clic-droit sol -> "[PHNPC] Faire apparaitre un PNJ"
4. Verifier C:\Users\Nicolas\Zomboid\console.txt pour "[PHNPC] NPC spawned:"
