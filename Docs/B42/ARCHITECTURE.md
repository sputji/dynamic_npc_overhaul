# ARCHITECTURE — PH Dynamic NPC Overhaul B42
_Version 2.2.0 — Combat manuel NPC + traductions FR corrigees + inventaire + Say() dialogue_

---

## Changelog rapide

| Version | Changements clés |
|---------|------------------|
| 2.0.0 | NPC fonctionnel : spawn, suivi, stats, combat (setTarget), peur, inventaire |
| 2.1.0 | Fix menu crash, vitesse NPC, colere 4 niveaux, 4 AnimSets bumped, traductions JSON |
| **2.2.0** | **Combat entierement manuel** (faceLocationF+setBumpType+knockDown), `npc:Say()` remplace HaloTextHelper, `UI.json` requis pour traductions FR, inventaire via `OnRefreshInventoryWindowContainers`, suppression `setBumpType("IdleToWalk")` |

---

## Principe fondateur

**Client-only, sans dispatcher réseau.**  
Le NPC est un `IsoZombie` "banditisé" : créé via `addZombiesInOutfit()` puis transformé via des appels API.  
Aucun serveur n'est impliqué en mode solo. `PHNPC_Server.lua` est prêt pour l'extension multijoueur.

> **Pourquoi pas IsoPlayer.new() ?**  
> `IsoPlayer.new()` ne fonctionne QUE dans `isDebugEnabled()`. Abandonné v1.0.0.  
> `addZombiesInOutfit()` = seule méthode prouvée pour spawner des entités humanoïdes en B42.

---

## Structure des fichiers (v2.0.0)

```
B42/
  common/
    media/
      lua/
        shared/
          PHNPC_Core.lua          <- namespace global PHNPC, VERSION
          PHNPC_Stats.lua         <- noms genrés, profils stats, generateName/generateStats
        client/
          PHNPC_Manager.lua       <- spawn, enforceNPC, menu, peur, combat, inventaire
        server/
          PHNPC_Server.lua        <- stub (futur multijoueur)
      AnimSets/
        zombie/
          idle/
            ZSIdle.xml            <- Bob_Idle | condition: PHNPC_IsNPC=true
          pathfind/               <- état quand pathToLocationF() est actif
            ZSWalk.xml            <- Bob_Walk | zombieWalkType=Walk
            ZSRun.xml             <- Bob_Run  | zombieWalkType=Run
            ZSSneakWalk.xml       <- Bob_WalkSneak | zombieWalkType=SneakWalk
            ZSLimp*.xml           <- Bob_Limp variants
            ZSWalkAim*.xml        <- Bob_WalkAim variants (armes)
          walktoward/             <- état poursuite directe (setTarget)
            ZSWalk.xml            <- idem pathfind
            ZSRun.xml             <- idem pathfind
          lunge/
            ZSlunge.xml           <- Bob_Walk (vitesse 1.1) | PHNPC_IsNPC=true
          lunge-network/
            ZSlunge.xml           <- idem
          thump/
            door.xml              <- Zombie_Door | PHNPC_IsNPC=false (exclusion)
            ZSdoor.xml            <- Bob_FrontKick | PHNPC_IsNPC=true + ThumpType=Door
            DoorBang.xml          <- Zombie_DoorBang | PHNPC_IsNPC=false
            ZSDoorBang.xml        <- Bob_FrontKick | PHNPC_IsNPC=true + DoorBang
            DoorClaw.xml          <- Zombie_DoorClaw | PHNPC_IsNPC=false
            ZSDoorClaw.xml        <- Bob_FrontKick | PHNPC_IsNPC=true + DoorClaw
          bumped/
            ZSBump*.xml           <- Bob_Push* | PHNPC_IsNPC=true + BumpType
          attack/                 <- combat humain
            ZSAttack*.xml         <- Bob_Attack* | PHNPC_IsNPC=true
          hitreaction/
            ZSPain*.xml           <- Bob_Pain* | PHNPC_IsNPC=true
          face-target/, falldown/, getup/, climbrope/, etc.
      textures/                   <- icones UI (futur)
  mod.info
```

---

## Flux de création d'un NPC (v2.0.0)

```
Clic-droit sur le sol
  -> OnPreFillWorldObjectContextMenu
  -> option "[PHNPC] Faire apparaitre un PNJ"
  -> createNPC(square)
      |
      +-- addZombiesInOutfit(x, y, z, 1, outfit, femaleChance)
      |       => IsoZombie avec tenue humaine
      |
      +-- PHNPC.generateName(isFemale)        <- liste M/F séparées
      +-- PHNPC.generateStats(outfit)         <- profil stats selon outfit
      |
      +-- Banditize (pattern NPC_Helper_Mod + Bandits):
      |   setNoTeeth(true)
      |   setVariable("PHNPC_IsNPC", true)    <- active ZSIdle.xml + tous les ZS*.xml
      |   setWalkType("Walk")
      |   setVariable("zombieWalkType", "Walk")  <- active ZSWalk.xml
      |   setVariable("ZombieHitReaction", "Chainsaw")
      |   setVariable("NoLungeTarget", true)
      |   setSpeedMod(1.0)                    <- CRITIQUE: sans ça vitesse=0
      |   setVariable("WalkSpeed", 1.04)
      |   setVariable("RunSpeed", 1.10)
      |   setDressInRandomOutfit(false)
      |   setTurnAlertedValues(-5, 5)
      |   setBumpType("Shrug")
      |   getDescriptor():setVoicePrefix("NotAZombie")
      |   setTarget(nil) + clearAggroList()
      |   setHealth(10000)
      |
      +-- ModData: PHNPC_ID, PHNPC_Name, PHNPC_Female, PHNPC_Outfit, PHNPC_Stats
      +-- PHNPC.npcs[npc] = { id, name, stats, followMode, attackMode, ... }
```

---

## Boucle principale (OnTick + OnZombieUpdate)

```
OnZombieUpdate(zombie)          <- une fois par IsoZombie par frame
  -> si PHNPC.npcs[zombie]:
       enforceNPC(zombie)
         setUseless(false)      <- PREMIER APPEL: débloque le NPC après un hit
         setHealth(10000)
         setNoTeeth(true)
         setVariable("PHNPC_IsNPC", true) + zombieWalkType + setSpeedMod
         switch(getActionStateName()):
           "pathfind" -> return (ne pas interrompre le déplacement)
           "thump"    -> return (laisser ouvrir la porte)
           "attack"   -> return si attackMode actif, sinon reset
           "lunge"/"eatBody" -> changeState(ZombieIdleState) + reset
           "turnalerted"     -> changeState(ZombieIdleState) + reset
           "bumped"   -> compter 35 ticks, handleAnger, setBumpType niveau 4
           TOUJOURS en debut: setTarget(nil) + clearAggroList (sauf colere joueur)

OnTick()                        <- toutes les frames
  -> cleanup NPC morts (toutes les 300 ticks)
  -> pour chaque NPC:
       colere vs joueur  (si playerAngerTicks > 0)
         doMeleeAttack() si dist <= 1.8 tile, sinon approcher
       checkFear()     (toutes les 30 ticks)
         si courage < 50 ET zombie < 10 tiles -> fuite (oppose, 15 tiles)
       checkCombat()   (toutes les 10 ticks si attackMode)
         trouver zombie le plus proche < 15 tiles
         si dist <= 1.8 tile -> doMeleeAttack(npc, zombie) + cooldown 60 ticks
         si trop loin -> npcStartMoving() vers zombie
       suivre joueur   (si followMode + dist > 3 tiles + pas en fuite/combat)
         pathToLocationF(px, py, pz) toutes les 15 ticks
```

---

## Variables de contrôle AnimSets

| Variable | Type | Valeur | Effet |
|----------|------|--------|-------|
| `PHNPC_IsNPC` | BOOL | true | Active tous les ZS*.xml (idle, walk, lunge, thump, attack...) |
| `zombieWalkType` | STRING | "Walk" | Active ZSWalk.xml (Bob_Walk) dans pathfind/ et walktoward/ |
| `zombieWalkType` | STRING | "Run" | Active ZSRun.xml (Bob_Run) |
| `zombieWalkType` | STRING | "SneakWalk" | Active ZSSneakWalk.xml (Bob_WalkSneak) |
| `ZombieHitReaction` | STRING | "Chainsaw" | Évite crash dans testDefense |
| `NoLungeTarget` | BOOL | true | Empêche le lunge vers les cibles |
| `BumpType` | STRING | "Shrug" | Animation de bump par défaut |

---

## Système de stats (PHNPC_Stats.lua)

### Profils par outfit
| Outfit | Courage | Force | Mêlée | Tir | Endurance |
|--------|---------|-------|-------|-----|-----------|
| Police | 60-95 | 50-80 | 55-85 | 60-90 | 55-80 |
| Fireman | 70-100 | 65-95 | 60-90 | 30-60 | 70-95 |
| Doctor | 35-65 | 30-55 | 25-50 | 30-60 | 40-65 |
| Ranger | 55-85 | 50-80 | 45-75 | 65-95 | 60-85 |
| Chef | 30-60 | 40-70 | 35-65 | 20-50 | 35-60 |
| Farmer | 40-70 | 55-85 | 40-70 | 40-70 | 50-75 |
| Survivor | 45-75 | 40-70 | 40-70 | 35-65 | 45-70 |

### Seuils comportementaux
- `FEAR_COURAGE_THRESHOLD = 50` : en-dessous → peut fuir les zombies proches
- `FEAR_ZOMBIE_DIST = 10` : distance (tiles) de détection
- `FIGHT_COURAGE_THRESHOLD = 40` : utilisé pour l'engagement automatique (futur)

---

## Menu clic-droit (v2.0.0)

```
Clic sur sol vide:
  "[PHNPC] Faire apparaitre un PNJ"

Clic sur un NPC (rayon 2 tiles):
  "[PHNPC] NomNPC (M/F)"
    -> "Suis-moi" / "Reste ici"
    -> "Mode combat (tuer zombies)" / "Arreter le combat"
    -> "Voir l'inventaire"  (hook OnRefreshInventoryWindowContainers)
    -> "Voir les stats"     (npc:Say() avec nom + stats)
    -> "Renvoyer"           (removeFromWorld)
```

---

## Systeme de traductions (v2.2)

- Fichiers JSON dans `Translate/EN/UI.json` et `Translate/FR/UI.json`
- **Nom obligatoire : `UI.json`** — tout autre nom (ex: `PHNPC.json`) est ignore pour les langues non-EN en B42
- Acces : `getText("PHNPC_Menu_StayHere")` etc.
- Cle exemple : `"PHNPC_Menu_SpawnNPC"`, `"PHNPC_Anger_M_1"`...
- Pattern confirme depuis ssr_quests (supporte 7 langues)

---

## Dialogue NPC (v2.2)

- `npc:Say("texte")` — bulle blanche au-dessus du NPC
- Utilise pour : colere (handleAnger), stats (showNPCStats), salutation (createNPC)
- **`HaloTextHelper.addText()` n'existe pas en B42** — ne pas utiliser

---

## Combat manuel (v2.2)

```lua
-- doMeleeAttack(npc, target)
npc:faceLocationF(target:getX(), target:getY())
npc:setBumpType("Shove")       -- ou "FrontKick", "HighKick" (en alternance)
pcall(function() target:knockDown(true) end)  -- sur zombies seulement
data.attackCooldown = 60       -- ticks avant prochaine attaque
```

> Confirme depuis GCCombatActionsAttack.lua (NPC_Helper_Mod)
> `setTarget(nil)` + `clearAggroList()` TOUJOURS appeles dans enforceNPC
> Le zombie AI natif est 100% desactive pour les NPCs

---

## Inventaire (v2.2)

```lua
-- Hook — ajoute le conteneur NPC a la fenetre de loot
Events.OnRefreshInventoryWindowContainers.Add(function(page, step)
    if step ~= "beforeFloor" then return end
    if page.onCharacter then return end
    if not _openInvNPC then return end
    local loot = getPlayerLoot(page.player)
    if loot then
        loot:addContainerButton(npcInv, nil, npcName, npcName)
    end
end)
```

> `ISInventoryTransferUI.transferBetween()` crash en B42 (module ISInventoryTransferAction echoue)
> Pattern confirme depuis GCMenuInventory.lua (NPC_Helper_Mod)