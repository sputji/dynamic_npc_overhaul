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

### Phase 2 — Qualité des interactions
- [ ] Sons de pas (events Footstep dans ZSWalk — déjà en XML, tester)
- [ ] NPC peut ramasser des armes au sol et les équiper
- [ ] Dialogue basique (bark texte au-dessus de la tête selon état)
- [ ] Ordre "Va là-bas" (click droit sur une tuile cible)

### Phase 3 — Persistence
- [ ] Sauvegarder l'état des NPC à OnSave (ModData global)
- [ ] Recharger les NPC à OnGameStart depuis ModData

### Phase 4 — IA avancée
- [ ] Système de faction (pas d'attaque entre NPC alliés)
- [ ] Patrouille de zone (waypoints)
- [ ] Fouille de bâtiments (loot)
- [ ] Commerce (échange d'objets avec coût en ressources)

### Phase 5 — Caractéristiques étendues
- [ ] Fatigue (endurance diminue à l'effort, récupération au repos)
- [ ] Faim/soif (consomme items de l'inventaire)
- [ ] Moral (courage évolue selon les événements)
- [ ] Historique (journal des actions du NPC)
