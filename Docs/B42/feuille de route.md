# Dynamic NPC Overhaul — Feuille de route B42
> Mise a jour : 22 mai 2026 | Version **3.0.0** | Refonte complete from scratch
| Wiki PZ modding B42 | [Référence API](https://pzwiki.net) |
---

## Historique des versions

| Version | Date | Resume |
|---------|------|--------|
| 1.x | mars 2026 | Fondations, structure B42 |
| 2.x | mai 2026 | Cerveau FSM, NetworkDispatcher — NPC jamais spawne en jeu |
| **3.0.0** | **22 mai 2026** | **Refonte complete : pattern Custom NPC mod, IsoPlayer direct client-side** |

---

## Root cause des versions 1.x / 2.x

Le `NPC_NetworkDispatcher` pensait etre en MULTI meme en solo (a cause de `getServerOptions()`).
`Dispatcher.send("all", "PHNPC_DoSpawn")` appelait `getOnlinePlayers()` (vide en solo).
`PHNPC_DoSpawn` n'arrivait jamais au client → aucun NPC cree.

**Solution v3** : Supprimer le dispatcher. Creation directe `IsoPlayer.new()` cote client.

---

## v3.0.0 — Architecture finale (22 mai 2026)

### Fichiers actifs

| Fichier | Role |
|---------|------|
| `shared/PHNPC_Core.lua` | Namespace global `PHNPC`, `VERSION = "3.0.0"` |
| `client/PHNPC_Manager.lua` | TOUTE la logique : spawn, pathfinding, menu |
| `server/PHNPC_Server.lua` | Stub serveur (vide, futur multi) |

### Ce qui fonctionne en v3.0.0

- [x] Clic-droit sol → spawn NPC (`IsoPlayer.new()` exact pattern Custom NPC)
- [x] NPC visible avec animations humaines (SurvivorFactory + Bob skeleton)
- [x] NPC suit le joueur (`getPathFindBehavior2():pathToLocation()` chaque N ticks)
- [x] Clic-droit NPC → "Suis-moi" / "Reste ici" / "Supprimer"
- [x] Nettoyage automatique des NPC morts
- [x] Limite MAX_NPCS = 10

---

## Prochaines etapes (par priorite)

### Phase 1 — Stabilisation (a tester en jeu)
- [ ] Verifier IsoPlayer.new() visible et non-hostile
- [ ] Verifier pathfinding (NPC suit vraiment le joueur)
- [ ] Verifier context menu (clic-droit fonctionne)
- [ ] Consigner les erreurs console.txt

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

- `IsoPlayer.new(cell, desc, x, y, z)` = seule methode pour animations humaines en B42
- `npc:setNPC(true)` = OBLIGATOIRE (sinon traite comme joueur)
- `npc:getPathFindBehavior2():pathToLocation(x,y,z)` = mouvement NPC
- `npc:getPathFindBehavior2():update()` = appel OBLIGATOIRE chaque tick
- `getGameMode()` retourne "Sandbox" (solo) ou "Multiplayer" (multi)
- Pas de BOM UTF-8, pas de `goto`, pas de `next()`, pas de `obj:method and ...`
