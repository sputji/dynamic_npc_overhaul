# Dynamic NPC Overhaul — Feuille de route B42
> Mise à jour : 19 mai 2026 | Version 1.0.0 | Dernier commit : `434c700`

---

## État actuel (mai 2026)

### ✅ Terminé — Fondations

| Élément | Détail |
|---------|--------|
| Structure mod B42 native | `common/media/lua/` + `42/` — détection PZ OK |
| `mod.info` | `versionMin=42.0`, `poster=poster.png`, `require=` absent — mod **VERT** (activable) ✅ |
| `sandbox-options.txt` | 17 options, format bloc, type=integer (pas d'enum) |
| `common/` + `42/` déployés | Sync vers `Zomboid/mods/` et dossier Steam |
| Script `tools/sync_to_mods.ps1` | Déploiement en un clic vers les deux destinations |
| Wiki PZ modding B42 | [Référence API](https://pzwiki.net/wiki/Build_42) |

### ✅ Terminé — Cerveau (`shared/`)

| Fichier | Rôle |
|---------|------|
| `00_Core.lua` | Namespace `PHNPC`, utilitaires, vérif version PZ |
| `NPC_Logger.lua` | Logger 7 niveaux, ring buffer 2000 entrées |
| `NPC_Config.lua` | Lecture `SandboxVars.PHNPC` + valeurs par défaut |
| `NPC_DataModel.lua` | Classe PNJ OO : stats, besoins, santé, économie |
| `NPC_Professions.lua` | 5 métiers avec FSM priorities et outfits B42 |
| `NPC_FactionManager.lua` | 4 factions, relations croisées −100/+100 |
| `NPC_Dialogue.lua` | Banques FR/EN, 11 contextes, fallback clés |
| `NPC_NetworkDispatcher.lua` | Réseau transparent Solo (mémoire) / Multi (commandes) |
| `NPC_Brain.lua` | FSM 7 états, boucle OnTick ~33 ms |
| `Translate/EN/ + FR/` | Sandbox, UI, ContextMenu, IGUI |

### 🔶 En cours — Squelette Corps

| Fichier | État |
|---------|------|
| `server/00_Init.lua` | Créé (squelette) |
| `server/NPC_SpawnManager.lua` | Créé (à compléter avec API B42) |
| `client/00_Init.lua` | Créé (squelette) |
| `client/NPC_FollowTick.lua` | Créé (à compléter) |
| `client/NPC_InteractionClient.lua` | Créé (squelette clic-droit) |
| `client/NPC_SpawnDebug.lua` | Créé (debug spawn) |

---

## Prochaines étapes

### Étape 1 — Spawn d'un PNJ jouable *(priorité haute)*

Objectif : faire spawner un PNJ visible en jeu, capable de marcher.

- [ ] Compléter `server/NPC_SpawnManager.lua` :
  - Étudier l'API de `NPC_Helper_Mod` et `Bandits` (mods exemples)
  - Utiliser `SurvivorFactory.CreateSurvivor()` + `dressInNamedOutfit()`
  - Marquer comme NPC : `iso:setNPC(true)`
  - Mouvement : `iso:pathToLocationF(x, y, z)` (**pas** `pathToCharacter` → ClassCastException)
- [ ] Valider en jeu : spawner une coquille vide, vérifier déplacement sans crash

### Étape 2 — Greffe du Cerveau

Objectif : connecter `NPC_Brain.lua` à l'entité spawnable.

- [ ] Associer un `NPC_DataModel` à chaque IsoPlayer NPC via `modData`
- [ ] Brancher la boucle FSM sur `Events.OnTick` (serveur)
- [ ] Tester les 7 états : idle → wander → work → trade → defend → flee → guard

### Étape 3 — Interactions client

Objectif : le joueur peut interagir avec le PNJ.

- [ ] Compléter `client/NPC_InteractionClient.lua` : menu clic-droit (`OnFillWorldObjectContextMenu`)
- [ ] Créer `client/UI/NPC_UI.lua` : fiche info PNJ (ISPanel)
- [ ] Créer `client/UI/SpeechBubbles.lua` : bulles de dialogue 3D

### Étape 4 — Commerce et dialogues

- [ ] Créer `client/UI/TradeWindow.lua` : fenêtre d'échange d'objets
- [ ] Compléter `server/NPC_NetworkServer.lua` : handlers commandes client→serveur
- [ ] Valider synchronisation Solo et Multijoueur

### Étape 5 — Systèmes avancés

- [ ] `server/OllamaBridge.lua` : bridge HTTP → Ollama (`HTTPRequest` B42 async)
- [ ] `client/UI/OllamaChatUI.lua` : fenêtre chat IA
- [ ] `server/NPC_BiteManagement.lua` : morsure cachée → transformation zombie
- [ ] `server/NPC_ObservationLearning.lua` : XP passif par observation du joueur
- [ ] `client/UI/QuestJournalUI.lua` : journal de quêtes (touche J)

### Étape 6 — Finitions et déploiement

- [ ] `server/AdminCommands.lua` : `/phnpc list/spawn/kill/debug/reload`
- [ ] Tests multijoueur (serveur dédié)
- [ ] Publication Workshop Steam
- [ ] Montée de version → `1.1.0`

---

## Rappel structure B42 (leçons apprises)

> En B42, le dossier **`common/`** est **obligatoire** pour que PZ détecte le mod.  
> Tout fichier Lua dans `media/lua/` à la **racine** est **ignoré** (structure B41 uniquement).

> **`require=` vide** dans mod.info → PZ interprète comme « dépendance ID vide » → **mod rouge**.  
> Toujours **supprimer la ligne** si aucune dépendance.

> **`versionMin`** doit être au format `build.major` (ex : `42.0`).  
> Valeur `42` seule (sans `.0`) n'est **pas reconnue**. Absent = comportement indéfini.

```
PH_DynamicNPCOverhaul/
├── 42/           ← présence requise (même vide)
├── common/       ← OBLIGATOIRE — contient tout le Lua
│   └── media/lua/{shared,server,client}/
├── mod.info
└── preview.png
```