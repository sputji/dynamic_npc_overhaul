# GUIDE DE CRÉATION DE NPC — PH Dynamic NPC Overhaul B42
_Version 0.0.9p_

> **Mise a jour v0.0.9p (2026-05-27)** — Passe d'audit API B42.18 (JavaDoc officielle + PZ Wiki + patterns Bandits 42.18) : **toutes** les methodes Java utilisees par le mod sont confirmees existantes dans la build `42.18.0 rev 9d7e334cab` (2026-05-11). `console.txt` propre. Hardening pcall applique sur `PHNPC_Enforce.lua` : tous les `setTarget(nil)`, `setHealth(10000)`, `setUseless(...)`, `changeState(...)` bare sont desormais defensifs. Le for-loop `OnTick` est blinde contre toute future evolution d'API.
>
> **Mise a jour v0.0.9o** — Methodologie consolidee : **copier directement les patterns du mod Bandits B42.18** plutot que d'extrapoler depuis la doc decompilee. Les approximations de ma part (v0.0.9k -> v0.0.9n) ont a chaque fois introduit des regressions. Reference : `D:\PZ Mods\Dynamic_NPC_Overhaul\mod example\B42\Bandits\42.18`.
>
> ### Piege 0 (NOUVEAU v0.0.9o) — Les methodes `ToggleDoor`/`isLocalPlayer` plantent sur un IsoZombie
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
> ### Piege 0bis (NOUVEAU v0.0.9o) — Saccades sur re-path
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
> ### Piege 1 — `npc:getCurrentBuilding()` retourne un `IsoBuilding`, **pas** un `BuildingDef`
> `IsoBuilding` n'a **pas** de methode `getRooms()`. Utiliser `getRoomsNumber()` + `getRoom(int)` (qui renvoie `IsoRoom`). Sur l'`IsoRoom`, utiliser `getRandomFreeSquare()` pour obtenir une case libre. Verifie par extraction des `.class` du moteur.
>
> ### Piege 2 — Ne JAMAIS re-appeler `setBumpType` ou `faceLocationF` chaque tick pendant un path
> Cause directe des "saccades" : ces appels reinitialisent l'animation a chaque frame. Pattern Bandits `ZAGoTo.onStart` confirme : `setBumpType("IdleToRun")` n'est appele qu'au **lancement** du path et seulement si le NPC n'est pas deja en mouvement. Architecture recommandee : un helper `applyMoveStart` (au lancement, anim setup complet) et un `applyMoveTick` (chaque tick, idempotent, **uniquement** `setVariable("BanditWalkType",...)` + `setRunning(...)`).
>
> ### Piege 3 — Drop loot a la mort : `OnZombieDead` precede la creation du `IsoDeadBody`
> Au moment ou `OnZombieDead(zombie)` est appele, `zombie:getDeadBody()` est encore `nil`. Pattern fiable (Bandits `ZADrop.lua`) : drop direct au sol via `sq:AddWorldInventoryItem(item, randX, randY, 0)`. Ne pas oublier les `getWornItems()` (vetements/armures). Eviter `pcall`/wrappers silencieux qui masquent les vraies causes d'echec.
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
