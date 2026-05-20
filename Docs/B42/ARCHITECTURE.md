# ARCHITECTURE — PH Dynamic NPC Overhaul B42
_Version 1.0.1 — addZombiesInOutfit + Banditize + AnimSets ZSIdle/ZSWalk_

---

## Principe fondateur v1

**Client-only, sans dispatcher réseau.**  
Le NPC est créé via `addZombiesInOutfit()` (IsoZombie banditisé). Aucun serveur n'est impliqué en mode solo.  
En multijoueur futur, `PHNPC_Server.lua` sera étendu.

> **Pourquoi pas IsoPlayer.new() ?**  
> `IsoPlayer.new()` ne fonctionne QUE dans `isDebugEnabled()` (Custom NPC mod).  
> En mode normal, rien ne spawn. Approche abandonnée depuis v1.0.0.

---

## Structure des fichiers

```
B42/
  common/
    media/
      lua/
        shared/
          PHNPC_Core.lua        <- namespace global PHNPC, VERSION = "1.0.0"
        client/
          PHNPC_Manager.lua     <- TOUTE la logique (spawn, tick, menu, pathfinding)
        server/
          PHNPC_Server.lua      <- stub serveur (usage futur multijoueur)
  42/
    media/
      AnimSets/
        zombie/
          idle/ZSIdle.xml       <- Bob_Idle si PHNPC_IsNPC=true
          walktoward/ZSWalk.xml <- Bob_Walk si zombieWalkType=Walk
      textures/                 <- icones UI
  mod.info
```

---

## Flux de creation d'un NPC

```
Clic-droit sur le sol
  -> OnPreFillWorldObjectContextMenu
  -> option "[PHNPC] Faire apparaitre un PNJ"
  -> spawnNPC(square, playerIndex)
  -> createNPC(square)
      +-- addZombiesInOutfit(x, y, z, 1, outfit, femaleChance)  <- IsoZombie
      +-- Banditize:
          npc:setNoTeeth(true)
          npc:setVariable("PHNPC_IsNPC", true)       <- active ZSIdle.xml
          npc:setWalkType("Walk")                    <- active ZSWalk.xml
          npc:setVariable("zombieWalkType", "Walk")
          npc:setVariable("ZombieHitReaction", "Chainsaw")
          npc:setVariable("NoLungeTarget", true)
          npc:setDressInRandomOutfit(false)
          npc:setTurnAlertedValues(-5, 5)
          npc:setBumpType("Shrug")
      +-- hv:removeDirt() / removeBlood()
      +-- npc:getModData() <- PHNPC_ID, PHNPC_Name, PHNPC_Female
      +-- PHNPC.npcs[npc] = { id, name, isFemale, followMode=true }
```

---

## Flux du pathfinding (OnTick)

```
OnTick (chaque frame)
  +-- Cleanup pass (tous les 300 ticks) : retire les NPC morts (isDead())
  +-- Movement pass (chaque tick)
        +-- SI followMode=true ET dist > STOP_DIST
        |     +-- Tous les RETARGET ticks : npc:getPathFindBehavior2():pathToLocation(px,py,pz)
        |     +-- Chaque tick :             npc:getPathFindBehavior2():update()
        +-- SI followMode=true ET dist <= STOP_DIST
        |     +-- npc:getPathFindBehavior2():cancel() + npc:setPath2(nil)
        +-- SI followMode=false
              +-- npc:getPathFindBehavior2():update()  <- evite le gel
```

---

## Source des patterns

| Pattern | Source dans les mods exemples |
|---------|-------------------------------|
| `IsoPlayer.new()` | `7 - Custom NPC / 42 / shared / CnpcHuman.lua` -> `newIsoHuman()` |
| `getPathFindBehavior2():pathToLocation()` | `7 - Custom NPC / media / shared / ISAction / ISHumanWalk.lua` |
| `getPathFindBehavior2():update()` | `7 - Custom NPC / media / shared / ISAction / ISHumanWalk.lua` |
| `SurvivorFactory.CreateSurvivor()` | `7 - Custom NPC / 42 / shared / CnpcHuman.lua` -> `newHumanDescObj()` |
| `OnPreFillWorldObjectContextMenu` | `7 - Custom NPC / media / shared / CnpcMenu.lua` |
| Solo/multi detection | `Bandits / 42.18 / BanditPlayer.lua` -> `getGameMode()` |

---

## Regles de code (Kahlua / PZ B42)

- Pas de BOM UTF-8 -- ASCII pur
- Pas de `goto` / `continue` -- remplacer par `if` / early return
- Pas de `next()` -- iterer avec `pairs()` + break
- `obj.method and obj:method()` -- ne jamais tester avec `obj:method and ...`
- `pcall(fn)` -- wrapper tous les appels API PZ potentiellement nil
- `getGameMode()` pour detecter solo ("Sandbox") vs multi ("Multiplayer")

---

## Variables de configuration (PHNPC_Manager.lua)

| Variable | Valeur | Role |
|----------|--------|------|
| `STOP_DIST` | 3 | distance en tiles pour arreter le suivi |
| `RETARGET` | 15 | ticks entre deux `pathToLocation` |
| `CLEANUP` | 300 | ticks entre deux nettoyages de NPC morts |
| `MAX_NPCS` | 10 | nombre maximal de NPC simultanes |

---

## TODO futur

- Sauvegarde NPC entre sessions (ModData)
- Dialogue via bulle de parole
- Factions et relations
- Multijoueur (sync via sendModData / onServerCommand)

---

## Ressources

| Ressource | Lien |
|-----------|------|
| Wiki PZ modding B42 | [pzwiki.net](https://pzwiki.net) |
| API Lua B42 | [pzwiki.net/wiki/Modding](https://pzwiki.net/wiki/Modding) |
