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
| Wiki PZ modding B42 | [Référence API](https://pzwiki.net/wiki/Build_42) |

Répertoire de test en jeu : `C:\Users\<USER>\Zomboid\mods\PH_DynamicNPCOverhaul\`

---

## 1. Structure du dossier mod

La structure **obligatoire** pour que PZ B42 charge le mod :

> **Important** : En B42, `common/` est **requis** pour que le mod soit détecté dans le menu.  
> Les fichiers dans `media/lua/` à la racine sont ignorés (structure B41 uniquement).

```
B42/
├── mod.info                    ← OBLIGATOIRE
├── preview.png                 ← Visuel 128×128 (référencé poster=preview.png)
├── icon.png                    ← Icône Workshop
├── tools/
│   └── sync_to_mods.ps1        ← Déploiement en un clic
├── 42/                         ← Chargé uniquement en B42.x
│   ├── mod.info                ← Copie du mod.info racine
│   └── media/lua/              ← Peut rester vide (contenu dans common/)
└── common/                     ← OBLIGATOIRE — Chargé dans toutes les versions B42
    └── media/
        ├── sandbox-options.txt
        └── lua/
            ├── shared/             ← Chargé CLIENT + SERVEUR
            ├── server/             ← Chargé SERVEUR uniquement
            └── client/             ← Chargé CLIENT uniquement
```

---

## 2. `mod.info` — Format B42

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

> **Règles** :
> - `poster=` = nom du fichier image à la racine du mod (`poster.png`)
> - `versionMin=42.0` — format **obligatoire** `build.major` ; `42` seul (sans `.0`) n'est pas reconnu
> - `require=` **absent** — une ligne `require=` vide est parsée par PZ comme « dépendance ID vide » → **mod rouge**
> - Supprimé : `url`, `tags`, `category`, `pzversion`, `targetVersion`

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

## 6. APIs B42 cles a implementer (architecture v2.3.0)

> **Architecture IsoPlayer** : Les NPCs sont des `IsoPlayer` natifs, pas des `IsoZombie` convertis.
> `IsoPlayer.new()` donne les animations Bob/Kate, les sons humains et le pathfinding reel.
> Le serveur calcule les destinations et les broadcast aux clients a 10Hz.

### 6.1 Spawn NPC cote serveur — `server/NPC_SpawnManager.lua`

```lua
-- Handler PHNPC_RequestSpawn (server ou solo via Dispatcher)
Dispatcher.on("PHNPC_RequestSpawn", function(data, fromPlayer)
    local isFemale = (ZombRand(2) == 1)
    local forename = SurvivorFactory.getRandomForename(isFemale)
    local surname  = SurvivorFactory.getRandomSurname()
    local ts       = tostring(getTimestampMs())
    local npcId    = "PHNPC_" .. forename .. "_" .. surname .. "_" .. ts

    -- Enregistrer l'etat serveur
    _serverNPCs[npcId] = { id = npcId, x = data.x, y = data.y, followMode = true, ... }

    -- Broadcaster le spawn a tous les clients
    Dispatcher.send("all", "PHNPC_DoSpawn", {
        id = npcId, forename = forename, surname = surname,
        isFemale = isFemale, x = data.x, y = data.y, z = data.z,
    })
end)
```

### 6.2 Creation NPC cote client — `client/NPC_FollowTick.lua`

```lua
local function createNPCFromData(data)
    -- Anti-doublon : ne pas recreer si l'ID existe deja
    if data.id and PHNPC.npcs_byId[data.id] then return end

    -- 1. Descripteur visuel (apparence + outfit + profession)
    local desc = SurvivorFactory.CreateSurvivor(nil, data.isFemale)
    desc:setForename(data.forename)
    desc:setSurname(data.surname)

    -- Profession aleatoire (visuel outfit)
    local plist = ProfessionFactory.getProfessions()
    if plist and plist:size() > 0 then
        local prof = plist:get(ZombRand(plist:size()))
        desc:setProfession(prof:getType())
    end

    -- 2. Entite IsoPlayer native (animations Bob/Kate)
    local cell = getWorld():getCell()
    local npc  = IsoPlayer.new(cell, desc, data.x, data.y, data.z)

    -- 3. Configuration NPC
    npc:setNPC(true)                            -- desactive l'input joueur
    npc:setForname(data.forename)
    npc:setSurname(data.surname)
    npc:setUsername(data.forename .. " " .. data.surname)
    npc:setSceneCulled(false)
    npc:setDir(IsoDirections.SE)

    -- 4. Registre
    PHNPC.npcs[npc]          = { id = data.id, followMode = true, ... }
    PHNPC.npcs_byId[data.id] = npc

    -- 5. Brain FSM
    Brain.register({ id = data.id, fsmState = "idle", isoObject = npc, ... })
end
```

### 6.3 Pathfinding cote client — `getPathFindBehavior2()`

```lua
-- Appeler update() chaque tick pour que l'IA progresse
npc:getPathFindBehavior2():update()

-- Recalculer la destination periodiquement (RETARGET = 10 ticks)
npc:getPathFindBehavior2():pathToLocation(tx, ty, tz)

-- Annuler le chemin (quand le NPC s'arrete)
npc:getPathFindBehavior2():cancel()
npc:setPath2(nil)

-- Faire face a un objet (idle)
npc:faceThisObject(player)
```

### 6.4 Server Authority Tick — `server/NPC_SpawnManager.lua`

```lua
-- Toutes les 6 ticks (~10Hz) : broadcaster la destination de chaque NPC
Events.OnTick.Add(function()
    _serverTick = _serverTick + 1
    if _serverTick % 6 ~= 0 then return end

    local players = getRealPlayers()  -- exclut les NPCs (isNPC() == true)

    for id, ns in pairs(_serverNPCs) do
        local tx, ty, tz
        if ns.followMode then
            -- Trouver le joueur reel le plus proche
            tx, ty, tz = nearest_player.x, nearest_player.y, nearest_player.z
        else
            -- Wander : cible aleatoire dans un rayon de 8 tiles
            if ns.wander_age > 300 then
                ns.wander_tx  = ns.x + ZombRand(16) - 8
                ns.wander_ty  = ns.y + ZombRand(16) - 8
                ns.wander_age = 0
            end
            tx, ty, tz = ns.wander_tx, ns.wander_ty, ns.z
        end
        Dispatcher.send("all", "PHNPC_SyncTarget", { id = id, tx = tx, ty = ty, tz = tz })
    end
end)
```

### 6.5 Handler PHNPC_SyncTarget cote client

```lua
Dispatcher.on("PHNPC_SyncTarget", function(data)
    local npc = PHNPC.npcs_byId[data.id]
    if npc and PHNPC.npcs[npc] then
        PHNPC.npcs[npc].server_tx = data.tx
        PHNPC.npcs[npc].server_ty = data.ty
        PHNPC.npcs[npc].server_tz = data.tz
    end
end)
```

### 6.6 Menus contextuels — `client/NPC_FollowTick.lua`

```lua
Events.OnFillWorldObjectContextMenu.Add(function(playerIndex, context, worldObjects, test)
    if test then return end
    local square = ISWorldObjectContextMenu.fetchVars.clickedSquare
    -- Trouver NPC proche du carre clique
    for npc, data in pairs(PHNPC.npcs) do
        if npcValid(npc) then
            local dx = npc:getX() - square:getX()
            local dy = npc:getY() - square:getY()
            if (dx*dx + dy*dy) <= 2.5 then
                context:addOption("Parler a " .. data.fullname, npc, npcOpenDialogue)
                if data.followMode then
                    context:addOption("[PHNPC] Reste ici", npc, npcStopFollow)
                else
                    context:addOption("[PHNPC] Suis-moi", npc, npcStartFollow)
                end
                return
            end
        end
    end
    -- Aucun NPC proche : option spawn
    context:addOption("[PHNPC] Faire apparaitre un PNJ", square, spawnNPC, playerIndex)
end)
```

### 6.7 UI (fenetres) — `client/UI/`

```lua
-- Pattern standard ISPanel B42
MaFenetre = ISPanel:derive("MaFenetre")

function MaFenetre:new(x, y, w, h)
    local o = ISPanel.new(self, x, y, w, h)
    return o
end

function MaFenetre:initialise()
    ISPanel.initialise(self)
    -- Ajouter les widgets (ISButton, ISLabel, ISListBox...)
end

function MaFenetre:render()
    ISPanel.render(self)
    self:drawText("Mon texte", 10, 10, 1, 1, 1, 1, UIFont.Medium)
end
```

### 6.8 Reseau Solo/Multi — NPC_NetworkDispatcher

```lua
-- API unifiee : meme code en solo et multi
Dispatcher.send("server", "PHNPC_RequestSpawn", { x = x, y = y, z = z })
Dispatcher.send("all",    "PHNPC_DoSpawn",      { id = id, ... })
Dispatcher.on("PHNPC_DoSpawn", function(data)  ... end)

-- En solo : Dispatcher court-circuite directement (meme VM)
-- En multi : sendClientCommand / sendServerCommand sous le capot
```

---

## 7. Persistance des NPC entre sessions — `client/NPC_Save.lua`

### Mecanisme

```
NPC vivant
  └── ModData.getOrCreate("PHNPC_Registry")  ← registre (id, position, fsmState, ...)
  └── npc:save(saveDir .. id)                ← apparence complete + inventaire

Au chargement (1 tick apres OnGameStart)
  └── Lire PHNPC_Registry
  └── Pour chaque entree : IsoPlayer.new() + npc:load(saveDir .. id)
  └── Brain.register() pour reprendre la FSM
```

### `getSaveDir()` — important : wrappee en pcall

```lua
local function getSaveDir()
    local sep = getFileSeparator()
    local ok, result = pcall(function()
        local gameMode  = getWorld():getGameMode() or "Survival"
        local worldName = getWorld():getWorld()     or "default"
        return Core.getMyDocumentFolder()
            .. sep .. "Saves"
            .. sep .. gameMode
            .. sep .. worldName
            .. sep
    end)
    return ok and result or nil  -- nil = skip save/load gracieusement
end
```

> **Pourquoi pcall ?** `getWorld():getGameMode()` peut throw si le monde n'est pas encore
> charge (ex. premier OnTick avant OnGameStart complet). En multijoueur dedie, le chemin
> `Saves/Multiplayer/<worldname>/` est valide cote client pour un cache local.

### Hooks

```lua
Events.OnSave.Add(function()     NPC_Save.saveAll()  end)
Events.OnGameStart.Add(function() _loadPending = true  end)
Events.OnTick.Add(function()
    if _loadPending and not _loadDone then
        _loadDone    = true
        _loadPending = false
        NPC_Save.loadAll()
    end
end)
```

---

## 8. Evenements PZ B42 utiles

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

## 9. Ordre d'implementation recommande

### Phase 1 - Fondations (faites)
- [x] `mod.info` + `sandbox-options.txt` + traductions
- [x] Structure B42 native (`common/` + `42/` + `tools/`)
- [x] `shared/00_Core.lua` — namespace PHNPC
- [x] `shared/NPC_Logger.lua` — systeme de logs
- [x] `shared/NPC_Config.lua` — lecture SandboxVars
- [x] `shared/NPC_DataModel.lua` — modele de donnees PNJ
- [x] `shared/NPC_Professions.lua` — catalogue metiers
- [x] `shared/NPC_FactionManager.lua` — gestion factions
- [x] `shared/NPC_Dialogue.lua` — banques de dialogues
- [x] `shared/NPC_NetworkDispatcher.lua` — reseau transparent
- [x] `shared/NPC_Brain.lua` — FSM IA

### Phase 2 - Spawn et Corps IsoPlayer (TERMINE v2.1-v2.2)
- [x] `server/NPC_SpawnManager.lua` v2.0 — spawn server-side, ID unique horodate
- [x] `client/NPC_FollowTick.lua` v2.2 — IsoPlayer.new(), SurvivorFactory, menu clic-droit, follow/wander/flee

### Phase 3 - Persistance + FSM Brain (TERMINE v2.2)
- [x] `client/NPC_Save.lua` v1.0 — ModData registry + npc:save/load
- [x] `NPC_FollowTick v2.2` — Brain FSM branche, NetworkDispatcher integre
- [x] 42 textures UI (`42/media/textures/NPC_*.png`)

### Phase 4 - Server Authority + Corrections (TERMINE v2.3)
- [x] `NPC_SpawnManager v3.0` — tick 10Hz PHNPC_SyncTarget, getRealPlayers(), PHNPC_SetFollowMode, PHNPC_RemoveNPC
- [x] `NPC_FollowTick v2.3` — handler PHNPC_SyncTarget, npcs_byId, spawn dedup, notify server on followMode change
- [x] `NPC_Save v1.1` — getSaveDir() pcall-safe

### Phase 5 - Fonctionnalites avancees
- [ ] `server/NPC_BiteManagement.lua` — morsure -> zombie
- [ ] `server/NPC_ObservationLearning.lua` — apprentissage XP
- [ ] `client/UI/TradeWindow.lua` — commerce
- [ ] `server/OllamaBridge.lua` — bridge IA local (facultatif)
- [ ] `client/UI/OllamaChatUI.lua` — chat IA (facultatif)
- [ ] `client/UI/QuestJournalUI.lua` — journal de quetes
- [ ] `server/AdminCommands.lua` — commandes /phnpc

---

## 10. Tester le mod

### Synchronisation rapide
```powershell
# Depuis D:\PZ Mods\Dynamic_NPC_Overhaul\B42\tools\
.\sync_to_mods.ps1
# Synchronise workspace -> C:\Users\Nicolas\Zomboid\mods\PH_DynamicNPCOverhaul\
```

### Activer les logs en jeu
Dans `sandbox-options.txt`, `DebugMode = true` active les logs `TRACE/DEBUG`.

### Commandes console (en jeu)
```
/phnpc list           -> liste les PNJ actifs
/phnpc spawn          -> force un spawn
/phnpc debug          -> bascule le mode debug
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
| **`getCell()` nil sur serveur dédié** | Sans joueur local, `getCell()` peut renvoyer `nil` | Toujours `local cell = getCell(); if not cell then return end` avant `getZombieList()` |
| **NPC fuit le joueur au lieu des zombies** | `flee` utilisait le joueur comme source | Utiliser `npcData.fsmTarget` (stocké par `evaluateThreat`) — voir `doBrainAction` |
| **`Object tried to call nil in pcall`** | Méthode absente en B42 (`ZombieIdleState`, `setTimeSinceSeenFlesh`, `stopSoundByName`) | Helper `safeCall(obj, method, ...)` ; guard nil sur `getEmitter()` |
| **WARN `read-only variable "zombiewalktype"`** | `zombie:setWalkType()` pose la variable en read-only | Supprimer `setWalkType()` ; utiliser `doSprinter()` / `doFastShambler()` / `doFakeShambler()` (API B42.18) |
| **`attempted index: clear of non-table: ActionContext@...`** | `getActionContext()` retourne un objet Java non-table — `.clear` inaccessible depuis Kahlua | ⛔ Ne jamais appeler `getActionContext():clear()`. Pattern Bandits : `setBumpType("Shrug")` dans `convertToNPC` |
| **NPC continue de lunger/attaquer** | L'IA zombie native se réactive entre les ticks | `setUseless(true)` dans `enforceNPC` chaque tick (pattern Bandits B42.18) + `clearAggroList + setTarget(nil)` si `asn == "lunge"` |
| **Boutons UI transparents / illisibles** | B42 ne donne pas de fond automatique aux ISButton | `btn.backgroundColor = {r=0.05,g=0.05,b=0.08,a=0.92}` et `btn.borderColor = {r=0.65,g=0.50,b=0.25,a=0.80}` |
| Commentaires `--` ignorés/plantent | Parseur PZ sandbox ne lit pas Lua | Supprimer tous les `--` du sandbox |
| Mod non chargé | `pzversion` au lieu de `targetVersion` | Corriger mod.info |
| **Mod rouge — dépendance manquante** | `require=` avec valeur vide dans mod.info | Supprimer la ligne `require=` si aucune dépendance |
| **Mod rouge — incompatibilité version** | `versionMin` absent ou mal formaté | Utiliser `versionMin=42.0` (format `build.major` obligatoire) |
