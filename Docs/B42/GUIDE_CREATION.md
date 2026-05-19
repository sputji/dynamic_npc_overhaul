# Guide de création du mod B42 — Dynamic NPC Overhaul
## Partir de zéro

> Ce guide décrit **toutes les étapes concrètes** pour construire le mod
> "Project Humain : Dynamic NPC Overhaul" sur Project Zomboid **Build 42**.
> Il s'appuie sur l'analyse des mods exemples `NPC_Helper_Mod`, `Bandits`,
> `DynamicTradingV2`, `7 - Custom NPC` et `ssr_core`.

---

## 0. Prérequis

| Outil | Usage |
|-------|-------|
| VS Code + Lua extension | Édition + vérification syntaxe |
| Git | Versionnage |
| Project Zomboid B42 (Steam) | Test en jeu |
| Lua 5.1 (optionnel) | Tests unitaires hors-jeu |

Répertoire de test en jeu : `C:\Users\<USER>\Zomboid\mods\PH_DynamicNPCOverhaul\`

---

## 1. Structure du dossier mod

La structure **minimale** pour que PZ charge le mod :

```
B42/
├── mod.info                    ← OBLIGATOIRE
├── poster.png                  ← Icône 128×128 (Workshop)
└── media/
    ├── sandbox-options.txt     ← Options Sandbox (format bloc)
    └── lua/
        ├── shared/             ← Chargé côté CLIENT + SERVEUR
        ├── server/             ← Chargé côté SERVEUR uniquement
        └── client/             ← Chargé côté CLIENT uniquement
```

---

## 2. `mod.info` — Format B42

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

> **Règles** :
> - `version` = version du mod (pas `modversion` ni `pzversion`)
> - `targetVersion` = version PZ minimale
> - `category` = catégorie Workshop (npcs, items, clothing, maps…)
> - Pas de `url`, `tags`, `versionMin` → non reconnus en B42

---

## 3. `sandbox-options.txt` — Format B42

Format **bloc**, une propriété par ligne, **aucun commentaire Lua** :

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

> - `translation = PHNPC_MaxActiveNPCs` → PZ cherche `Sandbox_PHNPC_MaxActiveNPCs` dans `Sandbox_EN.txt`
> - `type = enum` **n'existe pas** en B42 → utiliser `type = integer`
> - `page` regroupe les options dans l'onglet sandbox

---

## 4. Fichiers de traduction

Placer dans `media/lua/shared/Translate/<LANG>/` :

| Fichier | Table Lua | Contenu |
|---------|-----------|---------|
| `Sandbox_EN.txt` | `Sandbox_EN = {}` | Labels options Sandbox |
| `UI_EN.txt` | `UI_EN = {}` | Titres fenêtres, boutons |
| `ContextMenu_EN.txt` | `ContextMenu_EN = {}` | Entrées menu clic-droit |
| `IGUI_EN.txt` | `IGUI_EN = {}` | Textes in-game (bulles, quêtes) |

Format d'une entrée Sandbox :
```lua
Sandbox_EN = {
    Sandbox_PHNPC = "Dynamic NPC Overhaul",
    Sandbox_PHNPC_MaxActiveNPCs = "Max Active NPCs",
    Sandbox_PHNPC_MaxActiveNPCs_tooltip = "Maximum number of simultaneous NPCs.",
}
```

---

## 5. Ordre de chargement Lua

PZ charge les fichiers Lua **par ordre alphabétique de nom de fichier** dans chaque dossier.

- Préfixer les fichiers qui doivent charger en **premier** avec `00_`
- Exemple : `00_Core.lua` → chargé avant `NPC_Brain.lua`

```
shared/
  00_Core.lua         ← 1er : définit le namespace PHNPC
  NPC_Brain.lua       ← 2e et après (ordre alpha)
  NPC_Config.lua
  ...

server/
  00_Init.lua         ← 1er côté serveur
  NPC_SpawnManager.lua
  ...

client/
  00_Init.lua         ← 1er côté client
  NPC_InteractionClient.lua
  ...
```

---

## 6. APIs B42 clés à implémenter (Corps manquant)

### 6.1 Spawn d'un PNJ — `server/NPC_SpawnManager.lua`

> ⚠️ Les APIs de spawn ont changé entre B41 et B42.
> Référence : mod exemple `NPC_Helper_Mod` et `Bandits`.

**À vérifier dans les mods exemples :**
- Comment utiliser `IsoPlayer.new()` vs les nouveaux helpers B42
- `SurvivorFactory` : méthodes `CreateSurvivor`, `getRandomForename`, `getRandomSurname`
- Appliquer un outfit : `desc:dressInNamedOutfit(outfitName)`
- Marquer comme NPC : `iso:setNPC(true)`
- Attacher à la grille : `getWorld():getCell()`, `IsoDirections.SE`

**Structure minimale :**
```lua
-- server/NPC_SpawnManager.lua
if not isServer() then return end

local NPC_SpawnManager = {}

function NPC_SpawnManager.spawnAt(x, y, z, npcData)
    -- TODO : implémenter avec l'API B42 vérifiée
    -- Référence : mod example/NPC_Helper_Mod/
end

Events.EveryOneMinute.Add(function()
    -- Boucle de spawn/despawn
end)

PHNPC.registerModule("NPC_SpawnManager", NPC_SpawnManager)
```

### 6.2 Mouvement du PNJ — `server/NPC_SpawnManager.lua`

> ⚠️ `pathToCharacter()` cause un `ClassCastException` avec les IsoPlayer NPCs.
> Utiliser `pathToLocationF(x, y, z)` à la place.

```lua
-- BON :
iso:pathToLocationF(targetX, targetY, targetZ)

-- MAUVAIS (crash) :
iso:pathToCharacter(player)   -- ClassCastException IsoPlayer/IsoZombie
```

### 6.3 Menus contextuels — `client/NPC_InteractionClient.lua`

```lua
-- Ajouter une entrée au menu clic-droit sur un PNJ
Events.OnFillWorldObjectContextMenu.Add(function(player, context, worldObjects, test)
    for _, obj in ipairs(worldObjects) do
        if obj:getModData().PHNPC_id then
            context:addOption(
                getText("ContextMenu_PHNPC_Talk"),
                obj,
                function(isoObj)
                    -- TODO : ouvrir le dialogue
                end
            )
        end
    end
end)
```

### 6.4 UI (fenêtres) — `client/UI/`

```lua
-- Pattern standard ISPanel B42
MaFenetre = ISPanel:derive("MaFenetre")

function MaFenetre:new(x, y, w, h)
    local o = ISPanel.new(self, x, y, w, h)
    return o
end

function MaFenetre:initialise()
    ISPanel.initialise(self)
    -- Ajouter les widgets (ISButton, ISLabel, ISListBox…)
end

function MaFenetre:render()
    ISPanel.render(self)
    -- Dessiner du texte, des rectangles
    self:drawText("Mon texte", 10, 10, 1, 1, 1, 1, UIFont.Medium)
end
```

### 6.5 Réseau Solo/Multi — `server/NPC_NetworkServer.lua`

```lua
-- Serveur → tous les clients
sendServerCommand(PHNPC.MOD_ID, "cmd_name", { data = "..." })

-- Client → serveur
sendClientCommand(PHNPC.MOD_ID, "cmd_name", { data = "..." })

-- Réception côté serveur :
Events.OnClientCommand.Add(function(module, cmd, player, args)
    if module ~= PHNPC.MOD_ID then return end
    -- traiter cmd
end)

-- Réception côté client :
Events.OnServerCommand.Add(function(module, cmd, args)
    if module ~= PHNPC.MOD_ID then return end
    -- traiter cmd
end)
```

### 6.6 Bridge Ollama — `server/OllamaBridge.lua`

```lua
-- HTTPRequest asynchrone B42
local req = HTTPRequest.get(url, function(statusCode, body)
    if statusCode == 200 then
        -- traiter body (JSON string)
    end
end)
req:send()
```

### 6.7 Commandes admin — `server/AdminCommands.lua`

```lua
-- /phnpc <subcommand> <args>
Events.OnServerCommand.Add(function(module, cmd, args)
    if module ~= PHNPC.MOD_ID then return end
    if cmd == "admin_spawn" then
        -- ...
    end
end)
```

---

## 7. Événements PZ B42 utiles

| Événement | Côté | Description |
|-----------|------|-------------|
| `Events.OnGameStart` | SH | Jeu démarré (init modules) |
| `Events.OnTick` | SH | Chaque tick (~33 ms) |
| `Events.EveryOneMinute` | SH | Cadence spawn/despawn |
| `Events.OnPlayerUpdate` | SH | Mise à jour joueur |
| `Events.OnFillWorldObjectContextMenu` | CL | Menu clic-droit monde |
| `Events.OnServerCommand` | CL | Réception commande serveur→client |
| `Events.OnClientCommand` | SV | Réception commande client→serveur |
| `Events.OnWeaponHitCharacter` | SV | Coup/morsure reçue par un perso |
| `Events.OnZombiesDead` | SV | Zombie tué (pour transformation NPC) |
| `Events.OnCharacterDeath` | SV | Mort d'un personnage |

---

## 8. Ordre d'implémentation recommandé

### Phase 1 — Fondations (déjà faites ✅)
- [x] `mod.info` + `sandbox-options.txt` + traductions
- [x] `shared/00_Core.lua` — namespace PHNPC
- [x] `shared/NPC_Logger.lua` — système de logs
- [x] `shared/NPC_Config.lua` — lecture SandboxVars
- [x] `shared/NPC_DataModel.lua` — modèle de données PNJ
- [x] `shared/NPC_Professions.lua` — catalogue métiers
- [x] `shared/NPC_FactionManager.lua` — gestion factions
- [x] `shared/NPC_Dialogue.lua` — banques de dialogues
- [x] `shared/NPC_NetworkDispatcher.lua` — réseau transparent
- [x] `shared/NPC_Brain.lua` — FSM IA

### Phase 2 — Spawn & Vie (Corps à créer)
- [ ] `server/00_Init.lua` — point d'entrée serveur
- [ ] `server/NPC_SpawnManager.lua` — spawn/despawn B42
- [ ] `server/NPC_NetworkServer.lua` — réception commandes clients

### Phase 3 — Interactions client
- [ ] `client/00_Init.lua` — point d'entrée client
- [ ] `client/NPC_InteractionClient.lua` — menu clic-droit
- [ ] `client/UI/NPC_UI.lua` — fiche info PNJ

### Phase 4 — Fonctionnalités avancées
- [ ] `server/NPC_BiteManagement.lua` — morsure → zombie
- [ ] `server/NPC_ObservationLearning.lua` — apprentissage XP
- [ ] `client/UI/TradeWindow.lua` — commerce
- [ ] `client/UI/SpeechBubbles.lua` — bulles de dialogue

### Phase 5 — IA et extras
- [ ] `server/OllamaBridge.lua` — bridge IA local
- [ ] `client/UI/OllamaChatUI.lua` — chat IA
- [ ] `client/UI/QuestJournalUI.lua` — journal de quêtes
- [ ] `server/AdminCommands.lua` — commandes /phnpc

---

## 9. Tester le mod

### Synchronisation rapide
```powershell
# Copier le mod dans le dossier Zomboid pour tester
$src = "D:\PZ Mods\Dynamic_NPC_Overhaul\B42"
$dst = "C:\Users\$env:USERNAME\Zomboid\mods\PH_DynamicNPCOverhaul"
Copy-Item -Path "$src\*" -Destination $dst -Recurse -Force
```

### Activer les logs en jeu
Dans `sandbox-options.txt`, `DebugMode = true` active les logs `TRACE/DEBUG`.

### Commandes console (en jeu)
```
/phnpc list           → liste les PNJ actifs
/phnpc spawn          → force un spawn
/phnpc debug          → bascule le mode debug
```

---

## 10. Pièges courants à éviter

| Problème | Cause | Solution |
|----------|-------|----------|
| `KahluaException: '=' expected near continue` | `continue` invalide en Lua 5.1 | Remplacer par `if not ... then ... end` |
| `Object tried to call nil in pcall` | `pcall` indisponible au chargement | Wrapper local `local ok, err = pcall(...)` |
| `ClassCastException IsoPlayer/IsoZombie` | `pathToCharacter()` sur IsoPlayer NPC | Utiliser `pathToLocationF(x, y, z)` |
| Fichier Translate ignoré | Mauvais nom (`SandboxVars_EN.txt`) | Utiliser `Sandbox_EN.txt` |
| Option Sandbox absente | `type = enum` dans sandbox-options.txt | Utiliser `type = integer` |
| Commentaires `--` ignorés/plantent | Parseur PZ sandbox ne lit pas Lua | Supprimer tous les `--` du sandbox |
| Mod non chargé | `pzversion` au lieu de `targetVersion` | Corriger mod.info |
