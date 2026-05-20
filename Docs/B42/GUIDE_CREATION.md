# GUIDE DE CREATION - PH Dynamic NPC Overhaul B42
Version 1.0.0 - Pattern Custom NPC mod

## Principe

Tout PNJ est un IsoPlayer cree directement cote client via IsoPlayer.new().
Aucun serveur ne gere le spawn en solo. Methode prouvee par le mod "7 - Custom NPC".

---

## 1. Creer un NPC (code minimal)

    -- 1. Trouver la case sous le curseur
    local square = ISWorldObjectContextMenu.fetchVars.clickedSquare

    -- 2. Determiner Z (plancher solide)
    local squareZ = 0
    if square:isSolidFloor() then squareZ = square:getZ() end

    -- 3. Creer le descripteur visuel
    local isFemale = (ZombRand(2) == 1)
    local desc = SurvivorFactory.CreateSurvivor(nil, isFemale)
    desc:setForename("Jean")
    desc:setSurname("Dupont")

    -- 4. Spawn IsoPlayer
    local npc = IsoPlayer.new(getWorld():getCell(), desc, square:getX(), square:getY(), squareZ)

    -- 5. Configuration obligatoire
    npc:setNPC(true)            -- OBLIGATOIRE sinon traite comme joueur
    npc:setSceneCulled(false)   -- visible dans la scene
    npc:setDir(IsoDirections.SE)
    npc:getModData().MON_ID = "mon_id_unique"

---

## 2. Faire bouger un NPC

    -- Demarrer le mouvement vers une position
    npc:getPathFindBehavior2():pathToLocation(targetX, targetY, targetZ)

    -- OBLIGATOIRE : appeler chaque tick (Events.OnTick)
    npc:getPathFindBehavior2():update()

    -- Arreter le mouvement
    npc:getPathFindBehavior2():cancel()
    npc:setPath2(nil)

---

## 3. Enregistrer les events

    -- Tick (mouvement, IA)
    Events.OnTick.Add(maFonctionTick)

    -- Menu clic-droit
    Events.OnPreFillWorldObjectContextMenu.Add(maFonctionMenu)

    -- Reset a chaque nouvelle partie
    Events.OnGameStart.Add(function() monTable = {} end)

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
