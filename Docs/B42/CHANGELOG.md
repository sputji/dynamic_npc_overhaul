# CHANGELOG B42 — Dynamic NPC Overhaul

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
