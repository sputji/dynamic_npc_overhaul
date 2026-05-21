# Architecture B42 — Dynamic NPC Overhaul v0.0.9a

## Structure des fichiers

```
B42/
├── 42/media/lua/
│   ├── shared/
│   │   ├── PHNPC_Core.lua       # Namespace PHNPC, constantes, OUTFIT_STATS, helpers
│   │   ├── PHNPC_Stats.lua      # initStats() + initInventory() par metier
│   │   └── Translate/
│   │       ├── EN/UI_PHNPC_EN.txt   # Traductions EN (format .txt, pré-B42.18)
│   │       ├── EN/UI.json           # Traductions EN (format JSON, B42.18+)
│   │       ├── FR/UI_PHNPC_FR.txt   # Traductions FR (format .txt, pré-B42.18)
│   │       └── FR/UI.json           # Traductions FR (format JSON, B42.18+)
│   └── client/
│       ├── PHNPC_Actions.lua    # Déplacement NPC (startMovingTo, stopMoving, startFollowing)
│       ├── PHNPC_Barks.lua      # Barks auto (BARK_KEYS, getRandomBark, sayBark)
│       ├── PHNPC_Combat.lua     # Combat auto vs zombies (npcCombatStep, npcFlightStep)
│       ├── PHNPC_Convert.lua    # Conversion zombie → NPC (convertToNPC)
│       ├── PHNPC_Debug.lua      # Menu DEBUG_PHNPC (dbgSpawnAtPlayer)
│       ├── PHNPC_Enforce.lua    # OnZombieUpdate + barks auto toutes 500 ticks
│       ├── PHNPC_Health.lua     # OnHitZombie → dégâts → mort NPC
│       ├── PHNPC_Inventory.lua  # Inventaire NPC (openNPCInventory)
│       ├── PHNPC_Manager.lua    # Spawn + registres (allNPCs, recruited, spawnNPC)
│       ├── PHNPC_Menu.lua       # Menu contextuel clic-droit
│       ├── PHNPC_Orders.lua     # Ordres joueur (recruit, follow, stay, dismiss, combat…)
│       └── PHNPC_Update.lua     # Boucle OnTick principale
├── common/media/
│   ├── anims_X/Zombie/          # Animations custom (copies depuis NHM)
│   │   ├── Bob_FrontKick.X      # Coup de pied avant
│   │   ├── Bob_HighKick.x       # Coup de pied haut
│   │   └── Bob_PushKick.X       # Coup de pied poussee
│   └── AnimSets/zombie/
│       ├── idle/ZSIdle.xml            # PHNPC_IsNPC=true -> Bob_Idle
│       ├── bumped/ZSWalkToIdle.xml    # PHNPC_IsNPC=true -> Bob_EmoteShrug rapide (SpeedScale=3.0)
│       ├── bumped/ZSIdleToWalk.xml    # PHNPC_IsNPC=true -> Bob_EmoteShrug rapide (SpeedScale=3.0)
│       ├── bumped/ZSStaggerBack.xml       # PHNPC_IsNPC=false -> Zombie_ShoveStagger_2m
│       ├── bumped/ZSNPCStaggerBack.xml    # PHNPC_IsNPC=true  -> Bob_RunStumble
│       ├── bumped/ZSFrontKick.xml
│       ├── bumped/ZSHighKick.xml
│       ├── bumped/ZSPainHead.xml
│       ├── bumped/ZSPainTorso.xml
│       ├── bumped/ZSShove.xml
│       ├── bumped/ZSWaveHi.xml     # m_Looped=true (interruptible via EarlyTransitionOut)
│       ├── bumped/ZSShrug.xml
│       ├── bumped/ZSYes.xml
│       └── bumped/ZSNo.xml
```

## Ordre de chargement

PZ charge les fichiers client par **ordre alphabétique** :

1. `shared/PHNPC_Core.lua` — namespace + OUTFIT_STATS
2. `shared/PHNPC_Stats.lua` — initStats / initInventory
3. `client/PHNPC_Actions.lua` — startMovingTo, stopMoving, startFollowing
4. `client/PHNPC_Barks.lua` — BARK_KEYS, getRandomBark, sayBark
5. `client/PHNPC_Combat.lua` — npcCombatStep, npcFlightStep
6. `client/PHNPC_Convert.lua` — convertToNPC
7. `client/PHNPC_Debug.lua` — dbgSpawnAtPlayer
8. `client/PHNPC_Enforce.lua` — OnZombieUpdate (enforceNPC), barks auto
9. `client/PHNPC_Health.lua` — OnHitZombie
10. `client/PHNPC_Inventory.lua` — openNPCInventory
11. `client/PHNPC_Manager.lua` — spawnNPC, registres
12. `client/PHNPC_Menu.lua` — menu contextuel
13. `client/PHNPC_Orders.lua` — ordres (recruit/follow/stay/dismiss…)
14. `client/PHNPC_Update.lua` — OnTick principal

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
        ├── npcFlightStep(npc, player)    [PHNPC_Combat.lua] -- fuite si HP < 30%
        ├── npcCombatStep(npc)            [PHNPC_Combat.lua] -- attaque zombie le plus proche
        └── State == "following"?
              ├── dist > FOLLOW_STOP_DISTANCE (3)? startFollowing() -> pathToLocationF
              └── non: stopMoving()
        -- "staying"   : pas de pathfind
        -- "defending" : géré par npcCombatStep
        -- "fleeing"   : géré par npcFlightStep

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
| PHNPC_State | string | "idle"/"following"/"staying"/"defending"/"fleeing" |
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
6. **pcall sur tout** — aucun crash possible même si API PZ change
7. **getText() lazy** — les clés de traduction sont stockées comme strings, `getText()` appelé à l'utilisation (après chargement des traductions)
