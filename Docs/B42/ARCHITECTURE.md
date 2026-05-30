# Architecture B42 — Dynamic NPC Overhaul v0.0.17

> v0.0.17 — Stabilisation runtime B42, anti-saccades follow, combat/XP fiabilises (2026-05-30)
>
> Axes techniques appliques :
>
> 1. **Runtime-safe Java calls** : ajout de `PHNPC.hasMethod`/`PHNPC.tryCall` pour eviter les appels de methodes non exposees selon contexte Kahlua.
> 2. **Follow cadence controlee** : `FOLLOW_REPATH_TICKS=45` + throttling `PHNPC_FollowTick` dans Update pour supprimer le spam `follow anchor`.
> 3. **Combat contextuel** : selection ranged prioritaire a distance avec munitions + competence Aiming ; consommation munitions robuste.
> 4. **Progression active** : gain XP au combat (Aiming/Blunt/Strength/Fitness/Maintenance).
> 5. **Meteo B42 robuste** : detection via `ClimateManager` avec fallback `GameTime`.
> 6. **Debug outfit** : score defensif visible par slot via `getOutfitDefenseSummary`.

> v0.0.16 — Refactoring modulaire : IA armes a feu, progression XP, vetements auto, barks meteo (2026-05-30)
>
> Axes techniques appliques :
>
> 1. **Pathfinding natif** : `PHNPC_Pathfinding.lua` remplace `PHNPC_Pathfind.lua` ; `pathToLocationF` (NavigatorGrid) gere automatiquement portes/fenetres/clotures avec cooldown `PATH_MIN_TICKS=15`.
> 2. **Armes a feu** : `PHNPC_Combat.lua` detecte les munitions + le niveau `Aiming`, tire jusqu'a `RANGED_ATTACK_RANGE=10` tuiles avec cooldown 120 ticks.
> 3. **Progression XP** : `PHNPC_Stats.lua` gere 13 competences + formule XP + bark levelup.
> 4. **Module Outfits** : `PHNPC_Outfits.lua` centralise la selection/equipement de vetements (extrait de Inventory).
> 5. **Barks meteo** : `PHNPC_Barks.lua` detecte pluie/orage/neige/canicule/brouillard via `GameTime`.
> 6. **Init centrale** : `PHNPC_Main.lua` verifie la sante de tous les modules au demarrage.

## Structure des fichiers (v0.0.16)

```
B42/42/
  mod.info                              version=0.0.16
  media/
    lua/
      shared/
        PHNPC_Core.lua                  constantes globales + RANGED_ATTACK_RANGE
        PHNPC_Stats.lua                 stats NPC + systeme XP/competences (v0.0.16)
        Translate/
          EN/UI_PHNPC_EN.txt            traductions anglaises (+ 14 cles meteo/levelup)
          FR/UI_PHNPC_FR.txt            traductions francaises (+ 14 cles meteo/levelup)
      client/
        PHNPC_Main.lua                  [NOUVEAU v0.0.16] init centrale + health check
        PHNPC_Manager.lua               point d'entree ; liste les dependances modules
        PHNPC_Actions.lua               deplacement + fix proximity
        PHNPC_Barks.lua                 barks + barks meteo (v0.0.16)
        PHNPC_Combat.lua                IA combat / fuite + armes a feu (v0.0.16)
        PHNPC_Convert.lua               spawn NPC
        PHNPC_Debug.lua                 menu debug
        PHNPC_Enforce.lua               comportement NPC + animation
        PHNPC_Health.lua                sante NPC
        PHNPC_Inventory.lua             inventaire NPC + onItemGiven (v0.0.16)
        PHNPC_Loot.lua                  loot cadavre
        PHNPC_Menu.lua                  menu clic-droit
        PHNPC_Orders.lua                ordres recrutement/follow/stay/...
        PHNPC_Outfits.lua               [NOUVEAU v0.0.16] selection vetements par score
        PHNPC_Pathfind.lua              pathfinding legacy (conserve)
        PHNPC_Pathfinding.lua           [NOUVEAU v0.0.16] pathfinding natif coroutine
        PHNPC_Update.lua                events OnZombieUpdate / OnTick / OnGameStart
        PHNPC_Danger.lua                danger attractif zombies
        PHNPC_Dialogue.lua              dialogues Ollama
```

## Ordre de chargement PZ

PZ charge `shared/` avant `client/`, puis les fichiers `client/` dans l'ordre alphabetique. L'ordre effectif cote client est donc :

```
PHNPC_Actions → PHNPC_Barks → PHNPC_Combat → PHNPC_Convert → PHNPC_Danger
→ PHNPC_Debug → PHNPC_Dialogue → PHNPC_Enforce → PHNPC_Health
→ PHNPC_Inventory → PHNPC_Loot → PHNPC_Main  ← health check ici
→ PHNPC_Manager → PHNPC_Menu → PHNPC_Orders → PHNPC_Outfits
→ PHNPC_Pathfind → PHNPC_Pathfinding → PHNPC_Update
```

`PHNPC_Main.lua` (lettre M) est charge apres la majorite des modules : c'est intentionnel pour que le health check puisse verifier la presence de toutes les fonctions essentielles.

## Constantes cles (PHNPC_Core.lua)

| Constante | Valeur | Fichier usage |
|---|---|---|
| `PHNPC.FOLLOW_STOP_DISTANCE` | 2 | Actions |
| `PHNPC.RUN_DISTANCE` | 6 | Actions |
| `PHNPC.FOLLOW_REPATH_TICKS` | 45 | Actions |
| `PHNPC.FLEE_HP_RATIO` | 0.30 | Combat |
| `PHNPC.COMBAT_RANGE` | 1.5 | Combat |
| `PHNPC.RANGED_ATTACK_RANGE` | 10 | Combat (v0.0.16) |
| `PHNPC.DOOR_SEARCH_RADIUS` | 4 | Pathfinding (v0.0.16) |
| `PHNPC.PATH_MIN_TICKS` | 15 | Pathfinding (v0.0.16) |
| `PHNPC.RANGED_COOLDOWN` | 120 | Combat (v0.0.16) |
| `PHNPC.RANGED_MIN_SKILL` | 1 | Combat (v0.0.16) |

## Systeme de progression (PHNPC_Stats.lua v0.0.16)

- 13 competences par NPC : `Strength`, `Fitness`, `Aiming`, `Nimble`, `Sneaking`, `Axe`, `Blunt`, `SmallBlade`, `Maintenance`, `Doctor`, `Cooking`, `Carpentry`, `Farming`.
- Stockage en `ModData` : `PHNPC_Skill_<Name>` (niveau 0-10) + `PHNPC_XP_<Name>` (XP cumulee).
- Formule de montee de niveau : `xpForLevel(n) = sum(150 * (i+1)^1.5)` pour i de 0 a n-1.
- API : `PHNPC.getNPCSkillLevel(npc, skill)`, `PHNPC.addNPCXP(npc, skill, amount)`, `PHNPC.getSkillSummary(npc)`.

## Detection meteo (PHNPC_Barks.lua v0.0.16)

```lua
local rain  = GameTime.getInstance():getRainIntensity()  -- 0.0 - 1.0
local temp  = GameTime.getInstance():getTemperature()    -- Celsius
local fog   = GameTime.getInstance():getFogIntensity()   -- 0.0 - 1.0
-- storm  : rain > 0.7
-- rain   : rain > 0.1
-- snow   : rain > 0.1 AND temp < 0
-- hot    : temp > 35
-- fog    : fog > 0.3
```

> v0.0.15 — Stabilisation finale follow/ordres/clotures + inventaire/loot (2026-05-28)
>
> Axes techniques appliques :
>
> 1. Follow anti-saccades renforce : cadence minimale de re-path (`FOLLOW_REPATH_TICKS`) + hold zone anti yo-yo autour de la distance d'arret.
> 2. Clotures/obstacles bas : mitigation `ClimbOverFenceState` non bloquante (reset seulement si blocage prolonge).
> 3. Continuite d'ordres : verrou `PHNPC_OrderLock` applique sur `goingto/shelter` (Orders + Update + Combat).
> 4. Shelter : passage automatique en `staying` des l'entree dans un batiment + fermeture defensive portes/fenetres.
> 5. Inventaire/loot : auto-equip vetements compatible API B42 (`instanceof Clothing` + fallback worn API), et transfert loot mort fiabilise (`DeadPendingLoot` + fallback `AddItem(fullType)`).

> v0.0.14 — Stabilisation post re-test v0.0.13/v0.0.13b (2026-05-28)
>
> Axes techniques appliques :
>
> 1. Follow anti-saccades : suppression du recalcul d'ancre quasi continu, ajout d'une fenetre anti yo-yo proche du stop distance.
> 2. Continuite d'ordre : verrou explicite `PHNPC_OrderLock` pour `goingto`/`shelter` afin d'empecher les retours parasites vers `following`.
> 3. Clotures : mitigation `ClimbOverFenceState` non bloquante (reset seulement en cas de blocage prolonge).
> 4. Auto-equip vetements : detection robustifiee (`instanceof Clothing` + fallback worn API).
> 5. Mort/loot : preservation du contexte NPC jusqu'au snapshot, correction du transfert des objets donnes vers le cadavre.

> v0.0.13 — Stabilisation post-test v0.0.12 (2026-05-28)
>
> Axes techniques appliques :
>
> 1. Follow anti-collage : `startFollowing` utilise un point d'ancrage autour du joueur (distance de confort) au lieu d'un `pathToCharacter` relance en continu.
> 2. Continuite d'ordre : `enforceNPC` ne casse plus le mouvement sur `lunge/attack/eatBody` quand l'ordre actif est un deplacement explicite (`following`, `goingto`, `shelter`, `fleeing`).
> 3. Stabilite d'etat : delai idle plus large (120 ticks en ordre actif) pour eviter les cycles stop/repath.
> 4. Boucle equipement/loot : meilleure arme comparee a l'arme equipee, auto-equipement vetements depuis inventaire, snapshot loot incluant les armes en main.
>
> Impact attendu en jeu :
>
> - NPC arrete de pousser/coller le joueur au stop.
> - Moins d'allez-retour sur `Va la-bas` et `Mets-toi a l'abri`.
> - Armes equipees correctement en combat et presentes au cadavre.
> - Vetements donnes par le joueur portes automatiquement (si slot libre).

> **v0.0.12 — Correctifs post-test v0.0.11 (2026-05-28, à tester)**
>
> Les retours joueur v0.0.11 montrent que 6/6 P0 restent cassés. Analyse de `console.txt` + code confirme trois causes racines supplémentaires :
>
> 1. **Crash combat en boucle** sur `scoreWeapon` ([PHNPC_Combat.lua](B42/42/media/lua/client/PHNPC_Combat.lua#L31)) : la détection d'arme via `item:isWeapon()` n'est pas fiable sur tous les objets exposés Kahlua et déclenche des exceptions répétées, ce qui perturbe toute la boucle IA.
> 2. **Sortie prématurée de OnTick** dans l'état `staying` : un `return` dans la branche `NoPatrol` quittait tout le callback tick, interrompant la logique pour les NPCs suivants.
> 3. **Follow trop cadencé** (timer + seuil de déplacement) : bascule Run/Walk tardive et arrêt à distance peu réactif.
>
> Correctifs v0.0.12 appliqués :
>
> - `startMovingTo` en mode **path-once strict** : nouveau path uniquement si destination a changé (>2 tuiles) ou NPC à l'arrêt ; aucun re-fire sur destination identique.
> - `following` appelle `startFollowing` à chaque tick avec Run/Walk dynamique ; `startFollowing` garde son ancre interne (re-path joueur seulement à +5 tuiles) donc pas de spam.
> - `staying` : suppression du `return` global ; le tick continue normalement.
> - `getNPCWeapon` durci : `instanceof(item, "HandWeapon")` + garde-fous dégâts/condition, plus de dépendance critique à `item:isWeapon()`.
> - `attackOrderNPC` reset désormais aussi `PHNPC_NoPatrol`.
>
> Références officielles re-vérifiées :
>
> - [Lua API](https://pzwiki.net/wiki/Lua_(API)) : rappel des règles d'exposition Java↔Lua, charge `client/shared/server`, et bonnes pratiques modding B42.
> - [JavaDocs](https://demiurgequantified.github.io/ProjectZomboidJavaDocs/index.html) : vérification des familles de classes (`IsoZombie`, `InventoryItem`, `HandWeapon`).
> - [Category:Modding](https://pzwiki.net/wiki/Category:Modding) : pages officielles de référence modding.
> - [Build status](https://projectzomboid.com/blog/news/2017/02/buildstatus/) : B42.18.0 confirmée côté canal officiel.

> **v0.0.11 — REFONTE ARCHITECTURALE "path-once"** (2026-05-28, non testée)
>
> Après échec en jeu de la v0.0.10 (4/5 P0 régressés malgré les fixes ciblés), changement de paradigme du moteur de déplacement :
>
> - **Suivi joueur** : `pathToCharacter(player)` UNE FOIS (engine-side tracking, pattern NPC_Helper_Mod) au lieu de `pathToLocationF(tx,ty)` avec offset recalculé chaque tick. Re-path seulement si player bouge ≥ 5 tuiles.
> - **Va là-bas** : `pathToLocationF(x,y)` une fois ; re-path uniquement si nouvelle destination > 2 tuiles de l'ancienne. Anchor stocké dans `md.PHNPC_PathX/Y`.
> - **Portes/fenêtres** : ouvertes UNIQUEMENT au lancement d'un path (entrée `startFollowing`/`startMovingTo`), JAMAIS à chaque tick. Fermées UNIQUEMENT à la transition `staying` (nouvelle fonction `PHNPC.closeBehindNPC`). Élimine le ping-pong qui causait 18 blocs ERROR.
> - **Arrivée goingto/shelter** → `staying` + flag `md.PHNPC_NoPatrol=true` → pas de patrouille aléatoire. Reset à `nil` par tous les ordres pour réengager.
> - **Enforce idle stop** : seuil 15 → 60 ticks pour tolérer les transitions pathfind du moteur.
> - **`getNPCWeapon`** : scan complet inventaire + ranking par `dmg*10 + condRatio` au lieu du premier `tryGet` séquentiel (hache > batte si les deux présentes).
>
> Détails complets dans [CHANGELOG.md](CHANGELOG.md) section v0.0.11. Tests à valider : suivi sans saccade, arrivée Va là-bas immobile, shelter porte fermée UNE FOIS, combat avec meilleure arme.
>
> ---
>
> **v0.0.9p TESTÉE (2026-05-27)** — Test joueur en jeu termine. Base technique saine (chargement OK, console.txt propre, FPS stable avec 5-15 NPCs, structure XML + Lua coherente), mais **~60 % des points gameplay sont defaillants**. 10 causes racines identifiees, dont 2 trouvees post-test par audit code :
>
> 1. **`setEquippedItem` n'existe PAS en B42.18** ([PHNPC_Combat.lua:131](B42/42/media/lua/client/PHNPC_Combat.lua)) — methode appelee depuis v0.0.7a, masquee par pcall depuis toujours. Bonne methode : `setPrimaryHandItem(item)`. Consequence : les NPCs n'equipent JAMAIS leurs armes d'inventaire et frappent toujours a mains nues.
> 2. **`applyMoveTick(npc, md.PHNPC_WalkType or walkType)` ignore les changements de walkType** ([PHNPC_Actions.lua:168](B42/42/media/lua/client/PHNPC_Actions.lua)) — si `md.PHNPC_WalkType` est deja "Walk" du premier path, le nouveau walkType="Run" est ignore. Consequence : NPC ne court JAMAIS en suivi.
>
> Les 8 autres causes racines (NPC colle joueur, allez-retour Va la-bas, shelter aleatoire, combat pas tourne vers cible, fuite en boucle, zombies ignorent NPC, loot dans NPC pas cadavre, anim idle = posture zombie) sont detaillees dans [CHANGELOG.md](CHANGELOG.md) section "RÉSULTATS DE TEST" et [feuille de route.md](feuille%20de%20route.md) section "ROADMAP v0.0.10".
>
> **v0.0.9p (2026-05-27)** — Passe d'audit API B42.18 + hardening pcall.
>
> Audit complet des 17 fichiers client + 2 shared (~3800 LOC) contre la JavaDoc officielle B42.18 (`demiurgequantified.github.io/ProjectZomboidJavaDocs`), le PZ Wiki Lua API et les patterns Bandits 42.18 / NPC_Helper_Mod. **Toutes** les methodes Java utilisees sont confirmees existantes dans la build courante (`42.18.0 rev 9d7e334cab` 2026-05-11). Le `console.txt` post-v0.0.9o est propre (aucune erreur mod). En prevention, durcissement defensif sur les derniers appels bare dans `PHNPC_Enforce.lua` (step 6 securite, step 7 setUseless, step 5 setTarget pour turnalerted/lunge/attack) : tous wrappes en pcall pour qu'une evolution future de l'API ne casse jamais le for-loop principal d'`OnTick`.
>
> **v0.0.9o (2026-05-27)** — Cause racine des saccades + « rien ne fonctionne » trouvee dans `console.txt` :
>
> 1. **`obj:ToggleDoor(npc)` plantait** avec `NullPointerException: IsoPlayer.isLocalPlayer() because "player" is null`. La methode Java cast en interne en `IsoPlayer` ; le NPC du mod est un `IsoZombie`. Le NPE non-rattrape interrompait le for-loop principal -> tous les NPCs suivants perdaient leur tick (saccades, ordres ignores, pas d'attaque).
> 2. **Fix** : pattern Bandits B42.18 verifie (`BanditUpdate.lua:823`, `BanditServerCommands.lua:172/178/184`) -> **`obj:ToggleDoorSilent()` sans argument**. Applique aux 3 sites (`closeNearbyDoors` x2, `checkAndOpenDoors`).
> 3. **Saccades residuelles** : `setBumpType` (dans `applyMoveStart`) etait re-declenche a chaque cooldown de re-path (8 ticks). Desormais `applyMoveStart` est appele **uniquement** au tout premier path (`md.PHNPC_Moving == false`). Pendant le mouvement, seuls `applyMoveTick` (idempotent) + `pathToLocationF(newTx, newTy)` tournent -> le moteur enchaine sans reset d'anim.
>
> **v0.0.9n (2026-05-27)** — Building.lua ultra-defensif (`IsoBuilding:getRoom(int)` n'existe PAS - extraction `.class` -> seuls `getRoom()` no-arg, `getRoomByID(long)`, `getRandomRoom()`. Fallback `getDef():getRooms()` ArrayList iter). Loot.lua via `OnDeadBodySpawn` (items INTO corpse, pattern Bandits `body:getContainer():AddItem`). Update.lua : `pickShelterPoint` + `findNearestZombie` proteges en pcall.
>
> **v0.0.9m (2026-05-27)** — Trois fixes critiques majeurs :
>
> 1. **`PHNPC_Building.lua`** — l'API `IsoBuilding` (retournee par `getCurrentBuilding()`) n'a **pas** de `getRooms()`. Reecrit avec `getRoomsNumber()` + `getRoom(i)` + `IsoRoom:getRandomFreeSquare()`. Le crash en boucle (chaque frame) est resolu.
> 2. **`PHNPC_Actions.lua`** — split `applyMoveSetup` -> `applyMoveStart` (au lancement, anim setup complet) + `applyMoveTick` (chaque tick, idempotent). Les saccades viennent de `setBumpType` + `faceLocationF` re-appeles chaque tick (confirme par audit Bandits `ZAGoTo.onStart`). Ajoute `forceWalkType` a `startFollowing`.
> 3. **`PHNPC_Loot.lua`** — refonte sur pattern Bandits `ZADrop` : `IsoGridSquare:AddWorldInventoryItem` au sol, drop des worn items, backup via `OnZombieUpdate`, retrait de `safePcall` (echec silencieux).
> 4. **`PHNPC_Update.lua`** — handler `following` force `"Run"` quand `dist > RUN_DISTANCE` (6 tuiles).

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
