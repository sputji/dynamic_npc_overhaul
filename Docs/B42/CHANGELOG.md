# CHANGELOG B42 — Dynamic NPC Overhaul

## [0.0.17] — Stabilisation runtime B42 + suivi/combat/XP/outfits (2026-05-30)

### Correctifs critiques

- `PHNPC_Core.lua`
  - ajout de helpers `PHNPC.hasMethod(obj, methodName)` et `PHNPC.tryCall(obj, methodName, ...)` pour eviter les appels Java non exposes en B42.
  - tuning suivi: `FOLLOW_MOVE_THRESHOLD=2.5`, `FOLLOW_REPATH_TICKS=45` pour limiter le repath spam.
- `PHNPC_Actions.lua`
  - `startFollowing` ne relance plus un path immediatement apres une transition idle courte.
  - anti-saccade: le re-path est conditionne par `FOLLOW_REPATH_TICKS` meme si `PHNPC_Moving=false` temporairement.
- `PHNPC_Update.lua`
  - cadence de follow maitrisee (`PHNPC_FollowTick`) avec declenchement immediat seulement si distance tres grande.
  - garde-fou explicite avant appels `sayWeatherBark` et `npcCombatStep`.
- `PHNPC_Barks.lua`
  - detection meteo migree vers `ClimateManager.getInstance()` (fallback `GameTime`) pour compat B42.
  - suppression des appels meteo fragiles non disponibles selon contexte.
- `PHNPC_Combat.lua`
  - selection d'arme contextuelle : priorite ranged a distance si munitions + skill.
  - ajout `consumeAmmoForWeapon` avec fallback d'API inventaire (`Remove` / `RemoveOneOf`).
  - ajout gain XP en combat (`Aiming`, `Blunt`, `Strength`, `Fitness`, `Maintenance`).
  - hardening des degats via verif d'existence methodes (`setHealth`, `knockDown`, `setPrimaryHandItem`).
- `PHNPC_Stats.lua`
  - `getSkillSummary(npc)` affiche maintenant les 13 competences meme a 0 (conforme checklist debug).
- `PHNPC_Outfits.lua` + `PHNPC_Debug.lua`
  - nouveau `getOutfitDefenseSummary(npc)` expose les scores defensifs par slot.
  - affichage du resume dans debug (`OutfitDef`).

### Version

- `B42/42/mod.info` -> `version=0.0.17`.
- Banners modules principaux alignes sur `v0.0.17 loaded`.

## [0.0.16] — Refactoring modulaire : IA armes a feu, progression XP, vetements auto, barks meteo (2026-05-30)

### Nouveaux modules

- `PHNPC_Main.lua` *(client)* — point d'entree central v0.0.16 : verifie la sante de tous les modules au chargement, coordonne les hooks `OnGameStart` et `OnConnected`, expose `PHNPC.VERSION = "0.0.16"`.
- `PHNPC_Pathfinding.lua` *(client)* — pathfinding nouvelle generation :
  - utilise `pathToLocationF` natif (NavigatorGrid PZ) pour gerer automatiquement portes, fenetres et clotures.
  - cooldown `PATH_MIN_TICKS = 15` pour eviter les micro-freezes lies au recalcul par seconde.
  - `schedulePathTo(npc, x, y, z)` : remplace les appels directs a `pathToLocationF`.
  - `checkNearbyDoor(npc, tx, ty)` : detecte une porte dans le rayon `DOOR_SEARCH_RADIUS = 4` et l'ouvre avant de pather.
  - `findFreeSquareNear`, `findEscapeDirection`, `findClearAreaNear` ameliores.
- `PHNPC_Outfits.lua` *(client)* — selection de vetements extraite de `PHNPC_Inventory.lua` :
  - `scoreClothing(item)` : calcule le score defensif/confort d'un vetement.
  - `getCurrentWorn(npc, bodyLocation)` : retourne le vetement porte sur un slot donne.
  - `setWornItem(npc, bodyLocation, item)` : equipe un vetement avec fallback API B42.
  - `autoEquipBestOutfit(npc)` : remplace les tenues de score inferieur, compatible `autoEquipFromInventory`.

### Armes a feu (PHNPC_Combat.lua v0.0.16)

- `hasAmmoForWeapon(npc, weapon)` : verifie la presence d'une munition correspondante (`weapon:getAmmoType()`) dans l'inventaire du NPC.
- `scoreWeapon(npc, item)` : les armes a distance recoivent un bonus de +20 si le NPC a les munitions adaptees ET le niveau de competence `Aiming >= RANGED_MIN_SKILL` (1 par defaut).
- Bloc d'attaque a distance ajoute : le NPC tire jusqu'a `PHNPC.RANGED_ATTACK_RANGE = 10` tuiles avec un cooldown `RANGED_COOLDOWN = 120` ticks entre deux tirs.
- Constante `PHNPC.RANGED_ATTACK_RANGE = 10` ajoutee dans `PHNPC_Core.lua`.

### Progression XP / competences (PHNPC_Stats.lua v0.0.16)

- Table `OUTFIT_SKILLS` : 40+ tenues de spawn × 13 competences (Strength, Fitness, Aiming, Nimble, Sneaking, Axe, Blunt, SmallBlade, Maintenance, Doctor, Cooking, Carpentry, Farming).
- `initSkills(npc)` : initialise les niveaux de base depuis `OUTFIT_SKILLS` et les stocke en `ModData`.
- `getNPCSkillLevel(npc, skillName)` : retourne le niveau courant d'une competence.
- `addNPCXP(npc, skillName, amount)` : ajoute de l'XP, fait monter le niveau selon la formule `xpForLevel(n) = XP_BASE * (n+1)^XP_EXPONENT` (`XP_BASE=150`, `XP_EXPONENT=1.5`, `MAX_LEVEL=10`), declenche un bark `levelup` si niveau augmente.
- `getSkillSummary(npc)` : retourne une chaine resumant les niveaux actuels pour le debug.
- `initStats()` appelle desormais `initSkills()` automatiquement.

### Barks meteo (PHNPC_Barks.lua v0.0.16)

- `getWeatherState()` : detecte la meteo via `GameTime.getInstance()` (pluie, orage, neige, canicule, brouillard).
- `sayWeatherBark(npc)` : fait dire au NPC un bark adapte a la meteo courante.
- Nouvelles cles `BARK_KEYS` : `weather_rain`, `weather_storm`, `weather_snow`, `weather_hot`, `weather_fog`, `levelup`.
- Garde-fou `getText()` : appel lazisse pour eviter le retour de la cle brute au chargement de fichier.

### Inventaire (PHNPC_Inventory.lua v0.0.16)

- `autoEquipFromInventory` delegue desormais a `PHNPC_Outfits.autoEquipBestOutfit` (suppression de la logique dupliquee).
- Hook `onItemGiven(npc, item)` : appelle `autoEquipBestOutfit` immediatement si l'objet donne est un vetement.

### Traductions

- `UI_PHNPC_EN.txt` : 14 nouvelles cles (BarkRain1-3, BarkStorm1-3, BarkSnow1-3, BarkHot1-2, BarkFog1-2, BarkLevelUp1-2).
- `UI_PHNPC_FR.txt` : memes 14 cles en francais.

### Version

- `B42/42/mod.info` -> `version=0.0.16`.
- `PHNPC_Manager.lua` reference les nouveaux modules (Main, Pathfinding, Outfits).
- Banners modules alignes sur `v0.0.16 loaded`.

---

## [0.0.15] — Stabilisation finale follow/ordres/clotures + inventaire/loot (2026-05-28)

### Correctifs gameplay

- `PHNPC_Actions.lua`
  - reduction des micro-saccades follow : hold anti yo-yo autour du stop distance + cadence min de re-path (`FOLLOW_REPATH_TICKS`).
  - stop follow plus stable a proximite immediate du joueur.
- `PHNPC_Enforce.lua`
  - mitigation `ClimbOverFenceState` assouplie : reset uniquement si l'etat reste bloque, sans casser un franchissement valide.
- `PHNPC_Orders.lua` + `PHNPC_Update.lua` + `PHNPC_Combat.lua`
  - verrou explicite `PHNPC_OrderLock` active sur `goingto/shelter` pour empecher les retours parasites vers `following`.
  - combat/fuite n'interrompent plus ces ordres verrouilles.
  - shelter force `staying` des que le NPC est dans un batiment (pas d'aller-retour vers le joueur).

### Correctifs inventaire / mort

- `PHNPC_Inventory.lua`
  - detection vetements via `instanceof(item, "Clothing")` + fallback `IsClothing`.
  - equipement vetements via API classique et fallback `getWornItems():setItem(...)`.
- `PHNPC_Health.lua` + `PHNPC_Loot.lua`
  - conservation du contexte NPC jusqu'au snapshot (`PHNPC_DeadPendingLoot`).
  - transfert cadavre avec fallback `AddItem(fullType)` si l'objet brut est refuse par le container.

### Version

- `B42/42/mod.info` -> `version=0.0.15`.
- Banners modules alignes sur `v0.0.15 loaded`.

## [0.0.14] — Stabilisation follow/ordres + fix auto-equip/loot (2026-05-28)

### Correctifs gameplay

- `PHNPC_Actions.lua` : stabilisation follow pour supprimer le re-path quasi permanent (source des micro-saccades).
  - ajout d'une fenetre anti yo-yo (`PHNPC_FollowHoldTicks`) autour de la distance d'arret.
  - re-path follow seulement si le joueur a vraiment bouge (ou stuck detecte), plus sur derive d'ancre continue.
- `PHNPC_Orders.lua` + `PHNPC_Update.lua` + `PHNPC_Combat.lua` : ajout d'un verrou d'ordre (`PHNPC_OrderLock`) pour garantir la continuite de `Va la-bas` et `Mets-toi a l'abri`.
  - empeche le retour parasite vers `following` tant que l'ordre explicite n'est pas termine.
  - combat/fuite ne cassent plus ces ordres verrouilles.
- `PHNPC_Enforce.lua` : mitigation fence rendue non bloquante.
  - on laisse le franchissement normal des clotures.
  - reset defensif seulement si `ClimbOverFenceState` reste bloque trop longtemps.

### Correctifs inventaire / mort

- `PHNPC_Inventory.lua` : auto-equip vetements rendu robuste API B42.
  - detection vetements via `instanceof(item, "Clothing")` (fallback `IsClothing`).
  - lecture/ecriture worn items avec fallback `getWornItems():getItem/setItem`.
- `PHNPC_Health.lua` + `PHNPC_Loot.lua` : correction perte d'objets donnes au NPC a la mort.
  - le marker NPC est conserve jusqu'au snapshot loot (`PHNPC_DeadPendingLoot`).
  - `OnZombieDead`/`OnZombieUpdate` traitent aussi ce marker pending.
  - transfert vers cadavre avec fallback `AddItem(fullType)` si transfert objet brut refuse.

### Validation de log

- Banners modules alignes sur `v0.0.14` pour eviter les faux diagnostics de version en test.
- Sources officielles re-verifiees : Lua API / JavaDocs / Category:Modding / Build status.

### Version

- `B42/42/mod.info` -> `version=0.0.14`.

## [0.0.13b] — Mitigation ClimbOverFenceState + auto-equip vetements best stats (2026-05-28)

### Correctifs code

- Mitigation agressive `ClimbOverFenceState`:
  - `PHNPC_Enforce.lua` intercepte `getCurrentState():find("ClimbOverFenceState")`.
  - reset immediate vers idle, purge path courant, cooldown recovery (`PHNPC_FenceRecoverTicks`).
  - objectif: casser la boucle d'entree d'etat qui provoquait des erreurs rouges `BodyDamage nil`.
- `PHNPC_Actions.lua`:
  - pendant recovery fence, redirection locale vers case libre proche avant reprise de la destination d'ordre.
  - reduction des retentatives de franchissement de cloture.
- `PHNPC_Inventory.lua`:
  - auto-equipement vetements upgrade: selection du meilleur item par slot (BodyLocation) selon score defensif.
  - remplace un vetement porte si un meilleur existe dans l'inventaire NPC.

### Score vetements (auto-equip)

- Priorites: `bulletDefense` > `biteDefense` > `scratchDefense` + etat (condition ratio) + leger bonus isolation.
- Comparaison slot par slot; remplacement seulement si le score du candidat est superieur au vetement actuellement porte.

### Version

- `B42/42/mod.info` -> `version=0.0.13b`.

## [0.0.13] — Stabilisation post-retour test v0.0.12 (2026-05-28)

### Correctifs gameplay

- Suivi joueur refondu dans `PHNPC_Actions.lua` : abandon de `pathToCharacter` en continu, suivi par point d'ancrage autour du joueur (`pathToLocationF`) pour tenir la distance de confort et reduire le collage.
- Distance d'arret follow retournee a 2 tuiles (`PHNPC.FOLLOW_STOP_DISTANCE=2`) pour coller a la checklist en jeu.
- `PHNPC_Enforce.lua` durci contre les interruptions de path : les etats transitoires `lunge/attack/eatBody` ne cassent plus le deplacement quand l'ordre actif est `following/goingto/shelter/fleeing`.
- Seuil idle pendant deplacement d'ordre explicite augmente a 120 ticks avant `stopMoving`, pour limiter les re-paths parasites.

### Correctifs combat / inventaire / loot

- Selection arme melee amelioree : comparaison de l'arme deja equipee avec tout l'inventaire, equipement de la meilleure arme disponible.
- Auto-equipement des vetements depuis l'inventaire NPC ajoute (`PHNPC.autoEquipFromInventory`), appele periodiquement dans `PHNPC_Update.lua`.
- Loot mort NPC corrige : les items en main (primary/secondary) sont maintenant inclus dans le snapshot et dedupliques avant transfert au cadavre.
- Correction data spawn metier `Chef` : `Base.CanOpener` remplace par `Base.TinOpener` (erreur AddItem console supprimee).

### Version

- `B42/42/mod.info` -> `version=0.0.13`.

### Notes

- Les erreurs de type `ClimbOverFenceState ... getBodyDamage() is null` restent surveillees: mitigation appliquee cote IA (moins d'entrees d'etat parasites), mais ce point doit etre valide en retest intensif ordres `Va la-bas`/`Abri` sur zones avec clotures.

## [0.0.12] — Correctifs post-test v0.0.11 (2026-05-28)

### Résultat test joueur v0.0.11

- Recrutement/suivi : **KO** (marche au lieu de course, colle joueur)
- Va là-bas : **KO** (direction aléatoire, n'arrive pas proprement)
- Reste ici : **KO** (retourne vers le joueur)
- Shelter : **KO** (aller-retour, pas de fermeture porte)
- Combat arme : **KO** (n'équipe pas correctement)
- Console : **KO** (erreurs mod)

### Causes confirmées

1. `console.txt` montre des exceptions répétées `scoreWeapon/getNPCWeapon` ([PHNPC_Combat.lua](B42/42/media/lua/client/PHNPC_Combat.lua#L31)).
2. `staying` utilisait `if md.PHNPC_NoPatrol then return end` dans [PHNPC_Update.lua](B42/42/media/lua/client/PHNPC_Update.lua), ce qui quittait tout le callback `OnTick`.
3. `startMovingTo` pouvait re-émettre des paths trop souvent dans certains cas d'état transitoire.
4. `following` reposait encore sur un timer global peu réactif pour la bascule course/marche.

### Correctifs appliqués en v0.0.12

- **`PHNPC_Combat.lua`**
  - `scoreWeapon` durci : `instanceof(item, "HandWeapon")` + filtre `isRanged` + garde-fous `getMaxDamage/getMinDamage`.
  - Suppression de la dépendance critique à `item:isWeapon()`.
- **`PHNPC_Update.lua`**
  - `following` simplifié : appel `startFollowing(...)` à chaque tick, `wt` dynamique selon distance.
  - `staying` : suppression du `return` global quand `NoPatrol` est actif.
- **`PHNPC_Actions.lua`**
  - `startMovingTo` en path-once strict : nouveau path seulement si destination réellement différente (>2 tuiles) ou NPC à l'arrêt.
  - plus de re-fire inutile sur destination identique.
- **`PHNPC_Orders.lua`**
  - `attackOrderNPC` reset `md.PHNPC_NoPatrol = nil`.
- **`mod.info`**
  - version montée à `0.0.12`.

### Validation API officielle (sources)

- [Lua (API)](https://pzwiki.net/wiki/Lua_(API))
- [JavaDocs index](https://demiurgequantified.github.io/ProjectZomboidJavaDocs/index.html)
- [Category:Modding](https://pzwiki.net/wiki/Category:Modding)
- [Build status](https://projectzomboid.com/blog/news/2017/02/buildstatus/)

## [0.0.11] — REFONTE ARCHITECTURALE "path-once" (2026-05-28)

> **Tests v0.0.10 echoues à 4/5** : malgre les 5 fixes P0, les saccades, le porte-ping-pong, l'arrivée "Va là-bas" aléatoire et le shelter en boucle ont persisté. Analyse du `console.txt` v0.0.10 a montre :
>
> - `[Actions] -> Run follow offset (X,Y)` avec X,Y **différents** chaque ligne toutes ~40 ticks → l'offset `tx = px - nx * stopDist` est recalcule depuis la position **courante** du NPC, donc change a chaque tick = re-path infini = saccades.
> - `[Actions] -> Run pathToLocationF(10891.5,9477.5)` avec **mêmes coords** spammees toutes les 8 ticks → `PATH_COOLDOWN=8` fait retomber `needNewPath`, donc `pathToLocationF` re-tire le même point sans cesse.
> - **18 blocs ERROR** au moment du shelter → fermeture/ouverture/fermeture portes (ping-pong entre `stopMoving.closeNearbyDoors` et `OnTick.checkAndOpenDoors` à chaque tick).

### Architecture v0.0.11 — pattern **path-once** (référence : Bandits 42.18 `ZAGoTo.lua` + NPC_Helper_Mod `GCCoreActions.lua`)

| Aspect | v0.0.10 (cassé) | v0.0.11 (corrigé) |
|--------|-----------------|-------------------|
| Suivi joueur | `pathToLocationF(tx,ty)` avec offset recalculé chaque tick | `pathToCharacter(player)` UNE FOIS, le moteur Java trace dynamiquement |
| Re-path follow | Toutes les ~40 ticks dès que cooldown expire | Seulement si player a bougé ≥ 5 tuiles depuis dernier path |
| Re-path goingto | Idem, spam 8 ticks même destination identique | Anchor `md.PHNPC_PathX/Y` ; re-path uniquement si nouvelle destination > 2 tuiles |
| Portes/fenêtres | `checkAndOpenDoors` + `checkAndOpenWindows` à **chaque tick** dans OnTick | Appelés UNIQUEMENT au lancement d'un path (dans `startFollowing`/`startMovingTo`) |
| `stopMoving` | Fermait portes/fenêtres → tick suivant `checkAndOpenDoors` les réouvre → ping-pong | Ne ferme plus rien. Nouvelle fonction `PHNPC.closeBehindNPC(npc)` appelée explicitement à la transition `staying` (arrivée goingto/shelter) |
| Arrivée goingto | `state="staying"` → patrouille immédiate → NPC repart direction aléatoire | Set `md.PHNPC_NoPatrol=true` ; `staying` saute la patrouille si flag présent |
| Enforce idle stop | 15 ticks (~0.5s) → coupait l'anim toutes les secondes | 60 ticks (~2s) → tolère les transitions pathfind |
| `getNPCWeapon` | Sequence `tryGet("Base.Bat") → tryGet("Base.Axe")` ; **premier match** | Scan complet inventaire + score `dmg*10 + condRatio` → meilleure arme |

### Fixes specifiques v0.0.11

- **`PHNPC_Actions.lua`** : `startFollowing` réécrite (pathToCharacter + anchor player); `startMovingTo` réécrite (anchor destination + needPath si > 2 tuiles); `stopMoving` ne ferme plus de portes/fenêtres; nouvelle fonction `PHNPC.closeBehindNPC(npc)`.
- **`PHNPC_Update.lua`** : suppression des `checkAndOpenDoors`/`Windows` à chaque tick (OnTick); arrivée goingto set `NoPatrol=true` + `closeBehindNPC`; arrivée shelter idem; `staying` skip patrouille si `NoPatrol`.
- **`PHNPC_Enforce.lua`** : seuil idle 15 → 60.
- **`PHNPC_Combat.lua`** : `getNPCWeapon` refondu avec ranking (scan complet, `item:isWeapon()` + filtre `isRanged`, score `maxDamage*10 + condRatio`).
- **`PHNPC_Orders.lua`** : tous les handlers (`recruit`, `follow`, `stay`, `attack`, `shelter`, `free`, `goingto`) reset `md.PHNPC_NoPatrol = nil` pour que les nouveaux ordres réengagent le comportement normal.

---

## [0.0.10] — 5 fixes P0 (regressed in test) (2026-05-27)

## [0.0.9p] — RÉSULTATS DE TEST (2026-05-27)

### Tests joueur réalisés (sandbox Apocalypse, langue FR, build 42.18.0)

Référence complète : [Docs/B42/Checklist de test en jeux.md](Docs/B42/Checklist%20de%20test%20en%20jeux.md).

| Catégorie | ✅ | ⚠️ | ❌ | Statut |
|---|---|---|---|---|
| 1. Chargement mod | 3 | 0 | 0 | OK (console.txt propre, bannière `Enforce v0.0.9p loaded`) |
| 2. Spawn NPC | 4 | 1 | 0 | OK sauf **animation idle = posture zombie persistante** |
| 3. Recrutement + suivi | 2 | 0 | 3 | **CASSÉ** — NPC ne court pas, colle le joueur, saccades sur re-path |
| 4. Ordres de déplacement | 2 | 1 | 3 | **CASSÉ** — Va là-bas allez-retour, shelter aléatoire, casse fenêtre |
| 5. Combat NPC | 1 | 3 | 2 | **CASSÉ** — armes non équipées, pas de `faceLocationF` effectif |
| 6. Fuite blessé | 1 | 2 | 0 | Tourne en boucle autour du joueur au lieu de fuir |
| 7. Mort + loot | 2 | 3 | 0 | **Items restent dans inventaire NPC**, pas transférés vers cadavre |
| 8. Portes/fenêtres | 3 | 1 | 0 | OK mais NPC casse fenêtre si porte ouverte à côté + 0 anim humain |
| 9. Danger module | 0 | 2 | 0 | **Zombies ignorent totalement le NPC** (Danger inopérant) |
| 10. Stabilité | 1 | 2 | 0 | FPS OK avec 5-15 NPCs |
| 11. Knockdown | 1 | 1 | 0 | T-pose résolue |
| 12. Inventaire | 1 | 1 | 1 | Transfert OK, armes/vêtements non utilisés |
| 13. Divers | 3 | 1 | 0 | Aucune erreur ROUGE console |

**Bilan global** : la base technique est saine (chargement, structure, anti-crash). Le **comportement gameplay reste défaillant** sur ~60 % des points clés. La cause récurrente est un **conflit entre états comportementaux et conditions de re-path** dans `PHNPC_Update.lua`/`PHNPC_Actions.lua`.

### Causes racines confirmées (audit code post-test)

1. **NPC ne court pas en suivi** — [PHNPC_Actions.lua:168](B42/42/media/lua/client/PHNPC_Actions.lua) dans la branche `else` de `startFollowing` (déjà en mouvement) : `applyMoveTick(npc, md.PHNPC_WalkType or walkType)`. Si `md.PHNPC_WalkType` est déjà "Walk" du premier path, le nouveau `walkType="Run"` est **ignoré**. Fix v0.0.10 : `applyMoveTick(npc, walkType or md.PHNPC_WalkType)` + reset explicite `md.PHNPC_WalkType = walkType` quand `walkType` est fourni.
2. **Armes non équipées en combat** — [PHNPC_Combat.lua:131](B42/42/media/lua/client/PHNPC_Combat.lua) appelle `npc:setEquippedItem(weapon)`. Cette méthode **n'existe pas** sur `IsoZombie` en B42.18 (vérifié JavaDoc). La bonne méthode est `setPrimaryHandItem(item)` (déjà utilisée correctement avec `nil` dans Convert.lua:47 et Loot.lua:105). Le `pcall` masque l'erreur silencieusement.
3. **NPC colle le joueur (pas de stop à 2 tuiles)** — Hypothèse : `pathToCharacter(player)` recalcule en continu vers la position exacte du joueur, sans honorer `FOLLOW_STOP_DISTANCE`. `stopMoving` est bien appelé quand `dist <= 2` mais le pathfind moteur a déjà mis le NPC sur le tile du joueur avant. Fix v0.0.10 : utiliser `pathToLocationF(px + offset, py + offset)` avec offset radial 2-3 tuiles depuis l'angle joueur→NPC.
4. **« Va là-bas » allez-retour** — Le NPC va vers la cible, croise un zombie, `npcCombatStep` met en `defending` (interrompt le path), puis le combat se résout, retour en état précédent mais `md.PHNPC_GoToX/Y` est encore set. Mais entre-temps, le handler `following` peut s'être déclenché si état réinitialisé vers "following". Cause racine probable : `md.PHNPC_PrevState` est mal restauré dans `npcCombatStep` quand on quitte `defending`.
5. **Shelter va aléatoirement** — `PHNPC.pickShelterPoint(npc)` retourne `nil` car `findSafeRoomSquare` ne trouve aucune room dans le bâtiment scanné (boucle 8 tentatives `getRandomRoom()` qui échoue). Le fallback `findClearAreaNear` puis le fallback aléatoire (`math.cos(ang) * 10`) prennent la main → NPC va dans une direction random. Fix v0.0.10 : améliorer le scan de bâtiments via `getCell():getRoomList()` + filtrer rooms inside.
6. **Combat ne tourne pas vers cible** — `faceLocationF` est bien appelé (Combat.lua:124) mais `enforceNPC` step 10 réapplique `setRunning` chaque tick ce qui peut neutraliser le facing. À investiguer si `setBumpType("HitLeft")` triggers une transition d'état qui annule le facing.
7. **Animation idle = posture zombie** — Les overrides XML dans `B42/common/media/AnimSets/zombie/` doivent activer le variant humain via la variable `PHNPC_IsNPC=true`. L'enforce.lua step 10 la réapplique, mais visiblement l'AnimSet XML ne déclenche pas le bon variant. À auditer : `common/media/AnimSets/zombie/idle/*.xml` et `common/media/anims_X/Zombie/...`.
8. **Zombies ignorent le NPC** — `PHNPC_Danger.lua` fait `obj:setTarget(npc) + obj:setAttackedBy(npc)` sur les zombies dans le rayon. Soit la fonction n'est pas appelée (timer trop long ?), soit le moteur ignore `setTarget(IsoZombie marked PHNPC_IsNPC)`. À auditer : `npcDangerStep` + cadence d'appel dans Update.lua.
9. **Loot pas dans le cadavre** — `OnDeadBodySpawn` peut ne pas firer en B42.18 (rename event vanilla ?), ou le matching de proximité dans `_pendingLoot` échoue. Le fallback drop au sol n'est pas non plus visible selon le joueur (items restent dans le NPC). À auditer : confirmer que `OnZombieDead` fire, vérifier que `snapshotNPCLoot` retire bien les items de `inv:Remove(it)`.
10. **Vêtements donnés non portés** — Aucune fonction n'écoute `OnReceiveItem` ou `OnInventoryChanged` côté NPC pour auto-équiper. C'est une feature manquante, pas un bug.

### Conclusion v0.0.9p

L'audit API était nécessaire mais a **masqué une zone grise** : `setEquippedItem` n'existe pas et le pcall a caché l'erreur en silence depuis v0.0.7a. Le grep manuel a permis de confirmer. La passe v0.0.10 doit cibler ces 10 causes racines **dans cet ordre de priorité gameplay** (cf. [feuille de route.md](feuille%20de%20route.md)).

### Fichiers touchés v0.0.9p

- Aucune modif de code Lua (audit + hardening pcall seulement, cf. entrée précédente).
- [Docs/B42/CHANGELOG.md](CHANGELOG.md)
- [Docs/B42/feuille de route.md](feuille%20de%20route.md)
- [Docs/B42/GUIDE_CREATION.md](GUIDE_CREATION.md)
- [Docs/B42/ARCHITECTURE.md](ARCHITECTURE.md)
- [Docs/B42/Checklist de test en jeux.md](Checklist%20de%20test%20en%20jeux.md) — résultats annotés par le joueur

---

## [0.0.9p] — 2026-05-27

### Passe d'audit API B42.18 + hardening defensif (avant tests joueur)

Avant la session de tests en jeu post-v0.0.9o, audit complet de toutes les API utilisees contre les sources officielles :

- **JavaDoc B42.18** : https://demiurgequantified.github.io/ProjectZomboidJavaDocs/
- **PZ Wiki Lua API** : https://pzwiki.net/wiki/Lua_(API)
- **PZ Wiki Modding** : https://pzwiki.net/wiki/Category:Modding
- **Build status TIS** : https://projectzomboid.com/blog/news/2017/02/buildstatus/
- **Patterns reference** : `mod example/B42/Bandits/42.18/`, `mod example/B42/BanditsWeekOne/42.18/`, `mod example/B42/NPC_Helper_Mod/`

**Verifications effectuees** :
- Toutes les methodes IsoZombie / IsoGameCharacter / IsoMovingObject / IsoObject utilisees existent en B42.18 (rev `9d7e334cab5e2ac8c6f2664535c6b23a745a8600`, build 2026-05-11).
- `setHealth`, `knockDown`, `setBumpType`, `setWalkType`, `setRunning`, `setVariable`, `clearVariable`, `pathToLocationF`, `pathToCharacter`, `faceLocationF`, `setTarget(IsoMovingObject)`, `setAttackedBy(IsoGameCharacter)`, `clearAggroList`, `addAggro`, `getWornItems`, `getInventory`, `getPrimaryHandItem`, `getCurrentBuilding`, `playSound`, `dressInRandomOutfit`, `getActionStateName`, `changeState`, `setUseless`, `setNoTeeth`, `setSpeedMod`, `setFemaleEtc`, `setAnimatingBackwards`, `setEatBodyTarget`, `resetModel`, `resetModelNextFrame`, `setOnFloor`, `setKnockedDown`, `setBecomeCrawler`, `setCrawler`, `setCanWalk`, `setSprinting`, `getDescriptor`, `getEmitter`, `getCurrentState`, `setVoicePrefix`, `stopSoundByName`, `addLineChatElement`, `getModData`, `getCell`, `setDrag`, `ToggleDoorSilent`, `AddWorldInventoryItem` : **TOUTES CONFIRMEES**.
- `console.txt` post-v0.0.9o : aucune erreur de mod (uniquement warnings vanilla `Build_AnvilStone`, `CorpseDrop`, `corpseStorageCheck` qui sont des bugs PZ stock).

### Corrections appliquees

**`PHNPC_Enforce.lua` v0.0.9p** : hardening pcall sur les derniers appels Java bare-natifs qui pouvaient theoriquement remonter une exception si le moteur change leur signature en future patch :
- `zombie:setHealth(10000)` → `pcall(function() zombie:setHealth(10000) end)` (tank-mode)
- `zombie:setTarget(nil)` (turnalerted) → wrappe en pcall
- `zombie:setTarget(nil)` (lunge fallback) → wrappe en pcall
- `zombie:setTarget(nil)` (attack/eatBody) → wrappe en pcall
- `zombie:setTarget(nil)` (securite step 6) → wrappe en pcall
- `zombie:setUseless(true/false)` (step 7) → wrappe en pcall
- `zombie:changeState(ZombieIdleState.instance())` (turnalerted/lunge/attack) → wrappe en pcall

**Effet** : meme si une future evolution de l'API B42 modifie la signature ou rend une de ces methodes nullable, le tick NPC continue de tourner sans interrompre le for-loop `OnTick` (le bug qui a cause les saccades en v0.0.9n).

### Fichiers touches

- [B42/42/mod.info](B42/42/mod.info) : `version=0.0.9p`
- [B42/42/media/lua/client/PHNPC_Enforce.lua](B42/42/media/lua/client/PHNPC_Enforce.lua) : 7 wraps pcall, banner `Enforce v0.0.9p loaded`
- [Docs/B42/CHANGELOG.md](Docs/B42/CHANGELOG.md)
- [Docs/B42/ARCHITECTURE.md](Docs/B42/ARCHITECTURE.md)
- [Docs/B42/feuille de route.md](Docs/B42/feuille%20de%20route.md)
- [Docs/B42/GUIDE_CREATION.md](Docs/B42/GUIDE_CREATION.md)

### Action joueur

Lancer la checklist de tests fournie a la fin de la conversation (12 categories, depuis le menu sandbox).

---

## [0.0.9o] — 2026-05-27

### Cause racine identifiee dans `console.txt` : `ToggleDoor(npc)` plantait en boucle

Le joueur signalait apres v0.0.9n : « les NPC font n'importe quoi, saccades, trop d'erreurs, rien ne fonctionne ». Analyse de `C:\Users\Nicolas\Zomboid\console.txt` :

```
Caused by: java.lang.NullPointerException:
  Cannot invoke "zombie.characters.IsoPlayer.isLocalPlayer()" because "player" is null
  at PHNPC_Actions.lua:258  (closeNearbyDoors -> obj:ToggleDoor(npc))
  via stopMoving (line 228) <- npcCombatStep (PHNPC_Combat.lua:106)
```

**Diagnostic** : `IsoDoor.ToggleDoor(IsoGameCharacter)` et `IsoThumpable.ToggleDoor(IsoGameCharacter)` cast en interne le character en `IsoPlayer` pour `isLocalPlayer()`. Le NPC du mod est un `IsoZombie` (pas un `IsoPlayer`) -> NPE non-rattrape qui :
- interrompt le for-loop `for npc in pairs(PHNPC.recruited)` -> les NPCs suivants ne recoivent **plus de ticks** ce frame -> saccades visuelles + ordres ignores
- spamme 18 stack traces par seconde -> log pollue + impression de « tout crash »

Pattern verifie chez Bandits B42.18 (`BanditUpdate.lua:823`, `BanditServerCommands.lua:172/178/184`) : **`object:ToggleDoorSilent()` sans argument**.

### Corrections principales

**`PHNPC_Actions.lua` v0.0.9o** :
- `closeNearbyDoors` : `obj:ToggleDoor(npc)` -> `obj:ToggleDoorSilent()` (IsoDoor)
- `closeNearbyDoors` : meme correction pour `IsoThumpable`
- `checkAndOpenDoors` : `obj:ToggleDoor(npc)` -> `obj:ToggleDoorSilent()`
- `startMovingTo` / `startFollowing` : `setBumpType` (via `applyMoveStart`) appele **uniquement** quand `md.PHNPC_Moving == false` (premier path). Si NPC deja en mouvement, on appelle `applyMoveTick` (idempotent : pas de `setBumpType`/`faceLocationF`) puis `pathToLocationF(tx, ty, tz)` met simplement a jour la destination. Le moteur enchaine sans interrompre l'anim -> **plus de saccades** quand le joueur bouge pendant le suivi.
- Bannieres mises a jour : `Actions v0.0.9o loaded`.

### Verification

- `Get-Content console.txt | grep PHNPC -> ToggleDoor` : 36 occurrences en v0.0.9n -> 0 attendues en v0.0.9o.
- `pathToLocationF` log conserve mais `setBumpType` ne se redeclenche plus chaque cooldown (8 ticks).

### Fichiers touches

- [B42/42/media/lua/client/PHNPC_Actions.lua](B42/42/media/lua/client/PHNPC_Actions.lua)
- [Docs/B42/CHANGELOG.md](Docs/B42/CHANGELOG.md)
- [Docs/B42/feuille de route.md](Docs/B42/feuille%20de%20route.md)

### Action joueur

1. Redemarrer le jeu (pas seulement reload mod) pour purger le KahluaThread.
2. Recruter un NPC et le faire stopper pres d'une porte ouverte : aucune erreur dans `console.txt`.
3. Suivre le joueur en courant : aucune saccade.

---

## [0.0.9n] — 2026-05-27

### Correctifs post-v0.0.9m (re-crash + loot mal place)

Apres v0.0.9m le joueur signale **encore** : crash en boucle `Object tried to call nil in findSafeRoomSquare`, le NPC ne va pas a l'endroit demande, n'attaque pas les zombies, les items ne sont pas visibles dans le cadavre.

Diagnostic : ma supposition v0.0.9m que `IsoBuilding:getRoom(int)` existait etait **fausse**. Extraction `.class` confirme : seuls `getRoom()` (sans arg), `getRoomByID(long)`, `getRandomRoom()` existent — pas de `getRoom(int)`. Mon code v0.0.9m crashait donc en boucle, ce qui empechait par cascade le combat et les ordres "Va la-bas" de s'executer (le crash dans le for-loop tuait l'iteration sur tous les NPCs suivants).

### Corrections principales

- **`PHNPC_Building.lua` v0.0.9n — defense totale (zero crash possible)**
  - Reecriture ULTRA-DEFENSIVE : tous les appels Java sont en `pcall`.
  - `findSafeRoomSquare` n'utilise plus `getRoom(int)`. Strategie : `building:getRandomRoom()` jusqu'a 8 tentatives, fallback `building:getDef():getRooms()` (ArrayList<RoomDef>) puis `roomDef:getIsoRoom():getRandomFreeSquare()`.
  - Si tout echoue, retour `nil` sans crash : le NPC reste en `shelter` et `Update.lua` finit par le passer en idle.

- **`PHNPC_Loot.lua` v0.0.9n — items DANS le cadavre (pas par terre)**
  - Pattern Bandits `BanditUpdate.lua:2412` confirme : `body:getContainer():AddItem(item)`.
  - Nouvelle architecture :
    1. `OnZombieDead` : snapshot des items + retrait de l'inventaire NPC, stocke dans `PHNPC._pendingLoot[id] = { x, y, z, items }`.
    2. `OnDeadBodySpawn(body)` : matching par proximite (≤ 2 tuiles), transfert dans `body:getContainer()`. Flag `body.modData.PHNPC_WasNPC = true`.
    3. Fallback : si pas de cadavre apres 120 ticks (~2s), drop au sol (pattern Bandits `ZADrop` `sq:AddWorldInventoryItem`).

- **`PHNPC_Update.lua` v0.0.9n — protection cascade**
  - `pickShelterPoint` desormais en `pcall` (anti-cascade si Building.lua plante).
  - `findNearestZombie` en `pcall` pour l'etat `attacking` (cas cell nil).

### Effet attendu

- Plus aucun crash en boucle, meme si l'API B42.18 evolue.
- L'ordre "Mets-toi a l'abri" trouve une chambre ou abandonne silencieusement.
- L'ordre "Va la-bas" et le combat fonctionnent (la cascade qui les bloquait est supprimee).
- Loot visible dans le clic-droit -> Examiner le cadavre.

---

## [0.0.9m] — 2026-05-27

### Correctifs post-v0.0.9l (3 bugs critiques persistants apres test)

Apres v0.0.9l le joueur confirme : crash shelter toujours present + saccades sur "Va la-bas" + NPC ne court pas en follow + items non droppes a la mort.
Audit complet realise sur l'API B42.18 par extraction des `.class` du moteur, comparaison avec `mod example/B42/Bandits/42.18` (`ZAGoTo`, `ZAMove`, `BanditUpdate.OnZombieDead`, `ZADrop`).

### Corrections principales

- **`PHNPC_Building.lua` — crash `getRooms()` en boucle (chaque frame)**
  - **Cause racine confirmee** : `IsoGameCharacter:getCurrentBuilding()` retourne un `IsoBuilding` (et non un `BuildingDef`). `IsoBuilding` n'a **pas** de methode `getRooms()`. API reelle (verifie par extraction `.class`) : `getRoomsNumber():int`, `getRoom(int):IsoRoom`, `getRandomRoom()`, `getRoomByID(int)`, `getFreeTile()`, `getRandomFirstFloorWindow()`.
  - `IsoRoom` (et non `RoomDef`) expose `getRandomFreeSquare():IsoGridSquare`.
  - **Fix** : `findSafeRoomSquare` reecrit pour iterer `0..getRoomsNumber()-1` et utiliser `building:getRoom(i):getRandomFreeSquare()`.
  - **Bonus** : retrait des wrappers `spc`/`safePcall` du fichier (cause de cascades d'erreurs en Kahlua quand `pcall` est temporairement indisponible).

- **`PHNPC_Actions.lua` — saccades sur "Va la-bas" et "Suis-moi"**
  - **Cause racine** : `applyMoveSetup` etait re-appele a chaque tick dans la branche "path en cours" et incluait `setBumpType("IdleToRun")` + `faceLocationF(x,y)`. Pattern Bandits `ZAGoTo.onStart` (mod example) confirme : `setBumpType` ne doit etre appele **que** quand le NPC n'est pas deja en mouvement, et `faceLocationF` jamais en boucle.
  - **Fix** : split en deux helpers :
    - `applyMoveStart(npc, x, y, walkType)` -> appele **une seule fois** au lancement d'un nouveau path : `setVariable("BanditWalkType",...)` + `setWalkType` + `setRunning` + `faceLocationF` + `setBumpType`.
    - `applyMoveTick(npc, walkType)` -> appele chaque tick (idempotent) : juste `setVariable("BanditWalkType",...)` + `setRunning(...)`. **Aucun reset d'animation**.
  - Les branches `else` de `startFollowing` et `startMovingTo` (path deja lance) utilisent desormais `applyMoveTick`.

- **`PHNPC_Update.lua` — le NPC ne court pas quand le joueur est loin**
  - **Cause racine** : `startFollowing(npc, player)` etait appele sans `walkType`. La fonction calculait ensuite `walkType` via `pickWalkType` qui retourne "Run" si dist>6 mais le walkType etait recompute a partir de la dist post-offset (toujours `stopDist=3`) et tombait en "Walk".
  - **Fix** : `startFollowing` accepte maintenant un parametre `forceWalkType`. Le handler `following` dans `PHNPC_Update.lua` passe explicitement `"Run"` quand `dist > PHNPC.RUN_DISTANCE` (=6 tuiles), `"Walk"` sinon.

- **`PHNPC_Loot.lua` — items non droppes a la mort du NPC**
  - **Cause racine** : `safePcall` masquait les erreurs (echec silencieux). De plus la tentative de transfert dans `IsoDeadBody:getContainer()` echouait souvent car `OnZombieDead` est declenche **avant** la creation du cadavre.
  - **Fix** : refonte complete sur le pattern Bandits `ZADrop.lua` (`sq:AddWorldInventoryItem(item, rx, ry, 0)`) :
    - Drop direct **au sol** via `IsoGridSquare:AddWorldInventoryItem(item, randX, randY, 0)` (toujours fiable, items visibles).
    - Drop des **WORN ITEMS** (vetements/armures) - oublies en v0.0.9k/l.
    - Drop des items en main via `setPrimaryHandItem(nil)` + `setSecondaryHandItem(nil)` + `clearAttachedItems()`.
    - **Backup** : second handler sur `OnZombieUpdate` qui detecte la mort si `OnZombieDead` n'est pas declenche (cas explosions/multi-degats en B42).
    - **Logs INFO explicites** a chaque etape pour diagnostic : nombre de worn items, nombre d'items inventaire, total droppes.
    - Retrait de `safePcall` (cause d'echec silencieux).

### Fichiers modifies

- `B42/42/media/lua/client/PHNPC_Building.lua` (reecriture API IsoBuilding)
- `B42/42/media/lua/client/PHNPC_Actions.lua` (split applyMoveStart/Tick + forceWalkType)
- `B42/42/media/lua/client/PHNPC_Update.lua` (force "Run" dans follow handler)
- `B42/42/media/lua/client/PHNPC_Loot.lua` (refonte pattern Bandits ZADrop + worn + backup OnZombieUpdate)

### API B42.18 verifiees (extraction `.class`)

| Methode | Classe reelle | Note |
| --- | --- | --- |
| `IsoGameCharacter:getCurrentBuilding()` | retourne `IsoBuilding` | **PAS `BuildingDef`** |
| `IsoBuilding:getRoomsNumber()` | int | |
| `IsoBuilding:getRoom(int)` | `IsoRoom` | |
| `IsoBuilding:getRandomRoom()` | `IsoRoom` | |
| `IsoRoom:getRandomFreeSquare()` | `IsoGridSquare` ou null | |
| `IsoZombie:getDeadBody()` | `IsoDeadBody` ou null | Existe en B42.18 mais null durant OnZombieDead |
| `IsoGridSquare:AddWorldInventoryItem(item, rx, ry, rz)` | `IsoWorldInventoryObject` | Pattern Bandits ZADrop |

---

## [0.0.9l] — 2026-05-27

### Correctifs post-v0.0.9k (rapport de test joueur)

La v0.0.9k a introduit le systeme de batiments et la course mais 2 bugs persistaient en jeu :
- crash total lors de l'ordre "Mets-toi a l'abri"
- ordre "Va la-bas" : le NPC court mais avec saccades + impression de retour-aller

### Corrections principales

- **CRASH `PHNPC_Building.lua` — "Mets-toi a l'abri" plantait le mod**
  - **Cause racine** : le wrapper interne `local function spc(fn) local ok, err = _pcall(fn); return ok, err end` reposait sur `local _pcall = pcall` capture au chargement. Dans certains contextes Kahlua B42, `pcall` peut etre `nil` au moment du load du chunk -> `_pcall = nil` -> chaque appel `spc(...)` levait `Object tried to call nil in spc` (PHNPC_Building.lua:30).
  - **Stack trace observe** :
    ```
    spc(PHNPC_Building.lua:99)
    spc(PHNPC_Building.lua:30)        <- _pcall(fn) avec _pcall=nil
    findSafeRoomSquare(...:99)
    pickShelterPoint(...:170)
    ```
  - **Fix** : reecriture complete de `PHNPC_Building.lua` **sans aucun `pcall`**. Toutes les API Java utilisees (`getCurrentBuilding`, `getSquare`, `getBuilding`, `getRooms`, `getRandomFreeSquare`, `isFree`, `getGridSquare`, `getMovingObjects`) sont verifiees presentes en B42.18 via extraction `.class`. Les retours nullables sont gardes par `if obj then ... end` au niveau Lua.

- **SACCADES "Va la-bas" / "Mets-toi a l'abri" — NPC court mais saccade + revient**
  - **Cause racine #1** : `PHNPC_Enforce.lua` handler `actionStateName == "idle"` appelait `PHNPC.stopMoving(zombie)` au **premier** tick d'idle. Or le moteur `PathFindBehavior2` alterne occasionnellement les etats `idle`/`pathfind` entre 2 steps de marche. `stopMoving` brutal reset `md.PHNPC_PathX/Y` + `md.PHNPC_Moving=false` -> le tick suivant `Update.lua` re-call `startMovingTo` -> `pathToLocationF` est appele en boucle (log `console.txt` montrait 100+ appels consecutifs f:5595 -> f:5878).
  - **Fix** : compteur `md.PHNPC_IdleTicks`. `stopMoving` declenche seulement apres **15 ticks** idle consecutifs. Reset a 0 en cas de `pathfind` ou de mouvement.
  - **Cause racine #2** : `PHNPC_Actions.lua::needNewPath` retournait `true` des que `md.PHNPC_Moving == false`, sans cooldown. Combine avec le bug #1 ci-dessus, chaque oscillation idle/pathfind reset le path immediatement.
  - **Fix** : ajout d'un compteur global `PHNPC._pathTickCounter` (incremente OnTick). `needNewPath` exige maintenant un cooldown minimum de **8 ticks** entre 2 `pathToLocationF` aux memes coordonnees. Seuil de difference de destination assoupli de `dx*dx+dy*dy > 1` a `> 4` (2 tuiles) pour eviter les micro-recalculs.

### Detail technique

- `PHNPC_Building.lua` : suppression de `local _pcall = pcall` et `local function spc(fn)`. Les 9 anciens appels `spc(function() ... end)` sont remplaces par des appels Java directs avec garde `if obj then`.
- `PHNPC_Enforce.lua` idle handler : `if md.PHNPC_Moving then md.PHNPC_IdleTicks = (md.PHNPC_IdleTicks or 0) + 1; if md.PHNPC_IdleTicks >= 15 then ... PHNPC.stopMoving(zombie) end else md.PHNPC_IdleTicks = 0 end`. Reset additionnel dans le bloc `pathfind`.
- `PHNPC_Actions.lua` : `PATH_COOLDOWN = 8`. `md.PHNPC_LastPathTick = PHNPC._pathTickCounter` ecrit a chaque `pathToLocationF` (dans `startMovingTo` et `startFollowing`).
- `PHNPC_Update.lua` OnTick : `PHNPC._pathTickCounter = (PHNPC._pathTickCounter or 0) + 1` en tete de handler.
- Banniere `[PHNPC] ... v0.0.9l loaded` sur les 10 fichiers Lua (Actions, Combat, Core, Enforce, Log, Loot, Building, Orders, Stats, Update).

### Fichiers modifies

| Fichier | Changement |
|---------|-----------|
| `PHNPC_Building.lua` | **Reecriture complete** : suppression wrapper `spc`/`_pcall`, appels Java directs |
| `PHNPC_Enforce.lua` | Idle handler avec compteur `PHNPC_IdleTicks` (seuil 15 ticks) |
| `PHNPC_Actions.lua` | `needNewPath` avec cooldown 8 ticks via `_pathTickCounter`, seuil dist 2 tuiles |
| `PHNPC_Update.lua` | Incrementation `PHNPC._pathTickCounter` chaque `OnTick` |

### API B42.18 reconfirmees (sans pcall)

- `IsoGameCharacter:getCurrentBuilding()` : retourne `BuildingDef` ou `nil` (jamais d'exception)
- `IsoGridSquare:getBuilding()` / `getMovingObjects()` : retourne `null`/liste vide
- `BuildingDef:getRooms()` + `RoomDef:getRandomFreeSquare()` : surs (gardes nil au niveau Lua)
- `IsoCell:getGridSquare(x,y,z)` : retourne `null` hors map

### Lecons retenues

- En Kahlua B42, `local _pcall = pcall` capture au load peut donner `nil` dans certains scopes. Plutot que de wrapper avec fallback, **mieux vaut ne pas utiliser pcall du tout** quand les API sont verifiees existantes et que les retours nuls sont gerables.
- `actionStateName == "idle"` peut etre transitoirement vrai pendant un pathfind actif. Ne jamais reagir au premier tick : compter les ticks consecutifs.
- Tout appel `pathToLocationF` doit etre throttle par un cooldown pour eviter qu'une oscillation d'etat ne le declenche en boucle.

---

## [0.0.9k] — 2026-05-27

### REFONTE GAMEPLAY — ordres / course / loot / batiments

La v0.0.9j ne crashait plus mais les ordres "Va la-bas" et "Mets-toi a l'abri" laissaient le NPC sur place : `pathToLocationF` etait rappele toutes les 20 ticks ce qui **annulait** le pathfind en cours juste apres son demarrage. En parallele, `Enforce.lua` faisait `setWalkType("Walk")` et `setTarget(nil)` **a chaque tick**, ce qui interdisait toute course et tout deplacement durable.

### Corrections principales

- **`PHNPC_Actions.lua`** — refonte `startMovingTo` / `startFollowing` (pattern Bandits B42.18 ZAGoTo/ZAMove) :
  - `pathToLocationF` appele **UNE FOIS** au lancement d'un nouveau path (memorisation de `md.PHNPC_PathX/Y/Z`)
  - `needNewPath()` decide si on relance le pathfind (destination differente OU NPC a l'arret)
  - `setVariable("BanditWalkType", walkType)` + `setVariable("PHNPC_WalkType", walkType)` + `setWalkType(walkType)` + `setRunning(walkType=="Run")` : declenche les AnimSets B42 pour la course
  - `pickWalkType()` : choisit "Run" si distance > `PHNPC.RUN_DISTANCE` (=6), si HP < 50%, ou si etat shelter/fleeing
  - `faceLocationF` avant `pathToLocationF` evite la rotation sur place
  - `forceRepath()` expose pour debloquer un NPC stuck

- **`PHNPC_Enforce.lua`** :
  - `setTarget(nil)` + `clearAggroList()` UNIQUEMENT si NPC a l'arret (sinon le pathfind etait casse)
  - `setAttackedBy(nil)` idem
  - `setWalkType` suit maintenant `md.PHNPC_WalkType` (au lieu de hardcoder "Walk"), ce qui permet la course
  - `setRunning(walkType == "Run")` re-applique chaque tick si le NPC bouge

- **`PHNPC_Update.lua`** :
  - Handler `goingto` : ne rappelle plus `startMovingTo` chaque `FOLLOW_TICK_RATE` ticks. Surveillance `STUCK_TICKS` (=90 ticks) : si le NPC n'a pas bouge de plus de `STUCK_THRESHOLD` (=0.3 tiles), on declenche un `forceRepath` en Run pour debloquer
  - Handler `shelter` : meme logique stuck, et utilise `PHNPC.pickShelterPoint` pour cibler une chambre interieure

- **`PHNPC_Combat.lua`** : le NPC court (`"Run"`) en approche du zombie cible.

### Nouveaux fichiers

- **`PHNPC_Loot.lua`** — drop de l'inventaire NPC a la mort :
  - `Events.OnZombieDead` : transfere les items dans `IsoDeadBody:getContainer()` du corps fraichement cree (`sq:getDeadBodys()`), ou les drop au sol via `AddWorldInventoryItem` en fallback
  - Marque `md.PHNPC_Looted = true` pour eviter le double drop

- **`PHNPC_Building.lua`** — detection batiments pour "Mets-toi a l'abri" :
  - `isInsideBuilding(npc)` : `getCurrentBuilding()` + fallback `sq:getBuilding()`
  - `findNearestBuildingSquare(x,y,z,maxRadius=30)` : scan **spirale** par anneaux, retourne la premiere case interieure libre
  - `findSafeRoomSquare(building)` : itere `building:getRooms()` et choisit `room:getRandomFreeSquare()` avec le moins de zombies a 4 tuiles
  - `pickShelterPoint(npc)` : strategie (1) chambre safe si deja dans batiment, (2) batiment proche + chambre, (3) fallback `findClearAreaNear`

### Nouvelles constantes (`PHNPC_Core.lua`)

```lua
PHNPC.RUN_DISTANCE      = 6     -- au-dela : Run
PHNPC.STUCK_TICKS       = 90    -- ticks pour declencher repath
PHNPC.STUCK_THRESHOLD   = 0.3   -- tiles min de deplacement
PHNPC.FLEE_RUN_HP_RATIO = 0.50  -- HP < 50% => course (independant de FLEE_HP_RATIO)
```

### API B42.18 verifiees (extraction `.class` du jar)

- `IsoGameCharacter:setRunning(bool)` : OK (course)
- `IsoZombie:getInventory()` / `getCurrentBuilding()` : OK (loot, batiments)
- `IsoDeadBody:getContainer()` / `addItem(item)` : OK
- `IsoGridSquare:getDeadBodys()` / `getBuilding()` / `getRoom()` : OK
- `BuildingDef:getRooms()` + `RoomDef:getRandomFreeSquare()` : OK
- `Events.OnZombieDead` : OK

### Fichiers modifies

| Fichier | Changement |
|---------|-----------|
| `PHNPC_Actions.lua` | Refonte complete `startMovingTo` / `startFollowing` / `stopMoving` (path-once, walkType, setRunning) |
| `PHNPC_Enforce.lua` | `setTarget/setAttackedBy` conditionnel, `setWalkType` dynamique |
| `PHNPC_Update.lua` | Detection stuck remplace retry chaque 20 ticks, `pickShelterPoint` pour shelter |
| `PHNPC_Combat.lua` | Approche zombie en `"Run"` |
| `PHNPC_Core.lua` | Nouvelles constantes RUN/STUCK |
| `PHNPC_Loot.lua` | **NOUVEAU** drop inventaire a la mort |
| `PHNPC_Building.lua` | **NOUVEAU** detection batiments + chambres safe |

---

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
