# GUIDE DE CRÉATION DE NPC — PH Dynamic NPC Overhaul B42
_Version 2.2.0_

> Ce guide explique le fonctionnement complet du systeme NPC tel qu'implemente en v2.2.0.

---

## Vue d'ensemble

Le NPC est un `IsoZombie` "humanisé" par un ensemble de variables et d'AnimSets personnalisés.  
Il ne peut pas être un `IsoPlayer` (limité au mode debug de PZ).

**Pipeline de création :**
1. `addZombiesInOutfit()` → crée l'entité IsoZombie avec une tenue humaine
2. "Banditize" → configure les variables pour désactiver le comportement zombie
3. AnimSets → animations humaines selon les variables de la variable `PHNPC_IsNPC`
4. PHNPC_Stats → génère un nom genré + des stats selon l'outfit
5. PHNPC.npcs → enregistre l'état pour la boucle de tick

---

## 1. Spawning

### Code
```lua
local npc = addZombiesInOutfit(x, y, z, 1, outfit, femaleChance)
```

### Outfits disponibles
`"Police"`, `"Fireman"`, `"Doctor"`, `"Ranger"`, `"Chef"`, `"Farmer"`, `"Survivor"`

### Configuration Banditize obligatoire (dans l'ordre !)
```lua
npc:setUseless(false)              -- TOUJOURS EN PREMIER (PZ remet true après hit)
npc:setNoTeeth(true)               -- Pas de morsure zombie
npc:setVariable("PHNPC_IsNPC", true)  -- Active tous les ZS*.xml
npc:setWalkType("Walk")
npc:setVariable("zombieWalkType", "Walk")  -- Active ZSWalk.xml
npc:setVariable("ZombieHitReaction", "Chainsaw")  -- Évite crash
npc:setVariable("NoLungeTarget", true)
npc:setSpeedMod(1.0)              -- CRITIQUE: sans ça, vitesse = 0
npc:setVariable("WalkSpeed", 1.04)
npc:setVariable("RunSpeed", 1.10)
npc:setDressInRandomOutfit(false)
npc:setTurnAlertedValues(-5, 5)
npc:setBumpType("Shrug")
npc:getDescriptor():setVoicePrefix("NotAZombie")  -- Voix humaine B42
npc:setTarget(nil)
npc:clearAggroList()
npc:setHealth(10000)
```

---

## 2. AnimSets

### Principe
Les AnimSets sont des fichiers XML dans `media/AnimSets/zombie/<etat>/`.  
PZ choisit l'animation à jouer selon l'**état** de l'IsoZombie et les **variables** définies.

Notre mod ajoute des conditions `PHNPC_IsNPC=true` pour jouer des animations Bob_ (humain) au lieu de Zombie_.

### Structure d'un AnimSet personnalisé
```xml
<AnimSet name="ZSWalk" file="BOB_Walk" Priority="2">
    <condition variable="PHNPC_IsNPC" value="true" type="BOOL"/>
    <condition variable="zombieWalkType" value="Walk" type="STRING"/>
</AnimSet>
```

### États et AnimSets actifs
| État PZ | Dossier | Fichier | Animation jouée |
|---------|---------|---------|-----------------|
| Stationnaire | `idle/` | ZSIdle.xml | Bob_Idle |
| Pathfinding (pathToLocationF) | `pathfind/` | ZSWalk.xml | Bob_Walk |
| Poursuite (setTarget) | `walktoward/` | ZSWalk.xml | Bob_Walk |
| Lunge (transition état) | `lunge/` | ZSlunge.xml | Bob_Walk (vitesse 1.1) |
| Interaction porte | `thump/` | ZSdoor.xml | Bob_FrontKick |
| Combat | `attack/` | ZSAttack*.xml | Bob_Attack* |
| Réaction coup | `hitreaction/` | ZSPain*.xml | Bob_Pain* |
| Bump | `bumped/` | ZSBump*.xml | Bob_Push* |

> ⚠️ **pathfind/ et walktoward/ doivent contenir les mêmes fichiers.**  
> `pathToLocationF()` → état `pathfind` → lit `pathfind/`  
> `setTarget()` → état `walktoward` → lit `walktoward/`

---

## 3. Noms et Stats (PHNPC_Stats.lua)

### Génération du nom
```lua
local name = PHNPC.generateName(isFemale)
-- Pioche dans PHNPC.NAMES_MALE ou PHNPC.NAMES_FEMALE selon le sexe
```

### Génération des stats
```lua
local stats = PHNPC.generateStats(outfit)
-- Retourne: { courage=N, force=N, melee=N, tir=N, endurance=N }
-- Valeurs dans les ranges de PHNPC.STAT_PROFILES[outfit]
```

### Affichage
```lua
local desc = PHNPC.statsToString(stats)
-- Retourne: "Courage: Excellent | Force: Bon | Mêlée: Moyen | Tir: Faible | Endurance: Bon"
```

---

## 4. Boucle de comportement

### enforceNPC (appele par OnZombieUpdate)
C'est le "gardien" du NPC. Il est appele a chaque update de l'IsoZombie.
Son role : **empecher PZ de reactiver le comportement zombie**.

```lua
-- Ordre imperatif des appels:
npc:setUseless(false)          -- 1er TOUJOURS
npc:setHealth(10000)
npc:setNoTeeth(true)
npc:setVariable("PHNPC_IsNPC", true)
npc:setVariable("zombieWalkType", "Walk")
npc:setSpeedMod(0.8)

-- TOUJOURS effacer la cible (sauf colere vs joueur)
-- Raison: l'IA zombie native est incompatible avec nos variables
npc:setTarget(nil)
npc:clearAggroList()

-- Etats autorises (ne pas interrompre):
if state == "pathfind" then return end   -- En deplacement
if state == "thump"    then return end   -- Ouvre une porte

-- Etats a reset:
if state == "eatBody" or state == "turnalerted" then
    npc:changeState(ZombieIdleState)
end

-- Poussee : gestion colere
if state == "bumped" then
    -- handleAnger() + compter 35 ticks puis reset
end
```

### Suivi joueur
```lua
-- Dans OnTick, toutes les 15 ticks si followMode actif
if dist > 3 then
    npcStartMoving(npc, player:getX(), player:getY(), player:getZ())
else
    npcStopMoving(npc)
end
```

### Peur des zombies (checkFear)
```lua
-- Toutes les 30 ticks
if data.stats.courage < PHNPC.FEAR_COURAGE_THRESHOLD then
    -- Chercher zombies dans PHNPC.FEAR_ZOMBIE_DIST tiles
    if zombieFound then
        -- Fuir dans la direction opposée (15 tiles)
        npcStartMoving(npc, fleeX, fleeY, fleeZ)
    end
end
```

### Mode combat (v2.2 — entierement manuel)
```lua
-- doMeleeAttack(npc, target) — JAMAIS setTarget/NPCSetAttack en B42
npc:faceLocationF(target:getX(), target:getY())
npc:setBumpType("Shove")         -- ou "FrontKick", "HighKick" (alternance)
pcall(function() target:knockDown(true) end)  -- sur zombies uniquement
data.attackCooldown = 60         -- ticks avant prochaine attaque

-- checkCombat, toutes les 10 ticks si attackMode:
if dist <= 1.8 then
    doMeleeAttack(npc, zombie)
else
    npcStartMoving(npc, zx, zy, zz)  -- approcher
end
```

> **Pourquoi pas setTarget/NPCSetAttack ?**  
> `NPCSetAttack()` n'existe pas en B42.  
> `setTarget()` ignore nos overrides (`NoLungeTarget`, `setUseless`...).  
> L'IA zombie native est completement desactivee pour nos NPCs.  
> Pattern confirme depuis GCCombatActionsAttack.lua (NPC_Helper_Mod).
```

---

## 5. Inventaire (v2.2)

En B42, `ISInventoryTransferUI.transferBetween()` crash (module ISInventoryTransferAction echoue a charger).
On utilise a la place le hook `OnRefreshInventoryWindowContainers` (pattern NPC_Helper_Mod) :

```lua
local _openInvNPC = nil

local function openNPCInventory(npc)
    _openInvNPC = npc
    local pdata = getPlayerData(0)
    if pdata and pdata.lootInventory then
        pdata.lootInventory:refreshBackpacks()  -- force l'ouverture de la fenetre
    end
end

Events.OnRefreshInventoryWindowContainers.Add(function(page, step)
    if step ~= "beforeFloor" then return end
    if page.onCharacter then return end
    if not _openInvNPC then return end
    local loot = getPlayerLoot(page.player)
    if loot then
        loot:addContainerButton(npcInv, nil, npcName, npcName)
    end
end)
```

---

## 6. Traductions (v2.2)

**Nom obligatoire : `UI.json`** (PZ B42 ignore tout autre nom pour les langues non-EN)

Chemin : `media/lua/shared/Translate/FR/UI.json` (et `/EN/UI.json`)

```json
{
    "PHNPC_Menu_SpawnNPC": "[PHNPC] Faire apparaitre un PNJ",
    "PHNPC_Menu_StayHere": "Reste ici",
    "PHNPC_Anger_M_1":     "He ! Fais attention ou tu marches !"
}
```

Acces en Lua : `getText("PHNPC_Menu_StayHere")`

> Un nom comme `PHNPC.json` fonctionne UNIQUEMENT pour EN. Pour toutes les autres langues, PZ exige `UI.json`.
> Confirme depuis ssr_quests mod (supporte EN/FR/RU/CN/ES/KO/PTBR avec UI.json dans chaque dossier).

---

## 7. Dialogue NPC (v2.2)

Pour afficher du texte au-dessus du NPC :

```lua
-- Bulle de parole blanche au-dessus du NPC
npc:Say("Mon message")

-- NE PAS utiliser HaloTextHelper.addText() - n'existe pas en B42
```

Le menu apparaît :
- Sur une tuile vide → option de spawn
- Sur un NPC (détection dans rayon 2 tiles) → sous-menu d'ordres

```lua
-- Détection d'un NPC sous le curseur
for npc, data in pairs(PHNPC.npcs) do
    local dist = math.abs(npc:getX()-wx) + math.abs(npc:getY()-wy)
    if dist <= 2 then
        -- Afficher sous-menu
    end
end
```

---

## 9. Ajout d'un nouveau NPC type (workflow)

1. **Définir le profil stats** dans `PHNPC_Stats.lua` → `PHNPC.STAT_PROFILES["MonOutfit"] = {...}`
2. **Vérifier l'outfit PZ** : doit exister dans les assets vanilla B42
3. **Tester le spawn** : clic droit → vérifier que les animations humaines jouent
4. **Vérifier les AnimSets** : état `pathfind` doit jouer `Bob_Walk` (pas `Zombie_Walk`)
5. **Tester les ordres** : suivi, arrêt, combat, inventaire, stats

---

## 10. Debogage frequent

| Symptome | Cause probable | Fix |
|----------|----------------|-----|
| NPC ne bouge pas | `setSpeedMod` manquant | Ajouter `npc:setSpeedMod(0.8)` |
| NPC marche accroupi | ZSlunge.xml avec `Bob_WalkSneak_Slow` | Remplacer par `Bob_Walk` |
| NPC mord le joueur | `setNoTeeth` pas appele | Mettre `setNoTeeth(true)` apres `setUseless(false)` |
| NPC n'ouvre pas les portes | "thump" interrompu par enforceNPC | Ajouter `if state=="thump" then return end` |
| NPC attaque le joueur | `clearAggroList` + `setTarget(nil)` manquant | Appeler les deux dans enforceNPC |
| AnimSet ignore | Fichier dans `walktoward/` mais PZ utilise `pathfind/` | Copier dans les deux dossiers |
| Stats nil au clic | `PHNPC_Stats.lua` non charge avant Manager | Verifier l'ordre dans `mod.info` ou `shared/` |
| Menus en anglais (langue FR) | Fichier traduction pas nomme `UI.json` | Renommer en `Translate/FR/UI.json` |
| Dialogue NPC absent | Utilisation de `HaloTextHelper.addText()` | Remplacer par `npc:Say("texte")` |
| Inventaire ne s'ouvre pas | `ISInventoryTransferUI.transferBetween()` crash | Utiliser hook `OnRefreshInventoryWindowContainers` |
| NPC n'attaque pas | `NPCSetAttack()` n'existe pas en B42 | Utiliser `doMeleeAttack()` manuel (faceLocationF + setBumpType + knockDown) |
| Punch anim avant marche | `setBumpType("IdleToWalk")` dans npcStartMoving | Supprimer cet appel |
