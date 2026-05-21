# Architecture B42 — Dynamic NPC Overhaul v0.0.8a

## Structure des fichiers

```
B42/
├── 42/media/lua/
│   ├── shared/
│   │   ├── PHNPC_Core.lua       # Namespace PHNPC, constantes, OUTFIT_STATS, helpers
│   │   └── PHNPC_Stats.lua      # initStats() + initInventory() par metier
│   └── client/
│       ├── PHNPC_Manager.lua    # Spawn, enforceNPC, follow/stay, menu contextuel  (v0.8)
│       ├── PHNPC_Health.lua     # OnHitZombie -> degats -> mort                    (v0.2)
│       └── PHNPC_Debug.lua      # Menu DEBUG_PHNPC
├── common/media/
│   ├── anims_X/Zombie/          # Animations custom (copies depuis NHM)
│   │   ├── Bob_FrontKick.X      # Coup de pied avant
│   │   ├── Bob_HighKick.x       # Coup de pied haut
│   │   └── Bob_PushKick.X       # Coup de pied poussee
│   └── AnimSets/zombie/
│       ├── idle/ZSIdle.xml      # Condition: PHNPC_IsNPC=true -> Bob_Idle
│       ├── bumped/ZSWalkToIdle.xml      # PHNPC_IsNPC=true -> Bob_EmoteShrug rapide (SpeedScale=3.0)
│       ├── bumped/ZSIdleToWalk.xml      # PHNPC_IsNPC=true -> Bob_EmoteShrug rapide (SpeedScale=3.0)
│       ├── bumped/ZSFrontKick.xml
│       ├── bumped/ZSHighKick.xml
│       ├── bumped/ZSPainHead.xml
│       ├── bumped/ZSPainTorso.xml
│       ├── bumped/ZSNPCPushedBack.xml
│       ├── bumped/ZSShove.xml
│       ├── bumped/ZSWaveHi.xml
│       ├── bumped/ZSShrug.xml
│       ├── bumped/ZSYes.xml
│       └── bumped/ZSNo.xml
│       (+ nombreux autres XMLs pour animations avancees)
```

## Ordre de chargement

1. `shared/PHNPC_Core.lua` — namespace + OUTFIT_STATS
2. `shared/PHNPC_Stats.lua` — initStats / initInventory
3. `client/PHNPC_Health.lua` — Events.OnHitZombie
4. `client/PHNPC_Manager.lua` — spawn / enforce / menu
5. `client/PHNPC_Debug.lua` — debug menu

## Flux de creation d'un NPC

```
spawnNPC(square)
  └── addZombiesInOutfit(x,y,z,1,outfit,femaleChance)
        └── convertToNPC(zombie, outfit, isFemale, npcName)
              ├── [1-14] Config base (setNoTeeth, setWalkType, variables animset, voix, etc.)
              ├── PHNPC.allNPCs[zombie] = true
              ├── PHNPC.initStats(zombie, outfit, isFemale)   -- speed, HP, stats
              └── PHNPC.initInventory(zombie, outfit)         -- poids max, items
```

## Flux tick NPC

```
Events.OnZombieUpdate (chaque tick)
  └── enforceNPC(zombie)
        ├── setUseless(false)
        ├── setVariable("PHNPC_IsNPC", true)  -- active nos AnimSets
        ├── setWalkType("Walk")
        ├── setFemaleEtc(isFemale)
        ├── setSpeedMod(md.PHNPC_SpeedMod)    -- vitesse selon metier
        ├── Gestion etats: pathfind/bumped/hitreaction/lunge/...
        ├── setTarget(nil) si pas en skipSecurity
        └── setUseless(true) si non-recrute

Events.OnTick (chaque trame)
  └── [NPCs recruited]
        ├── npcFlightStep(npc, player)    -- fuite si HP < 30%
        ├── npcCombatStep(npc)            -- attaque zombie le plus proche
        └── State == "following"?
              ├── dist > FOLLOW_DISTANCE? startFollowing() -> pathToCharacter
              └── non: stopMoving()
        -- "staying"   : setUseless(false), pas de pathfind
        -- "defending" : gere par npcCombatStep
        -- "fleeing"   : gere par npcFlightStep

Events.OnHitZombie (quand joueur frappe)
  └── PHNPC.isNPC(zombie)?
        ├── Calcul degats (handWeapon:getMaxDamage * 15)
        ├── md.PHNPC_Health -= damage
        ├── zombie:setHealth(10000)  -- prevent vanilla death
        ├── setBumpType("PainHead" or "PainTorso")
        └── hp<=0?
              ├── md.PHNPC_IsNPC = nil      -- CRITIQUE: coupe OnZombieUpdate AVANT mort
              ├── retirer de allNPCs/recruited
              └── zombie:setHealth(0)       -- PZ cree corpse lootable avec tout l'inventaire
```

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
| PHNPC_Recruited | bool | Recrute ou non |
| PHNPC_State | string | "idle"/"following"/"staying"/"defending"/"fleeing" |
| PHNPC_Moving | bool | En deplacement |
| PHNPC_Health | number | PV actuels (systeme PHNPC) |
| PHNPC_MaxHealth | number | PV max |
| PHNPC_SpeedMod | number | Multiplicateur vitesse (lu par enforceNPC) |
| PHNPC_Strength | number | Force (0-10) |
| PHNPC_Female | bool | Sexe (Bob=male, Kate=female) |
| PHNPC_Outfit | string | Metier |
| PHNPC_Name | string | Nom |
| PHNPC_HitTicks | number | Compteur ticks hitreaction |
| PHNPC_ShowTimer | number | Delai apres spawn (ignore enforce) |
| PHNPC_CombatMode | string | "auto" (combat actif) ou "off" (combat desactive) |
| PHNPC_PrevState | string | Etat sauvegarde avant combat/fuite |
| PHNPC_BarkTick | number | Compteur pour barks auto (reset a BARK_TICK_RATE) |
| PHNPC_AttackCooldown | number | Ticks restants avant prochain attack melee |

## Variable AnimSet critiques (setVariable)

| Variable | Valeur | Role |
|----------|--------|------|
| PHNPC_IsNPC | true | Active ZSIdle, ZSWalk, ZSNPCPushedBack, etc. |
| NoLungeTarget | true | Desactive lunge vers cible |
| ZombieHitReaction | "Chainsaw" | Animation de hit reaction humaine |
| WalkSpeed | float | Vitesse de marche animation |
| RunSpeed | float | Vitesse de course animation |

## Principes architecturaux

1. **Ne jamais interrompre pathfind** — setTarget(nil) tue le pathfind (pattern NHM)
2. **enforceNPC = idempotent** — peut etre appele chaque tick sans effet de bord
3. **setUseless(false) avant setBumpType** — requis pour animations haute priorite (FrontKick, Shove)
4. **BumpAnimFinished** — tous les bumped XMLs ont cet event a End -> retour idle auto
5. **setHealth(10000)** — empeche mort vanilla; mort geree via md.PHNPC_Health
6. **pcall sur tout** — aucun crash possible meme si API PZ change
