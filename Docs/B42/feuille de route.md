# Dynamic NPC Overhaul — Feuille de route B42

> Mise a jour : 20 mai 2026 | Version **1.0.1** | AnimSets corriges, menu double fixe

---

## Historique des versions

| Version | Date | Resume |
|---------|------|--------|
| 1.x | mars 2026 | Fondations, structure B42 |
| 2.x | mai 2026 | Cerveau FSM, NetworkDispatcher — NPC jamais spawne en jeu |
| 1.0.0 | 20 mai 2026 | Base NPC fonctionnelle : addZombiesInOutfit + Banditize (remplacement IsoPlayer.new) |
| **1.0.1** | **20 mai 2026** | **Fix : AnimSets ZSIdle/ZSWalk (noms corrects), menu clic-droit en double supprime** |

---

## Root cause des echecs precedents

### IsoPlayer.new() (< v1.0.0)
`IsoPlayer.new()` ne fonctionne qu'en `isDebugEnabled()` (Custom NPC). Hors debug = rien.
**Solution v1.0.0** : `addZombiesInOutfit()` + Banditize (pattern NPC_Helper_Mod / Bandits).

### AnimSets mal nommees (< v1.0.1)
Fichiers `PHNPC_Idle.xml` / `PHNPC_Walk.xml` avec `m_Name = PHNPC_Idle/PHNPC_Walk`.
La state machine zombie ne connait que `ZSIdle` / `ZSWalk` — les custom m_Name ne sont jamais selectionnes.
**Solution v1.0.1** : Fichiers renommes `ZSIdle.xml` / `ZSWalk.xml` avec `m_Name` corrects.

### Menu en double (< v1.0.1)
`Events.OnPreFillWorldObjectContextMenu.Add(onContextMenu)` enregistre deux fois dans le code.
**Solution v1.0.1** : Doublons supprimes.

---

## v1.0.1 — Architecture (20 mai 2026)

### Fichiers actifs

| Fichier | Role |
|---------|------|
| `shared/PHNPC_Core.lua` | Namespace global `PHNPC`, `VERSION = "1.0.0"` |
| `client/PHNPC_Manager.lua` | TOUTE la logique : spawn, pathfinding, menu |
| `server/PHNPC_Server.lua` | Stub serveur (vide, futur multi) |
| `42/media/AnimSets/zombie/idle/ZSIdle.xml` | Bob_Idle si `PHNPC_IsNPC = true` |
| `42/media/AnimSets/zombie/walktoward/ZSWalk.xml` | Bob_Walk si `zombieWalkType = Walk` |

### Ce qui fonctionne en v1.0.1

- [x] Clic-droit sol → spawn NPC (`addZombiesInOutfit` + Banditize)
- [x] NPC visible avec animations humaines Bob/Kate (ZSIdle.xml / ZSWalk.xml)
- [x] NPC suit le joueur (`pathToLocationF` + `setBumpType` transitions)
- [x] Clic-droit NPC → "Suis-moi" / "Reste ici" / "Supprimer"
- [x] Nettoyage automatique des NPC morts (cleanup tous les 300 ticks)
- [x] Limite MAX_NPCS = 10
- [x] Menu clic-droit unique (plus de doublon d'inscription event)

### Comportement connu (by design)
- Les NPC sont des `IsoZombie` banditises. Ils se defendent si frappes/pousses.
  C'est le comportement normal des NPCs zombie-based en B42 (Bandits, NPC_Helper_Mod).
  Version future : systeme d'equipe (faction) pour NPC passifs.

---

## Prochaines etapes (par priorite)

### Phase 1 — Stabilisation ✅ (v1.0.1)
- [x] Spawn NPC visible (addZombiesInOutfit + Banditize)
- [x] Animations humaines (ZSIdle.xml / ZSWalk.xml corriges)
- [x] Menu clic-droit unique
- [x] Pathfinding (pathToLocationF + setBumpType)
- [ ] Tester suivi continu en jeu (NPC suit vraiment sur la duree)
- [ ] Tester suppression NPC (removeFromWorld)

### Phase 1b — Comportement defensif (futur)
- [ ] NPC passif (ne se defend pas si frappe) : systeme de faction / equipe
- [ ] setCurrentBehavior("idle") apres chaque tick pour bloquer l'IA de combat

### Phase 2 — Persistence
- [ ] Sauvegarder les NPC actifs via ModData a OnSave
- [ ] Recharger les NPC a OnGameStart depuis ModData
- [ ] Gerer la mort/suppression persistante

### Phase 3 — Comportement
- [ ] Dialogue simple (bulle de parole OnRenderTick)
- [ ] Detection zombies proches → etat alerte
- [ ] Fuite si menace (npc:runTo(safeSquare))

### Phase 4 — Multijoueur
- [ ] Sync spawn via sendModData / onServerCommand
- [ ] Etendre PHNPC_Server.lua
- [ ] Tester en coop LAN

---

## Notes techniques cles (B42 / Kahlua)

- `addZombiesInOutfit(x, y, z, count, outfit, femaleChance)` = seule methode viable pour NPC humains B42
- `IsoPlayer.new()` = NE FONCTIONNE PAS hors isDebugEnabled() — ne pas utiliser
- `npc:setVariable("PHNPC_IsNPC", true)` = active ZSIdle.xml condition (Bob_Idle)
- `npc:setWalkType("Walk")` + `setVariable("zombieWalkType", "Walk")` = active ZSWalk.xml (Bob_Walk)
- `npc:pathToLocationF(x, y, z)` = mouvement IsoZombie (PAS getPathFindBehavior2)
- `npc:setUseless(false)` = OBLIGATOIRE avant pathToLocationF (sinon NPC immobile)
- `setBumpType("IdleToWalk")` / `setBumpType("WalkToIdle")` = transitions animation
- `setVariable("ZombieHitReaction", "Chainsaw")` = previent crash testDefense sur hit
- AnimSets : le m_Name DOIT etre `ZSIdle` / `ZSWalk` (noms connus de la state machine)
- Pas de BOM UTF-8, pas de `goto`, pas de `next()`, pas de `obj:method and ...`
