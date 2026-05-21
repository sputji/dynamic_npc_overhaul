# GUIDE DE CRÉATION DE NPC — PH Dynamic NPC Overhaul B42
_Version 0.1_

> Ce guide explique le fonctionnement du systeme NPC tel qu'implemente en v0.1.
> Pattern copie EXACTEMENT depuis NPC_Helper_Mod (GCCoreConvert + GCCoreEnforceMain + GCCoreSpawn + GCUpdate).

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

### Outfits disponibles
`"Police"`, `"Fireman"`, `"Doctor"`, `"Ranger"`, `"Chef"`, `"Farmer"`, `"Survivor"`

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
zombie:setWalkType("Walk")
zombie:setVariable("zombieWalkType", "Walk")    -- active ZSWalk.xml dans pathfind/

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
md.PHNPC_State      = "idle"     -- "idle" | "following" | "staying"
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
zombie:setVariable("zombieWalkType", "Walk")
zombie:setWalkType("Walk")
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
| NPC mord le joueur | `setNoTeeth(true)` pas inconditionnel | En tête de `OnZombieUpdate`, AVANT `ShowTimer` |
| NPC invisible après coup | Pas de handler `hitreaction` | Compteur 25 ticks + revive `isDead` |
| pathToCharacter() ignoré | `setTarget(nil)` appelé pendant `pathfind` | `skipSecurity=true` dans état "pathfind" |
| NPC attaque le joueur | `setUseless(true)` absent | Obligatoire pour NPCs non-recrutés |
| NPC ne bouge pas | `setUseless(false)` non appelé avant pathfind | `startFollowing()` appelle `setUseless(false)` d'abord |
| `addZombiesInOutfit` introuvable | Appelé comme méthode | Fonction GLOBALE : `addZombiesInOutfit(x,y,z,...)` |
