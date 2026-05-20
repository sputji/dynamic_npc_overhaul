# Dynamic NPC Overhaul — Architecture B42
> Version 2.3.0 | Project Zomboid Build 42.18.0 | Auteur : sputji  
> **État actuel : Fondations ✅ — Cerveau ✅ — Serveur v3.0 ✅ — Client v2.3 ✅ — IsoPlayer ✅ — UI ✅ — Save ✅**

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
| **Corps serveur** (`server/`) | Spawn, réseau serveur, commandes admin | ✅ Fonctionnel + réstauration reload |
| **Corps client** (`client/`) | Menu clic-droit, FollowTick, debug spawn, **NPC_Brain branché** | ✅ Fonctionnel |
| **AnimSets** (`42/media/AnimSets/`) | Animations humaines Bob_Idle / Bob_Walk | ✅ Actif |
| **UI** (`client/UI/`) | Fenêtres ISPanel (dialogue, speech bubbles) | ✅ Actif |
| **Wiki PZ modding B42** | [Référence API](https://pzwiki.net/wiki/Build_42) |

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
└── B42\                             # Structure B42 native (common/ + 42/)
    ├── mod.info                     # id, name, version=1.0.0, versionMin=42.0, poster=poster.png
    ├── poster.png                   # Visuel mod (128×128, référencé par poster=)
    ├── preview.png                  # Image alternative / Workshop
    ├── icon.png                     # Icône Workshop
    │
    ├── tools\
    │   └── sync_to_mods.ps1         # Synchronise workspace → dossiers mods PZ
    │
    ├── 42\                          # Chargé uniquement en B42.x
    │   ├── mod.info                 # Copie du mod.info racine (requis par PZ B42)
    │   └── media\lua\               # Vide — contenu dans common/
    │
    └── common\                      # Chargé dans TOUTES les versions B42
        └── media\
            ├── sandbox-options.txt  # Options Sandbox (format bloc, type=integer)
            │
            └── lua\
                │
                ├── shared\          ✅ CERVEAU — Chargé CLIENT + SERVEUR
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
                ├── server\ ✅ CORPS SERVEUR v3.0 — Spawn autorité + sync position 10Hz
                │   ├── 00_Init.lua          # Log démarrage serveur
                │   └── NPC_SpawnManager.lua # ACTIF v3.0 — Spawn, PHNPC_SyncTarget 10Hz, PHNPC_SetFollowMode
                │
                └── client\ ✅ CORPS CLIENT v2.3 — IsoPlayer + server authority
                    ├── 00_Init.lua              # Bootstrap client : disableTieredZombieUpdates
                    ├── NPC_FollowTick.lua        # IsoPlayer.new() + spawn dedup + PHNPC_SyncTarget + menu clic-droit
                    ├── NPC_Save.lua             # Persistance ModData + npc:save/load — getSaveDir() pcall-safe
                    ├── NPC_InteractionClient.lua # DESACTIVE — interaction integree dans NPC_FollowTick.lua
                    ├── NPC_SpawnDebug.lua        # DESACTIVE — spawn zombies remplace par IsoPlayer
                    └── UI\
                        ├── NPC_DialogueWindow.lua   # ISPanel dialogue — API open(npc, npcData)
                        ├── NPC_SpeechBubble.lua     # Toast bas-ecran (en attente refonte)
                        └── (a creer) TradeWindow.lua, OllamaChatUI.lua
```

---

## Architecture IsoPlayer v2.3.0 — Server Authority

> **Principe** : Le SERVEUR calcule la destination de chaque NPC à ~10Hz et la broadcast aux clients.
> Les clients utilisent cette destination pour `pathToLocation()` au lieu de calculer localement.
> Cela elimine la desynchronisation multijoueur (chaque client calculait son propre pathfinding independamment).

### Flux complet

```
[Client] clic-droit "Faire apparaitre un PNJ"
    --> PHNPC_RequestSpawn {x, y, z}
    --> [Serveur] NPC_SpawnManager.lua
        - genere ID unique: PHNPC_<forename>_<surname>_<timestamp>
        - enregistre _serverNPCs[id] = { x, y, z, followMode=true, ... }
        --> PHNPC_DoSpawn {id, forename, surname, isFemale, x, y, z}
    --> [Tous clients] createNPCFromData()
        - verif anti-doublon: if PHNPC.npcs_byId[data.id] then return end
        - IsoPlayer.new() + Brain.register()
        - PHNPC.npcs[npc] = npcData
        - PHNPC.npcs_byId[id] = npc

[Serveur] Events.OnTick (chaque 6 ticks = ~10Hz)
    Pour chaque _serverNPCs[id]:
        - si followMode: target = position du joueur reel le plus proche
        - si wander: target = point aleatoire dans rayon 8 tiles
        --> PHNPC_SyncTarget {id, tx, ty, tz}
    --> [Tous clients] PHNPC.npcs[npc].server_tx/ty/tz = tx/ty/tz

[Client] Events.OnTick (chaque 10 ticks = RETARGET)
    Si fsmState == "flee"  --> client-side (threat local)
    Sinon si data.server_tx --> pathToLocation(server_tx, server_ty, server_tz)  [SERVER AUTHORITY]
    Sinon si followMode    --> pathToLocation(player.x, player.y)                [FALLBACK LOCAL]
    Sinon si wander        --> pathToLocation(wander_target.x, wander_target.y)  [FALLBACK LOCAL]
    Sinon                  --> idle (faceThisObject)
```

### Commandes reseau

| Commande | Direction | Emetteur | Description |
|----------|-----------|----------|-------------|
| `PHNPC_RequestSpawn` | client → server | NPC_FollowTick | Demande de spawn |
| `PHNPC_DoSpawn` | server → all clients | NPC_SpawnManager | Creation NPC |
| `PHNPC_SyncTarget` | server → all clients | NPC_SpawnManager | Destination 10Hz |
| `PHNPC_SetFollowMode` | client → server | NPC_FollowTick | Bascule follow/wander |
| `PHNPC_RemoveNPC` | client → server | NPC_FollowTick | NPC mort/despawn |

### Pattern de creation NPC (NPC_FollowTick.lua)

```lua
-- 1. Descripteur visuel complet (apparence + outfit + profession)
local isFemale = (ZombRand(2) == 1)
local forename = SurvivorFactory.getRandomForename(isFemale)
local surname  = SurvivorFactory.getRandomSurname()
local desc     = SurvivorFactory.CreateSurvivor(nil, isFemale)
desc:setForename(forename)
desc:setSurname(surname)

-- 2. Création de l'entité IsoPlayer (animations Bob/Kate natives)
local cell = getWorld():getCell()
local npc  = IsoPlayer.new(cell, desc, x, y, z)

-- 3. Configuration NPC
npc:setNPC(true)               -- Désactive l'input joueur
npc:setForname(forename)
npc:setSurname(surname)
npc:setUsername(forename .. " " .. surname)
npc:setSceneCulled(false)
npc:setDir(IsoDirections.SE)

-- 4. Suivi joueur (dans Events.OnTick)
npc:getPathFindBehavior2():update()                          -- chaque tick
npc:getPathFindBehavior2():pathToLocation(tx, ty, tz)       -- recalcul périodique
```

### Registre global PHNPC.npcs

```lua
-- PHNPC.npcs[IsoPlayer] = { forename, surname, fullname, followMode, isFemale }
PHNPC.npcs[npc] = { followMode = true, fullname = "Bob Martin", ... }
```

---

## Pièges UTF-8 et Kahlua

### ⛔ BOM UTF-8 — Cause #1 de SEVERE error au chargement

`[System.Text.Encoding]::UTF8` en PowerShell ajoute un BOM (octets `EF BB BF` = `239 187 191`).  
Kahlua lit ces 3 octets au début du fichier → parse error → `SEVERE: Error in LUA file`.

**Vérification** :
```powershell
$b = [System.IO.File]::ReadAllBytes($path)
"Has BOM: $(($b[0] -eq 239 -and $b[1] -eq 187 -and $b[2] -eq 191))"
```

**Solution** : Toujours écrire les fichiers Lua avec :
```powershell
$enc = [System.Text.UTF8Encoding]::new($false)  # false = NO BOM
[System.IO.File]::WriteAllText($path, $content, $enc)
```

### ⛔ Caractères Unicode dans les commentaires Lua

Les caractères de dessin de boîte Unicode (─ U+2500, • U+2022, etc.) dans les commentaires `--[[ ... ]]` peuvent causer des erreurs de parse dans certains contextes Kahlua. Utiliser uniquement des caractères ASCII (0-127) dans les fichiers Lua.

---

## Pattern de déclenchement Lua (validé B42.18)

Les animations humaines sont activées via des fichiers XML placés dans `42/media/AnimSets/zombie/`.  
PZ charge les XML **par ordre alphabétique** dans chaque sous-dossier ; les fichiers préfixés `PHNPC_` overrident les animations zombie natives.

> **Confirmé en jeu** : la console affiche `overrides media/animsets/zombie/idle/phnpc_idle.xml` et `...phnpc_walk.xml` au chargement du mod.

### Fichiers créés

| Fichier | Condition(s) | Animation |
|---------|-------------|-----------|
| `idle/PHNPC_Idle.xml` | `PHNPC_IsNPC=BOOL true` | `Bob_Idle` (humain) |
| `walktoward/PHNPC_Walk.xml` | `PHNPC_IsNPC=BOOL true` **+** `zombieWalkType=STRING "Walk"` | `Bob_Walk` (humain) |
| `walktoward/PHNPC_Run.xml` | `PHNPC_IsNPC=BOOL true` **+** `zombieWalkType=STRING "Run"` | `Bob_Run` (humain) |
| `faceTarget/PHNPC_FaceTarget.xml` | `PHNPC_IsNPC=BOOL true` | Face humaine |

### ⚠️ Points critiques

1. **`PHNPC_IsNPC` doit être en BOOL** — `zombie:setVariable("PHNPC_IsNPC", true)` **hors pcall**.  
   En Kahlua, un `pcall` peut avaler l'écriture silencieusement → variable jamais envoyée côté Java.

2. **`zombieWalkType` est requis par PHNPC_Walk.xml** — DEUX conditions dans ce fichier :  
   - `PHNPC_IsNPC=BOOL true`  
   - `zombieWalkType=STRING "Walk"`  
   Si la 2ème est absente, `Bob_Walk` ne se déclenche **jamais**. Envoyer à chaque tick de déplacement :
   ```lua
   zombie:setVariable("zombieWalkType", "Walk")  -- ou "Run" selon la vitesse
   ```

3. **`getActionContext():clear()`** — ⛔ **NE PAS APPELER depuis Kahlua**.  
   `getActionContext()` retourne un objet Java (`zombie.characters.action.ActionContext`). Kahlua ne peut pas appeler `.clear()` dessus → erreur `attempted index: clear of non-table` loggée à chaque tick.  
   **Solution Bandits** : `setBumpType("Shrug")` dans `convertToNPC` force la réévaluation AnimEngine sans toucher ActionContext.

4. **`setUseless(true)` = désactivation totale de l'IA zombie (pattern Bandits)**  
   Appeler `zombie:setUseless(true)` à chaque tick empêche le moteur PZ de déclencher ses propres actions (lunge, pathfind vers joueur, etc.). Les appels manuels à `pathToLocationF`, `doSprinter`, etc. continuent de fonctionner indépendamment.

5. **`NoLungeTarget`** est le flag Bandits pour bloquer les attaques (pas `NoLungeAttack`).  
   `NoLungeAttack` empêche le zombie de lancer une attaque en lunge ; `NoLungeTarget` empêche le zombie d'être la cible d'un lunge d'un autre zombie.

### Pattern de déclenchement Lua (validé B42.18)

```lua
-- convertToNPC : écriture garantie hors pcall
zombie:setVariable("PHNPC_IsNPC",    "true")  -- STRING fallback (sûreté)
zombie:setVariable("PHNPC_IsNPC",    true)     -- BOOL (condition XML)

-- enforceNPC : chaque tick — pattern Bandits B42.18
safeCall(zombie, "setUseless", true)           -- Désactive l'IA moteur ; pathToLocationF fonctionne toujours
safeCall(zombie, "setTarget",  nil)
zombie:setVariable("NoLungeTarget", true)      -- Bandits utilise NoLungeTarget (pas NoLungeAttack)
-- Lunge/turnalerted : clearAggroList + setTarget(nil) — PAS getActionContext().clear()
local asn = zombie:getActionStateName()
if asn == "lunge" or asn == "turnalerted" then
    safeCall(zombie, "clearAggroList")
    safeCall(zombie, "setTarget", nil)
end
```

---

## Fichiers de configuration

### `mod.info`
```
name=Project Humain : Dynamic NPC Overhaul
id=PH_DynamicNPCOverhaul
author=sputji
description=Autonomous NPCs with AI brain (FSM), Ollama dialogues, trading, hidden bites and passive learning. Compatible B42.
poster=poster.png
icon=icon.png
version=1.0.0
versionMin=42.0
```

> `versionMin=42.0` — format obligatoire `build.major` (pas `42` seul) ; absent = comportement indéfini selon les builds.  
> `require=` **absent** — une ligne `require=` vide est parsée comme « dépendance ID vide manquante » → **mod rouge** en jeu.  
> Supprimé : `pzversion`, `modversion`, `tags`, `url`, `category`.

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
- **IA & FSM** : fsmState, fsmTarget `{x,y}`, lastFsmTick, stuckTicks, followMode
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
| `defend` | flee, idle | Trauma ≥ 80, moral ≥ seuil |
| `flee` | idle, wander | Trauma ≥ 80, moral < seuil |
| `guard` | defend, idle | Point fixe assigné |

**Connexion physique** (`NPC_FollowTick.doBrainAction`) :
- `wander`/`work` → `doWander()` — point aléatoire voisin
- `flee` → course à l'opposé de la menace (priorité : `fsmTarget` > zombie hostile proche > joueur)
- `guard`/`trade`/`defend` → immobile (`setPath2(nil)`)
- `idle` → `doWander()` (errance légère)

**Localisation de la menace** : lors de `flee`, `evaluateThreat` scanne les 60 zombies les plus
proches (rayon 15 cases) et stocke le plus proche dans `npcData.fsmTarget = {x, y}`.
`doBrainAction` utilise cette position comme source de fuite.

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
| **Mod invisible en B42** | `common/` absent dans le dossier mod | Créer `common/` (même vide) — condition **obligatoire** B42 |
| **Lua ignoré en B42** | Fichiers dans `media/lua/` (racine) | Déplacer dans `common/media/lua/` ou `42/media/lua/` |
| **Mod rouge — dépendance manquante** | `require=` avec valeur vide dans mod.info | Supprimer la ligne `require=` si aucune dépendance |
| **Mod rouge — incompatibilité version** | `versionMin` absent ou mal formaté | Utiliser `versionMin=42.0` (format `build.major` obligatoire) |
| **`pcall` nil au chargement** | Runtime Kahlua instable | Wrapper `pcall(...)` systématique |
| **AnimSets ignorent la variable** | `setVariable` dans un pcall qui échoue silencieusement | Appeler `zombie:setVariable("PHNPC_IsNPC", true)` **hors pcall** |
| **Bob_Walk jamais joué** | `PHNPC_Walk.xml` a 2 conditions : `PHNPC_IsNPC` ET `zombieWalkType=Walk` | Envoyer `zombie:setVariable("zombieWalkType", "Walk")` dans `doFollow` |
| **Bob_Idle ne se déclenche pas** | Contexte d'action courant pas vidé | Appeler `zombie:getActionContext():clear()` dans `convertToNPC` |
| **Crash `setMaxHealth` en boucle** | `setMaxHealth`/`setHealth` inexistants sur IsoZombie B42 | Supprimer ces appels ; la boucle infinie vient de `_convertedNPCs` non marqué |
| **`getGameMode()` = Multiplayer en solo** | B42 retourne toujours `"Multiplayer"` | Utiliser `not isMultiplayer()` pour détecter le solo |
| **`getOptionCount()` crash au lancement** | `getServerOptions()` retourne un objet sans cette méthode en solo | Guard `type(opts.getOptionCount) == "function"` avant l'appel |
| **Zombie re-cible le joueur** | Moteur conserve la mémoire de chair fraîche | `zombie:setTimeSinceSeenFlesh(1000000)` dans `convertToNPC` et `enforceNPC` |
| **NPC redevient zombie après reload** | `setVariable` (AnimEngine) **n'est pas persisté** sur disque | Serveur : `EveryOneMinute` re-scanne `getCell():getZombieList()` et ré-applique `setVariable` pour tout zombie avec `ModData.PHNPC_IsNPC` |
| **NPC redevient zombie après chunk unload** | Même cause : variables AnimEngine perdues au déchargement | Même fix que ci-dessus + détection Method B (ModData) tolère `true` ET `"true"` |
| **État FSM perdu au reload** | `fsmState` / `health` jamais écrits en ModData pendant le jeu | Client : `Events.OnTick` écrit `md.PHNPC_FsmState` et `md.PHNPC_Health` toutes les ~4 secondes |
| **Glissement du modèle à l'arrêt** | Inertie physique B42 non réinitialisée après `setPath2(nil)` | `zombie:setForwardDirection(player:getForwardDirection())` dans `doFollow` au moment de l'arrêt |
| **Spam setVariable (perf)** | `enforceNPC` écrit `PHNPC_IsNPC` à chaque tick même si déjà défini | Guard `if not zombie:getVariableBoolean("PHNPC_IsNPC")` avant l'écriture |
| **`getCell()` nil en multijoueur** | Sur serveur dédié sans joueur local, `getCell()` peut renvoyer `nil` | Toujours `local cell = getCell() ; if not cell then return end` avant `getZombieList()` — **guard déjà en place** dans `NPC_SpawnManager` |
| **NPC fuit le joueur au lieu de la menace** | État `flee` calculait la direction depuis le joueur comme source | **Corrigé** : `evaluateThreat` stocke la position du zombie hostile dans `npcData.fsmTarget`; `doBrainAction` fuit cette position (fallback : zombie hostile proche, puis joueur) |
| **`Object tried to call nil in pcall` (ligne 608/619)** | `ZombieIdleState` absent en B42, `getEmitter()` peut retourner nil, `setTimeSinceSeenFlesh` supprimé | **Corrigé** : helper `safeCall(obj, method, ...)` vérifie l'existence avant d'appeler ; guard nil sur emitter ; `getActionContext():clear()` remplace `ZombieIdleState.instance()` |
| **WARN `Trying to set read-only variable "zombiewalktype"`** | `setWalkType()` (Java) pose `zombiewalktype` en read-only | **Corrigé** : tous les appels `setWalkType()` supprimés ; l'AnimEngine lit uniquement `zombie:setVariable("zombieWalkType", ...)` |
| **Boutons UI transparents / illisibles** | Le moteur de rendu B42 ne donne pas de fond automatique aux ISButton | **Corrigé** : `button.backgroundColor = {r,g,b,a}` + `button.borderColor = {r,g,b,a}` sur chaque bouton dans `initialise()` |
