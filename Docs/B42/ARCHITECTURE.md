# Architecture B42 — Dynamic NPC Overhaul v0.0.9k

## Structure des fichiers

```
B42/
├── 42/media/lua/
│   ├── shared/
│   │   ├── PHNPC_Core.lua       # Namespace PHNPC, constantes, OUTFIT_STATS (47 outfits), PHNPC.Log stub
│   │   ├── PHNPC_Stats.lua      # initStats() + initInventory() par metier
│   │   └── Translate/
│   │       ├── EN/UI_PHNPC_EN.txt   # Traductions EN (format .txt, pré-B42.18)
│   │       ├── EN/UI.json           # Traductions EN (format JSON, B42.18+)
│   │       ├── FR/UI_PHNPC_FR.txt   # Traductions FR (format .txt, pré-B42.18)
│   │       └── FR/UI.json           # Traductions FR (format JSON, B42.18+)
│   └── client/
│       ├── PHNPC_Actions.lua    # Déplacement NPC (startMovingTo, stopMoving, startFollowing)
│       │                        # v0.0.9g : checkAndOpenDoors reécrit (ToggleDoorSilent + recalc pathfind)
│       │                        # v0.0.9g : closeNearbyDoors reécrit (ToggleDoorSilent)│       │                        # NEW v0.0.9h : checkAndOpenWindows / closeNearbyWindows (pattern Bandits ZAOpenWindow)
│       │                        # FIX v0.0.9h : startFollowing utilise pathToLocationF offset (bug NPC qui colle)│       ├── PHNPC_Barks.lua      # Barks auto (BARK_KEYS, getRandomBark, sayBark)
│       ├── PHNPC_Combat.lua     # Combat auto vs zombies (npcCombatStep, npcFlightStep)
│       │                        # v0.0.9c : armes inventaire + NoiseTimer
│       ├── PHNPC_Convert.lua    # Conversion zombie → NPC (convertToNPC)
│       ├── PHNPC_Danger.lua     # Sons NPC → agro zombies (aggroZombiesOnNPC)
│       │                        # NEW v0.0.9c : PHNPC_NoiseTimer + scan DANGER_TICK_RATE
│       ├── PHNPC_Debug.lua      # Menu DEBUG_PHNPC (dbgSpawnAtPlayer)
│       ├── PHNPC_Enforce.lua    # OnZombieUpdate + barks auto toutes 500 ticks
│       ├── PHNPC_Health.lua     # OnHitZombie → dégâts → mort NPC
│       ├── PHNPC_Inventory.lua  # Inventaire NPC (openNPCInventory)
│       ├── PHNPC_Log.lua        # Logging centralisé (niveaux + écriture fichier)
│       │                        # NEW v0.0.9d : PHNPC.Log.debug/info/warn/error, flush 300 ticks
       │                        # FIX v0.0.9h : guard Events.OnGameEnd (n'existe plus en B42.18)
│       ├── PHNPC_Manager.lua    # Spawn + registres (allNPCs, recruited, spawnNPC)
│       ├── PHNPC_Menu.lua       # Menu contextuel clic-droit
│       │                        # v0.0.9d : ordres mis à jour (shelter/free/quitTeam)
│       ├── PHNPC_Orders.lua     # Ordres joueur (recruit, follow, stay, attack, shelter…)
│       │                        # v0.0.9g : hardening nil-guard sur toutes les fonctions d'ordre
│       ├── PHNPC_Pathfind.lua   # Utilitaires pathfinding
│       │                        # NEW v0.0.9c : findFreeSquareNear, findEscapeDirection, findClearAreaNear
│       └── PHNPC_Update.lua     # Boucle OnTick principale
│                                # v0.0.9d : recalcul conditionnel (seuil joueur), +4 états
├── common/media/
│   ├── anims_X/Zombie/          # Animations custom (copies depuis NHM)
│   └── AnimSets/zombie/         # Jeux d'animations conditionnels (PHNPC_IsNPC)
```

## Ordre de chargement

PZ charge les fichiers client par **ordre alphabétique** :

1. `shared/PHNPC_Core.lua` — namespace + constantes + PHNPC.Log stub minimal
2. `shared/PHNPC_Stats.lua` — initStats / initInventory
3. `client/PHNPC_Actions.lua` — startMovingTo, stopMoving, startFollowing, checkAndOpenDoors (v0.0.9g: ToggleDoorSilent)
4. `client/PHNPC_Barks.lua` — BARK_KEYS, getRandomBark, sayBark
5. `client/PHNPC_Combat.lua` — npcCombatStep, npcFlightStep
6. `client/PHNPC_Convert.lua` — convertToNPC
7. `client/PHNPC_Danger.lua` — aggroZombiesOnNPC, scan OnTick (v0.0.9c)
8. `client/PHNPC_Debug.lua` — dbgSpawnAtPlayer
9. `client/PHNPC_Enforce.lua` — OnZombieUpdate (enforceNPC), barks auto
10. `client/PHNPC_Health.lua` — OnHitZombie
11. `client/PHNPC_Inventory.lua` — openNPCInventory
12. `client/PHNPC_Log.lua` — **PHNPC.Log complet** remplace stubs Core (v0.0.9d NEW)
13. `client/PHNPC_Manager.lua` — spawnNPC, registres
14. `client/PHNPC_Menu.lua` — menu contextuel (v0.0.9d: shelter/free/quitTeam)
15. `client/PHNPC_Orders.lua` — ordres (v0.0.9g: hardening nil-guard toutes fonctions)
16. `client/PHNPC_Pathfind.lua` — findFreeSquareNear, findEscapeDirection, findClearAreaNear (v0.0.9c)
17. `client/PHNPC_Update.lua` — OnTick principal (v0.0.9d: 4 nouveaux états comportementaux)

## Flux de creation d'un NPC

```
spawnNPC(square)
  └── addZombiesInOutfit(x,y,z,1,outfit,femaleChance)
        └── convertToNPC(zombie, outfit, isFemale, npcName)   [PHNPC_Convert.lua]
              ├── [1-14] Config base (setNoTeeth, setWalkType, variables animset, voix, etc.)
              ├── PHNPC.allNPCs[zombie] = true
              ├── PHNPC.initStats(zombie, outfit, isFemale)   -- speed, HP, stats
              └── PHNPC.initInventory(zombie, outfit)         -- poids max, items
```

## Flux tick NPC

```
Events.OnZombieUpdate (chaque tick)                          [PHNPC_Enforce.lua]
  └── enforceNPC(zombie)
        ├── setUseless(false)
        ├── setVariable("PHNPC_IsNPC", true)  -- active nos AnimSets
        ├── setWalkType("Walk")
        ├── setFemaleEtc(isFemale)
        ├── setSpeedMod(md.PHNPC_SpeedMod)    -- vitesse selon metier
        ├── Gestion etats: pathfind/bumped/hitreaction/lunge/...
        ├── Barks auto toutes BARK_TICK_RATE (500) ticks pour NPCs recrutés
        └── setUseless(true) si non-recrute

Events.OnTick (chaque trame)                                 [PHNPC_Update.lua]
  └── [NPCs recrutés]
        ├── checkAndOpenDoors(npc)        [PHNPC_Actions.lua] -- ouvre portes adjacentes (ToggleDoorSilent)
        ├── handleStuck(npc)              [PHNPC_Actions.lua] -- détection blocage
        ├── npcFlightStep(npc, player)    [PHNPC_Combat.lua]  -- fuite si HP < 30%
        ├── npcCombatStep(npc)            [PHNPC_Combat.lua]  -- attaque zombie le plus proche
        └── États comportement :
              -- "following"  : pathToCharacter si joueur s'éloigne (seuil FOLLOW_MOVE_THRESHOLD)
              -- "goingto"    : pathToLocationF vers destination désignée
              -- "staying"    : patrouille dans STAY_RADIUS autour de la zone mémorisée
              -- "free"       : errance autonome jusqu'à FREE_WANDER_DIST
              -- "shelter"    : findClearAreaNear → staying
              -- "attacking"  : attaque active → retour position de base
              -- "fleeing"    : géré par npcFlightStep

Events.OnHitZombie (quand joueur frappe)                     [PHNPC_Health.lua]
  └── PHNPC.isNPC(zombie)?
        ├── Calcul dégâts (handWeapon:getMaxDamage * 15)
        ├── md.PHNPC_Health -= damage
        ├── zombie:setHealth(10000)  -- prevent vanilla death
        ├── setBumpType("PainHead" or "PainTorso")
        └── hp<=0?
              ├── addLineChatElement(getText("UI_PHNPC_BarkDeath"), ...)
              ├── md.PHNPC_IsNPC = nil      -- CRITIQUE: coupe OnZombieUpdate AVANT mort
              ├── retirer de allNPCs/recruited
              └── zombie:setHealth(0)       -- PZ crée corpse lootable avec tout l'inventaire
```

## Système de traductions

```
Translate/
  EN/UI_PHNPC_EN.txt   -- table UI_EN = {}, format pré-B42.18
  EN/UI.json           -- format JSON plat, B42.18+
  FR/UI_PHNPC_FR.txt   -- table UI_FR = {}, format pré-B42.18
  FR/UI.json           -- format JSON plat, B42.18+
```

Clés disponibles : `UI_PHNPC_MenuLabel/Talk/Recruit/Inventory/Orders/Delete/Spawn`,  
`UI_PHNPC_Order*`, `UI_PHNPC_Bark*` (Recruit/Dismiss/Stay/Follow/Attack/Flee/CombatOn/CombatOff/Death),  
`UI_PHNPC_BarkFollowing1-7`, `BarkStaying1-5`, `BarkDefending1-5`, `BarkFleeing1-4`, `BarkIdle1-4`,  
`UI_PHNPC_InfoLine1/2`, `UI_PHNPC_HpRestored/FleeHurt/FleeOk`.

Tous les `addLineChatElement` passent par `string.format(getText("UI_PHNPC_..."), ...)`.

## Règle critique : ordre de mort d'un NPC

```
md.PHNPC_IsNPC = nil     ← TOUJOURS EN PREMIER
PHNPC.allNPCs[npc] = nil
PHNPC.recruited[npc] = nil
npc:setHealth(0)         ← crée le corpse lootable

-- NE PAS faire setHealth(1) : ne tue pas le NPC, aucun corpse, items perdus
-- NE PAS laisser PHNPC_IsNPC=true : OnZombieUpdate ressuscite via setHealth(10000)
```

## Variables ModData importantes

| Variable | Type | Description |
|----------|------|-------------|
| PHNPC_IsNPC | bool | Marque NPC (aussi variable AnimSet) |
| PHNPC_Recruited | bool | Recruté ou non |
| PHNPC_State | string | "idle"/"following"/"staying"/"goingto"/"free"/"shelter"/"attacking"/"fleeing" |
| PHNPC_Moving | bool | En déplacement |
| PHNPC_Health | number | PV actuels (système PHNPC) |
| PHNPC_MaxHealth | number | PV max |
| PHNPC_SpeedMod | number | Multiplicateur vitesse (lu par enforceNPC) |
| PHNPC_Strength | number | Force (0-10) |
| PHNPC_Female | bool | Sexe (Bob=male, Kate=female) |
| PHNPC_Outfit | string | Métier |
| PHNPC_Name | string | Nom |
| PHNPC_HitTicks | number | Compteur ticks hitreaction |
| PHNPC_ShowTimer | number | Délai après spawn (ignore enforce) |
| PHNPC_CombatMode | string | "auto" (combat actif) ou "off" (combat désactivé) |
| PHNPC_PrevState | string | État sauvegardé avant combat/fuite |
| PHNPC_BarkTick | number | Compteur pour barks auto (reset à BARK_TICK_RATE) |
| PHNPC_AttackCooldown | number | Ticks restants avant prochain attack melee |

## Variables AnimSet critiques (setVariable)

| Variable | Valeur | Rôle |
|----------|--------|------|
| PHNPC_IsNPC | true | Active ZSIdle, ZSWalk, ZSNPCStaggerBack, etc. |
| NoLungeTarget | true | Désactive lunge vers cible |
| ZombieHitReaction | "Chainsaw" | Animation de hit reaction humaine |
| WalkSpeed | float | Vitesse de marche animation |
| RunSpeed | float | Vitesse de course animation |

## Principes architecturaux

1. **Ne jamais interrompre pathfind** — setTarget(nil) tue le pathfind (pattern NHM)
2. **enforceNPC = idempotent** — peut être appelé chaque tick sans effet de bord
3. **setUseless(false) avant setBumpType** — requis pour animations haute priorité (FrontKick, Shove)
4. **BumpAnimFinished** — tous les bumped XMLs ont cet event à End → retour idle auto
5. **setHealth(10000)** — empêche mort vanilla ; mort gérée via md.PHNPC_Health
6. **ToggleDoorSilent() pour les portes** — `ToggleDoor(npc)` est invalide en B42 (mauvaise signature). Séquence correcte : `DirtySlice()` → `RecalcLightTime = -1.0` → `InvalidateSpecialObjectPaths()` → `ToggleDoorSilent()` → `RecalcProperties()` → `syncIsoObject()`. Puis `ReCalculateCollide` + `ReCalculatePathFind` sur rayon 2 tuiles pour invalider le cache du pathfinder zombie.
7. **pcall sur tout** — aucun crash possible même si API PZ change
8. **getText() lazy** — les clés de traduction sont stockées comme strings, `getText()` appelé à l'utilisation (après chargement des traductions)
9. **nil-guard en tête de chaque ordre** — toutes les fonctions `PHNPC.*Orders` vérifient `if not npc then return end` + `if not md then return end` avant tout traitement
