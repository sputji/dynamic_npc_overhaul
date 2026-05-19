# Dynamic NPC Overhaul — Architecture B42
> Version 2.0.0 | Project Zomboid Build 42 | Auteur : sputji

---

## Vue d'ensemble

Le mod **Dynamic NPC Overhaul** ajoute à Project Zomboid des PNJ vivants, dotés d'une IA contextuelle, d'un système de commerce, de quêtes, de factions et d'une mémoire persistante. Il est conçu pour fonctionner en solo et en multijoueur de manière transparente.

L'architecture suit le principe **"namespace global + modules auto-enregistrés"** : un seul objet Lua `PHNPC` est partagé entre tous les fichiers, et chaque module s'y enregistre via `PHNPC.registerModule(name, tbl)`.

---

## Arborescence complète

> Structure vérifiée et alignée sur les mods de référence B42 :
> `NPC_Helper_Mod`, `Bandits`, `DynamicTradingV2`, `7 - Custom NPC`, `ssr_core`

```
D:\PZ Mods\Dynamic_NPC_Overhaul\
│
├── .gitignore                          # Exclusions Git (B41/, mod example/, *.log…)
│
├── Docs\
│   └── B42\
│       └── ARCHITECTURE.md             # Ce fichier
│
└── B42\                                # Dossier du mod chargé par PZ B42
    │
    ├── mod.info                        # Métadonnées : id, name, version, targetVersion, category…
    ├── poster.png                      # Icône affichée dans le lanceur PZ
    ├── icon.png                        # Miniature dans la liste des mods
    │
    ├── 42\                             # Réservé aux assets spécifiques B42 (futur)
    ├── common\                         # Réservé aux assets multi-version (futur)
    │
    └── media\
        ├── sandbox-options.txt         # Déclaration des options Sandbox PZ (format bloc)
        │
        └── lua\
            │
            ├── shared\                 # Chargé côté CLIENT + SERVEUR
            │   ├── 00_Core.lua         # [1] Namespace PHNPC, registerModule(), utilitaires
            │   ├── NPC_Logger.lua      # [2] Logger TRACE/DEBUG/INFO/WARN/ERROR/FAIL
            │   ├── NPC_Config.lua      # [3] Lecture SandboxVars.PHNPC + valeurs par défaut
            │   ├── NPC_DataModel.lua   # [4] Classe PNJ OO : stats, sérialisation, besoins
            │   ├── NPC_Professions.lua # [5] Catalogue 5 métiers + outfits B42
            │   ├── NPC_FactionManager.lua  # [6] 4 factions, relations −100/+100
            │   ├── NPC_Dialogue.lua    # [7] Banques FR/EN + fallback Ollama keyword
            │   ├── NPC_NetworkDispatcher.lua # [8] Routage transparent Solo/Multi
            │   ├── NPC_Brain.lua       # [9] FSM 7 états, boucle ~33 ms (OnTick)
            │   │
            │   └── Translate\
            │       ├── EN\
            │       │   ├── Sandbox_EN.txt      # Labels options Sandbox (Sandbox_EN = {})
            │       │   ├── UI_EN.txt           # Titres fenêtres, boutons (UI_EN = {})
            │       │   ├── ContextMenu_EN.txt  # Entrées menu clic droit (ContextMenu_EN = {})
            │       │   └── IGUI_EN.txt         # Textes in-game, bulles, quêtes (IGUI_EN = {})
            │       └── FR\
            │           ├── Sandbox_FR.txt      # Labels options Sandbox en français
            │           ├── UI_FR.txt           # Titres et boutons en français
            │           ├── ContextMenu_FR.txt  # Menu clic droit en français
            │           └── IGUI_FR.txt         # Textes in-game en français
            │
            ├── server\                 # Chargé côté SERVEUR uniquement
            │   ├── 00_Init.lua         # Point d'entrée : démarre SpawnMgr, BiteMgr, ObsLearning
            │   ├── NPC_SpawnManager.lua    # Spawn/despawn IsoPlayer (API B42 native)
            │   ├── NPC_NetworkServer.lua   # Handlers commandes clients (talk, trade…)
            │   ├── NPC_BiteManagement.lua  # Progression morsure cachée → transformation zombie
            │   ├── NPC_ObservationLearning.lua # XP passif PNJ par observation du joueur
            │   ├── OllamaBridge.lua    # Bridge HTTP → Ollama API, cache LRU
            │   └── AdminCommands.lua   # Commandes admin /phnpc (list/spawn/kill/bite/debug)
            │
            └── client\                 # Chargé côté CLIENT uniquement
                ├── 00_Init.lua         # Réception événements serveur, registre clientNPCs
                ├── NPC_InteractionClient.lua  # Menu clic droit sur PNJ (Parler/Commercer/Examiner)
                │
                └── UI\
                    ├── NPC_UI.lua          # Panneau info PNJ (nom, métier, santé, morale, faction)
                    ├── SpeechBubbles.lua   # Bulles 3D TextDrawObject au-dessus des PNJ
                    ├── TradeWindow.lua     # Fenêtre de commerce PNJ ↔ Joueur
                    ├── OllamaChatUI.lua    # Interface chat IA (historique scrollable, async)
                    └── QuestJournalUI.lua  # Journal de quêtes (touche J, filtres Actives/Terminées)
```

---

## Description des modules

### `shared/` — Couche commune (client + serveur)

#### `00_Core.lua`
Point de départ absolu. Crée la table globale `PHNPC` avec :
- `PHNPC.VERSION = "2.0.0"`, `PHNPC.BUILD = "B42"`, `PHNPC.MOD_ID`
- `PHNPC.registerModule(name, tbl)` — enregistre un sous-module
- `PHNPC.getModule(name)` — récupère un module par nom
- Utilitaires : `PHNPC.clamp()`, `PHNPC.randInt()`, `PHNPC.deepCopy()`, `PHNPC.env()`
- Vérification version PZ au démarrage via `Events.OnGameBoot`

#### `NPC_Logger.lua`
Système de journalisation unifié. Niveaux : `TRACE < DEBUG < INFO < OK < WARN < ERROR < FAIL`.
- Tag d'environnement automatique : `[SV]` serveur / `[CL]` client / `[SH]` shared
- Ring buffer de 2 000 entrées, accessible via `log.tail(n)` et `log.clear()`
- Raccourcis directs : `log.debug()`, `log.info()`, `log.warn()`, `log.error()`

#### `NPC_Config.lua`
Lit `SandboxVars.PHNPC` à la demande avec cache invalidable.
- `NPC_Config.get()` → table de configuration complète avec valeurs par défaut
- `NPC_Config.invalidate()` → force une relecture (utilisé par `AdminCommands.reload`)
- Validation : clamp des entiers, cast des booléens, valeurs dérivées (ex: `NetworkSyncInterval = tenths × 0.1`)

#### `NPC_DataModel.lua`
Classe Lua (métatable) représentant un PNJ :
- **Identité** : id, firstName, lastName, isFemale, professionId (via `SurvivorFactory` B42)
- **Besoins** : hunger, thirst, fatigue, morale, stress (0–100), décroissance par `decayNeeds(dtSec)`
- **Santé** : health, bitten (bool), biteTime, trauma, ptsdState
- **IA** : fsmState, fsmTarget, stuckTicks
- **Économie** : observedSkills, inventory, gold
- **Monde** : isoObject (référence `IsoPlayer` B42)
- Méthodes : `isAlive()`, `setNeed()`, `addObservationXP()`, `serialize()`, `deserialize()`

#### `NPC_Professions.lua`
Catalogue de 5 métiers, chacun avec :
- `label`, `tradeMode` (broker/barter), `produces`, `buys`, `sells`
- `fsm_priorities` (liste ordonnée d'états FSM préférés)
- `outfitHints` (noms d'outfits B42 `_M`/`_F`, ex: `"Worker_M"`)
- `skillBonuses` (table skill → bonus XP observation)

| ID | Métier | Mode |
|----|--------|------|
| `merchant` | Marchand | broker (or) |
| `cook` | Cuisinier | barter (nourriture) |
| `artisan` | Artisan | barter (outils) |
| `medic` | Médecin | barter (médical) |
| `explorer` | Éclaireur | barter (divers) |

#### `NPC_FactionManager.lua`
Système de factions à relations dynamiques :
- 4 factions : `survivors`, `traders`, `bandits`, `unknown`
- Relations initiales entre factions (−100 à +100)
- `assign(npcId, faction)`, `getRelation(fA, fB)`, `adjustRelation(fA, fB, delta)`, `npcRelation(npcA, npcB)`

#### `NPC_Dialogue.lua`
Banques de dialogues contextuels FR + EN :
- 11 contextes : `greeting`, `trade`, `trade_accept`, `trade_refuse`, `hostile`, `idle`, `help_request`, `bitten_deny`, `quest_give`, `quest_complete`, `death`
- `get(context, tokens)` → phrase aléatoire avec substitution `{name}`
- Détection locale automatique via `getCore():getLanguage()`
- `ollamaFallback(npcData, playerMsg)` → détection par mots-clés si Ollama indisponible

#### `NPC_NetworkDispatcher.lua`
Couche d'abstraction réseau Solo/Multi :
- En **solo** : dispatch direct en mémoire (pas de sérialisation réseau)
- En **multi** : `sendServerCommand` / `sendClientCommand` B42
- `on(cmd, handler)` — enregistre un handler de commande
- `send(target, cmd, data, player)` — envoi transparent

#### `NPC_Brain.lua`
Moteur FSM (Finite State Machine) — boucle toutes les ~33 ms via `Events.OnTick` :

| État | Déclencheur |
|------|------------|
| `idle` | Par défaut, entre deux actions |
| `wander` | Aucune priorité active |
| `work` | Selon `fsm_priorities` du métier |
| `trade` | Joueur à portée + demande |
| `defend` | Trauma ≥ 80 (choc post-agression) |
| `flee` | Menace détectée (zombies proches) |
| `guard` | Assigné à un point fixe |

- `register(npcData)` / `unregister(npcId)` / `getContext(npcId)`
- Priorité : `evaluateThreat()` > `evaluateNeeds()` > état métier

---

### `server/` — Couche serveur uniquement

#### `00_Init.lua`
Garde `isServer()`, démarre les 3 sous-systèmes sur `Events.OnGameStart` :
`SpawnManager.start()`, `BiteMgr.start()`, `ObsLearning.start()`

#### `NPC_SpawnManager.lua`
Gestion du cycle de vie des PNJ dans le monde :
- `createIsoNPC(square, data)` → `IsoPlayer.new()` + `SurvivorFactory.CreateSurvivor()` + `dressInNamedOutfit()` + `setNPC(true)`
- `spawnNearPlayer(player)` → vérifie rayon + sol solide
- `despawnFarNPCs()` → retire les PNJ hors rayon de despawn
- Boucle `OnEveryOneMinute`, limite `MaxActiveNPCs`

#### `NPC_NetworkServer.lua`
Handlers côté serveur pour les commandes client :
- `npc_talk` → appel `OllamaBridge.ask()` ou fallback dialogue
- `npc_trade_request` → envoie l'inventaire PNJ au client
- `npc_trade_confirm` → validation et échange d'items

#### `NPC_BiteManagement.lua`
Simulation de morsure cachée à progression temporelle :
- Toutes les 10 s : décroissance morale, augmentation trauma
- Probabilité de toux configurable (SandboxVar `BiteCoughProbabilityPercent`)
- Transformation zombie à `trauma ≥ 100` : retire `isoObject`, notifie les clients
- API publique : `BiteMgr.bite(npcId)`

#### `NPC_ObservationLearning.lua`
XP passif : les PNJ apprennent en regardant faire le joueur :
- `observePlayerAction(player, skillName)` → vérifie portée, appelle `npcData:addObservationXP()`
- Hooks : `OnCooked → Cooking`, `OnObjectAdded → Carpentry`
- Check médecin toutes les 600 ticks via `OnPlayerUpdate`

#### `OllamaBridge.lua`
Bridge asynchrone vers l'API Ollama locale :
- `ask(npcData, playerMsg, callback)` → `HTTPRequest` B42 natif
- `buildPrompt(npcData, playerMsg)` → contexte métier + personnalité + état
- Cache LRU de taille configurable (`OllamaCacheSize`)
- Parse la réponse JSON `{ "response": "..." }`

#### `AdminCommands.lua`
Commandes in-game pour les admins via `OnCommandEntered` :

| Commande | Effet |
|----------|-------|
| `/phnpc list` | Liste les PNJ actifs |
| `/phnpc spawn` | Spawn un PNJ sur position admin |
| `/phnpc kill <id>` | Supprime un PNJ |
| `/phnpc bite <id>` | Applique une morsure cachée |
| `/phnpc debug` | Active/désactive les logs DEBUG |
| `/phnpc reload` | Recharge la configuration Sandbox |

---

### `client/` — Couche client uniquement

#### `00_Init.lua`
Registre `PHNPC.clientNPCs`, handlers Dispatcher :
- `npc_spawn` → crée l'entrée locale
- `npc_despawn` → nettoie l'entrée + ferme les UI ouvertes
- `npc_talk_reply` → `SpeechBubbles.show()` + `OllamaChatUI.addMessage()`
- `npc_cough` → bulle toux
- `npc_turned` → bulle décès + suppression locale
- `npc_trade_open` / `npc_trade_result` → `TradeWindow.open()` / `onResult()`

#### `NPC_InteractionClient.lua`
Menu contextuel clic droit sur les `IsoPlayer` identifiés comme PNJ :
- Détection via `isoObject:getModData().PHNPC_id`
- **"Parler à X"** → ouvre `OllamaChatUI`
- **"Commercer avec X"** → disponible pour merchant/cook/artisan
- **"Examiner X"** → ouvre `NPC_UI`

#### `UI/NPC_UI.lua`
Panneau info (ISPanel) affiché en overlay :
- Nom complet, métier, faction
- Barre de santé colorée (vert → rouge)
- Indicateur de morale

#### `UI/SpeechBubbles.lua`
Bulles de dialogue 3D (`TextDrawObject`) flottant au-dessus des PNJ :
- Durée 180 ticks (~3 s)
- 4 types visuels : `normal` (blanc), `cough` (jaune), `quest` (cyan), `trade` (vert)
- Rendu via `Events.OnRenderTick`, détection de l'isoObject par scan des personnages de la cellule

#### `UI/TradeWindow.lua`
Fenêtre de commerce ISPanel :
- Liste l'inventaire du PNJ + or disponible
- Bouton "Confirmer l'échange"
- `open(data)` / `onResult(data)` appelés par `client/00_Init.lua`

#### `UI/OllamaChatUI.lua`
Interface de chat asynchrone avec le PNJ :
- Historique scrollable MAX_HISTORY = 20 messages
- Couleurs : joueur = vert, PNJ = jaune
- Bloque l'envoi pendant la réponse en cours (`_waiting`)
- `open(npcId, npcName, player)` / `addMessage(who, text)` / `isOpen()`

#### `UI/QuestJournalUI.lua`
Journal de quêtes (toggle touche `J`) :
- Registre `PHNPC.clientQuests`
- Filtres : Actives / Terminées / Toutes
- Codes couleur : blanc (active), vert (terminée), rouge (échouée)
- `updateQuest(questData)` / `toggle()`

---

## Fichiers de configuration

### `mod.info`
```
name=Project Humain : Dynamic NPC Overhaul
id=PH_DynamicNPCOverhaul
description=...
poster=poster.png
icon=icon.png
author=sputji
version=2.0.0
targetVersion=42.0
category=npcs
```

> **Champs B42 standards** (alignés sur `NPC_Helper_Mod`, `DynamicTradingV2`, `Bandits`) :
> - `version` = version du mod
> - `targetVersion` = version minimale de PZ requise
> - `category` = catégorie Steam Workshop
> - Champs supprimés car non-standards : `pzversion`, `modversion`, `versionMin`, `tags`, `url`

### `media/sandbox-options.txt`

Format **bloc** avec chaque propriété sur sa propre ligne, sans commentaires Lua. Exemple :
```
VERSION = 1,

option PHNPC.MaxActiveNPCs
{
    type = integer,
    min = 1,
    max = 40,
    default = 12,
    page = PHNPC,
    translation = PHNPC_MaxActiveNPCs,
}
```

> La clé `translation = PHNPC_MaxActiveNPCs` est résolue en cherchant `Sandbox_PHNPC_MaxActiveNPCs`
> dans `Sandbox_EN.txt` (PZ ajoute le préfixe `Sandbox_` automatiquement).
> **`type = enum` est remplacé par `type = integer`** car non utilisé dans les mods B42 de référence.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `ActiveProfile` | integer (1-5) | 2 | Profil IA actif |
| `DebugMode` | boolean | false | Logs DEBUG activés |
| `MaxActiveNPCs` | integer (1-40) | 12 | Nombre max de PNJ simultanés |
| `PerPlayerBudget` | integer (1-10) | 4 | Budget PNJ par joueur |
| `SpawnRadius` | integer (10-80) | 32 | Rayon de spawn (tiles) |
| `DespawnRadius` | integer (20-120) | 48 | Rayon de despawn (tiles) |
| `FSMRange` | integer (10-80) | 40 | Portée du moteur FSM |
| `NetworkSyncIntervalTenths` | integer (1-20) | 5 | Intervalle sync réseau × 0.1 s |
| `EnableOllama` | boolean | false | Dialogues IA activés |
| `OllamaModel` | string | neural-chat | Modèle Ollama à utiliser |
| `OllamaTimeoutMs` | integer (1000-30000) | 8000 | Timeout HTTP Ollama |
| `OllamaCacheSize` | integer (0-200) | 50 | Taille du cache réponses |
| `BiteCoughIntervalSec` | integer (10-120) | 30 | Intervalle entre toux |
| `BiteCoughProbabilityPercent` | integer (1-100) | 15 | Probabilité de toux |
| `ObservationRange` | integer (4-30) | 12 | Portée d'observation XP |
| `ObservationIntervalSec` | integer (1-10) | 2 | Intervalle observation |
| `DisableNeedsDecay` | boolean | false | Désactive la décroissance des besoins |
| `ServiceBasePriceMultiplierTenths` | integer (1-50) | 10 | Multiplicateur prix × 0.1 |

### Fichiers de traduction (`Translate/`)

PZ cherche les fichiers dans `media/lua/shared/Translate/<LANG>/`. Le format de table attendu :

| Fichier | Table Lua | Contenu |
|---------|-----------|---------|
| `Sandbox_EN.txt` | `Sandbox_EN = {}` | Labels options Sandbox |
| `UI_EN.txt` | `UI_EN = {}` | Titres fenêtres, boutons |
| `ContextMenu_EN.txt` | `ContextMenu_EN = {}` | Entrées menu clic droit |
| `IGUI_EN.txt` | `IGUI_EN = {}` | Textes in-game, bulles, quêtes |

Chaque fichier est dupliqué pour `FR/` avec les suffixes `_FR`.

> **Convention clés** : la clé dans `sandbox-options.txt` est `PHNPC_MaxActiveNPCs` →
> PZ la cherche comme `Sandbox_PHNPC_MaxActiveNPCs` dans `Sandbox_EN.txt`.

---

## Ordre de chargement PZ

Project Zomboid charge les fichiers Lua par dossier (`shared` → puis `server` ou `client`), dans l'ordre alphabétique des noms de fichiers. Le préfixe `00_` garantit que les fichiers d'initialisation sont chargés en premier.

```
shared/00_Core.lua           ← chargé en PREMIER (namespace PHNPC)
shared/NPC_Brain.lua
shared/NPC_Config.lua
shared/NPC_DataModel.lua
shared/NPC_Dialogue.lua
shared/NPC_FactionManager.lua
shared/NPC_Logger.lua
shared/NPC_NetworkDispatcher.lua
shared/NPC_Professions.lua
     ↓ ensuite (selon côté) :
server/00_Init.lua           ← démarre les sous-systèmes serveur
server/AdminCommands.lua
server/NPC_BiteManagement.lua
...
client/00_Init.lua           ← initialise le registre client
client/NPC_InteractionClient.lua
client/UI/*.lua
```

---

## Conventions de code

- **Namespace** : tout passe par `PHNPC` — aucune variable globale directe
- **Logging** : utiliser `log.info()` / `log.warn()` / `log.error()` (jamais `print()`)
- **Config** : toujours lire via `NPC_Config.get().MaCle` — jamais `SandboxVars` directement
- **Réseau** : toujours passer par `NPC_NetworkDispatcher` — jamais `sendServerCommand` directement
- **Lua B42** : pas de `goto`, pas de `continue` (Kahlua 5.1), utiliser des blocs `if` imbriqués
- **Sécurité** : les appels API PZ critiques sont encapsulés dans `pcall()`
