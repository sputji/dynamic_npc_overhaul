# Dynamic NPC Overhaul — Feuille de route B42

> Mise a jour : 21 mai 2026 | Version **2.2.0** | Combat NPC manuel + traductions FR + inventaire

---

## Historique des versions

| Version | Date | Resume |
|---------|------|---------|
| 1.x | mars 2026 | Fondations, structure B42, IsoPlayer.new (ne fonctionnait pas) |
| 1.0.0 | 20 mai 2026 | Base fonctionnelle : addZombiesInOutfit + Banditize, spawn ok |
| 1.0.1 | 20 mai 2026 | Fix AnimSets noms (ZSIdle/ZSWalk), menu double supprime |
| 1.1.0 | 20 mai 2026 | setUseless(false) en premier, voix NotAZombie, NPC ne mord plus |
| 1.2.0 | 21 mai 2026 | AnimSets complets NPC_Helper_Mod copies dans pathfind/, setSpeedMod, zombieWalkType re-set |
| **2.0.0** | **21 mai 2026** | **1er NPC FONCTIONNEL** : se deplace, suit le joueur. Stats, noms genres, combat, peur zombies, inventaire, sous-menus |
| **2.1.0** | **21 mai 2026** | Fix menu crash, vitesse NPC, systeme colere 4 niveaux, 4 AnimSets bumped, traductions JSON (PHNPC.json) |
| **2.2.0** | **21 mai 2026** | **Fix 5 bugs in-game** : traductions FR (UI.json), combat manuel (faceLocationF+setBumpType+knockDown), npc:Say() remplace HaloTextHelper, inventaire via OnRefreshInventoryWindowContainers, suppression punch anim avant marche |

---

## Resultats de test v2.2.0 (attendus)

| Fonctionnalite | Statut |
|----------------|--------|
| Spawn NPC (clic droit) | ✅ |
| NPC se deplace | ✅ |
| NPC suit le joueur | ✅ |
| Animation marche Bob_Walk | ✅ |
| Animation idle Bob_Idle | ✅ |
| Voix humaine (NotAZombie) | ✅ |
| NPC ne mord pas | ✅ |
| Noms genres M/F | ✅ |
| Stats par outfit | ✅ |
| Menus en FRANCAIS | ✅ fix v2.2 (UI.json) |
| Mode combat (tuer zombies) | ✅ fix v2.2 (combat manuel) |
| NPC attaque zombies | ✅ fix v2.2 (doMeleeAttack) |
| Peur des zombies (fuite) | ✅ |
| Inventaire (transfert) | ✅ fix v2.2 (OnRefreshInventoryWindowContainers) |
| Stats affichees (Say) | ✅ fix v2.2 (npc:Say) |
| Sous-menus clic-droit | ✅ |
| Animation lunge (Bob_Walk) | ✅ |
| Ouverture porte (Bob_FrontKick) | ✅ |
| Colere 4 niveaux | ✅ |
| Dialogue colere (Say) | ✅ fix v2.2 |
| Pas de punch anim avant marche | ✅ fix v2.2 |
| NPC attaque joueur (colere niv 4) | ✅ |
| AnimSets bumped 4 types | ✅ v2.1 (ZSNPCBite, ZSNPCBiteLow, ZSNPCPushedBack, ZSNPCPushedFront) |

---

## Root cause des échecs précédents

### IsoPlayer.new() (avant v1.0.0)
`IsoPlayer.new()` ne fonctionne qu'en `isDebugEnabled()`.  
**Solution** : `addZombiesInOutfit()` + Banditize (pattern NPC_Helper_Mod / Bandits).

### AnimSets dans le mauvais dossier (avant v1.2.0)
`ZSWalk.xml` était dans `walktoward/` seulement.  
`pathToLocationF()` = état `pathfind` = lit `zombie/pathfind/`.  
**Solution** : Copier dans `pathfind/` (identique à NPC_Helper_Mod).

### setSpeedMod manquant (avant v1.2.0)
Sans `setSpeedMod(1.0)`, le NPC pouvait avoir vitesse 0 → immobile.  
**Solution** : Ajouté dans `npcStartMoving` + `enforceNPC` + Banditize.

---

## Architecture actuelle v2.0.0

### Fichiers Lua

| Fichier | Role |
|---------|------|
| `shared/PHNPC_Core.lua` | Namespace global `PHNPC`, VERSION |
| `shared/PHNPC_Stats.lua` | Noms genrés M/F, profils stats par outfit, PHNPC.generateName/generateStats/statsToString |
| `client/PHNPC_Manager.lua` | Toute la logique client : spawn, pathfinding, enforceNPC, menu, peur, combat |
| `server/PHNPC_Server.lua` | Stub serveur (prêt pour futur multi) |

### Fichiers AnimSets (zombie/)

| Dossier | Fichier(s) | Animation | Condition |
|---------|-----------|-----------|-----------|
| `idle/` | ZSIdle.xml | Bob_Idle | PHNPC_IsNPC=true |
| `pathfind/` | ZSWalk.xml | Bob_Walk | zombieWalkType=Walk |
| `pathfind/` | ZSRun.xml | Bob_Run | zombieWalkType=Run |
| `pathfind/` | ZSSneakWalk.xml | Bob_WalkSneak | zombieWalkType=SneakWalk |
| `walktoward/` | ZSWalk.xml | Bob_Walk | zombieWalkType=Walk (idem) |
| `lunge/` | ZSlunge.xml | Bob_Walk | PHNPC_IsNPC=true |
| `thump/` | ZSdoor.xml | Bob_FrontKick | PHNPC_IsNPC=true + Door |
| `bumped/` | ZSBump*.xml | Bob_Push* | PHNPC_IsNPC=true + BumpType |
| `attack/` | ZSAttack*.xml | Bob_Attack* | PHNPC_IsNPC=true |
| `hitreaction/` | ZSPain*.xml | Bob_Pain* | PHNPC_IsNPC=true |

### Système de stats (PHNPC_Stats.lua)

Stats générées aléatoirement selon l'outfit au spawn :
- **courage** : résistance à la peur des zombies (0-100)
- **force** : dégâts mêlée + capacité transport (0-100)
- **melee** : compétence corps à corps (0-100)
- **tir** : compétence armes à feu (0-100)
- **endurance** : résistance fatigue, vitesse (0-100)

Profils : Police > tir/courage | Fireman > force/endurance | Doctor < tout | Ranger > tir | etc.

---

## Comportements implémentés v2.0.0

### Suivi joueur
- `pathToLocationF(px, py, pz)` toutes les 15 ticks si dist > 3 tiles
- `WalkToIdle` / `IdleToWalk` transitions via `setBumpType`
- `enforceNPC` ne coupe pas le pathfind en cours

### Peur des zombies
- Check toutes les 30 ticks
- Si `courage < 50` ET zombie à moins de 10 tiles → fuite (direction opposée, 15 tiles)
- Désactivé si mode combat actif

### Mode combat
- Activation/désactivation via menu clic-droit
- Cherche le zombie le plus proche (< 15 tiles)
- Se déplace vers la cible → `NPCSetAttack()` si < 5 tiles
- `enforceNPC` laisse passer l'état "attack" si mode combat actif

### Inventaire
- Clic-droit → "Voir l'inventaire" → `ISInventoryTransferUI.transferBetween(player, npc)`
- NPC peut transporter des items dans son inventaire natif

---

## Prochaines étapes (par priorité)

### Phase 2.1 — Les sons et animations
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
