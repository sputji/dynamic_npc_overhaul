# GUIDE DE CRÉATION DE NPC — PH Dynamic NPC Overhaul B42
_Version 2.0.0_

> Ce guide explique le fonctionnement complet du système NPC tel qu'implémenté en v2.0.0.

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

### enforceNPC (appelé par OnZombieUpdate)
C'est le "gardien" du NPC. Il est appelé à chaque update de l'IsoZombie.  
Son rôle : **empêcher PZ de réactiver le comportement zombie**.

```lua
-- Ordre impératif des appels:
npc:setUseless(false)          -- 1er TOUJOURS
npc:setHealth(10000)
npc:setNoTeeth(true)
npc:setVariable("PHNPC_IsNPC", true)
npc:setVariable("zombieWalkType", "Walk")
npc:setSpeedMod(1.0)

-- États autorisés (ne pas interrompre):
if state == "pathfind" then return end   -- En déplacement
if state == "thump"    then return end   -- Ouvre une porte
if state == "attack" and attackMode then return end  -- Combat actif
if state == "bumped" and ticks < 30 then return end  -- Bump récent

-- États à reset:
if state == "lunge" or state == "eatBody" or state == "turnalerted" then
    npc:changeState(ZombieIdleState)
    npc:setTarget(nil)
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

### Mode combat (checkCombat)
```lua
-- Toutes les 10 ticks si attackMode
-- Chercher zombie le plus proche (< 15 tiles)
if dist < PHNPC.COMBAT_RANGE then
    npc:NPCSetAttack(target)        -- Attaque corps à corps
else
    npcStartMoving(npc, tx, ty, tz) -- S'approche
end
```

---

## 5. Inventaire

L'IsoZombie a un inventaire natif. L'accès se fait via :
```lua
ISInventoryTransferUI.transferBetween(player, npc)
```
Cela ouvre l'interface d'échange classique de PZ entre le joueur et le NPC.

Le NPC peut porter des armes et équipements dans son inventaire. L'équipement automatique d'armes sera ajouté en phase future.

---

## 6. Menu contextuel

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

## 7. Ajout d'un nouveau NPC type (workflow)

1. **Définir le profil stats** dans `PHNPC_Stats.lua` → `PHNPC.STAT_PROFILES["MonOutfit"] = {...}`
2. **Vérifier l'outfit PZ** : doit exister dans les assets vanilla B42
3. **Tester le spawn** : clic droit → vérifier que les animations humaines jouent
4. **Vérifier les AnimSets** : état `pathfind` doit jouer `Bob_Walk` (pas `Zombie_Walk`)
5. **Tester les ordres** : suivi, arrêt, combat, inventaire, stats

---

## 8. Débogage fréquent

| Symptôme | Cause probable | Fix |
|----------|----------------|-----|
| NPC ne bouge pas | `setSpeedMod` manquant | Ajouter `npc:setSpeedMod(1.0)` |
| NPC marche accroupi | ZSlunge.xml avec `Bob_WalkSneak_Slow` | Remplacer par `Bob_Walk` |
| NPC mord le joueur | `setNoTeeth` pas appelé ou pas en premier | Mettre `setNoTeeth(true)` après `setUseless(false)` |
| NPC n'ouvre pas les portes | "thump" interrompu par enforceNPC | Ajouter `if state=="thump" then return end` |
| NPC attaque le joueur | `clearAggroList` + `setTarget(nil)` manquant | Appeler les deux au spawn ET dans enforceNPC |
| AnimSet ignoré | Fichier dans `walktoward/` mais PZ utilise `pathfind/` | Copier dans les deux dossiers |
| Stats nil au clic | `PHNPC_Stats.lua` non chargé avant Manager | Vérifier l'ordre dans `mod.info` ou `shared/` |
