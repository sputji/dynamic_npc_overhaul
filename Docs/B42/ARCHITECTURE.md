# ARCHITECTURE — PH Dynamic NPC Overhaul B42
_Version 0.0.3 — Corrections bugs menu DEBUG + animations/sons NPC._

---

## Changelog rapide

| Version | Changements clés |
|---------|------------------|
| 1.x–2.2.0 | Tentatives iteratives (animations zombie, NPC mordait, invisible quand frappe) |
| **0.1** | **Rewrite complet** base NPC_Helper_Mod EXACT. 2 fichiers. Spawn + follow/stay fonctionnel. Plus d'animations zombie, plus de morsure, plus d'invisibilite. |
| **0.0.2** | Menu DEBUG_PHNPC complet + delete NPC. (bugs callbacks + zombieWalkType) |
| **0.0.3** | Corrections : signature callbacks ISContextMenu, suppression setVariable("zombieWalkType"), ajout setFemaleEtc() pour animations Bob/Kate. |

---

## Principe fondateur

**Client-only, sans dispatcher réseau.**  
Le NPC est un `IsoZombie` "banditisé" : créé via `addZombiesInOutfit()` puis transformé via des appels API.  
Aucun serveur n'est impliqué en mode solo.

> **Pourquoi pas IsoPlayer.new() ?**  
> `IsoPlayer.new()` ne fonctionne QUE dans `isDebugEnabled()`. Abandonné v1.0.0.  
> `addZombiesInOutfit()` = seule méthode prouvée pour spawner des entités humanoïdes en B42.

> **Pourquoi une réécriture totale en v0.1 ?**  
> Les versions 1.x–2.2.x présentaient des animations zombie persistantes, morsure du joueur et NPC invisible après un coup.  
> Cause racine : patterns non conformes à NPC_Helper_Mod. Solution : copie EXACTE des patterns GCCore*.lua.

---

## Structure des fichiers (v0.1)

```
B42/
  42/                           <- racine du mod pour B42 (mod.info ici)
    mod.info
    icon.png
    poster.png
    media/
      lua/
        shared/
          PHNPC_Core.lua        <- namespace global PHNPC, constantes, isNPC()
        client/
          PHNPC_Manager.lua     <- toute la logique : spawn, enforce, follow, menu
  common/
    media/
      AnimSets/
        zombie/
          idle/
            ZSIdle.xml          <- Bob_Idle | condition: PHNPC_IsNPC=true
          pathfind/             <- etat quand pathToCharacter() ou pathToLocationF() actif
            ZSWalk.xml          <- Bob_Walk | zombieWalkType=Walk
          walktoward/           <- etat poursuite directe (setTarget)
            ZSWalk.xml          <- Bob_Walk | zombieWalkType=Walk (idem pathfind)
          lunge/                <- transition de deplacement
            defaultlunge.xml    <- override vanilla (empeche lunge zombie)
          lunge-network/
            defaultlunge.xml    <- idem
          bumped/
            ZS*.xml             <- toutes les animations humaines Bob_ (Pain, Attack, Shove...)
          attack/
            ZS*.xml             <- attaques avec armes / mains nues
          hitreaction/
            ZSClimbWall*.xml    <- override vanilla
          thump/
            door.xml, doorbang.xml, doorclaw.xml  <- override (excluent zombies)
            ZSdoor.xml, ZSDoorBang.xml, ZSDoorClaw.xml <- animations humaines
          face-target/, falldown/, getup/, staggerback/, turnalerted/, etc.
```

**Note importante :** `mod.info`, `icon.png` et `poster.png` doivent être dans `B42/42/` (la racine B42), pas dans `B42/`. PZ B42 lit `42/` comme racine du mod.

---

## Flux de création d'un NPC (v0.1)

```
Clic-droit sur le sol
  -> OnPreFillWorldObjectContextMenu
  -> option "[PHNPC] Appeler un survivant"
  -> spawnNPC(square)
      |
      +-- addZombiesInOutfit(x, y, z, 1, outfit, femaleChance)
      |       => IsoZombie avec tenue humaine (fonction GLOBALE, pas methode)
      |
      +-- convertToNPC(zombie, outfit, isFemale, name)
              |
              +-- setNoTeeth(true)                    <- dents desactivees
              +-- setVariable("PHNPC_IsNPC", true)    <- active tous les ZS*.xml
              +-- setWalkType("Walk")                 <- marche humaine + fixe zombieWalkType en interne
              +-- setFemaleEtc(isFemale)              <- CRITIQUE: Bob_Idle/Walk (M) vs Kate_Idle/Walk (F)
              +-- setVariable("ZombieHitReaction","Chainsaw")
              +-- setVariable("NoLungeTarget", true)
              +-- getEmitter():stopAll()              <- silence sons zombie
              +-- vider les mains
              +-- setTurnAlertedValues(-5, 5)
              +-- getDescriptor():setVoicePrefix("PHNPC")
              +-- setDressInRandomOutfit(false)
              +-- setBumpType("Shrug")
              +-- nettoyer sang/saleté (HumanVisual)
              +-- ModData: PHNPC_IsNPC=true, PHNPC_Recruited=false,
                           PHNPC_State="idle", PHNPC_Name, PHNPC_Female,
                           PHNPC_Outfit, PHNPC_Moving=false, PHNPC_HitTicks=0
              +-- PHNPC_ShowTimer = 5   <- ignore les 5 premiers ticks (spawn)
              +-- PHNPC.allNPCs[zombie] = true
```

---

## Boucle principale (OnTick + OnZombieUpdate)

```
OnZombieUpdate(zombie)          <- une fois par IsoZombie par frame
  -> si pas PHNPC.isNPC(zombie) : return

  -- IMMEDIAT (GCUpdate pattern inconditionnel) :
  pcall setNoTeeth(true)
  pcall setTarget(nil)

  -- Gerer isDead (fakeDead/knockDown) :
     si isDead -> setHealth(10000)+setFakeDead(false)+knockDown(false)+
                  setKnockedDown(false)+setCanWalk(true)+setUseless(false)+
                  changeState(ZombieIdleState)
     -> si encore mort : return

  -- ShowTimer guard :
     si PHNPC_ShowTimer > 0 -> decrementer, return

  pcall(enforceNPC(zombie))


enforceNPC(zombie)              <- coeur du pattern NPC_Helper_Mod
  1. setUseless(false)          <- active l'engine zombie (pathfind possible)
  2. setAnimatingBackwards(false) <- fix B42 marche en arriere
  3. setVariable("PHNPC_IsNPC", true)       <- CHAQUE TICK (sinon zombie reprend)
     setVariable("NoLungeTarget", true)
     setWalkType("Walk")                     <- fixe zombieWalkType en interne (read-only: NE PAS faire setVariable!)
     setFemaleEtc(md.PHNPC_Female or false) <- maintenir Bob/Kate CHAQUE TICK
     setSpeedMod(0.8)
  4. setNoTeeth(true) + setEatBodyTarget(nil,false) + setHealth(10000)
  5. Machine d'etats (getActionStateName()) :
     "pathfind"    -> skipSecurity = true   (ne jamais couper pathfind)
     "bumped"      -> skipSecurity = true   (laisser animation se terminer)
     "hitreaction" -> skipSecurity=true + PHNPC_HitTicks++ ;
                      si HitTicks>25 : changeState(idle)+Shrug+reset
     "turnalerted" -> changeState(idle) + clearAggro + setTarget(nil)
     "lunge"       -> si PHNPC_Moving: skipSecurity=true
                      sinon: changeState(idle)+clearAggro+reset
     "attack","eatBody" -> changeState(idle)+clearAggro+setTarget(nil)+Moving=false
  6. si not skipSecurity : setTarget(nil) + clearAggroList()
  7. si not PHNPC_Recruited : setUseless(true)  <- CRITIQUE: freeze zombie AI
  8. Supprimer sons zombie (stopSoundByName) + setVoicePrefix("PHNPC")


OnTick()                        <- toutes les frames
  -> pour chaque NPC dans PHNPC.recruited :
       si isDead -> cleanup (allNPCs, recruited, followTimers)
       si PHNPC_State == "following" :
          calculer distance joueur
          si dist > FOLLOW_DISTANCE (3 tiles) :
             _followTimers++ ; si >= FOLLOW_TICK_RATE (20) :
               startFollowing(npc, player)   <- pathToCharacter + IdleToWalk
          sinon : stopMoving (WalkToIdle)
```

---

## Variables de contrôle AnimSets

| Variable | Type | Valeur | Effet |
|----------|------|--------|-------|
| `PHNPC_IsNPC` | BOOL | true | Active tous les ZS*.xml (idle, walk, lunge, bumped, attack...) |
| `zombieWalkType` | STRING | "Walk" | Active ZSWalk.xml (Bob_Walk) dans pathfind/ et walktoward/. **READ-ONLY** : fixee via `setWalkType("Walk")`, jamais via `setVariable`. |
| `ZombieHitReaction` | STRING | "Chainsaw" | Evite crash dans testDefense (engine PZ) |
| `NoLungeTarget` | BOOL | true | Empeche lunge automatique vers les cibles |
| `BumpType` | STRING | "Shrug" | Animation par defaut (transition idle) |
| `BumpType` | STRING | "IdleToWalk" | Transition idle → marche |
| `BumpType` | STRING | "WalkToIdle" | Transition marche → idle |
| `BumpType` | STRING | "PainHead/PainTorso/..." | Animations de douleur quand frappe |

**Règle critique :** `PHNPC_IsNPC` et `zombieWalkType` doivent être re-appliqués à CHAQUE tick dans `enforceNPC`. Sans ça, le moteur PZ les réinitialise et reprend les animations zombie.

---

## Menu clic-droit (v0.1)

```
Clic sur sol vide (aucun NPC à portee):
  "[PHNPC] Appeler un survivant"  -> spawnNPC(square)

Clic avec NPC à portee (rayon INTERACTION_DIST = 3 tiles):
  "[NomNPC (M/F)]"
    -> "Rejoins-moi !"          (si pas recrute)
    -> "Reste ici."             (si following)
    -> "Suis-moi !"             (si staying)
    -> "Tu peux partir."        (si recrute)
```

---

## Règles importantes (pièges B42)

| Piège | Solution |
|-------|----------|
| `setUseless(false)` interrompu après hit | Re-appeler à chaque tick dans `enforceNPC` |
| Zombie reprend ses animations | Re-appliquer `PHNPC_IsNPC=true` à chaque tick + `setWalkType("Walk")` (pas `setVariable`) |
| `setVariable("zombieWalkType",...)` → WARN spam | Variable read-only en B42. Utiliser uniquement `setWalkType("Walk")` qui la fixe en interne |
| NPC joue `Bob_Idle` même si femme | `setFemaleEtc(isFemale)` obligatoire dans `convertToNPC` ET `enforceNPC` |
| Callback ISContextMenu signature erronee | `addOption(text, target, fn)` → `fn(target)`. Signature correcte: `(player)`, pas `(_, player)` |
| `setTarget(nil)` tue le pathfind | Ne l'appeler que si `skipSecurity=false` (jamais pendant "pathfind") |
| NPC invisible après hit | Handler `hitreaction` 25 ticks + revive `isDead` dans `OnZombieUpdate` |
| NPC mord le joueur | `setNoTeeth(true)` INCONDITIONNEL en tête de `OnZombieUpdate` |
| `addZombiesInOutfit` retourne IsoZombie | Fonction GLOBALE (pas méthode), prendre `zombieList:get(0)` |
| `mod.info` au mauvais endroit | Doit être dans `B42/42/`, pas `B42/` |

