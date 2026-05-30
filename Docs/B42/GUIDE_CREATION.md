# GUIDE DE CRÉATION DE NPC — PH Dynamic NPC Overhaul B42
_Version 0.0.19 (hotfix combat ranged B42 + stabilisation runtime)_

> Mise a jour v0.0.19 (2026-05-30) — regles runtime/IA ajoutees.
>
> 1. **Methodes Java exposees** : avant tout appel sensible sur objet Java (meteo, inventaire, combat), verifier `PHNPC.hasMethod(obj, "method")`. Les appels manquants peuvent casser la frame meme dans un `pcall`.
> 2. **Follow stable** : ne jamais forcer un re-path immediat quand `PHNPC_Moving` devient faux sur un tick transitoire. Respecter un delai minimal (`FOLLOW_REPATH_TICKS`).
> 3. **Armes a feu** : pour engager a distance, choisir une arme ranged dediee (pas juste "meilleure arme globale"), puis verifier munitions juste avant le tir.
> 4. **Filtre type obligatoire** : ne jamais appeler `isRanged()` sur un item generique ; filtrer d'abord `instanceof(item, "HandWeapon")`.
> 5. **AmmoType B42** : `getAmmoType()` peut renvoyer un objet (avec `getItemKey`) ou une string ; normaliser avant `containsTypeRecurse/getFirstTypeRecurse`.
> 6. **XP gameplay** : l'XP doit etre attribuee au moment des impacts (melee/ranged) pour que la progression soit visible pendant les tests.
> 7. **Debug outfit** : exposer un resume lisible des scores defensifs par slot pour valider rapidement les remplacements de vetements.
> 8. **Pipeline mouvement unique** : centraliser les path dans `schedulePathTo(...)` plutot que rappeler `pathToLocationF` a plusieurs endroits.
> 9. **Portes en pathfind** : pour des NPC non joueur, eviter `ToggleDoor(npc)` et preferer une ouverture safe (`ToggleDoorSilent` ou helper porte dedie).
> 10. **Transition animation d'arret** : conserver le dernier mode de locomotion et basculer vers `RunToIdle` ou `WalkToIdle` selon ce mode.

> Mise a jour v0.0.16 (2026-05-30) — nouveaux patterns ajoutes.
>
> 1. **Armes a feu (gate ammo + skill)** : avant de scorer une arme ranged, verifier TOUJOURS deux conditions : munitions dans l'inventaire (`hasAmmoForWeapon`) ET niveau Aiming suffisant (`getNPCSkillLevel(npc,"Aiming") >= RANGED_MIN_SKILL`). Ne jamais donner de bonus ranged si l'une des deux conditions echoue.
> 2. **API meteo GameTime** : detecter la meteo via `GameTime.getInstance():getRainIntensity()`, `:getTemperature()`, `:getFogIntensity()`. Entourer d'un `pcall` pour robustesse. Ne jamais appeler ces methodes au chargement du fichier, seulement dans un callback de tick.
> 3. **Systeme XP** : stocker les niveaux dans `ModData` avec `PHNPC_Skill_<Name>` et `PHNPC_XP_<Name>`. Ne jamais appeler `PerkFactory.getPerkByName` a chaque tick ; mettre en cache la reference.
> 4. **Pathfinding natif** : preferer `npc:pathToLocationF(x, y, z, 0)` (NavigatorGrid) pour gerer automatiquement portes/fenetres/clotures. Ajouter un cooldown `PATH_MIN_TICKS` (15 ticks) pour eviter les micro-freezes.
> 5. **getText() timing** : ne jamais stocker `getText("UI_PHNPC_*")` dans une variable globale au chargement; la traduction n'est pas encore disponible. Stocker la cle brute et appeler `getText(key)` au moment du bark.
>
> Mise a jour v0.0.15 (2026-05-28) — regles ajoutees apres KO v0.0.14.
>
> 1. Follow : imposer une cadence minimale de re-path (`FOLLOW_REPATH_TICKS`) et une hold zone anti yo-yo au stop distance.
> 2. Clotures : `ClimbOverFenceState` ne doit pas etre casse immediatement; reset seulement apres blocage prolonge.
> 3. Ordres explicites : poser `PHNPC_OrderLock` a la creation d'un ordre (`goingto/shelter`) et le faire respecter par Update + Combat.
> 4. Shelter : des qu'un NPC est in-building, forcer `staying` local + fermeture defensive.
> 5. Mort/loot : conserver un marker pending loot jusqu'au snapshot et prevoir un fallback de transfert par fullType.

> Mise a jour v0.0.14 (2026-05-28) — regles ajoutees apres re-test v0.0.13/v0.0.13b.
>
> 1. Follow : ne jamais declencher de re-path sur la derive locale de l'ancre. Re-path seulement si le joueur a bouge suffisamment, ou stuck detecte.
> 2. Ordres explicites : toujours verrouiller `goingto/shelter` (`PHNPC_OrderLock`) pour empecher les bascules parasites d'etat.
> 3. Clotures : ne pas interrompre agressivement `ClimbOverFenceState`; ne reset qu'en blocage prolonge.
> 4. Vetements : pour B42, preferer `instanceof(item, "Clothing")` avec fallback et supporter `getWornItems():setItem(...)`.
> 5. Loot mort : si la mort retire le NPC des registres, conserver un marker `DeadPendingLoot` jusqu'au snapshot sinon les items donnes sont perdus.

> Mise a jour v0.0.13 (2026-05-28) — regles ajoutees apres retours v0.0.12.
>
> 1. Follow anti-collage : privilegier un point d'ancrage autour du joueur (`pathToLocationF`) plutot que `pathToCharacter` en continu.
> 2. Ne pas casser le mouvement sur etats transitoires : en `following/goingto/shelter/fleeing`, ignorer la destruction de `PHNPC_Moving` lors de `lunge/attack/eatBody`.
> 3. Arme melee : comparer l'arme equipee ET l'inventaire complet avant equipement (sinon la premiere arme reste figee).
> 4. Loot fiable : inclure explicitement `primaryHand` et `secondaryHand` dans le snapshot de mort.
> 5. QoL inventaire : auto-equiper les vetements de l'inventaire quand le slot cible est libre (`setWornItem`).

> **Mise à jour v0.0.12 (2026-05-28)** — Trois pièges critiques supplémentaires identifiés après test v0.0.11.
>
> ### Piège -5 (CRITIQUE) — `return` dans une branche d'état peut tuer tout le tick IA
> Dans une callback `Events.OnTick.Add(function() ... end)`, un `return` dans une branche locale (`staying`) quitte la callback entière, pas seulement la branche.
>
> ```lua
> -- MAUVAIS
> if md.PHNPC_NoPatrol then return end
>
> -- BON
> if not md.PHNPC_NoPatrol then
>   -- logique patrouille
> end
> ```
>
> ### Piège -6 (CRITIQUE) — `item:isWeapon()` n'est pas un filtre universel fiable en Kahlua
> Certains items exposés côté Lua ne supportent pas cette méthode de manière homogène selon le type runtime. Résultat : exceptions en boucle dans `scoreWeapon`.
>
> **Pattern robuste** : filtrer avec `instanceof(item, "HandWeapon")`, puis lire les stats avec garde-fous (`getMaxDamage/getMinDamage`).
>
> ### Piège -7 — Sur-cadencer le follow côté Update alors que le helper est déjà path-once
> Si `startFollowing` sait déjà limiter ses re-paths (ancre + seuil), le recadrer encore avec un timer global peut rendre Run/Walk et stop-distance non réactifs.
>
> **Règle** : laisser la logique de throttling au helper de mouvement, et appeler le helper chaque tick avec l'intention courante (`Run`/`Walk`).

> **Mise à jour v0.0.11 (2026-05-28)** — Tests v0.0.10 échoués 4/5. Leçons architecturales majeures consolidées ci-dessous.
>
> ### Piège 0 (CRITIQUE) — NE JAMAIS recalculer une destination depuis la position courante du NPC
> v0.0.10 : `startFollowing` faisait `tx = px - nx*stopDist` où `nx = (px-npc.x)/dist`. Comme `npc.x` change à chaque tick, `tx,ty` change → `needNewPath` voit > 2 tuiles → `pathToLocationF` re-tiré → **saccade infinie**.
>
> ```lua
> -- MAUVAIS (v0.0.10) :
> local nx = (player:getX() - npc:getX()) / d  -- npc:getX() change chaque tick
> local tx = player:getX() - nx * stopDist     -- tx change donc
> if needNewPath(npc, md, tx, ty, ...) then    -- toujours vrai = spam
>     npc:pathToLocationF(tx, ty, pz)
> end
>
> -- BON (v0.0.11) — pattern NPC_Helper_Mod GCCoreActions.lua :
> if not md.PHNPC_Moving then
>     npc:pathToCharacter(player)  -- engine-side tracking, UNE FOIS
>     md.PHNPC_Moving = true
>     md.PHNPC_PathX = player:getX()  -- anchor PLAYER, pas NPC
>     md.PHNPC_PathY = player:getY()
> elseif (player:getX()-md.PHNPC_PathX)^2 + (player:getY()-md.PHNPC_PathY)^2 >= 25 then
>     npc:pathToCharacter(player)  -- re-path SEULEMENT si player a bougé 5+ tuiles
>     md.PHNPC_PathX = player:getX()
>     md.PHNPC_PathY = player:getY()
> end
> ```
>
> ### Piège -1 (CRITIQUE) — NE JAMAIS faire fermer/ouvrir portes à chaque tick + à chaque stopMoving
> v0.0.10 : `OnTick` appelait `checkAndOpenDoors` chaque tick + `stopMoving` appelait `closeNearbyDoors`. Quand un NPC s'arrêtait près d'une porte ouverte, `stopMoving` la fermait → tick+1 `checkAndOpenDoors` la rouvrait → tick+2 `stopMoving` la refermait. 18 blocs ERROR dans console.txt.
>
> **Pattern correct (v0.0.11)** : portes/fenêtres ouvertes UNIQUEMENT à l'entrée d'un path (start de mouvement), fermées UNIQUEMENT via une fonction explicite `PHNPC.closeBehindNPC(npc)` appelée à la transition `staying` (arrivée goingto/shelter), JAMAIS dans `stopMoving` générique.
>
> ### Piège -2 — Flag de patrouille à reset dans TOUS les ordres
> v0.0.11 introduit `md.PHNPC_NoPatrol=true` à l'arrivée d'un goingto pour bloquer la patrouille `staying` aléatoire. Tous les ordres (`recruit`/`follow`/`stay`/`attack`/`shelter`/`free`/`goingto`) doivent **reset `md.PHNPC_NoPatrol = nil`** sinon le NPC reste figé après le premier goingto.
>
> ### Piège -3 — Seuil idle trop court coupe l'anim
> v0.0.10 : Enforce step 5 stop le NPC après 15 ticks idle (0.5s). Le moteur `PathFindBehavior2` alterne brièvement `idle`/`pathfind` pendant les transitions normales (passage de porte, demi-tour). Stop brutal = reset anim = cut visible chaque seconde. v0.0.11 : **60 ticks (2s)** de tolérance.
>
> ### Piège -4 — `tryGet` séquentiel ≠ "meilleure arme"
> v0.0.10 `getNPCWeapon` faisait `tryGet("Base.Bat") or tryGet("Base.Axe")` → Bat retourné en premier même si Axe plus puissante. v0.0.11 : scan complet `inv:getItems()` + filtre `item:isWeapon()` + score `maxDamage*10 + condition` → meilleure arme sélectionnée.
>
> ---
>
> ### Pièges identifiés au test v0.0.9p (toujours valides)
>
> ### Piège 1 (CRITIQUE) — `setEquippedItem` n'existe PAS en B42.18
> Pendant des semaines (depuis v0.0.7a) le mod appelait `npc:setEquippedItem(weapon)` dans `PHNPC_Combat.lua:131`, wrappe en `pcall`. **La methode n'existe pas sur `IsoZombie`**. Le `pcall` masquait silencieusement l'echec → le NPC n'equipait jamais ses armes et frappait toujours a mains nues.
>
> **Pattern correct** (verifie B42.18 + utilise dans `Convert.lua:47` + `Loot.lua:105`) :
>
> ```lua
> -- BON :
> pcall(function() npc:setPrimaryHandItem(weapon) end)
> -- MAUVAIS (silencieux a cause du pcall) :
> pcall(function() npc:setEquippedItem(weapon) end)
> ```
>
> **Lecon transverse** : `pcall` est utile pour le hardening defensif, mais **dangereux pour les appels API critiques** qu'on suppose existants. Pour ces cas, **toujours grep le mod example Bandits** d'abord pour confirmer le nom exact de la methode B42.18.
>
> ### Piege 2 (CRITIQUE) — `applyMoveTick(npc, md.PHNPC_WalkType or walkType)` ignore les changements de walkType
> Dans `startFollowing` branche `else` (NPC deja en mouvement) :
>
> ```lua
> -- MAUVAIS (gele le walkType au premier path) :
> applyMoveTick(npc, md.PHNPC_WalkType or walkType)
> -- BON (force le nouveau walkType si fourni) :
> if walkType then md.PHNPC_WalkType = walkType end
> applyMoveTick(npc, md.PHNPC_WalkType)
> ```
>
> Sinon : NPC commence en "Walk" au premier path, le joueur s'eloigne tres loin, le handler `following` rappelle `startFollowing(npc, player, "Run")` → ignore le "Run" → NPC continue en "Walk" et reste a la traine indefiniment.
>
> ### Piege 3 — `pathToCharacter(player)` colle le joueur
> `pathToCharacter` met le NPC sur le tile **exact** du joueur. `FOLLOW_STOP_DISTANCE = 2` ne s'applique que via la condition de stop, mais entre 2 ticks le moteur a deja avance le NPC sur le tile cible. **Solution** : utiliser `pathToLocationF(px + offset, py + offset)` ou l'offset est un vecteur radial de 2-3 tuiles depuis l'angle (joueur → NPC).
>
> ```lua
> local angle = math.atan2(npc:getY() - player:getY(), npc:getX() - player:getX())
> local stopDist = PHNPC.FOLLOW_STOP_DISTANCE or 2
> local tx = player:getX() + math.cos(angle) * stopDist
> local ty = player:getY() + math.sin(angle) * stopDist
> pcall(function() npc:pathToLocationF(tx, ty, npc:getZ()) end)
> ```
>
> ### Piege 4 — Etats comportementaux s'ecrasent mutuellement
> Quand un NPC en etat `goingto` rencontre un zombie, `npcCombatStep` le passe en `defending`. Si la transition `defending → previous_state` ne restaure pas aussi `md.PHNPC_GoToX/Y/Z`, le NPC perd sa destination → retourne en `following` (joueur) → bug "allez-retour".
>
> **Pattern recommande** : sauvegarder un snapshot complet du contexte avant transition :
>
> ```lua
> if md.PHNPC_State ~= "defending" then
>     md.PHNPC_PrevState = md.PHNPC_State
>     md.PHNPC_PrevGoToX = md.PHNPC_GoToX  -- snapshot total
>     md.PHNPC_PrevGoToY = md.PHNPC_GoToY
>     md.PHNPC_PrevGoToZ = md.PHNPC_GoToZ
>     md.PHNPC_State = "defending"
> end
> -- restore plus tard :
> md.PHNPC_State = md.PHNPC_PrevState
> md.PHNPC_GoToX = md.PHNPC_PrevGoToX  -- etc.
> ```
>
> ### Piege 5 — `pickShelterPoint` retourne souvent nil
> `getRandomRoom()` boucle 8 fois sur un `IsoBuilding` peut tout echouer si le batiment a peu de rooms ou que les rooms sont rejetees. Le fallback aleatoire prend la main → NPC va dans une direction random.
>
> **Pattern recommande** : combiner avec `getCell():getRoomList()` filtre par distance.
>
> ### Piege 6 — Variables AnimSet (`PHNPC_IsNPC`) reset par `changeState`
> L'enforce.lua step 10 re-applique `setVariable("PHNPC_IsNPC", true)` chaque tick **apres** tous les `changeState`. Mais si les XMLs d'AnimSet dans `B42/common/media/AnimSets/zombie/idle/*.xml` ne contiennent pas de **variant conditionnel** sur cette variable, l'animation idle reste la posture zombie standard.
>
> **A verifier dans chaque XML d'AnimSet** :
>
> ```xml
> <AnimSet name="idle">
>   <Variant Condition="PHNPC_IsNPC == true" AnimFile="Bob_Idle.x" />  <!-- ou Kate_Idle pour femmes -->
>   <Variant AnimFile="ZombieIdle.x" />  <!-- fallback zombie -->
> </AnimSet>
> ```
>
> Si le variant conditionnel manque, on a beau setter la variable, l'AnimSet selectionne toujours le default zombie.
>
> ---
>
> ### Piege 7 (v0.0.9o) — Les methodes `ToggleDoor`/`isLocalPlayer` plantent sur un IsoZombie
> `IsoDoor:ToggleDoor(character)` et `IsoThumpable:ToggleDoor(character)` cast en interne le character en `IsoPlayer` pour appeler `isLocalPlayer()`. **Notre NPC est `IsoZombie`** -> `NullPointerException` non-rattrape par `pcall` qui interrompt le for-loop principal -> tous les NPCs perdent leur tick (saccades, ordres ignores).
>
> **Reference Bandits B42.18** (`BanditUpdate.lua:823`, `BanditServerCommands.lua:172/178/184`) :
>
> ```lua
> -- BON pour un NPC IsoZombie :
> object:ToggleDoorSilent()       -- sans argument
> -- MAUVAIS :
> object:ToggleDoor(npc)           -- crash si npc n'est pas IsoPlayer
> ```
>
> **Pour les fenetres**, `window:ToggleWindow(zombie)` accepte un `IsoZombie` (pattern `ZAOpenWindow.lua:21` Bandits) -> OK.
>
> ### Piege 8 (v0.0.9o) — Saccades sur re-path
> Appeler `setBumpType` + `faceLocationF` a chaque cooldown de re-path interrompt l'anim a chaque fois -> NPC saccade visiblement. Pattern Bandits `ZAGoTo.onStart` : `setBumpType` est appele **une seule fois** au lancement, ensuite seul `pathToLocationF(newX, newY)` est rappele pour mettre a jour la destination -> le moteur enchaine sans reset d'anim.
>
> ```lua
> if not md.PHNPC_Moving then
>     applyMoveStart(npc, x, y, walkType)   -- setBumpType + faceLocationF UNE FOIS
> else
>     applyMoveTick(npc, walkType)          -- idempotent : setVariable + setRunning seulement
> end
> pcall(function() npc:pathToLocationF(x, y, z) end)
> ```
>
> ### Piege 9 — `npc:getCurrentBuilding()` retourne un `IsoBuilding`, **pas** un `BuildingDef`
> `IsoBuilding` n'a **pas** de methode `getRooms()`. Utiliser `getRoomsNumber()` + `getRoom(int)` (qui renvoie `IsoRoom`). Sur l'`IsoRoom`, utiliser `getRandomFreeSquare()` pour obtenir une case libre. Verifie par extraction des `.class` du moteur.
>
> ### Piege 10 — Ne JAMAIS re-appeler `setBumpType` ou `faceLocationF` chaque tick pendant un path
> Cause directe des "saccades" : ces appels reinitialisent l'animation a chaque frame. Pattern Bandits `ZAGoTo.onStart` confirme : `setBumpType("IdleToRun")` n'est appele qu'au **lancement** du path et seulement si le NPC n'est pas deja en mouvement.
>
> ### Piege 11 — Drop loot a la mort : `OnZombieDead` precede la creation du `IsoDeadBody`
> Au moment ou `OnZombieDead(zombie)` est appele, `zombie:getDeadBody()` est encore `nil`. Pattern fiable (Bandits `ZADrop.lua`) : drop direct au sol via `sq:AddWorldInventoryItem(item, randX, randY, 0)`. Ne pas oublier les `getWornItems()` (vetements/armures). Eviter `pcall`/wrappers silencieux qui masquent les vraies causes d'echec.
>
> **Methodologie consolidee depuis v0.0.9o** : copier directement les patterns du mod Bandits B42.18 plutot que d'extrapoler depuis la doc decompilee. Les approximations (v0.0.9k -> v0.0.9n) ont a chaque fois introduit des regressions. Reference : `D:\PZ Mods\Dynamic_NPC_Overhaul\mod example\B42\Bandits\42.18`.
>
> _Version 0.0.9g_ : guide ecrit initialement pour cette version, complete avec les fixes v0.0.9i-l-m.

> Ce guide explique le fonctionnement du système NPC tel qu'implémenté en v0.0.9i.
> Pattern copié EXACTEMENT depuis NPC_Helper_Mod (GCCoreConvert + GCCoreEnforceMain + GCCoreSpawn + GCUpdate),
> enrichi avec les corrections B42.18 (portes, outfits, Kahlua upvalue).

---

## Vue d'ensemble

Le NPC est un `IsoZombie` "banditisé" par un ensemble de variables et d'AnimSets personnalisés.  
Il ne peut pas être un `IsoPlayer` (limité au mode debug de PZ).

**Pipeline de création (v0.1) :**
1. `addZombiesInOutfit()` → crée l'entité IsoZombie avec une tenue humaine
2. `convertToNPC()` → configure les variables pour désactiver le comportement zombie
3. AnimSets → animations humaines selon les variables `PHNPC_IsNPC` et `zombieWalkType`
4. `enforceNPC()` chaque tick → maintient le NPC "humain" contre les réinitialisations de PZ

---

## 1. Spawning (spawnNPC)

```lua
-- addZombiesInOutfit est une FONCTION GLOBALE (pas une méthode d'IsoZombie)
local zombieList = addZombiesInOutfit(x, y, z, 1, outfit, femaleChance)
local zombie = zombieList:get(0)
convertToNPC(zombie, outfit, isFemale, npcName)
```

### Outfits disponibles (v0.0.9g — 47 métiers)

Liste complète issue de `clothing.xml` (PZ 42.18) :

**Forces de l'ordre / Militaire** : `"Police"`, `"Sheriff_Deputy"`, `"Detective"`, `"Security"`, `"MallSecurity"`, `"PrisonGuard"`, `"Veteran"`, `"ArmyCamoGreen"`, `"ArmyCamoDesert"`, `"PrivateMilitia"`, `"BountyHunter"`

**Services d'urgence / Santé** : `"Fireman"`, `"Doctor"`, `"Nurse"`, `"AmbulanceDriver"`, `"Pharmacist"`

**Travailleurs / Artisans** : `"Farmer"`, `"Chef"`, `"Mechanic"`, `"ConstructionWorker"`, `"Trucker"`, `"Woodcut"`, `"MetalWorker"`, `"Sanitation"`, `"Postal"`, `"Foreman"`

**Nature / Plein air** : `"Ranger"`, `"Hunter"`, `"Fisherman"`, `"Camper"`, `"Survivalist"`

**Civils** : `"Teacher"`, `"IT"`, `"OfficeWorker"`, `"Resident"`, `"Retiree"`, `"Student"`, `"Tourist"`, `"Biker"`, `"Redneck"`, `"Hobbo"`, `"Inmate"`, `"Priest"`, `"FitnessInstructor"`

**Génériques** : `"Generic01"` à `"Generic05"`

> ⚠️ `"Survivor"` (ancienne valeur) est conservé comme alias rétrocompat dans `OUTFIT_STATS`, mais n'est plus dans la liste de spawn. Le nom B42 correct est `"Survivalist"`.

---

## 2. convertToNPC — Configuration Banditize (ordre obligatoire)

```lua
-- 1. Dents : empeche morsure zombie immediatement
zombie:setNoTeeth(true)

-- 2. Variables de vitesse
zombie:setVariable("LimpSpeed", 0.80)
zombie:setVariable("RunSpeed",  0.75)
zombie:setVariable("WalkSpeed", 1.04)

-- 3. Variable principale AnimSet => active tous nos ZS*.xml
zombie:setVariable("PHNPC_IsNPC", true)

-- 4. Marche humaine
--    setWalkType() est l'API officielle PZ : elle fixe zombieWalkType en interne.
--    NE PAS appeler setVariable("zombieWalkType",...) => variable READ-ONLY en B42 => WARN spam.
zombie:setWalkType("Walk")

-- 4b. Genre : OBLIGATOIRE pour que le moteur choisisse Bob (M) ou Kate (F)
--     Sans ca, toutes les femmes jouent Bob_Idle au lieu de Kate_Idle
zombie:setFemaleEtc(isFemale)

-- 5. Hit reaction humaine (evite crash testDefense)
zombie:setVariable("ZombieHitReaction", "Chainsaw")

-- 6. Desactiver lunge vers cible
zombie:setVariable("NoLungeTarget", true)

-- 7. Silence sons zombie
zombie:getEmitter():stopAll()

-- 8. Vider les mains
zombie:setPrimaryHandItem(nil)
zombie:setSecondaryHandItem(nil)
zombie:resetEquippedHandsModels()
zombie:clearAttachedItems()

-- 9. Neutraliser TurnAlerted
zombie:setTurnAlertedValues(-5, 5)

-- 10. Voix humaine
zombie:getDescriptor():setVoicePrefix("PHNPC")

-- 11. Empecher re-habillage automatique
zombie:setDressInRandomOutfit(false)

-- 12. Premiere transition propre depuis Zombie_Idle
zombie:setBumpType("Shrug")

-- 13. Nettoyer visuels (saleté, sang)
zombie:getHumanVisual():removeDirt()
zombie:getHumanVisual():removeBlood()

-- 14. ModData
local md = zombie:getModData()
md.PHNPC_IsNPC      = true
md.PHNPC_Recruited  = false
md.PHNPC_State      = "idle"     -- "idle" | "following" | "staying" | "goingto" | "free" | "shelter" | "attacking" | "fleeing"
md.PHNPC_Name       = npcName
md.PHNPC_Female     = isFemale
md.PHNPC_Outfit     = outfit
md.PHNPC_Moving     = false
md.PHNPC_HitTicks   = 0
md.PHNPC_ShowTimer  = 5         -- ignorer les 5 premiers ticks (spawn)

-- 15. Enregistrer
PHNPC.allNPCs[zombie] = true
```

> ⚠️ **PAS de `setUseless()` ici.** `setUseless` est géré par `enforceNPC` à chaque tick.  
> ⚠️ **PAS de `setHealth()` ici.** Géré par `enforceNPC`.  
> ⚠️ **PAS de `setTarget(nil)` ici.** Géré par `OnZombieUpdate`.  
> ⚠️ **PAS de `setSpeedMod()` ici.** Géré par `enforceNPC`.  

---

## 3. AnimSets

### Principe
Les AnimSets sont des fichiers XML dans `common/media/AnimSets/zombie/<etat>/`.  
PZ choisit l'animation à jouer selon l'**état** de l'IsoZombie et les **variables** définies.

Notre mod ajoute des conditions `PHNPC_IsNPC=true` pour jouer des animations Bob_ (humain) au lieu de Zombie_.

### États et AnimSets actifs (v0.1)
| État PZ | Dossier | Fichier | Animation jouée |
|---------|---------|---------|-----------------|
| Stationnaire | `idle/` | ZSIdle.xml | Bob_Idle |
| Pathfinding (pathToCharacter) | `pathfind/` | ZSWalk.xml | Bob_Walk |
| Poursuite (setTarget) | `walktoward/` | ZSWalk.xml | Bob_Walk |
| Lunge (transition) | `lunge/` | defaultlunge.xml | (override vanilla) |
| Bump/Pain/Shove/Action | `bumped/` | ZS*.xml (180+) | Bob_* selon BumpType |
| Attaques | `attack/` | ZS*.xml | Bob_Attack* selon BumpType |
| Interaction porte | `thump/` | ZSdoor.xml | Bob_FrontKick |

> ⚠️ `pathfind/` et `walktoward/` doivent contenir les mêmes ZSWalk.xml.  
> `pathToCharacter()` → état `pathfind`  
> `setTarget()` → état `walktoward`

### BumpTypes disponibles (via setBumpType)
Les animations humaines sont déclenchées en positionnant `BumpType` :

| BumpType | Animation | Usage |
|----------|-----------|-------|
| `"Shrug"` | Bob_EmoteShrug | Transition idle (défaut) |
| `"IdleToWalk"` | Bob_IdleToWalk | Démarrer la marche |
| `"WalkToIdle"` | Bob_WalkToIdle | Arrêter la marche |
| `"PainHead"` | Bob_EmotePainHead | Réaction coup à la tête |
| `"PainTorso"` | Bob_EmotePainTorso | Réaction coup au torse |
| `"PainStomach1"` | Bob_EmotePainStomach1 | Réaction coup ventre |
| `"NPCPushedBack"` | Bob_NPCPushedBack | Reculer (poussé) |
| `"NPCPushedFront"` | Bob_NPCPushedFront | Trébucher en avant |
| `"Shove"` | Bob_Shove | Pousser (corps à corps) |
| `"FrontKick"` | Bob_FrontKick | Coup de pied avant |
| `"HighKick"` | Bob_HighKick | Coup de pied haut |
| `"WaveHi"` | Bob_EmoteWaveHi | Salut de la main |
| `"Yes"` | Bob_EmoteYes | Acquiescer |
| `"No"` | Bob_EmoteNo | Refuser |

---

## 4. enforceNPC — Maintien du comportement (chaque tick)

`enforceNPC` est le gardien du NPC. Appelé depuis `OnZombieUpdate` à chaque frame.

```lua
-- ORDRE DES APPELS (NPC_Helper_Mod EXACT) :

-- 1. Activer l'engine zombie (requis pour pathToCharacter)
zombie:setUseless(false)

-- 2. Fix B42 : empeche marche en arriere
zombie:setAnimatingBackwards(false)

-- 3. Variables AnimSet — OBLIGATOIRE A CHAQUE TICK
--    Sans ca, PZ les reinitialise et les animations zombie reprennent
zombie:setVariable("PHNPC_IsNPC", true)
zombie:setVariable("NoLungeTarget", true)
-- setWalkType fixe zombieWalkType en interne (READ-ONLY: ne pas appeler setVariable)
zombie:setWalkType("Walk")
-- Genre : maintenir chaque tick pour eviter regression B42 (Bob vs Kate)
zombie:setFemaleEtc(md.PHNPC_Female or false)
zombie:setSpeedMod(0.8)

-- 4. Prevention comportement zombie
zombie:setNoTeeth(true)
zombie:setEatBodyTarget(nil, false)
zombie:setHealth(10000)

-- 5. Machine d'etats
local asn = zombie:getActionStateName()

if asn == "pathfind" then
    skipSecurity = true      -- CRITIQUE : ne pas appeler setTarget(nil) !

elseif asn == "bumped" then
    skipSecurity = true      -- Laisser animation bumped se terminer

elseif asn == "hitreaction" then
    skipSecurity = true
    md.PHNPC_HitTicks = md.PHNPC_HitTicks + 1
    if md.PHNPC_HitTicks > 25 then
        zombie:changeState(ZombieIdleState.instance())
        zombie:setBumpType("Shrug")
        md.PHNPC_HitTicks = 0
        md.PHNPC_Moving = false
    end

elseif asn == "turnalerted" then
    zombie:changeState(ZombieIdleState.instance())
    zombie:clearAggroList()
    zombie:setTarget(nil)

elseif asn == "lunge" then
    if md.PHNPC_Moving then
        skipSecurity = true
    else
        zombie:changeState(ZombieIdleState.instance())
        zombie:clearAggroList()
        zombie:setTarget(nil)
    end

elseif asn == "attack" or asn == "eatBody" then
    zombie:changeState(ZombieIdleState.instance())
    zombie:clearAggroList()
    zombie:setTarget(nil)
    md.PHNPC_Moving = false
end

-- 6. Securite (SEULEMENT si pas en pathfind)
if not skipSecurity then
    zombie:setTarget(nil)
    zombie:clearAggroList()
end

-- 7. CRITIQUE : freeze zombie AI si NPC non-recrute
if not md.PHNPC_Recruited then
    zombie:setUseless(true)
end

-- 8. Supprimer sons zombie
zombie:getDescriptor():setVoicePrefix("PHNPC")
zombie:getEmitter():stopSoundByName("MaleZombieVoiceA")
zombie:getEmitter():stopSoundByName("MaleZombieVoiceB")
zombie:getEmitter():stopSoundByName("FemaleZombieVoiceA")
zombie:getEmitter():stopSoundByName("FemaleZombieVoiceB")
```

> ⚠️ **`setTarget(nil)` dans "pathfind" = pathfinding IMMÉDIATEMENT ANNULÉ.**  
> C'est pour ça que `skipSecurity=true` est CRITIQUE pendant l'état "pathfind".

---

## 5. OnZombieUpdate — Patron d'appel

```lua
Events.OnZombieUpdate.Add(function(zombie)
    if not PHNPC.isNPC(zombie) then return end

    -- INCONDITIONNEL (avant tout, meme avant ShowTimer)
    pcall(function() zombie:setNoTeeth(true) end)
    pcall(function() zombie:setTarget(nil) end)

    -- Gerer isDead / fakeDead
    if zombie:isDead() then
        zombie:setHealth(10000)
        zombie:setFakeDead(false)
        zombie:knockDown(false)
        zombie:setKnockedDown(false)
        zombie:setCanWalk(true)
        zombie:setUseless(false)
        zombie:changeState(ZombieIdleState.instance())
        if zombie:isDead() then return end  -- encore mort : abandonner
    end

    -- ShowTimer : ignorer les 5 premiers ticks
    local md = zombie:getModData()
    if (md.PHNPC_ShowTimer or 0) > 0 then
        md.PHNPC_ShowTimer = md.PHNPC_ShowTimer - 1
        return
    end

    pcall(function() enforceNPC(zombie) end)
end)
```

> ⚠️ Le `setTarget(nil)` INCONDITIONNEL en début de `OnZombieUpdate` ne tue PAS le pathfind.  
> C'est un mécanisme différent de `setTarget(nil)` dans `enforceNPC` qui lui le tue.  
> Pattern confirmé depuis GCUpdate.lua (NPC_Helper_Mod).

---

## 6. Structure du projet (v0.1)

```
B42/
  42/                               <- RACINE DU MOD (mod.info ici, pas dans B42/)
    mod.info
    icon.png
    poster.png
    media/
      lua/
        shared/
          PHNPC_Core.lua            <- namespace PHNPC, constantes, isNPC()
        client/
          PHNPC_Manager.lua         <- spawn, enforce, follow, menu
  common/
    media/
      AnimSets/
        zombie/                     <- 464 fichiers XML (>= NPC_Helper_Mod)
          idle/, pathfind/, walktoward/, lunge/, ...
```

> ⚠️ `mod.info` DOIT être dans `B42/42/`, PAS dans `B42/`.  
> PZ B42 lit `42/` comme racine du mod (découverte automatique B42).

---

## 7. Pièges courants

| Piège | Cause | Solution |
|-------|-------|---------|
| Animations zombie à la place de Bob | `PHNPC_IsNPC` pas re-appliqué chaque tick | Re-appliquer dans `enforceNPC` |
| Femme joue Bob_Idle au lieu de Kate_Idle | `setFemaleEtc(isFemale)` manquant | Appeler dans `convertToNPC` ET `enforceNPC` |
| WARN spam `zombieWalkType` | `setVariable("zombieWalkType",...)` variable read-only en B42 | Utiliser uniquement `setWalkType("Walk")` |
| Crash callback menu clic-droit | Signature `(_, player)` erronee : `player=nil` | `ISContextMenu:addOption(t,target,fn)` => `fn(target)`, signature correcte : `(player)` |
| NPC mord le joueur | `setNoTeeth(true)` pas inconditionnel | En tete de `OnZombieUpdate`, AVANT `ShowTimer` |
| NPC invisible apres coup | Pas de handler `hitreaction` | Compteur 25 ticks + revive `isDead` |
| pathToCharacter() ignore | `setTarget(nil)` appele pendant `pathfind` | `skipSecurity=true` dans etat "pathfind" |
| NPC attaque le joueur | `setUseless(true)` absent | Obligatoire pour NPCs non-recrutes |
| NPC ne bouge pas | `setUseless(false)` non appele avant pathfind | `startFollowing()` appelle `setUseless(false)` d'abord |
| `addZombiesInOutfit` introuvable | Appele comme methode | Fonction GLOBALE : `addZombiesInOutfit(x,y,z,...)` |
| **Tous les NPCs redeviennent zombies** | **Erreur de syntaxe/runtime dans Manager.lua** | **Verifier console.txt : `SEVERE: Error found in LUA file` = crash chargement total** |
| **NPC ressuscite apres setHealth(0)** | `PHNPC_IsNPC=true` encore present → `OnZombieUpdate` appelle `setHealth(10000)` | **Toujours `md.PHNPC_IsNPC = nil` AVANT `setHealth(0)`** |
| **NPC mort sans corpse / items perdus** | `setHealth(1)` ne tue pas l'IsoZombie | **Utiliser `setHealth(0)` uniquement — crée le corpse lootable** |
| **Bulle de dialogue invisible** | `zombie:Say()` ne crée pas de bulle sur IsoZombie en B42 | **Utiliser `zombie:addLineChatElement(text, r, g, b)`** |
| **NPC bloqué en animation bumped** | XMLs `ZSWalkToIdle.xml`/`ZSIdleToWalk.xml` absents → vanilla PZ sans condition `PHNPC_IsNPC` | **Ces XMLs doivent exister avec `PHNPC_IsNPC=true` + `SpeedScale=3.0` + `EarlyTransitionOut=true`** |
| **NPC tape les portes** | `ToggleDoor(npc)` invalide en B42 — aucun recalcul du cache pathfinder zombie | **Séquence : `DirtySlice()` → `RecalcLightTime=-1.0` → `InvalidateSpecialObjectPaths()` → `ToggleDoorSilent()` → `RecalcProperties()` → `syncIsoObject()` → puis `ReCalculatePathFind()` sur rayon 2 tiles** |
| **NPC ouvre une double porte mais bloque sur l'autre battant** | `ToggleDoorSilent()` n'ouvre qu'une moitié de double porte | **Vérifier `IsoDoor.getDoubleDoorIndex(obj) > -1` → utiliser `IsoDoor.toggleDoubleDoor(obj, true)`** |
| **Crash `function PHNPC.X` appelle nil** | Variable/fonction `local` utilisée comme upvalue dans une closure `PHNPC.*` en Kahlua B42 | **Stocker comme `PHNPC.X` (champ de table) au lieu de `local X`** |
| **Crash dans ordre NPC si NPC est nil** | `npc:getModData()` appelé sans vérification préalable | **Toujours `if not npc then return end` + `if not md then return end` en tête de chaque fonction d'ordre** |
