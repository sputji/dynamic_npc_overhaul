# CHANGELOG B42 — Dynamic NPC Overhaul

## [0.0.9j] — 2026-05-27

### HOTFIX critique — Cascade `Object tried to call nil` (PHNPC_Update.lua:61)

**Diagnostic** : la v0.0.9i appelait 5 méthodes Java qui **n'existent pas** sur `IsoZombie` en B42.18 :
`setAlertedBy`, `setPathTargetCharacter`, `setPrimaryTarget`, `setSecondaryTarget`, `setSkeletonResetting`.

Lorsque Kahlua tente d'invoquer une méthode Java inexistante, il lève une `KahluaException "Object tried to call nil"` qui **n'est PAS rattrapable par `pcall`** (contrairement aux erreurs Lua standard). Résultat : cascade infinie dans `OnZombieUpdate` à chaque tick pour chaque NPC.

**Vérification** : extraction de `projectzomboid.jar` et scan des constants Utf8 de `IsoZombie.class` + `IsoGameCharacter.class` → ces 5 noms n'apparaissent nulle part.

**Fix** : retrait des 9 appels dans `PHNPC_Enforce.lua` (lignes 51-54, 149) et `PHNPC_Actions.lua` (lignes 47, 49, 85, 87).
Le neutralisation du ciblage zombie auto reste assurée par les méthodes **réellement existantes** : `setAttackedBy(nil)`, `setTarget(nil)`, `clearAggroList()`, plus le forçage `changeState(ZombieIdleState.instance())` en cas de `LungeState`.

**Aucune fonction supprimée** : toute la logique Combat / Follow / Goingto / Shelter / Falldown / Free de v0.0.9i est préservée, seuls les appels Java fantômes sont retirés.

---

## [0.0.9i] — 2026-05-23

### Corrections définitives Java natives (4 bugs persistants après v0.0.9h)

Diagnostic : le comportement résiduel d'`IsoZombie` (auto-ciblage du joueur, AnimEngine bloqué en BumpFall) court-circuitait les ordres Lua. Solutions trouvées via la JavaDoc `zombie/characters/IsoZombie`.

- **BUG 2 — « Va là-bas » ignoré (NPC reste à côté du joueur)**
  - **Cause racine** : dans `PHNPC_Update.OnTick`, `npcCombatStep` était appelé **avant** le test du state machine. Dès qu'un zombie passait à ≤ `COMBAT_RANGE` (8 tuiles, donc presque toujours), le NPC basculait en `state="defending"` et `startMovingTo(zombie_x, zombie_y)` écrasait notre destination `goingto`. Comme les zombies sont souvent près du joueur, le NPC tournait autour du joueur au lieu d'aller au point cliqué.
  - **Fix** : dans `PHNPC.npcCombatStep`, garde explicite `if md.PHNPC_State == "goingto" or md.PHNPC_State == "shelter" then return end`. Les ordres explicites du joueur sont désormais prioritaires sur l'IA combat.

- **BUG 5 — « Mets-toi à l'abri » ignoré (même symptôme)**
  - **Cause racine** : identique à Bug 2 (`npcCombatStep` + `npcFlightStep` écrasaient `state="shelter"`).
  - **Fix** : même garde dans `npcCombatStep` et dans `npcFlightStep` (sauf si HP critique < 15 % — la survie reste prioritaire).

- **BUG 4 — Le NPC pousse le joueur (offset négatif ignoré, mouvement saccadé)**
  - **Cause racine** : le moteur natif `IsoZombie` ré-applique automatiquement chaque tick le ciblage du joueur (`setTarget`, `LungeState`) via l'AI Lunge. Notre `pathToLocationF` calculait bien l'offset mais le `PathFindBehavior2` interne reprenait le joueur comme cible immédiatement après. Le NPC oscillait entre notre pathfind et le ciblage automatique zombie.
  - **Fix** : neutralisation native chaque tick dans `PHNPC_Enforce.enforceNPC` :
    - `setAttackedBy(nil)`, `setAlertedBy(nil)`, `setPathTargetCharacter(nil)`, `setPrimaryTarget(nil)`, `setSecondaryTarget(nil)`.
    - Si `getCurrentState()` retourne `LungeState` alors qu'un ordre `goingto`/`shelter` est actif, forçage immédiat de `ZombieIdleState.instance()`.
    - Reset cible **avant** chaque `pathToLocationF` dans `startMovingTo` et `startFollowing` (`setTarget(nil)` + `clearAggroList()` + `setPathTargetCharacter(nil)`).

- **BUG 3 — T-pose persistante après chute (AnimEngine bloqué)**
  - **Cause racine** : l'AnimEngine B42.18 conserve les variables AnimSet `BumpFall`, `BumpFallType`, `BumpDone`, `OnTheFloor` actives après une chute. Tant que `BumpFall=true`, le squelette n'est pas réinitialisé et l'entité reste figée en T-pose, même après `changeState(ZombieIdleState)`.
  - **Fix** : nouveau handler `falldown/staggerback/down` dans `enforceNPC` :
    - Reset variables AnimSet : `setVariable("BumpFall", false)`, `setVariable("BumpFallType", "")`, `setVariable("BumpDone", true)`, `setVariable("OnTheFloor", false)`, `setVariable("WasOnFloor", false)`.
    - Reset état physique : `setOnFloor(false)`, `knockDown(false)`, `setKnockedDown(false)`, `setBecomeCrawler(false)`, `setCrawler(false)`, `setCanWalk(true)`, `setSprinting(false)`, `setAnimatingBackwards(false)`.
    - Reset modèle 3D : `resetModel()`, `resetModelNextFrame()`, `setSkeletonResetting(true)`.
    - Transition propre : `changeState(ZombieIdleState.instance())` puis `setBumpType("IdleToWalk")` (au lieu de "Shrug" qui pouvait re-trigger une animation parasite).

### Détails techniques

- Bannière `[PHNPC] ... v0.0.9i loaded` sur Log, Core, Stats, Actions, Update, Orders, Enforce, Combat.
- Aucun nouveau réglage `PHNPC_Core`. Aucune nouvelle dépendance.
- Méthodes Java natives utilisées (toutes encapsulées en `pcall` pour la sécurité Kahlua) :
  - `IsoZombie.setAttackedBy/setAlertedBy/setPathTargetCharacter/setPrimaryTarget/setSecondaryTarget/setBecomeCrawler/setCrawler/setSprinting/setSkeletonResetting/resetModelNextFrame`
  - `IsoGameCharacter.setVariable("BumpFall"/"BumpFallType"/"BumpDone"/"OnTheFloor"/"WasOnFloor")`
  - `IsoGameCharacter.getCurrentState()` + détection `LungeState`

---

## [0.0.9h] — 2026-05-23

### Corrections de bugs (rapport de test joueur)

- **BUG 1 — `ERROR` au lancement (`Events.OnGameEnd.Add` de table nulle)**
  - **Cause** : `Events.OnGameEnd` n'existe **plus** en B42.18 (l'API d'événements Lua a été nettoyée côté Java ; aucun `Events.lua` côté `media/lua` ne le déclare). `PHNPC_Log.lua` enregistrait un flush final via `Events.OnGameEnd.Add(...)` → `attempted index: Add of non-table: null` au démarrage.
  - **Fix** : utiliser un fallback `Events.OnGameStop or Events.OnPreSave or Events.OnGameEnd` avec garde `if _onEndEvent and _onEndEvent.Add then ... end`. Plus aucun crash au lancement.

- **BUG 7 — Items d'inventaire introuvables (`Base.PoliceBaton` / `Base.NightStick`)**
  - **Cause** : noms invalides en B42.18. Le vrai identifiant en B42 est `Base.Nightstick` (s minuscule, un seul mot). `Base.PoliceBaton` n'existe pas.
  - **Fix** : remplacement dans les 6 outfits concernés (Police, Sheriff_Deputy, Detective, Security, MallSecurity, PrisonGuard) de `{{"Base.PoliceBaton","Base.NightStick"},"Base.HandTorch"}` par `{"Base.Nightstick","Base.HandTorch"}`. Plus d'erreur `ItemContainer.AddItem: can't find ...`.

- **BUG 4 — Le NPC se colle au joueur en suivi**
  - **Cause** : `npc:pathToCharacter(player)` route le pathfinder vers la **case exacte** du joueur ; le NPC essayait donc d'occuper la même tile et venait coller sa hitbox.
  - **Fix** : `startFollowing` calcule maintenant un point cible décalé de `FOLLOW_STOP_DISTANCE` (porté de 2 à 3 tuiles) dans la direction opposée au NPC, puis appelle `pathToLocationF(tx, ty, pz)`. Quand le NPC est déjà à portée, il s'arrête proprement au lieu de re-pathfinder.

- **BUG 2 — Ordre « Va là-bas » : le NPC reste à côté du joueur**
  - **Cause** : l'état `goingto` considérait l'arrivée dès que `dist <= FOLLOW_STOP_DISTANCE (=3)` — donc validait immédiatement la destination quand le NPC était à 3 tuiles du joueur.
  - **Fix** : nouveau seuil dédié `PHNPC.GOTO_ARRIVE_DISTANCE = 1`. L'arrivée n'est validée que quand le NPC est réellement sur la zone cliquée.

- **BUG 5 — Ordre « Mets-toi à l'abri » : le NPC ne bouge pas**
  - **Cause** : l'état `shelter` ne configurait `PHNPC_ZoneX/Y` qu'une fois (au premier tick), n'appelait `startMovingTo` qu'une seule fois et ne rappelait jamais le pathfind. Si l'abri était à 0 tuile (`findClearAreaNear` retournait la position actuelle), le NPC ne bougeait pas du tout.
  - **Fix** : (1) si `findClearAreaNear` rend un point trop proche (< 2 tuiles), fallback aléatoire à 8 tuiles ; (2) ajout d'un retry `startMovingTo` toutes les `FOLLOW_TICK_RATE` ticks comme pour `goingto` ; (3) log explicite « shelter atteint -> staying ».

- **BUG 6 — Les NPC ne savent pas ouvrir/refermer les fenêtres**
  - **Cause** : aucune logique de gestion des fenêtres dans le mod.
  - **Fix** : nouvelle fonction `PHNPC.checkAndOpenWindows(npc)` (4 directions + case courante) basée sur le pattern Bandits B42.18 `ZAOpenWindow.lua` : `square:getWindow():ToggleWindow(npc)` + `playSound("OpenWindow")`. Les fenêtres barricadées, brisées ou permaverrouillées sont ignorées. Ajout symétrique de `closeNearbyWindows` (9 directions) appelée dans `stopMoving`. Branchement dans `startMovingTo`, `startFollowing` et la boucle `OnTick` de `PHNPC_Update`.

- **BUG 3 — Bug d'animations / T-pose lors des chutes**
  - **Cause probable** : la transition `falldown/staggerback/down → ZombieIdleState` ne réinitialisait ni la posture (`setOnFloor`) ni le modèle 3D. Le NPC restait parfois bloqué en T-pose côté client.
  - **Fix défensif** : nouvel ordre d'opérations dans `PHNPC_Enforce.lua` : `setOnFloor(false)` → `knockDown(false)` → `setKnockedDown(false)` → `setCanWalk(true)` → `setAnimatingBackwards(false)` → `resetModel()` → `changeState(ZombieIdleState)` → `setBumpType("Shrug")`.

### Détails techniques

- `PHNPC.FOLLOW_STOP_DISTANCE` : 2 → 3 tuiles.
- Nouveau réglage : `PHNPC.GOTO_ARRIVE_DISTANCE = 1` tuile (anciennement = `FOLLOW_STOP_DISTANCE`).
- Nouveaux helpers : `PHNPC.checkAndOpenWindows(npc)`, `PHNPC.closeNearbyWindows(npc)`.
- Bannière `[PHNPC] ... v0.0.9h loaded` sur Log, Core, Stats, Actions, Update, Orders, Enforce.

---

## [0.0.9g] — 2026-05-25

### Nouvelles fonctionnalités

- **Tous les métiers (outfits) PZ B42 disponibles**
  - Avant : seulement 7 outfits (Farmer, Police, Fireman, Doctor, Ranger, Chef, Survivor).
  - **Ajout** : 50+ outfits issus de `clothing.xml` (source officielle PZ 42.18), répartis en 5 catégories :
    - Forces de l'ordre / Militaire : Police, Sheriff_Deputy, Detective, Security, MallSecurity, PrisonGuard, Veteran, ArmyCamoGreen, ArmyCamoDesert, PrivateMilitia, BountyHunter
    - Services d'urgence / Santé : Fireman, Doctor, Nurse, AmbulanceDriver, Pharmacist
    - Travailleurs / Artisans : Farmer, Chef, Mechanic, ConstructionWorker, Trucker, Woodcut, MetalWorker, Sanitation, Postal, Foreman
    - Nature / Plein air : Ranger, Hunter, Fisherman, Camper, Survivalist
    - Civils : Teacher, IT, OfficeWorker, Resident, Retiree, Student, Tourist, Biker, Redneck, Hobbo, Inmate, Priest, FitnessInstructor
    - Génériques : Generic01–05
  - Chaque outfit a des stats cohérentes (speed/strength/health/maxWeight/items).
  - `PHNPC.OUTFITS` mis à jour pour inclure tous ces métiers au spawn aléatoire.

### Corrections de bugs

- **NPCs tapent les portes au lieu de les ouvrir**
  - **Cause** : L'ancienne `checkAndOpenDoors` utilisait `ToggleDoor(npc)` sans recalculer les chemins du pathfinder. Le pathfinder zombie de PZ conservait les portes en mémoire comme obstacles → continuait de taper.
  - De plus, `checkAndOpenDoors` était appelée PENDANT le mouvement mais PAS avant le premier `pathToLocationF`/`pathToCharacter` → le pathfinder démarrait avec les portes fermées.
  - **Fix (pattern Bandits 42.18 `BanditUpdate.lua`)** :
    - `ToggleDoorSilent()` remplace `ToggleDoor(npc)` (méthode PZ B42 qui ouvre silencieusement).
    - Support complet : double portes (`IsoDoor.toggleDoubleDoor`), portes garage (`IsoDoor.toggleGarageDoor`), portes standard (`ToggleDoorSilent`).
    - Recalcul pathfind radius 2 tuiles après ouverture : `ReCalculateCollide` + `ReCalculatePathFind` sur les cases voisines → le pathfinder ne voit plus la porte comme obstacle.
    - `checkAndOpenDoors` appelée **AVANT** `pathToLocationF`/`pathToCharacter` dans `startMovingTo` et `startFollowing`.
    - Toujours appelée en continu dans `OnTick` via `PHNPC_Update.lua` pour les longs déplacements.

### Robustesse

- **Hardening de toutes les commandes NPC** (`PHNPC_Orders.lua`)
  - Toutes les fonctions d'ordre (`recruitNPC`, `followNPC`, `stayNPC`, `attackOrderNPC`, `shelterNPC`, `freeNPC`, `quitTeamNPC`, `toggleCombatNPC`, `deleteNPC`, `enterGoToMode`, `goToLocation`) vérifient maintenant `if not npc then return end` et `if not md then return end` en tête, évitant tout crash si appelées avec un NPC nil ou invalide.




### Corrections de bugs

- **ERRORs `Object tried to call nil in info` (et `debug`, `warn`, `error`)**
  - **Cause** : En Kahlua B42, les `local function _log`, `local function _formatLine` et `local LEVEL_INT = {}` dans `PHNPC_Log.lua` devenaient `nil` en tant qu'upvalues de closures dans des fonctions globales `PHNPC.*` (rechargement de module, contextes d'exécution multiples).
  - **Fix** : Toutes ces entités locales déplacées vers des champs de table `PHNPC.Log._log`, `PHNPC.Log._fmt`, `PHNPC.Log.LEVEL_INT`. Les fonctions publiques (`debug/info/warn/error`) wrappées dans `pcall`.

- **Commande "Va là-bas" non fonctionnelle (NPC tourne autour du joueur)**
  - **Cause** : `local PHGoToCursor = nil` et `local function initGoToCursor()` dans `PHNPC_Orders.lua` devenaient `nil` en upvalue (même règle Kahlua). `PHNPC.enterGoToMode` ne créait jamais le curseur → le NPC restait en état `"following"`.
  - **Fix** : `PHNPC._GoToCursor` et `PHNPC._initGoToCursor` stockés comme champs de table. `enterGoToMode` wrappé dans `pcall` avec log de diagnostic.

- **Noms NPC incomplets (un seul prénom)**
  - `PHNPC.NAMES_M` et `PHNPC.NAMES_F` contenaient uniquement des prénoms.
  - **Fix** : Listes mises à jour avec 16 entrées `"Prénom Nom"` dans `PHNPC_Core.lua`.
  - **Bonus** : Dans `PHNPC_Convert.lua`, après le spawn de l'outfit PZ, les items `Badge`/`IDCard` du zombie sont lus pour extraire le nom natif PZ (format "AL YI" → capitalisé "Al Yi"). Utilisé en priorité si disponible, sinon fallback vers nos listes.

- **Items manquants (policier sans matraque)**
  - `Base.PoliceBaton` peut être absent ou avoir un nom différent selon la build B42.
  - **Fix** : Dans `PHNPC_Core.lua`, les items des OUTFIT_STATS supportent maintenant des groupes alternatifs (table de types) : ex. `{ {"Base.PoliceBaton", "Base.NightStick"}, "Base.HandTorch" }`. Dans `PHNPC_Stats.lua::initInventory`, chaque groupe tente les types dans l'ordre jusqu'au premier succès. Log de diagnostic si aucun ne fonctionne.

- **NPC trop rapide**
  - `walkSpeed = stats.speed * 1.04` produisait des vitesses supérieures au joueur.
  - **Fix** : Multiplicateurs réduits dans `PHNPC_Stats.lua` (`0.85` / `0.60` / `0.65`). Vitesses de base également réduites dans `PHNPC_Core.lua` (Police: `0.85→0.70`, Ranger: `0.90→0.75`, etc.).

- **Portes non refermées après déplacement**
  - `checkAndOpenDoors` ouvrait les portes mais ne les refermait jamais.
  - **Fix** : Nouvelle fonction `PHNPC.closeNearbyDoors(npc)` dans `PHNPC_Actions.lua` qui referme toutes les `IsoDoor` et `IsoThumpable` ouvertes dans un rayon de 2 tuiles. Appelée automatiquement depuis `stopMoving`.

- **"Mets-toi à l'abri" — NPC revient vers le joueur**
  - `findClearAreaNear` ne cherchait pas de case à l'intérieur d'un bâtiment et testait un rayon trop faible.
  - **Fix** : `PHNPC_Pathfind.lua` — radius par défaut `10→15`, système de score avec bonus `-50` pour les cases couvertes (`not sq:isOutside()`). Teste maintenant 12 directions au lieu de 8. Retourne toujours la case avec le meilleur score (couvert + sans zombies).


## [0.0.9e] — 2026-05-23
### Corrections de bugs critiques

- **CRASH `PHNPC_Log.lua` ligne 99 : `__add not defined for operands in Add`**
  - **Cause confirmée** : En Kahlua B42, `Events.OnTick.Add(callback)` passe le numéro de tick (objet Java `Long`) en registre 0 de la callback. La variable locale `_logFlushTick` (upvalue de closure) pouvait se retrouver écrasée par cet argument Java, rendant l'opération `_logFlushTick + 1` invalide (`Long + Number → __add not defined`).
  - **Fix** : `_logFlushTick` et `_logBuffer` sont maintenant stockés comme champs `PHNPC.Log._flushTick` / `PHNPC.Log._buffer` dans la table globale (pas des upvalues de closure). L'accès via `PHNPC.Log._flushTick` n'est pas un registre local → pas de pollution par l'argument Java.
  - L'incrémentation utilise `(type(PHNPC.Log._flushTick) == "number" and PHNPC.Log._flushTick or 0) + 1` pour protection supplémentaire.
  - L'ensemble du handler `Events.OnTick` est wrappé dans `pcall`.

- **NPC tourne en rond / s'accroche au joueur**
  - **Cause** : `startFollowing` (v0.0.9d) utilisait `pathToLocationF(px, py, pz)` — l'engine calcule un chemin vers une **position fixe**. Quand le joueur bouge entre deux ticks, la destination devenait invalide → le NPC recalculait en permanence et pivotait sur place.
  - **Fix** : `startFollowing` utilise maintenant `npc:pathToCharacter(player)` — méthode standard `IsoZombie→IsoCharacter` qui suit dynamiquement un personnage en mouvement. Confirmé par NPC_Helper_Mod B42.18 (`GCUpdateAI.lua` ligne 74, `GCCoreActions.lua`).
  - Nos NPCs sont des `IsoZombie` convertis, pas des `IsoPlayer` → pas de risque de `ClassCastException`.

- **Désynchronisation nom NPC / items d'inventaire (badge "Trent Keen" ≠ NPC "Luc")**
  - **Cause** : L'outfit `Police` de PZ génère des items de badge avec des noms de personnages PZ prédéfinis (ex: "Officer Badge - Trent Keen") qui ne correspondent pas au nom aléatoire du NPC.
  - **Fix** : Dans `PHNPC_Stats.lua::initInventory`, après l'ajout des items, tous les items dont le `FullType` contient `Badge`, `Officer`, `IDCard` ou `Wallet` sont renommés via `item:setCustomName(npcName)` pour afficher le nom du NPC.

---

## [0.0.9d] — 2026-05-22

### Corrections de bugs

- **BUG CRITIQUE : NPC tournait en rond en suivant le joueur** (v0.0.9a → v0.0.9c)
  - **Cause** : `startFollowing` calculait un point cible à `FOLLOW_TARGET_DIST (2.5)` tuiles du joueur en direction du NPC. Quand le joueur bougeait, ce point changeait à chaque recalcul (toutes les `FOLLOW_TICK_RATE` ticks) → direction cible instable → NPC zigzaguait/tournait.
  - **Fix** : `startFollowing` utilise maintenant `pathToLocationF(px, py, pz)` vers la **position exacte** du joueur. L'arrêt est géré par `FOLLOW_STOP_DISTANCE` dans `Update.lua`.
  - **Optimisation** : le recalcul du pathfind n'a lieu que si le joueur s'est déplacé de plus de `FOLLOW_MOVE_THRESHOLD (2 tuiles)` depuis le dernier calcul. Constante `FOLLOW_TARGET_DIST` supprimée.

- **Doublon `elseif` dans `PHNPC_Update.lua`** : un second bloc `elseif dist <= FOLLOW_STOP_DISTANCE` subsistait après le bloc principal → supprimé.

- **Sémantique incorrecte des ordres** (v0.0.9b → v0.0.9c) :
  - `dismissNPC` (« Tu peux partir ») retirait le NPC de l'équipe → remplacé par `freeNPC` (garde dans l'équipe, état `"free"`) et `quitTeamNPC` (retire définitivement de l'équipe).
  - `orderFleeNPC` mappé à « Mets-toi à l'abri » → remplacé par `shelterNPC` (état `"shelter"` avec recherche de zone safe via `findClearAreaNear`).
  - `stayNPC` ne mémorisait pas la zone → corrigé : mémorise `ZoneX/ZoneY/ZoneZ/ZoneR` à la position actuelle du NPC.
  - `orderAttackNPC` n'avait pas de position de retour → corrigé : mémorise `ZoneX/ZoneY/ZoneZ` + état `"attacking"`.

### Nouvelles fonctionnalités

- **Système de logging centralisé : `PHNPC_Log.lua`** (nouveau fichier, position alphabétique L)
  - Niveaux : `DEBUG (0)`, `INFO (1)`, `WARN (2)`, `ERROR (3)`. `PHNPC.Log.LEVEL = 0` (tout en dev).
  - Écriture différée vers `PHNPC_Debug.log` toutes les ~300 ticks via `getFileWriter`.
  - API : `PHNPC.Log.debug/info/warn/error(module, msg)`, `PHNPC.Log.npc(npc, level, msg)`, `PHNPC.Log.npcState(npc)`.
  - Stub minimal initialisé dans `PHNPC_Core.lua` (shared) pour éviter nil-call dans les fichiers A→K.

- **Nouveaux états comportementaux dans `PHNPC_Update.lua`** :
  - `"staying"` (amélioré) : le NPC patrouille librement dans un rayon `STAY_RADIUS (5)` autour de sa zone mémorisée, toutes les `ZONE_PATROL_TICKS (200)` ticks. Si hors zone, retour au centre.
  - `"free"` (nouveau) : NPC reste dans l'équipe (`PHNPC_Recruited = true`) mais erre librement jusqu'à `FREE_WANDER_DIST (10)` tuiles. Il peut encore recevoir des ordres.
  - `"shelter"` (nouveau) : cherche une zone safe via `findClearAreaNear`, s'y déplace, puis passe en `"staying"` à l'arrivée.
  - `"attacking"` (nouveau) : combat actif. Si plus de zombies à portée, retourne à `ZoneX/ZoneY` mémorisée au moment de l'ordre.

- **Nouveaux ordres dans `PHNPC_Orders.lua`** :
  - `PHNPC.attackOrderNPC(npc)` : `"attacking"` + mémorise position de retour.
  - `PHNPC.shelterNPC(npc)` : `"shelter"` + bark `UI_PHNPC_BarkShelter`.
  - `PHNPC.freeNPC(npc)` : `"free"` + bark `UI_PHNPC_BarkFree` (NPC garde `PHNPC_Recruited = true`).
  - `PHNPC.quitTeamNPC(npc)` : `PHNPC_Recruited = false` + bark `UI_PHNPC_BarkQuitTeam` (retire définitivement de `recruited`).

- **Menu mis à jour (`PHNPC_Menu.lua`)** :
  - « Attaque les zombies ! » → `PHNPC.attackOrderNPC`
  - « Mets-toi à l'abri ! » → `PHNPC.shelterNPC`
  - « Tu peux partir. » → `PHNPC.freeNPC`
  - « Quitte mon equipe. » (nouvelle option) → `PHNPC.quitTeamNPC`

- **Destination "Va là-bas" améliorée** : à l'arrivée, le NPC passe en `"staying"` dans une zone centrée sur la destination (mémorise `ZoneX/ZoneY/ZoneR`).

### Nouvelles constantes (`PHNPC_Core.lua`)

| Constante | Valeur | Description |
|-----------|--------|-------------|
| `PHNPC.STAY_RADIUS` | 5 | Rayon (tuiles) de la zone staying/free |
| `PHNPC.PATROL_RADIUS` | 3 | Rayon d'exploration libre dans la zone |
| `PHNPC.FREE_WANDER_DIST` | 10 | Distance max d'errance en état free |
| `PHNPC.ZONE_PATROL_TICKS` | 200 | Ticks entre deux mouvements de patrouille |
| `PHNPC.FOLLOW_MOVE_THRESHOLD` | 2 | Seuil mouvement joueur pour recalcul pathfind |

### Nouvelles clés de traduction (EN + FR)

| Clé | EN | FR |
|-----|----|----|
| `UI_PHNPC_BarkShelter` | Looking for cover... | Je cherche un abri... |
| `UI_PHNPC_BarkFree` | I'll manage on my own. Stay safe. | Je me débrouille seul. Sois prudent. |
| `UI_PHNPC_BarkQuitTeam` | Going solo. Good luck out there. | Je pars seul. Bonne chance. |
| `UI_PHNPC_BarkAttackAll` | On it! Clearing the area. | Compris ! Je nettoie la zone. |

### Fichiers modifiés
- `shared/PHNPC_Core.lua` : v0.0.9d — PHNPC.Log stub minimal, +5 nouvelles constantes, suppression FOLLOW_TARGET_DIST
- `client/PHNPC_Actions.lua` : v0.0.9d — fix startFollowing (pathToLocationF direct, sans offset)
- `client/PHNPC_Update.lua` : v0.0.9d — fix recalcul conditionnel (seuil mouvement joueur), +4 nouveaux états comportementaux, suppression doublon
- `client/PHNPC_Orders.lua` : v0.0.9d — refonte complète : attackOrderNPC, shelterNPC, freeNPC, quitTeamNPC, stayNPC avec zone
- `client/PHNPC_Menu.lua` : v0.0.9d — nouveaux ordres, option "Quitte mon equipe"
- `client/PHNPC_Log.lua` : **NOUVEAU** — système logging centralisé (niveaux + fichier)
- `shared/Translate/EN/UI.json` : +4 nouvelles clés
- `shared/Translate/FR/UI.json` : +4 nouvelles clés

---

## [0.0.9c] — 2026-05-21

### Corrections de bugs

- **Anti-sticking NPC** (bug v0.0.9b) : Suppression complète du vecteur répulsif. À chaque tick le vecteur changeait (joueur mobile) → NPC tournait en rond. Fix : deux transitions simples uniquement (`stop` si dist ≤ 2, `startFollowing` si dist > 6). Constante `REPEL_DISTANCE` supprimée.
- **Curseur "Va là-bas" ne se fermait pas** (bug v0.0.9b) : `create()` dans `PHGoToCursor` n'appelait pas `getCell():setDrag(nil, 0)` → curseur restait à l'écran après le clic. Fix : `setDrag(nil, 0)` ajouté en première ligne de `create()`. De plus, `isValid()` utilisait `result == true` (trop strict) → corrigé en `res and true or false`.
- **Doublon dans la boucle "following"** : un second bloc `elseif dist <= FOLLOW_STOP_DISTANCE` restait après la suppression du REPEL. Supprimé.

### Nouvelles fonctionnalités

- **PHNPC_Pathfind.lua** (nouveau fichier) : Utilitaires de pathfinding.
  - `PHNPC.findFreeSquareNear(x, y, z, radius, maxTries)` : trouve une tuile libre dans un rayon (ZombRand), utilisée par la patrouille des non-recrutés.
  - `PHNPC.findEscapeDirection(npc, enemy, range)` : teste 8 angles autour de la direction opposée à l'ennemi, retourne la première tuile libre. Utilisée par `npcFlightStep`.
  - `PHNPC.findClearAreaNear(x, y, z, radius)` : cherche la zone avec le moins de zombies dans 8 directions. Utilisée comme priorité de fuite.
- **PHNPC_Danger.lua** (nouveau fichier) : Les sons et actions des NPCs attirent les zombies.
  - `PHNPC.aggroZombiesOnNPC(npc, radius)` : force `zombie:setTarget(npc)` + `addAggro(npc,1)` sur les zombies normaux dans le rayon. Pattern Bandits 42.16.
  - `OnTick` scan toutes les `DANGER_TICK_RATE (80)` ticks. NPCs bruyants (`PHNPC_NoiseTimer > 0`) → agro dans `NOISE_RADIUS (12)` tuiles. NPCs en déplacement → agro passif dans 5 tuiles.
  - `PHNPC_NoiseTimer` posé par `PHNPC_Combat.lua` après chaque attaque (valeur 150–200).
- **PHNPC_Combat.lua amélioré** :
  - `npcCombatStep` : détecte et équipe l'arme de l'inventaire NPC (batte, hache, couteau, pied-de-biche, pelle, marteau…). Animation d'attaque adaptée selon le type d'arme. Pose `PHNPC_NoiseTimer` après chaque attaque.
  - `npcFlightStep` : utilise `findEscapeDirection` (8 angles) puis `findClearAreaNear` pour fuir intelligemment. Si la destination est trop loin du joueur (> 30 tuiles), se rapproche du joueur.
- **Patrouille non-recrutés améliorée** : `PHNPC_Update.lua` utilise `PHNPC.findFreeSquareNear` (si disponible) au lieu du fallback ZombRand brut.

### Nouvelles constantes (PHNPC_Core.lua)

| Constante | Valeur | Description |
|-----------|--------|-------------|
| `PHNPC.AGGRO_RANGE` | 10 | Rayon (tuiles) d'agro zombies vers le NPC |
| `PHNPC.NOISE_RADIUS` | 12 | Rayon d'agro en cas de bruit NPC |
| `PHNPC.DANGER_TICK_RATE` | 80 | Ticks entre chaque scan de danger |
| `PHNPC.FLEE_ESCAPE_TRIES` | 8 | Tentatives max dans findEscapeDirection |

### Fichiers modifiés
- `shared/PHNPC_Core.lua` : version 0.0.9c, +4 constantes DANGER, suppression REPEL_DISTANCE
- `client/PHNPC_Update.lua` : fix anti-sticking, suppression doublon stop, patrouille via findFreeSquareNear
- `client/PHNPC_Orders.lua` : fix isValid() + setDrag(nil, 0) dans PHGoToCursor.create()
- `client/PHNPC_Combat.lua` : armes inventaire, NoiseTimer, findEscapeDirection, findClearAreaNear
- `client/PHNPC_Menu.lua` : version 0.0.9c
- `client/PHNPC_Pathfind.lua` : **NOUVEAU** — findFreeSquareNear, findEscapeDirection, findClearAreaNear
- `client/PHNPC_Danger.lua` : **NOUVEAU** — aggroZombiesOnNPC, scan OnTick

---

## [0.0.9b] — 2026-05-24

### Corrections

- **Anti-sticking NPC** : si le NPC est à moins de `REPEL_DISTANCE (1.5)` tuile du joueur, vecteur répulsif appliqué → `pathToLocationF` à 2.5 tuiles (+ jitter ±0.3) pour éviter la superposition.
- **Portes et blocages** : `checkAndOpenDoors(npc)` scrute 4 directions (sq + voisins), ouvre `IsoDoor` et `IsoThumpable:isDoor()` non-barricadées/verrouillées. `handleStuck(npc)` détecte l'immobilité sur 30 ticks et cherche une direction libre.
- **Animations bras tendus zombie** : `setVariable("PHNPC_IsNPC", true)` et `setWalkType("Walk")` déplacés **après tous les `changeState()`** dans `enforceNPC` (step 10). Supprime le reset de variables par `ZombieIdleState`.
- **Patrouille non-recrutés bloquée** : `setUseless(true)` empêchait le pathfinding. Fix via flag `PHNPC_PatrolActive` (entier countdown décrémenté par enforceNPC) — bypass `setUseless` pendant ~3 s.
- **Distances de suivi ajustées** : `FOLLOW_DISTANCE=6`, `FOLLOW_STOP_DISTANCE=2`, `FOLLOW_TARGET_DIST=2.5` (nouvelles constantes).

### Nouvelles fonctionnalités

- **Ordre "Va là-bas"** : clic sur une tuile via curseur ISBuildingObject (tuile verte/rouge vanilla). Menu contextuel > Ordres > "Va la-bas..." Active `PHNPC.enterGoToMode(npc)`.
- **`PHNPC.goToLocation(npc, x, y, z)`** : pose l'état `"goingto"`, bark `UI_PHNPC_BarkGoTo`, recalcul pathfind toutes les 20 ticks, bark d'arrivée `UI_PHNPC_BarkArrived` à 1.5 tuiles.
- **Nouvelles clés de traduction** : `UI_PHNPC_BarkGoTo`, `UI_PHNPC_BarkArrived`, `UI_PHNPC_OrderGoTo` (EN + FR).

### Fichiers modifiés
- `shared/PHNPC_Core.lua` : version + constantes FOLLOW/REPEL
- `client/PHNPC_Actions.lua` : `startFollowing` (jitter), `checkAndOpenDoors`, `handleStuck`
- `client/PHNPC_Enforce.lua` : step 10 AnimSet, `PHNPC_PatrolActive` countdown
- `client/PHNPC_Update.lua` : anti-sticking, état `"goingto"`, patrouille améliorée
- `client/PHNPC_Orders.lua` : `PHGoToCursor`, `enterGoToMode`, `goToLocation`
- `client/PHNPC_Menu.lua` : option "Va la-bas..." dans sous-menu Ordres
- `shared/Translate/EN/UI.json` + `shared/Translate/FR/UI.json` : 3 nouvelles clés

---

## [0.0.9a] — 2026-05-22

### Corrections

- **Animation StaggerBack NPC** : `ZSNPCStaggerBack.xml` utilisait `Bob_EmoteShrug` (identique au Shrug) — corrigé en `Bob_RunStumble`, animation humaine de trébuche adaptée au rig NPC.
- **Traductions B42.18** : PZ 42.18 charge les fichiers `.json` et non les `.txt` non-standard. Ajout de `Translate/EN/UI.json` et `Translate/FR/UI.json` contenant toutes les clés `UI_PHNPC_*`. Les anciens `.txt` sont conservés pour compatibilité pré-42.18.
- **Nouvelle clé `UI_PHNPC_BarkDeath`** : bark de mort du NPC (`%s: Argh...`) — ajouté dans les 4 fichiers de traduction (EN/FR, txt/json).
- **Tous les dialogues NPC passent par `getText()`** : suppression complète des strings hardcodées dans `PHNPC_Combat.lua`, `PHNPC_Health.lua`, `PHNPC_Menu.lua` (6 chaînes). Les fichiers `PHNPC_Orders.lua` (8 chaînes) avaient été corrigés en début de version.

### Fichiers modifiés
- `common/media/AnimSets/zombie/bumped/ZSNPCStaggerBack.xml` : `Bob_EmoteShrug` → `Bob_RunStumble`
- `client/PHNPC_Combat.lua` : FleeHurt + FleeOk via `getText()`
- `client/PHNPC_Health.lua` : BarkDeath via `getText()`
- `client/PHNPC_Menu.lua` : InfoLine1, InfoLine2, HpRestored via `getText()`
- `client/PHNPC_Orders.lua` : BarkRecruit, BarkFollow, BarkStay, BarkDismiss, BarkAttack, BarkFlee, BarkCombatOn, BarkCombatOff via `getText()`
- `shared/Translate/EN/UI.json` + `shared/Translate/FR/UI.json` : nouveaux fichiers JSON B42.18
- `shared/Translate/EN/UI_PHNPC_EN.txt` + `shared/Translate/FR/UI_PHNPC_FR.txt` : ajout `UI_PHNPC_BarkDeath`

---

## [0.0.9] — 2026-05-22

### Refactorisation majeure

- **Éclatement de `PHNPC_Manager.lua`** (1078 lignes) en 9 modules client spécialisés, chargés dans l'ordre alphabétique PZ :

| Fichier | Rôle |
|---------|------|
| `PHNPC_Actions.lua` | Déplacement NPC (startMovingTo, stopMoving, startFollowing) |
| `PHNPC_Barks.lua` | Système de barks automatiques (BARK_KEYS, getRandomBark, sayBark) |
| `PHNPC_Combat.lua` | Combat auto vs zombies (npcCombatStep, npcFlightStep, FleeHurt/FleeOk) |
| `PHNPC_Convert.lua` | Conversion zombie → NPC (convertToNPC) |
| `PHNPC_Debug.lua` | Menu DEBUG_PHNPC (dbgSpawnAtPlayer délègue à PHNPC.spawnNPC) |
| `PHNPC_Enforce.lua` | Boucle OnZombieUpdate + OnTick (enforceNPC, barks auto toutes 500 ticks) |
| `PHNPC_Health.lua` | Dégâts + mort NPC (OnHitZombie) |
| `PHNPC_Inventory.lua` | Inventaire NPC (openNPCInventory, hook containers) |
| `PHNPC_Manager.lua` | Spawn + registres (allNPCs, recruited, spawnNPC) |
| `PHNPC_Menu.lua` | Menu contextuel clic-droit (showNPCInfo, sous-menus) |
| `PHNPC_Orders.lua` | Ordres joueur (recruitNPC, followNPC, stayNPC, dismissNPC, toggleCombat…) |
| `PHNPC_Update.lua` | Boucle OnTick principale |

### Corrections
- **Proximité NPC** : `startFollowing` utilise `pathToLocationF` avec offset `FOLLOW_STOP_DISTANCE=3` — évite la superposition joueur/NPC.
- **getText() timing** : les clés de bark sont stockées dans `BARK_KEYS` comme strings ; `getText(key)` est appelé à l'utilisation dans `getRandomBark()`, après le chargement des traductions.
- **Animation coupée** : handler `asn == "idle"` + vérification `PHNPC_Moving` → `stopMoving()` pour couper l'animation en cours.
- **stopMoving** déclenché quand la cible de combat meurt.

---

## [0.0.8b] — 2026-05-21

### Corrections critiques
- **NPCs ne suivent plus le joueur** : `startFollowing` utilisait `pathToLocationF` avec calcul manuel de destination (point à N tiles du joueur). Remplacé par `pathToCharacter(player)` — méthode standard IsoZombie→IsoPlayer utilisée par NPC_Helper_Mod et Bandits. Plus fiable pour cibler un IsoCharacter mobile.
- **Pas de loot à la mort du NPC** : dans `OnHitZombie`, `setHealth(10000)` était appelé inconditionnellement AVANT le check `hp <= 0`. Résultat : `setHealth(10000)` puis `setHealth(0)` dans le même callback → PZ ignorait `setHealth(0)` → pas de corpse créé → items inaccessibles. Correction : `setHealth(10000)` déplacé dans la branche `hp > 0` (NPC vivant) uniquement.
- **PHNPC_Manager.lua v0.9** : fix pathToCharacter dans startFollowing
- **PHNPC_Health.lua v0.3** : fix setHealth(10000) conditionnel

---

## [0.0.8a] — 2026-05-21

### Correction critique (hotfix)
- **CRASH AU CHARGEMENT** : `PHNPC_Manager.lua` plantait au démarrage avec `SEVERE: Error found in LUA file` — la déclaration `local function deleteNPC(npc)` était absente du fichier, laissant le corps de la fonction comme code top-level orphelin. Résultat : le moteur Lua Kahlua lançait une exception dès le chargement, le système NPC ne s'initialisait jamais, et tous les NPCs de la save redevenaient des zombies normaux.
- **PHNPC_Manager.lua v0.8** : correction de la déclaration manquante

---

## [0.0.8] — 2026-05-21

### Corrections critiques
- **Animation bumped persistante** : les NPCs restaient bloqués en état `bumped` et ne bougeaient qu'avec cette animation. Cause : `ZSWalkToIdle.xml` et `ZSIdleToWalk.xml` supprimés en v0.0.7c → le vanilla PZ reprenait ces XMLs sans condition `PHNPC_IsNPC` → animations zombie jouées sur les NPCs. Suppression des appels `setBumpType("WalkToIdle"/"IdleToWalk")` dans le code Lua (stopMoving/startFollowing/startMovingTo). Suppression de `setTarget(nil)` inconditionnel dans `OnZombieUpdate`. Timeout bumped réduit 40→15 ticks.
- **Inventaire NPC perdu à la mort** : `setHealth(1)` ne tuait **pas** le NPC → aucun corpse PZ créé → items perdus. De plus `md.PHNPC_IsNPC` restait `true` → `OnZombieUpdate` ressuscitait le NPC via `setHealth(10000)`. Correction : `md.PHNPC_IsNPC = nil` AVANT `setHealth(0)` → PZ tue proprement et crée un corpse avec tout l'inventaire.
- **Pas de bulle de dialogue** : `zombie:Say()` ne crée pas de bulle visible sur `IsoZombie` en B42. Remplacement complet par `addLineChatElement(text, r, g, b)` (pattern confirmé dans Bandits). Couleurs : vert (recrutement/soin), rouge (combat/mort), jaune (info/ordres), blanc (idle).

### Nouveaux fichiers AnimSet
- `common/media/AnimSets/zombie/bumped/ZSWalkToIdle.xml` : override vanilla avec `PHNPC_IsNPC=true` → `Bob_EmoteShrug` ultra-rapide (SpeedScale=3.0, EarlyTransitionOut=true, BumpAnimFinished=true au départ) → sortie quasi-instantanée de l'état bumped
- `common/media/AnimSets/zombie/bumped/ZSIdleToWalk.xml` : identique pour `BumpType=IdleToWalk`

### Fichiers modifiés
- **PHNPC_Manager.lua v0.7** : fix bumped, fix deleteNPC (setHealth(0) + PHNPC_IsNPC=nil), fix dialogue (addLineChatElement)
- **PHNPC_Health.lua v0.2** : fix mort NPC (setHealth(0) + PHNPC_IsNPC=nil avant mort)

---

## [0.0.7b] — 2026-05-21

### Corrections critiques
- **Animations réparées** : `setUseless(false)` pour **tous** les NPCs (recrutés ET non-recrutés) — `setUseless(true)` bloquait les AnimSets (PHNPC_IsNPC) et `Say()`, causant animations zombie bras-tendus sur les NPCs libres
- **`Say()` réparé** : découlait du fix animations — `npc:Say()` ne fonctionnait pas avec `setUseless(true)`
- **Loot après mort** : `deleteNPC()` utilise maintenant `setHealth(1)` au lieu de `removeFromWorld()` — le NPC laisse un corpse lootable avec ses items
- **Menu simplifié** : suppression "Afficher l'état" (redondant), "Inventaire" → "Échange d'objets", "Mode combat" déplacé dans `[DEBUG]`

### Ajouts
- **NPC autonome** : comportement idle pour les NPCs non recrutés — patrouille aléatoire toutes les ~300 ticks dans un rayon de 6 tiles + bark idle occasionnel (1/4)
- **PHNPC_Manager.lua v0.6** : boucle `OnTick` séparée pour non-recrutés (`PHNPC_PatrolTick`), sécurisation de l'itération (liste `deadIdle` pour éviter modification pendant `pairs()`)

---

## [0.0.7a] — 2026-05-27

### Ajouts
- **Combat auto NPC vs zombies** : `npcCombatStep()` — détection range=8 tiles, attaque melee (Shove/FrontKick/HighKick), knockDown(true), cooldown 60 ticks
- **Fuite HP<30%** : `npcFlightStep()` — état "fleeing", direction opposée au zombie, replier sur joueur si zone dégagée
- **Dialogue contextuel** : table `PHNPC_BARKS` — 5 états (following/staying/defending/fleeing/idle), bark auto via `BARK_TICK_RATE`, bark immédiat via menu "Parler"
- **Menu clic-droit complet** : "Parler", "Mode combat : AUTO/OFF", sous-menu "[DEBUG]..." (états forcés, HP, animations)
- **PHNPC_Core.lua v0.4** : constantes `COMBAT_RANGE`, `COMBAT_ATTACK_RANGE`, `COMBAT_TICK_RATE`, `FLEE_HP_RATIO`, `FLEE_DISTANCE`, `BARK_TICK_RATE`
- **PHNPC_Manager.lua v0.5** : `npcCombatStep`, `npcFlightStep`, `talkNPC`, `dbgToggleCombat`, callbacks debug complets
- **OnTick** : appels `npcFlightStep` + `npcCombatStep` pour chaque NPC recruté à chaque tick

### Corrections
- Cleanup `_combatTimers` + `_attackCooldowns` dans `deleteNPC` et `OnTick` (NPC mort)
- Cleanup `_combatTimers` + `_attackCooldowns` dans `OnGameStart`
- Menu debug section `[DEBUG]...` uniquement si `isDebugEnabled()` — ne pollue pas le menu prod
- État "defending" ajouté dans condition stayNPC (suit → reste quand en combat)

---

## [0.0.7] — 2026-05-27

### Ajouts
- `setUseless(false)` pour tous les NPCs recrutés (pattern NPC_Helper_Mod) — empêche le freeze en hitreaction
- Inventaire NPC : `openNPCInventory()` + hook `OnRefreshInventoryWindowContainers` (injecte container dans loot panel)

### Corrections
- NPC bloqué après coup (stuck bumped) : `setUseless(false)` pour les recrutés
- Mauvaise animation "push" sur NPC : `ZSZombiePushedBack.xml` + `ZSZombiePushedFront.xml` avec condition `PHNPC_IsNPC=false`

---

## [0.0.5] — 2026-05-21

### Ajouts
- PHNPC_Stats.lua (shared) : initStats() + initInventory() par metier
- PHNPC_Health.lua (client) : systeme sante via Events.OnHitZombie
- Animations Bob_FrontKick.X, Bob_HighKick.x, Bob_PushKick.X (copiees depuis NHM)

### Modifications
- PHNPC_Core.lua : FOLLOW_DISTANCE 3->5, ajout OUTFIT_STATS + MAX_HEALTH + getOutfitStats()
- PHNPC_Manager.lua : setSpeedMod depuis md.PHNPC_SpeedMod (vitesse dynamique), appel initStats/initInventory dans convertToNPC
- PHNPC_Debug.lua : dbgAnim avec setUseless(false)+changeState avant setBumpType, HighKick dans menu, HP dans ShowState

### Corrections
- FrontKick ne jouait pas : Bob_FrontKick.X absent de vanilla B42 (copie depuis NHM)
- NPC trop collant : FOLLOW_DISTANCE 3->5
- HP NPC ne diminuait pas : hook OnHitZombie manquant

---

## [0.0.4] — 2026-05-26

### Ajouts
- Sons de pas via ZSWalk.xml events
- VoicePrefix genre-based (homme/femme differencies)
- ZSNPCPushedBack.xml (BumpType=ZombiePushedBack)

### Corrections
- stopMoving : setTarget(nil) + clearAggroList pour vraiment stopper
- ForceHitReaction crash fixe

---

## [0.0.3] — 2026-05-21

### Corrections
- Signatures callbacks (_, player) -> (player)
- setVariable(zombieWalkType) supprime (read-only B42)
- setFemaleEtc() ajoute dans convertToNPC + enforceNPC

---

## [0.0.2] — 2026-05-21

### Ajouts
- Menu DEBUG_PHNPC complet (animations, etat, spawn debug)
- Suppression NPC via menu
