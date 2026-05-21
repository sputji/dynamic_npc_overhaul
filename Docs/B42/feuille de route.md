# Dynamic NPC Overhaul — Feuille de route B42

> Mise a jour : 21 mai 2026 | Version **0.0.5** | Stats, inventaire, sante, FrontKick, distance follow.

---

## Historique des versions

| Version | Date | Resume |
|---------|------|---------|
| v0.0.5 | 21/05/2026 | Stats + inventaire par metier, sante (OnHitZombie), FrontKick corrige (Bob_FrontKick.X manquant), FOLLOW_DISTANCE 3→5, HighKick ajoute, dbgAnim avec setUseless(false)+changeState. |
| v0.0.4 | 26/05/2026 | Sons de pas (VoicePrefix genre-based), stopMoving fix (setTarget+clearAggroList), BumpType ZombiePushedBack, ForceHitReaction crash fixe. |
| v0.0.3 | 21/05/2026 | Corrections callbacks (_, player) -> (player), setVariable zombieWalkType supprime, setFemaleEtc ajoute. |
| v0.0.2 | 21/05/2026 | Menu DEBUG_PHNPC complet + delete NPC. |
| v0.1 | 25/05/2026 | Rewrite TOTAL base NPC_Helper_Mod EXACT. Spawn + follow/stay fonctionnel. |

---

## Architecture v0.0.5

### Fichiers Lua

| Fichier | Role |
|---------|------|
| `shared/PHNPC_Core.lua` | Namespace PHNPC, constantes, OUTFIT_STATS, noms, helpers |
| `shared/PHNPC_Stats.lua` | initStats() + initInventory() par metier |
| `client/PHNPC_Manager.lua` | Spawn, enforceNPC, follow/stay, menu contextuel |
| `client/PHNPC_Health.lua` | OnHitZombie -> degats -> animations douleur -> mort |
| `client/PHNPC_Debug.lua` | Menu DEBUG_PHNPC (animations, etat, spawn debug) |

### Fichiers AnimSet / AnimX cles

| Fichier | BumpType | Animation |
|---------|----------|-----------|
| `bumped/ZSFrontKick.xml` | `FrontKick` | Bob_FrontKick.X (**custom NHM**) |
| `bumped/ZSHighKick.xml` | `HighKick` | Bob_HighKick.x (**custom NHM**) |
| `bumped/ZSWalkToIdle.xml` | `WalkToIdle` | Bob_WalkToStop |
| `bumped/ZSIdleToWalk.xml` | `IdleToWalk` | Bob_IdleToWalk |
| `bumped/ZSPainHead.xml` | `PainHead` | Bob_EmotePainHead |
| `bumped/ZSPainTorso.xml` | `PainTorso` | Bob_EmotePainTorso |
| `bumped/ZSNPCPushedBack.xml` | `ZombiePushedBack` | Bob_Strafe_Left |
| `idle/ZSIdle.xml` | - (condition PHNPC_IsNPC) | Bob_Idle |

---

## Resultats de test

| Fonctionnalite | Statut |
|----------------|--------|
| Spawn NPC (clic droit) | ✅ v0.1 |
| NPC suit le joueur | ✅ v0.1 |
| NPC reste en place (stay) | ✅ v0.1 |
| Animation marche Bob_Walk/Kate_Walk | ✅ v0.1 |
| Animation idle Bob_Idle/Kate_Idle | ✅ v0.0.3 |
| Sons de pas (footsteps) | ✅ v0.0.4 |
| Voix zombie supprimees (humain silencieux) | ✅ v0.0.4 |
| Transitions WalkToIdle / IdleToWalk | ✅ v0.0.4 |
| Animation FrontKick | ✅ v0.0.5 (Bob_FrontKick.X copie depuis NHM) |
| Animation HighKick | ✅ v0.0.5 (Bob_HighKick.x copie depuis NHM) |
| Distance follow correcte (pas collant) | ✅ v0.0.5 (FOLLOW_DISTANCE 3->5) |
| NPC perd de la vie quand frappe | ✅ v0.0.5 (OnHitZombie + md.PHNPC_Health) |
| Animations douleur quand frappe | ✅ v0.0.5 (PainHead/PainTorso) |
| NPC meurt quand HP=0 | ✅ v0.0.5 |
| Stats par metier (vitesse, force, HP) | ✅ v0.0.5 (OUTFIT_STATS) |
| Inventaire avec poids max | ✅ v0.0.5 (initInventory) |
| Items de depart selon metier | ✅ v0.0.5 |
| Mode combat (tuer zombies) | ❌ futur (Phase 2.2) |
| Peur des zombies (fuite) | ❌ futur (Phase 2.2) |
| Dialogue/echanges | ❌ futur (Phase 3) |
| Persistance (sauvegarde) | ❌ futur (Phase 3) |

---

## Stats par metier (OUTFIT_STATS)

| Metier | Speed | HP | Poids max | Items depart |
|--------|-------|----|-----------|--------------|
| Farmer | 0.75 | 90 | 15 kg | Shovel, Trowel |
| Police | 0.85 | 110 | 20 kg | PoliceBaton, HandTorch |
| Fireman | 0.80 | 120 | 25 kg | Axe |
| Doctor | 0.78 | 100 | 15 kg | BandageDirty, Painkillers |
| Ranger | 0.90 | 105 | 18 kg | HuntingKnife, HandTorch |
| Chef | 0.75 | 90 | 15 kg | KitchenKnife, CanOpener |
| Survivor | 0.80 | 100 | 18 kg | Crowbar |

---

## Prochaines etapes (v0.0.6+)

- [ ] Systeme de combat NPC (attaquer zombies en defend mode)
- [ ] Comportement de fuite quand en danger
- [ ] Dialogue contextuel (PNJ donne infos sur la zone)
- [ ] Persistance (sauvegarder etat NPC entre sessions)
- [ ] GroupeIA (plusieurs NPCs recrutes coordonnent)
