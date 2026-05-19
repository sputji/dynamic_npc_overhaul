# Dynamic NPC Overhaul — Architecture B42
> Version 2.0.0 | Project Zomboid Build 42 | Auteur : sputji  
> **État actuel : Phase 1 complète — Cerveau implémenté, Corps à créer**

---

## Vue d'ensemble

Le mod **Dynamic NPC Overhaul** ajoute à Project Zomboid des PNJ vivants, dotés d'une IA contextuelle, d'un système de commerce, de quêtes, de factions et d'une mémoire persistante. Il fonctionne en solo et en multijoueur de manière transparente.

### Principe d'architecture
Un seul objet Lua `PHNPC` est partagé entre tous les fichiers.  
Chaque module s'enregistre via `PHNPC.registerModule(name, tbl)` et se retrouve via `PHNPC.getModule(name)`.

### Cerveau vs Corps

| Couche | Rôle | État |
|--------|------|------|
| **Cerveau** (`shared/`) | Logique pure, données, IA, réseau abstrait | ✅ Implémenté |
| **Corps** (`server/` + `client/`) | Implémentations B42 spécifiques (spawn, UI, hooks) | ❌ À créer |

---

## Arborescence actuelle

> Structure vérifiée et alignée sur les mods de référence B42 :  
> `NPC_Helper_Mod`, `Bandits`, `DynamicTradingV2`, `7 - Custom NPC`, `ssr_core`

```
D:\PZ Mods\Dynamic_NPC_Overhaul\
│
├── .gitignore
│
├── Docs\
│   └── B42\
│       ├── ARCHITECTURE.md          # Ce fichier
│       ├── GUIDE_CREATION.md        # Guide complet "depuis zéro"
│       └── feuille de route.md      # Roadmap fonctionnelle
│
└── B42\
    ├── mod.info                     # id, name, version=2.0.0, targetVersion=42.0, category=npcs
    ├── poster.png
    ├── 42\                          # Assets spécifiques B42 (futur)
    ├── common\                      # Assets multi-version (futur)
    │
    └── media\
        ├── sandbox-options.txt      # Options Sandbox (format bloc, type=integer)
        │
        └── lua\
            │
            ├── shared\              ✅ CERVEAU — Chargé CLIENT + SERVEUR
            │   ├── 00_Core.lua      # Namespace PHNPC, utilitaires, vérif version
            │   ├── NPC_Logger.lua   # Logger TRACE→FAIL, ring buffer 2000 entrées
            │   ├── NPC_Config.lua   # Lecture SandboxVars.PHNPC + defaults
            │   ├── NPC_DataModel.lua# Classe PNJ OO : stats, besoins, sérialisation
            │   ├── NPC_Professions.lua # Catalogue 5 métiers + outfits B42
            │   ├── NPC_FactionManager.lua # 4 factions, relations −100/+100
            │   ├── NPC_Dialogue.lua # Banques FR/EN, substitution, fallback Ollama
            │   ├── NPC_NetworkDispatcher.lua # Réseau transparent Solo/Multi
            │   ├── NPC_Brain.lua    # FSM 7 états, boucle OnTick ~33 ms
            │   │
            │   └── Translate\
            │       ├── EN\
            │       │   ├── Sandbox_EN.txt      # Sandbox_EN = {}
            │       │   ├── UI_EN.txt           # UI_EN = {}
            │       │   ├── ContextMenu_EN.txt  # ContextMenu_EN = {}
            │       │   └── IGUI_EN.txt         # IGUI_EN = {}
            │       └── FR\
            │           ├── Sandbox_FR.txt
            │           ├── UI_FR.txt
            │           ├── ContextMenu_FR.txt
            │           └── IGUI_FR.txt
            │
            ├── server\              ❌ CORPS — À créer (API B42 à vérifier)
            │   ├── 00_Init.lua      # Point d'entrée serveur
            │   ├── NPC_SpawnManager.lua    # Spawn/despawn (IsoPlayer, SurvivorFactory)
            │   ├── NPC_NetworkServer.lua   # Handlers commandes client→serveur
            │   ├── NPC_BiteManagement.lua  # Morsure cachée → transformation zombie
            │   ├── NPC_ObservationLearning.lua # XP passif par observation
            │   ├── OllamaBridge.lua        # Bridge HTTP → Ollama (HTTPRequest B42)
            │   └── AdminCommands.lua       # /phnpc list/spawn/kill/bite/debug/reload
            │
            └── client\              ❌ CORPS — À créer (API B42 à vérifier)
                ├── 00_Init.lua      # Point d'entrée client
                ├── NPC_InteractionClient.lua # Menu clic-droit (OnFillWorldObjectContextMenu)
                └── UI\
                    ├── NPC_UI.lua          # Fiche info PNJ (ISPanel)
                    ├── SpeechBubbles.lua   # Bulles 3D (TextDrawObject)
                    ├── TradeWindow.lua     # Fenêtre commerce
                    ├── OllamaChatUI.lua    # Chat IA (async, historique)
                    └── QuestJournalUI.lua  # Journal de quêtes (touche J)
```

---

## Fichiers de configuration

### `mod.info`
```
name=Project Humain : Dynamic NPC Overhaul
id=PH_DynamicNPCOverhaul
description=Dynamic NPCs with AI, factions, quests and trade for Build 42.
poster=poster.png
icon=icon.png
author=sputji
version=2.0.0
targetVersion=42.0
category=npcs
```

> Champs standard B42. Supprimé : `pzversion`, `modversion`, `versionMin`, `tags`, `url`.

### `media/sandbox-options.txt` — Format bloc

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

> - Pas de commentaires `--` (parseur PZ sandbox ne les supporte pas)
> - `type = enum` inexistant → remplacé par `type = integer`
> - La clé `translation = PHNPC_MaxActiveNPCs` → PZ cherche `Sandbox_PHNPC_MaxActiveNPCs`

### Options Sandbox

| Option | Type | Défaut | Description |
|--------|------|--------|-------------|
| `ActiveProfile` | integer (1-5) | 2 | Profil IA (1=rp_soft … 5=ultra_hardcore) |
| `DebugMode` | boolean | false | Logs DEBUG/TRACE activés |
| `MaxActiveNPCs` | integer (1-40) | 12 | Nombre max de PNJ simultanés |
| `PerPlayerBudget` | integer (1-10) | 4 | Budget PNJ par joueur |
| `SpawnRadius` | integer (10-80) | 32 | Rayon de spawn (tiles) |
| `DespawnRadius` | integer (20-120) | 48 | Rayon de despawn (tiles) |
| `FSMRange` | integer (10-80) | 40 | Portée du moteur FSM |
| `NetworkSyncIntervalTenths` | integer (1-20) | 5 | Intervalle sync réseau × 0.1 s |
| `EnableOllama` | boolean | false | Dialogues IA activés |
| `OllamaModel` | string | neural-chat | Modèle Ollama |
| `OllamaTimeoutMs` | integer (1000-30000) | 8000 | Timeout HTTP Ollama |
| `OllamaCacheSize` | integer (0-200) | 50 | Taille cache réponses |
| `BiteCoughIntervalSec` | integer (10-120) | 30 | Intervalle entre toux |
| `BiteCoughProbabilityPercent` | integer (1-100) | 15 | Probabilité de toux |
| `ObservationRange` | integer (4-30) | 12 | Portée d'observation XP |
| `ObservationIntervalSec` | integer (1-10) | 2 | Intervalle observation |
| `DisableNeedsDecay` | boolean | false | Désactive décroissance des besoins |

### Fichiers de traduction (`Translate/`)

| Fichier | Table Lua | Contenu |
|---------|-----------|---------|
| `Sandbox_EN.txt` | `Sandbox_EN = {}` | Labels options Sandbox |
| `UI_EN.txt` | `UI_EN = {}` | Titres fenêtres, boutons |
| `ContextMenu_EN.txt` | `ContextMenu_EN = {}` | Entrées menu clic-droit |
| `IGUI_EN.txt` | `IGUI_EN = {}` | Textes in-game, bulles, quêtes |

> Convention : `translation = PHNPC_MaxActiveNPCs` → PZ cherche `Sandbox_PHNPC_MaxActiveNPCs` (préfixe `Sandbox_` auto-ajouté).

---

## Description des modules (Cerveau)

### `00_Core.lua`
Crée `PHNPC` et expose :
- `PHNPC.registerModule(name, tbl)` / `PHNPC.getModule(name)`
- Utilitaires : `clamp()`, `randInt()`, `deepCopy()`, `env()`
- Vérification version PZ sur `Events.OnGameBoot`

### `NPC_Logger.lua`
Niveaux : `TRACE < DEBUG < INFO < OK < WARN < ERROR < FAIL`
- Tags auto `[SV]` / `[CL]` / `[SH]`
- Ring buffer 2000 entrées, `log.tail(n)`, `log.clear()`

### `NPC_Config.lua`
- `NPC_Config.get()` → config complète avec valeurs par défaut
- `NPC_Config.invalidate()` → relecture depuis `SandboxVars.PHNPC`
- `ActiveProfile` = entier 1-5 (aligné sur `type = integer` du sandbox)

### `NPC_DataModel.lua`
Classe OO via métatable. Un PNJ contient :
- **Identité** : id, firstName, lastName, isFemale, professionId
- **Besoins** : hunger, thirst, fatigue, morale, stress (0–100)
- **Santé** : health, bitten, biteTime, trauma, ptsdState
- **IA** : fsmState, fsmTarget, stuckTicks
- **Économie** : observedSkills, inventory, gold
- Méthodes : `isAlive()`, `setNeed()`, `serialize()`, `deserialize()`

### `NPC_Professions.lua`
5 métiers avec `label`, `tradeMode`, `fsm_priorities`, `outfitHints`, `skillBonuses` :

| ID | Métier | Mode |
|----|--------|------|
| `merchant` | Marchand | broker (or) |
| `cook` | Cuisinier | barter (nourriture) |
| `artisan` | Artisan | barter (outils) |
| `medic` | Médecin | barter (médical) |
| `explorer` | Éclaireur | barter (divers) |

### `NPC_FactionManager.lua`
4 factions (`survivors`, `traders`, `bandits`, `unknown`), relations croisées −100/+100.

### `NPC_Dialogue.lua`
11 contextes (greeting, trade, hostile, flee, death…) en FR + EN.  
Fallback par mots-clés si Ollama indisponible.

### `NPC_NetworkDispatcher.lua`
- **Solo** : dispatch direct en mémoire (zéro overhead)
- **Multi** : `sendServerCommand` / `sendClientCommand` B42
- API unifiée : `Dispatcher.send(target, cmd, data)`

### `NPC_Brain.lua`
FSM 7 états, boucle `OnTick` toutes les ~33 ms :

| État | Transitions | Déclencheur |
|------|------------|-------------|
| `idle` | wander, work, trade, guard | Par défaut |
| `wander` | idle, defend, flee | Aucune priorité |
| `work` | idle, trade | `fsm_priorities` métier |
| `trade` | idle, work | Joueur à portée |
| `defend` | flee, idle | Trauma ≥ 80 |
| `flee` | idle, wander | Zombies proches |
| `guard` | defend, idle | Point fixe assigné |

---

## Conventions de code

### Ordre de chargement
Fichiers chargés par ordre alphabétique → préfixe `00_` pour priorité absolue.

### Pattern module
```lua
local MonModule = {}
-- ... fonctions ...
PHNPC.registerModule("MonModule", MonModule)  -- TOUJOURS dernière ligne
```

### Garde de côté
```lua
if not isServer() then return end   -- server/ seulement
if not isClient() then return end   -- client/ seulement
```

### Pas de `goto`/`continue` (Lua 5.1 / Kahlua)
```lua
-- INTERDIT → KahluaException
for i = 1, 10 do
    if condition then continue end
end

-- CORRECT
for i = 1, 10 do
    if not condition then
        -- corps de boucle
    end
end
```

---

## Pièges B42 documentés

| Problème | Cause | Solution |
|----------|-------|----------|
| `ClassCastException IsoPlayer/IsoZombie` | `pathToCharacter()` sur IsoPlayer NPC | Utiliser `pathToLocationF(x, y, z)` |
| Fichier Translate ignoré | Mauvais nom (`SandboxVars_EN.txt`) | Utiliser `Sandbox_EN.txt` |
| Option Sandbox absente | `type = enum` dans sandbox-options | Utiliser `type = integer` |
| Commentaires ignorés/plantent | `--` non supporté dans sandbox | Supprimer tous les `--` |
| Mod non chargé | `pzversion` au lieu de `targetVersion` | Corriger mod.info |
| `pcall` nil au chargement | Runtime Kahlua instable | Wrapper `pcall(...)` systématique |
