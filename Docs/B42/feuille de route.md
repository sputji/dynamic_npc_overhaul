# Dynamic NPC Overhaul — Feuille de route B42

> Mise a jour : 25 mai 2026 | Version **0.1** | Base minimale fonctionnelle — spawn, follow/stay. Rewrite NPC_Helper_Mod EXACT.

---

## Historique des versions

| Version | Date | Resume |
|---------|------|---------|
| 1.x–2.2.0 | 20–21 mai 2026 | Versions iteratives : stats, combat, peur, inventaire. NPCs avaient animations zombie, mordaient le joueur, devenaient invisibles quand frappes. |
| **0.1** | **25 mai 2026** | **Rewrite TOTAL** base NPC_Helper_Mod EXACT. Suppression de tous les anciens fichiers Lua. 2 fichiers seulement. Spawn + follow/stay fonctionnel. Problemes resolus. |

---

## Resultats de test v0.1 (confirmes)

| Fonctionnalite | Statut |
|----------------|--------|
| Spawn NPC (clic droit) | ✅ v0.1 |
| NPC se deplace (follow) | ✅ v0.1 |
| NPC suit le joueur | ✅ v0.1 |
| NPC reste en place (stay) | ✅ v0.1 |
| NPC peut etre congedie | ✅ v0.1 |
| Animation marche Bob_Walk | ✅ v0.1 |
| Animation idle Bob_Idle | ✅ v0.1 |
| Voix humaine (prefix PHNPC) | ✅ v0.1 |
| NPC ne mord pas | ✅ v0.1 |
| NPC pas invisible quand frappe | ✅ v0.1 |
| Noms genres M/F | ✅ v0.1 |
| Sous-menus clic-droit | ✅ v0.1 |
| Supprimer NPC | ❌ v0.0.2 |
| Mode combat (tuer zombies) | ❌ futur (Phase 2.2) |
| Peur des zombies (fuite) | ❌ futur (Phase 2.2) |
| Inventaire (transfert) | ❌ futur (Phase 2.3) |
| Stats par outfit | ❌ futur (Phase 2.2) |
| Persistance (sauvegarde) | ❌ futur (Phase 3) |

---

## Root cause des échecs précédents

### IsoPlayer.new() (avant v1.0.0)
`IsoPlayer.new()` ne fonctionne qu'en `isDebugEnabled()`.  
**Solution** : `addZombiesInOutfit()` + Banditize (pattern NPC_Helper_Mod / Bandits).

### Animations zombie persistantes (v1.x–v2.2.x)
Variables `PHNPC_IsNPC` et `zombieWalkType` non re-appliquées à chaque tick.  
**Solution** : Re-appliquer dans `enforceNPC` à CHAQUE tick (pattern GCCoreEnforceMain EXACT).

### NPC mordait le joueur (v1.x–v2.2.x)
`setNoTeeth(true)` appliqué seulement dans convertToNPC, pas de facon inconditionnelle.  
**Solution** : `setNoTeeth(true)` INCONDITIONNEL en tete de `OnZombieUpdate` + `setUseless(true)` pour NPCs non-recrutes.

### NPC invisible apres un coup (v1.x–v2.2.x)
Pas de handler pour l'etat `hitreaction`. Le NPC entrait en `isDead`/fakeDead.  
**Solution** : Compteur 25 ticks dans `hitreaction` + revive dans `OnZombieUpdate` (pattern GCUpdate EXACT).

---

## Architecture actuelle v0.1

### Fichiers Lua

| Fichier | Chemin | Role |
|---------|--------|------|
| `PHNPC_Core.lua` | `42/media/lua/shared/` | Namespace global `PHNPC`, constantes, `isNPC()` |
| `PHNPC_Manager.lua` | `42/media/lua/client/` | Toute la logique : spawn, enforceNPC, follow/stay, menu |

### Fichiers AnimSets (common/media/AnimSets/zombie/)

| Dossier | Fichier(s) | Animation | Condition |
|---------|-----------|-----------|-----------|
| `idle/` | ZSIdle.xml | Bob_Idle | PHNPC_IsNPC=true |
| `pathfind/` | ZSWalk.xml | Bob_Walk | zombieWalkType=Walk |
| `walktoward/` | ZSWalk.xml | Bob_Walk | zombieWalkType=Walk |
| `lunge/` | defaultlunge.xml | (override vanilla) | — |
| `bumped/` | ZS*.xml (180+) | Bob_* (Pain, Attack, Shove...) | BumpType=... |
| `attack/` | ZS*.xml | Bob_Attack* | BumpType=... |
| `hitreaction/` | ZSClimbWall*.xml | (override vanilla) | — |
| `thump/` | door.xml (exclu) + ZSdoor.xml | Bob_FrontKick | PHNPC_IsNPC=true + Door |

### PHNPC_Core.lua : constantes clés

```lua
PHNPC.FOLLOW_DISTANCE  = 3      -- tiles avant de commencer a suivre
PHNPC.FOLLOW_TICK_RATE = 20     -- ticks entre chaque pathToCharacter
PHNPC.INTERACTION_DIST = 3      -- rayon menu clic-droit (tiles)
PHNPC.OUTFITS = {"Farmer","Police","Fireman","Doctor","Ranger","Chef","Survivor"}
PHNPC.allNPCs   = {}            -- [npcRef] = true
PHNPC.recruited = {}            -- [npcRef] = true (suivent ou restent)
```

---

## Comportements implémentés v0.1

### Suivi joueur
- `pathToCharacter(player)` toutes les 20 ticks si dist > 3 tiles
- `IdleToWalk` / `WalkToIdle` transitions via `setBumpType`
- `enforceNPC` ne coupe JAMAIS le pathfind en cours (`skipSecurity=true` dans etat "pathfind")

### Ordres disponibles (v0.1)
| Ordre | Fonction | Effect |
|-------|----------|--------|
| Rejoins-moi ! | `recruitNPC` | PHNPC_Recruited=true, State=following |
| Suis-moi ! | `followNPC` | State=following |
| Reste ici. | `stayNPC` | State=staying, stopMoving |
| Tu peux partir. | `dismissNPC` | PHNPC_Recruited=false, State=idle |



---

## Prochaines étapes (par priorité)

### Phase 2.1 — Les sons, AnimSet vanilla et des mods exemples (NPC_Helper_Mod, Bandits, etc.)
- [ ] Sons de pas (events Footstep dans ZSWalk — déjà en XML, tester)
- [ ] Sons d'attaque (events Attack dans ZSAttack )
- [ ] Sons de réaction (events Pain dans ZSPain )
- [ ] Sons de bump (events Bump dans ZSBump )
- [ ] Sons d'ouverture porte (events Thump dans ZSdoor )
- [ ] Sons de transition (events Lunge dans ZSlunge )
- [ ] Sons de peur (bark de peur si zombie proche)
- [ ] Sons de colère (bark de colère si attaque ou découverte joueur)
- [ ] Sons de satisfaction (bark de satisfaction si découverte allié ou mort d'ennemi)
- [ ] Sons de confiance (bark de confiance si découverte allié)
- [ ] Sons de plainte (bark de plainte si blessure, maladie, fatigue, etc.)
- [ ] Sons de demande d'aide (bark de demande d'aide si blessure grave ou attaque)
- [ ] Sons de soulagement (bark de soulagement si guérison)
- [ ] Sons de mort (bark de mort)
- [ ] Sons de découverte (bark de découverte si joueur, allié, ennemi, zombie)
- [ ] Sons de faim/soif (bark de faim/soif si besoin urgent)
- [ ] Sons de fatigue (bark de fatigue si endurance basse)
- [ ] Sons de douleur (bark de douleur si coupé, brûlé, etc.)
- [ ] Sons de recolte (bark de recolte si cueille une plante ou fouille un container)
- [ ] Sons de tousse (PHNPC_IsCoughing=true, tousse si malade ou infecter, bark de plainte)
- [ ] Sons de dialogue (Say) selon l'état (peur, colère, satisfaction, etc.)
- [ ] Sons de commerce (bark de commerce si échange avec le joueur)
- [ ] Sons de quête (bark de quête si quête donnée ou complétée)
- [ ] Sons de transformation (bark de transformation si incubation de la morsure)
- [ ] Sons de maladie (bark de maladie si malade)
- [ ] Sons de guérison (bark de guérison si soigné)
- [ ] Sons de vieillissement (bark de vieillissement si vieux)
- [ ] Sons de reproduction (bark de reproduction si mort)
- [ ] Sons de mémoire (bark de mémoire si interaction passée avec le joueur ou un autre NPC)
- [ ] Sons de moralité (bark de moralité si choix moral du joueur)
- [ ] Sons de reputation (bark de reputation si interaction avec un allié ou un ennemi)
- [ ] Sons de faction (bark de faction si interaction avec un membre de faction)
- [ ] Sons de profession (bark de profession si interaction avec un membre de profession)
- [ ] Sons de patrouille (bark de patrouille si patrouille de zone)
- [ ] Sons de construction (bark de construction si construit une barricade ou un piège)
- [ ] Tous les sons et annimations possibles selon les états et les événements (deplacement, actions, réaction, peur, colère, satisfaction, découverte, attaque, blessure, maladie, guérison, vieillissement, reproduction, mémoire, moralité, reputation, faction, profession, patrouille, construction, etc.)
- [ ] Toutes les animations corespondantes aux sons et actions (deplacement, actions, réaction, peur, colère, satisfaction, découverte, attaque, blessure, maladie, guérison, vieillissement, reproduction, mémoire, moralité, reputation, faction, profession, patrouille, construction, etc.)

### Phase 2.2 — Qualité des interactions
- [ ] NPC peut transporter des items dans son inventaire natif (Ne fonctionne pas, inventaire vide, à investiguer)
- [ ] Dialogue basique (bark texte au-dessus de la tête selon état)
- [ ] Bark de dialogue (texte au-dessus de la tête selon état : peur, colère, satisfaction, etc.)
- [ ] Ordre "Va là-bas" (click droit sur une tuile cible)
- [ ] Ordre "recolte' (faire cueillir des plantes ou fouiller des containers, loot, etc.)
- [ ] NPC peut etre attaquer par des Zombies (doMeleeAttack) et réagir (hitreaction)
- [ ] NPC peut attaquer les Zombies (doMeleeAttack) et réagir (hitreaction)
- [ ] NPC peut demander de l'aide à un allié ou un ennemi (bark de demande d'aide, peut attaquer ou fuir selon le niveau de colère)

### Phase 2.3 — Qualité des interactions (loot)
- [ ] Fouille de bâtiments (loot)
- [ ] Système de loot (tables d'items par type de bâtiment)
- [ ] NPC peut ramasser des items au sol et les transporter dans son inventaire
- [ ] NPC peut utiliser des items de son inventaire (nourriture, médicaments, armes contondantes, armes à feu, etc.)
- [ ] NPC peut échanger des items avec le joueur (transfert via ISInventoryTransferUI)



### Phase 3 — Persistence
- [ ] Sauvegarder l'état des NPC à OnSave (ModData global)
- [ ] Recharger les NPC à OnGameStart depuis ModData

### Phase 4.1 — IA avancée
- [ ] Système de faction (pas d'attaque entre NPC alliés)
- [ ] Patrouille de zone (waypoints)
- [ ] Commerce (échange d'objets avec coût en ressources)
- [ ] Oorde "construire" (faire construire des barricades, pièges, etc.)


### Phase 4.2 — IA avancée (événements et réactions)
- [ ] Réaction à la météo (pluie → chercher un abrit couvert, bark de plainte)
- [ ] Réaction à la faim/soif (cherche nourriture/boisson dans l'inventaire ou loot de nouriture/boisson, consomme, bark)
- [ ] Réaction à la fatigue (ralentit, cherche un lit, dort)
- [ ] Réaction à la douleur (ralentit, bark de douleur, peut fuir ou attaquer selon le niveau de colere, peut se soigner avec des bandages ou médicaments ou demander de l'aide à un allié ou un ennemi)
- [ ] Réaction à la mort d'un allié (colere +3, bark de colère, peut attaquer ou fuir selon le niveau de colere)
- [ ] Réaction à la mort d'un ennemi (colere -2, bark de satisfaction)
- [ ] Réaction à l'attaque du joueur (colere +1, bark de colère, attaque le joueur)
- [ ] Réaction à la guérison (colere -2, bark de soulagement)
- [ ] Réaction à la découverte d'un zombie (peur +1, bark de peur, peut fuir ou attaquer selon le niveau de courage)
- [ ] Réaction à la découverte d'un allié (courage +1, bark de confiance)
- [ ] Réaction à la découverte d'un ennemi (colere +1, bark de colère)
- [ ] Réaction à la découverte d'un joueur (peur +1, =0 ou -1, bark de peur, peut fuir, rien fair ou attaquer selon le niveau de courage)
- [ ] Réaction à la découverte d'un joueur blessé (peur +2, bark de peur, peut fuir ou attaquer selon le niveau de courage)
- [ ] Système de commerce (acheter/vendre des items avec le joueur, coût en ressources)
- [ ] systeme de maladie (les NPC peuvent tomber malades, nécessitant des soins ou pouvant mourir)
- [ ] systeme de transformation (les NPC mordus peuvent se transformer en zombies après une période d'incubation, avec des symptômes progressifssifs)

### Phase 5 — Caractéristiques étendues
- [ ] Fatigue (endurance diminue à l'effort, récupération au repos)
- [ ] Faim/soif (consomme items de l'inventaire)
- [ ] Moral (courage évolue selon les événements)
- [ ] Historique (journal des actions du NPC)


### Phase 6 — Apprentissage et mémoire
- [ ] système de quêtes (génération de quêtes, suivi dans un journal, récompenses)
- [ ] apprentissage (NPC apprend de ses expériences, améliore ses stats ou compétences)
- [ ] creation de memoires (NPC se souvient des interactions passées avec le joueur et les autres NPC, influence les réactions futures)
- [ ] creation de metiers (PNJ avec des professions spécifiques, influençant leur comportement, leurs dialogues et leur commerce)
- [ ] creation de factions (groupes de PNJ avec des relations dynamiques entre eux et le joueur)

### Phase 7 — Cerveau avancé
- [ ] creation du cerveau inteligent pour les NPC.
- [ ] systeme de réputation (le joueur gagne ou perd de la réputation auprès des factions en fonction de ses actions, influençant les interactions futures)
- [ ] systeme de moralité (le joueur peut faire des choix moraux qui influencent la perception des NPC et les interactions futures)
- [ ] systeme de vieillissement (les NPC vieillissent avec le temps, affectant leurs stats et leur apparence)
- [ ] systeme de reproduction (les NPC peuvent se reproduire, créant de nouveaux NPC avec des traits hérités)
- [ ] systeme de mémoire persistante (les NPC se souviennent des interactions passées avec le joueur et les autres NPC, influençant les réactions futures même après une sauvegarde et un rechargement du jeu)
