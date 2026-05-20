# Dynamic NPC Overhaul — Feuille de route B42
> Mise à jour : 20 mai 2026 | Version 1.0.0 | Dernier commit : `dffaae8`

---

## État actuel (20 mai 2026)

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

### ✅ Terminé — AnimSets (animations humaines)

| Fichier | Rôle |
|---------|------|
| `42/media/AnimSets/zombie/idle/PHNPC_Idle.xml` | `PHNPC_IsNPC=BOOL true` → `Bob_Idle` |
| `42/media/AnimSets/zombie/walktoward/PHNPC_Walk.xml` | `PHNPC_IsNPC=BOOL true` + `zombieWalkType=STRING Walk` → `Bob_Walk` |
| `42/media/AnimSets/zombie/walktoward/PHNPC_Run.xml` | `PHNPC_IsNPC=BOOL true` + `zombieWalkType=STRING Run` → `Bob_Run` |
| `42/media/AnimSets/zombie/faceTarget/PHNPC_FaceTarget.xml` | `PHNPC_IsNPC=BOOL true` → face humaine |
| `common/media/AnimSets/zombie/idle/PHNPC_Idle.xml` | Copie garantie (chargement cross-version) |
| `common/media/AnimSets/zombie/walktoward/PHNPC_Walk.xml` | Copie garantie (chargement cross-version) |

### ✅ Terminé — Corps Serveur (`server/`)

| Fichier | État |
|---------|------|
| `server/00_Init.lua` | ✅ Opérationnel — enregistre le handler `PHNPC_SpawnRequest` |
| `server/NPC_SpawnManager.lua` | ✅ Fonctionnel — `addZombiesInOutfit` B42, noms aléatoires, professions, génération NPC data |

### ✅ Terminé — Corps Client (`client/`)

| Fichier | État |
|---------|------|
| `client/00_Init.lua` | ✅ Opérationnel — handler `PHNPC_SpawnConfirm`, `disableTieredUpdates` |
| `client/NPC_FollowTick.lua` | ✅ Fonctionnel — conversion zombie→NPC, visuals humains, suivi joueur, animations |
| `client/NPC_SpawnDebug.lua` | ✅ Fonctionnel — menu clic-droit spawn (visible avec `-debug` flag) |
| `client/NPC_InteractionClient.lua` | 🔶 Stub — détecte le NPC (contour bleu), log interaction, **dialogue non implémenté** |

---

## Prochaines étapes

### ✅ Étape 1 — Spawn d'un PNJ jouable *(TERMINÉ)*

- [x] `server/NPC_SpawnManager.lua` : spawn via `addZombiesInOutfit` (API B42 validée)
- [x] Noms générés : `NPC_Professions` + noms aléatoires Lua
- [x] Marquage cross-VM : `zombie:setVariable("PHNPC_IsNPC", true)` (Java, cross-VM)
- [x] `client/NPC_FollowTick.lua` : détection triple méthode (var Java / ModData / position pending)
- [x] Conversion zombie → NPC : `convertToNPC` (pattern Banditize B42)
- [x] Visuals humains : skin texture, hair model, hair color, nettoyage sang/saleté
- [x] AnimSets : `Bob_Idle` et `Bob_Walk` activés via variables AnimEngine
- [x] Menu spawn : visible en mode `-debug` (`isDebugEnabled()` B42)

### 🔶 Étape 2 — Interactions joueur *(en cours)*

Objectif : le joueur peut interagir avec le PNJ via une vraie fenêtre de dialogue.

- [x] Détection clic-droit sur NPC → option "Parler à [Nom]" (contour bleu OK)
- [ ] `client/NPC_InteractionClient.lua` : implémenter la fenêtre de dialogue (`ISModalRichTextPanel`)
- [ ] `client/UI/SpeechBubbles.lua` : bulles de dialogue 3D au-dessus du PNJ
- [ ] `client/UI/NPC_UI.lua` : fiche info PNJ (nom, métier, santé, humeur)

### Étape 3 — Commerce et FSM

- [ ] Connecter `NPC_Brain.lua` à l'entité : boucle FSM states sur `Events.OnTick`
- [ ] `client/UI/TradeWindow.lua` : fenêtre d'échange d'objets
- [ ] Compléter `server/NPC_NetworkServer.lua` : handlers client→serveur pour trade
- [ ] Tester les 7 états FSM : idle → wander → work → trade → defend → flee → guard

### Étape 4 — Systèmes avancés

- [ ] `server/OllamaBridge.lua` : bridge HTTP → Ollama (`HTTPRequest` B42 async)
- [ ] `client/UI/OllamaChatUI.lua` : fenêtre chat IA
- [ ] `server/NPC_BiteManagement.lua` : morsure cachée → transformation zombie
- [ ] `server/NPC_ObservationLearning.lua` : XP passif par observation du joueur
- [ ] `client/UI/QuestJournalUI.lua` : journal de quêtes (touche J)

### Étape 5 — Finitions et déploiement

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

> **AnimEngine B42** : Les fichiers XML AnimSet lisent les variables via `zombie:getVariableBoolean()`,  
> **pas** le ModData Lua. Toujours passer par `zombie:setVariable(name, value)` hors pcall.

> **`zombieWalkType`** : La condition `STRING Walk` dans PHNPC_Walk.xml exige que la variable  
> `zombieWalkType` soit envoyée à chaque déplacement via `zombie:setVariable("zombieWalkType", "Walk")`.

> **`zombie:setMaxHealth()` / `setHealth()`** : Ces méthodes n'existent pas sur `IsoZombie` en B42.  
> Un appel dans un `pcall()` Kahlua cause `Object tried to call nil in pcall` qui remonte et  
> crash la fonction parente à chaque tick si `_convertedNPCs[zombie]` n'est pas marqué avant.

> **`pcall` Kahlua** : Ne jamais mettre des appels critiques (`setVariable` AnimEngine) dans un pcall.  
> En solo B42, `pcall` peut avaler silencieusement une erreur sans que la variable soit écrite.

> **`getWorld():getGameMode()`** retourne `"Multiplayer"` même en solo B42.  
> Pour détecter le solo, utiliser `not isMultiplayer()` ou vérifier `isServer()` côté serveur.

```
PH_DynamicNPCOverhaul/
├── 42/           ← présence requise (même vide)
├── common/       ← OBLIGATOIRE — contient tout le Lua
│   └── media/lua/{shared,server,client}/
├── mod.info
└── preview.png
```