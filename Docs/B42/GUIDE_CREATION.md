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

## 6. APIs B42 clés à implémenter (Corps manquant)

### 6.1 Spawn d'un PNJ — `server/NPC_SpawnManager.lua`

> ✅ API validée en jeu sur PZ B42.18.0 — `addZombiesInOutfit` est la méthode fonctionnelle.

**API de spawn B42 confirmée :**
```lua
-- server/NPC_SpawnManager.lua
-- addZombiesInOutfit(x, y, z, count, outfitName, female) → table d'IsoZombie
local npcs = addZombiesInOutfit(x, y, z, 1, "Survivor", isFemale)
local zombie = npcs and npcs[1]
```

> **Note** : `addZombiesInOutfit` retourne des `IsoZombie`, pas des `IsoPlayer`.  
> C'est intentionnel pour B42 — la conversion humaine se fait ensuite côté client via `NPC_FollowTick.lua`.

**Marquage cross-VM (serveur → client) :**
```lua
-- Via ModData Java (persiste entre VM, accessible dans Events.OnZombieUpdate côté client)
zombie:getModData()["PHNPC_id"]      = npcData.id
zombie:getModData()["PHNPC_IsNPC"]   = true
zombie:getModData()["PHNPC_Female"]  = isFemale

-- Via variable Java AnimEngine (accessible immédiatement dans la même VM)
zombie:setVariable("PHNPC_IsNPC", true)
```

**Structure complète du handler spawn :**
```lua
Events.OnClientCommand.Add(function(module, cmd, player, args)
    if module ~= PHNPC.MOD_ID or cmd ~= "PHNPC_SpawnRequest" then return end
    local x = player:getX() + (math.random(-3, 3))
    local y = player:getY() + (math.random(-3, 3))
    local z = player:getZ()
    local isFemale = (math.random(0, 1) == 1)
    local npcs = addZombiesInOutfit(x, y, z, 1, "Survivor", isFemale)
    if npcs and npcs[1] then
        local zombie = npcs[1]
        zombie:getModData()["PHNPC_IsNPC"]  = true
        zombie:getModData()["PHNPC_Female"] = isFemale
        zombie:setVariable("PHNPC_IsNPC", true)
        sendServerCommand(player, PHNPC.MOD_ID, "PHNPC_SpawnConfirm", {
            id = tostring(zombie:getOnlineID()),
            female = isFemale,
        })
    end
end)
```

### 6.2 Conversion zombie → NPC (pattern Banditize) — `client/NPC_FollowTick.lua`

> PZ B42 ne fournit pas d'API `IsoPlayer` NPC propre. La stratégie est :  
> **spawner un `IsoZombie` + le convertir en humain côté client** via `Events.OnZombieUpdate`.

**Déclencheur de conversion :**
```lua
-- client/NPC_FollowTick.lua
Events.OnZombieUpdate.Add(function(zombie)
    -- Triple détection : variable Java / ModData / liste pending
    local isNPC = zombie:getVariableBoolean("PHNPC_IsNPC")
              or (zombie:getModData()["PHNPC_IsNPC"] == true)
              or _pendingNPCIds[tostring(zombie:getOnlineID())]
    if not isNPC then return end

    local isFemale = zombie:getModData()["PHNPC_Female"] == true

    if not _convertedNPCs[zombie] then
        _convertedNPCs[zombie] = true  -- AVANT convertToNPC (anti-boucle infinie)
        convertToNPC(zombie, isFemale)
        attachDataModel(zombie)
    else
        enforceNPC(zombie)
        doFollow(zombie, getPlayer())
    end
end)
```

> **⚠️ Piège critique** : marquer `_convertedNPCs[zombie] = true` **AVANT** d'appeler `convertToNPC`.  
> Si `convertToNPC` plante (ex : méthode inexistante), le zombie est quand même marqué.  
> Sans ce guard, chaque tick retentera la conversion → crash en boucle sur la console.

**Fonctions clés de `convertToNPC` :**
```lua
local function convertToNPC(zombie, isFemale)
    -- CRITIQUE : hors pcall pour garantir l'écriture vers l'AnimEngine Java
    zombie:setVariable("PHNPC_IsNPC", "true")  -- STRING fallback
    zombie:setVariable("PHNPC_IsNPC", true)     -- BOOL (condition XML PHNPC_Idle.xml)
    zombie:setVariable("PHNPC_IsFemale", isFemale)

    -- Vider le contexte d'action → force AnimEngine à re-lire les XML
    pcall(function()
        if zombie:getActionContext() then zombie:getActionContext():clear() end
    end)

    -- Désactiver mécaniques zombie
    pcall(function() zombie:setNoTeeth(true) end)
    pcall(function() zombie:setTarget(nil) end)
    pcall(function() zombie:clearAggroList() end)
    pcall(function() zombie:setTimeSinceSeenFlesh(1000000) end)

    -- Type de marche humaine
    pcall(function() zombie:setWalkType("Walk") end)
    pcall(function() zombie:setVariable("GCWalkType", "Walk") end)

    -- Visuels humains
    applyHumanVisuals(zombie, isFemale)
    pcall(function() zombie:setDressInRandomOutfit(false) end)
end
```

> **⚠️ `setMaxHealth`/`setHealth` n'existent PAS sur `IsoZombie` en B42.**  
> Les appeler dans un pcall produit `Object tried to call nil in pcall` qui **remonte** et crashe la fonction.

**`enforceNPC` — ré-appliqué à chaque tick :**
```lua
local function enforceNPC(zombie)
    zombie:setVariable("PHNPC_IsNPC", true)  -- hors pcall, garanti chaque tick
    pcall(function() zombie:setNoTeeth(true) end)
    pcall(function() zombie:setTarget(nil) end)
    pcall(function() zombie:clearAggroList() end)
    pcall(function() zombie:setTimeSinceSeenFlesh(1000000) end)
end
```

**`doFollow` — navigation + animation Walk :**
```lua
local function doFollow(zombie, player)
    local dist = -- calculer distance zombie↔joueur
    if dist <= FOLLOW_MIN_DIST then
        zombie:setVariable("zombieWalkType", "")  -- → PHNPC_Idle.xml
        pcall(function() zombie:faceThisObject(player) end)
        return
    end
    local speed = (dist > FOLLOW_RUN_DIST) and "Run" or "Walk"
    zombie:setVariable("zombieWalkType", speed)  -- ⚠️ CRITIQUE : condition 2 PHNPC_Walk.xml
    pcall(function() zombie:setWalkType(speed) end)
    pcall(function() zombie:WalkTo(targetX, targetY, targetZ) end)
end
```

### 6.3 AnimSets XML — animer comme un humain

Les AnimSets sont des fichiers XML qui définissent des **règles de substitution d'animation**.  
Pour un `IsoZombie` converti en NPC, on crée des fichiers dans `42/media/AnimSets/zombie/<etat>/`.

> **Confirmé en jeu** : PZ log `overrides media/animsets/zombie/idle/phnpc_idle.xml` au chargement.

**Structure des fichiers :**
```
42/media/AnimSets/zombie/
├── idle/PHNPC_Idle.xml           # PHNPC_IsNPC=true → Bob_Idle
├── walktoward/PHNPC_Walk.xml     # PHNPC_IsNPC=true + zombieWalkType=Walk → Bob_Walk
├── walktoward/PHNPC_Run.xml      # PHNPC_IsNPC=true + zombieWalkType=Run → Bob_Run
└── faceTarget/PHNPC_FaceTarget.xml
```

**Exemple — PHNPC_Walk.xml (DEUX conditions obligatoires) :**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<animset>
    <animset_override>
        <conditions>
            <condition name="PHNPC_IsNPC"    type="BOOL"   value="true"/>
            <condition name="zombieWalkType" type="STRING" value="Walk"/>
        </conditions>
        <anims><anim name="Bob_Walk"/></anims>
    </animset_override>
</animset>
```

> **⚠️ Les deux conditions sont obligatoires** — `PHNPC_Walk.xml` ne se déclenche pas si  
> `zombieWalkType` n'est pas envoyé via `zombie:setVariable("zombieWalkType", "Walk")`.

### 6.4 Menus contextuels — `client/NPC_InteractionClient.lua`

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

## 7. Persistance des NPC après reload de partie

### Le problème

En PZ B42, **`zombie:setVariable()` n'est PAS sauvegardé sur disque**. C'est une variable AnimEngine
stockée en RAM sur l'objet Java. Après un reload ou un déchargement de chunk :
- `getVariableBoolean("PHNPC_IsNPC")` → `false` (perdu)
- Le client ne reconnaît plus le zombie comme NPC → pas d'`enforceNPC` → zombie attaque

**Ce qui est persisté** : `zombie:getModData()["PHNPC_IsNPC"]` (Java HashMap sérialisé sur disque).

### La solution double

**Côté serveur** (`NPC_SpawnManager.lua`) :
```lua
-- EveryOneMinute : re-scanner et ré-appliquer setVariable si perdu
Events.EveryOneMinute.Add(function()
    local list = getCell() and getCell():getZombieList()
    if not list then return end
    for i = 0, list:size() - 1 do
        local z = list:get(i)
        if z then
            local ok, md = pcall(function() return z:getModData() end)
            if ok and md then
                local v = md.PHNPC_IsNPC
                -- Gérer boolean ET string (sérialisation PZ variable selon le build)
                if v == true or v == "true" then
                    local already = false
                    pcall(function() already = z:getVariableBoolean("PHNPC_IsNPC") end)
                    if not already then
                        z:setVariable("PHNPC_IsNPC", true)
                        z:setVariable("PHNPC_IsFemale", md.PHNPC_IsFemale == true)
                    end
                end
            end
        end
    end
end)
```

**Côté client** (`NPC_FollowTick.lua`) :
```lua
-- 1. Vider les caches sur chargement (gère "charger sans quitter")
Events.OnGameStart.Add(function()
    _convertedNPCs = {}
    if PHNPC._activeNPCs then
        for k in pairs(PHNPC._activeNPCs) do PHNPC._activeNPCs[k] = nil end
    end
end)

-- 2. Détection Method B : tester boolean ET string
local v = md.PHNPC_IsNPC
if v == true or v == "true" then isNPC = true end

-- 3. Persister l'état FSM en ModData toutes les ~4 secondes
local _fsmSaveTick = 0
Events.OnTick.Add(function()
    _fsmSaveTick = _fsmSaveTick + 1
    if _fsmSaveTick < 120 then return end
    _fsmSaveTick = 0
    for zombie, _ in pairs(_convertedNPCs) do
        local npcData = PHNPC._activeNPCs and PHNPC._activeNPCs[zombie]
        if npcData then
            pcall(function()
                local md = zombie:getModData()
                if md then
                    md.PHNPC_FsmState = npcData.fsmState or "idle"
                    md.PHNPC_Health   = npcData.health   or 100
                end
            end)
        end
    end
end)
```

### Résumé du flux de persistance

```
SPAWN ──► addZombiesInOutfit
             ├── setVariable("PHNPC_IsNPC", true)   ← RAM seulement, perdu au reload
             └── ModData["PHNPC_IsNPC"] = true       ← Disque, TOUJOURS persisté

RELOAD ──► Zombie rechargé depuis disque
             ├── ModData.PHNPC_IsNPC  = true  ✅ (persisté)
             ├── getVariableBoolean() = false ❌ (perdu)
             ├── EveryOneMinute serveur → setVariable restauré ✅
             └── OnZombieUpdate client → convertToNPC re-déclenché ✅
```

---

## 8. Événements PZ B42 utiles

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

## 9. Ordre d'implémentation recommandé

### Phase 1 — Fondations (faites ✅)
- [x] `mod.info` + `sandbox-options.txt` + traductions
- [x] Structure B42 native (`common/` + `42/` + `tools/`)
- [x] `shared/00_Core.lua` — namespace PHNPC
- [x] `shared/NPC_Logger.lua` — système de logs
- [x] `shared/NPC_Config.lua` — lecture SandboxVars
- [x] `shared/NPC_DataModel.lua` — modèle de données PNJ
- [x] `shared/NPC_Professions.lua` — catalogue métiers
- [x] `shared/NPC_FactionManager.lua` — gestion factions
- [x] `shared/NPC_Dialogue.lua` — banques de dialogues
- [x] `shared/NPC_NetworkDispatcher.lua` — réseau transparent
- [x] `shared/NPC_Brain.lua` — FSM IA

### Phase 2 — Spawn & Corps ✅ (TERMINÉ)
- [x] `server/00_Init.lua` — point d'entrée serveur, handler PHNPC_SpawnRequest
- [x] `server/NPC_SpawnManager.lua` — spawn via `addZombiesInOutfit` B42 + `EveryOneMinute` re-scan ✅
- [x] `client/00_Init.lua` — point d'entrée client, handler PHNPC_SpawnConfirm
- [x] `client/NPC_FollowTick.lua` — conversion zombie→NPC, visuals humains, suivi joueur, errance autonome (`doWander`) ✅
- [x] `client/NPC_SpawnDebug.lua` — menu debug spawn (visible avec `-debug` flag)
- [ ] `42/media/AnimSets/zombie/` — AnimSets XML (Bob_Idle, Bob_Walk, Bob_Run), [Ne fonctionne toujours pas, à tester après correction du spawn ]

### Phase 3 — Interactions client ✅ (TERMINÉ)
- [x] `client/NPC_InteractionClient.lua` — détecte le NPC, option « Parler à [Nom] »
- [x] `client/NPC_InteractionClient.lua` — option **▶ Suivre moi / ■ Rester ici** (bascule `npcData.followMode`)
- [x] `client/UI/NPC_DialogueWindow.lua` — ISPanel : nom, profession, santé, ligne NPC_Dialogue, bouton Suivre/Rester, speech bubble
- [x] `client/UI/NPC_SpeechBubble.lua` — toast bas-écran + tentative `zombie:setSpeakBubble(text)` native PZ

### Phase 3b — IA comportementale ✅ (TERMINÉ)
- [x] `NPCDataModel.followMode = false` — NPC autonome par défaut
- [x] `NPC_Brain.register(npcData)` dans `attachDataModel` — cerveau branché à chaque NPC
- [x] `doBrainAction(zombie, npcData)` — lit `fsmState` et dispatche les actions physiques
- [x] `NPC_Brain.evaluateThreat` : scan zombie hostile proche (rayon 15 cases, cap 60) → stocke `npcData.fsmTarget`
- [x] FSM → physique : `wander`/`work` → `doWander`, `flee` → course opposée menace réelle, `guard`/`trade`/`defend` → sur place
- [x] `doBrainAction` flee : priorité `fsmTarget` > zombie hostile proche > joueur (fallback)
- [x] `NPC_Brain.unregister(id)` appelé au nettoyage des entités mortes
- [x] **Bug fix** : `safeCall` helper + `ZombieIdleState` → `getActionContext():clear()` + guard emitter
- [x] **Bug fix** : `setWalkType()` supprimé partout (read-only B42)
- [x] **Bug fix** : boutons UI ISButton — `backgroundColor` + `borderColor` pour visibilité

### Phase 4 — Fonctionnalités avancées
- [ ] `server/NPC_BiteManagement.lua` — morsure → zombie
- [ ] `server/NPC_ObservationLearning.lua` — apprentissage XP
- [ ] `client/UI/TradeWindow.lua` — commerce
- [ ] `client/UI/SpeechBubbles.lua` — bulles de dialogue

### Phase 5 — IA et extras
- [ ] `server/OllamaBridge.lua` — bridge IA local (Facultatif)
- [ ] `client/UI/OllamaChatUI.lua` — chat IA (Facultatif)
- [ ] `client/UI/QuestJournalUI.lua` — journal de quêtes
- [ ] `server/AdminCommands.lua` — commandes /phnpc

---

## 9. Tester le mod

### Synchronisation rapide
```powershell
# Depuis D:\PZ Mods\Dynamic_NPC_Overhaul\B42\tools\
.\sync_to_mods.ps1
# Synchronise workspace → C:\Users\Nicolas\Zomboid\mods\PH_DynamicNPCOverhaul\
# et              → F:\Steam Games\steamapps\common\ProjectZomboid\mods\PH_DynamicNPCOverhaul\
```

Le script supprime l'ancienne version et recopie proprement `42/`, `common/`, `mod.info`, `preview.png`, `icon.png`.

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
| **`getCell()` nil sur serveur dédié** | Sans joueur local, `getCell()` peut renvoyer `nil` | Toujours `local cell = getCell(); if not cell then return end` avant `getZombieList()` |
| **NPC fuit le joueur au lieu des zombies** | `flee` utilisait le joueur comme source | Utiliser `npcData.fsmTarget` (stocké par `evaluateThreat`) — voir `doBrainAction` |
| **`Object tried to call nil in pcall`** | Méthode absente en B42 (`ZombieIdleState`, `setTimeSinceSeenFlesh`, `stopSoundByName`) | Helper `safeCall(obj, method, ...)` : vérifie `obj[method]` avant d'appeler ; remplacer `ZombieIdleState.instance()` par `getActionContext():clear()` ; guard nil sur `getEmitter()` |
| **WARN `read-only variable "zombiewalktype"`** | `zombie:setWalkType()` (méthode Java) pose la variable en read-only | Supprimer tous les appels `setWalkType()` ; utiliser uniquement `zombie:setVariable("zombieWalkType", "Walk" \| "Run" \| "")` |
| **Boutons UI transparents / illisibles** | B42 ne donne pas de fond automatique aux ISButton | Après `btn:initialise()` : `btn.backgroundColor = {r=0.05,g=0.05,b=0.08,a=0.92}` et `btn.borderColor = {r=0.65,g=0.50,b=0.25,a=0.80}` |
| Commentaires `--` ignorés/plantent | Parseur PZ sandbox ne lit pas Lua | Supprimer tous les `--` du sandbox |
| Mod non chargé | `pzversion` au lieu de `targetVersion` | Corriger mod.info |
| **Mod rouge — dépendance manquante** | `require=` avec valeur vide dans mod.info | Supprimer la ligne `require=` si aucune dépendance |
| **Mod rouge — incompatibilité version** | `versionMin` absent ou mal formaté | Utiliser `versionMin=42.0` (format `build.major` obligatoire) |
