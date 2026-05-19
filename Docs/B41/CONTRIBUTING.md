# 🛠️ Guide de Contribution - Dynamic NPC Overhaul

**Standard editorial**: v1  
**Type**: Developpement (interne)  
**Audience**: Contributeurs et mainteneurs  
**Version doc**: v1.0  
**Confidentialite**: Interne  
**Derniere mise a jour**: 12 mai 2026

**Bienvenue, contributeur!** Ce document explique comment naviguer l'architecture du mod et ajouter des fonctionnalités.

---

## Architecture Générale

Le mod suit strictement l'architecture **Client/Serveur** de Project Zomboid.

```
Workspace Structure:
├── media/lua/
│   ├── server/          ← Logique serveur (calculs, transactions, ordres)
│   ├── client/          ← UI et interactions joueur
│   ├── shared/          ← Modèles de données et logique métier partagée
│   └── [future]/        ← Modules spécialisés
└── Docs/                ← Toute la documentation (publique + développement)

Rôles:
┌─────────────────────────────────────────────────────────┐
│ Server (media/lua/server/)                              │
│ • Exécution des ordres NPC (NPCBrain.lua)               │
│ • Transactions inventaire (NPCInteractionHooks.lua)     │
│ • Économie & prix (via NPCMemory partagé)               │
│ • Dialogue IA routing (NPC_NetworkServer.lua)           │
│ • Single source of truth pour état PNJ                  │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ Client (media/lua/client/)                              │
│ • HUD & interface (NPC_UI.lua)                          │
│ • Envoi de commandes serveur (NPCInteractionClient.lua) │
│ • Chat avec Ollama (OllamaChatUI.lua)                   │
│ • Affichage synced state du serveur                     │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ Shared (media/lua/shared/)                              │
│ • Modèles de données (NPCDataModel.lua)                 │
│ • Logique métier (NPCMemory.lua, NPCFactionManager.lua) │
│ • Structures économie, professions, relations sociales  │
└─────────────────────────────────────────────────────────┘
```

---

## Avant de Commencer

### Prérequis
1. **Git**: Clone le repo
2. **Lua IDE** (optionnel mais utile): VSCode + Lua extension
3. **Project Zomboid**: Installation fonctionnelle pour tester
4. **Basic Lua knowledge**: Tables, functions, OOP patterns

### Setup Local

```bash
git clone https://github.com/[ton-username]/Dynamic_NPC_Overhaul.git
cd Dynamic_NPC_Overhaul

# Copier dans dossier mods PZ
cp -r media ~/Zomboid/Mods/Dynamic_NPC_Overhaul/

# Vérifier que ça charge
# Lancer PZ et vérifier dans mod options
```

### Testing Setup

```bash
# Option 1: Solo test
1. Lancer PZ en solo
2. Charger le mod dans options
3. Spawner quelques NPCs (admin panel ou manuelle)
4. Observer console pour debug logs

# Option 2: Server multijoueur test
1. Lancer serveur avec mod
2. Connect clients
3. Tester avec `/phnpc` commandes
```

---

## Core Concepts

### 0. Traduction (Patch v1.0.1)

Règle projet:

- Ne pas créer de fichiers `.txt` pour les dialogues générés par IA.
- Côté client, récupérer la langue via `Translator.getLanguage():toString()`.
- Côté serveur, injecter ce code langue dans le `systemPrompt` (contrainte stricte de sortie).
- Pour fallback, utiliser d'abord `getText("IGUI_...")` puis un secours Lua FR/EN.
- Centraliser les clés et fallback dans `media/lua/shared/NPCDialogueLocalization.lua`.

Pourquoi:

- Les réponses IA sont dynamiques et non finies: une traduction statique exhaustive est impossible.
- Le mode mixte (`getText` + secours Lua) évite les régressions si une clé IGUI manque.

Verification recommandee:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/check_translation_keys.ps1
```

Mode strict (doublons suspects bloquants):

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tools/check_translation_keys.ps1 -FailOnDuplicate
```

Ce script vérifie l'alignement des clés entre:
- `media/lua/shared/NPCDialogueLocalization.lua`
- `media/lua/shared/Translate/FR/IG_UI_FR.txt`
- `media/lua/shared/Translate/EN/IG_UI_EN.txt`

Depuis la v1.0.1:
- Le fallback dialogue tente d'éviter la répétition (historique court par PNJ).
- Le fallback évite aussi la répétition thématique via une mémoire conversationnelle par PNJ + joueur.
- Le ton social du fallback respecte la relation joueur/PNJ: pas de ligne hostile pour un allié sans déclencheur négatif récent.
- Le fallback peut reparler d'événements mémoire récents déjà présents en runtime (trade, aide, hostilité, morsure cachée).
- Le fallback classe aussi explicitement la relation courante en variantes positives, neutres, méfiantes, craintives ou hostiles.
- Les ordres FSM terminés sont journalisés pour nourrir les dialogues de suivi après garde, récupération, fouille, construction ou cuisine.
- Les dialogues fallback peuvent aussi reformuler les paramètres d'ordre utiles: base ciblée, site de construction, cible de fouille, suivi joueur/PNJ, rayon défensif, escorte, discrétion.
- Les valeurs trop techniques sont humanisées avant injection dans les répliques pour éviter d'exposer des noms système bruts comme `base_12` ou `site_3`.
- Quand les données runtime sont disponibles, la base et le chantier sont décrits avec un contexte spatial (ex: atelier nord, barricade exterieure est, chantier nord-ouest).
- Les transactions de troc sont protégées par verrou court côté serveur sur les PNJ impliqués pour éviter les doubles consommations/duplications en concurrence.
- La mémoire sociale applique un pruning agressif et centralisé pour limiter l'empreinte de sauvegarde en serveur long terme.
- Le cerveau PNJ inclut une routine anti-blocage (surplace détecté -> déblocage progressif) pour les limites de pathfinding.
- Une couche serveur dédiée (`NPCEnvironmentHooks.lua`) applique une politique claire: porte fermée (ouverture active), barricade (blocage explicite), obstacle invalide (événement), fallback de contournement.
- Les dialogues fallback couvrent aussi commerce, actions métier, conditions terrain et état faction.

Depuis la v1.0.2:
- Les états avancés sont centralisés dans `NPCMemory.lua` (`social`, `psychology`, `environment`, `expedition`) et doivent rester la source de vérité.
- Les comportements de survie météo, freeze/rage trauma et expéditions hors-écran sont orchestrés dans `NPCBrain.lua`.
- Les blessures localisées doivent alimenter `ApplyLocalizedInjuryEffects()` plutôt que des malus ad hoc ailleurs.
- Les interactions sociales gameplay (trade/intel/dialogue) passent par `NPCInteractionHooks.lua` pour garder une logique unique de solitude/stress.
- Le fallback de dialogue dans `NPC_NetworkServer.lua` couvre maintenant aussi météo, trauma, blessures, expéditions, social/storytelling et pathing runtime.
- Toute nouvelle clé de dialogue doit être ajoutée simultanément dans:
    - `media/lua/shared/NPCDialogueLocalization.lua`
    - `media/lua/shared/Translate/FR/IG_UI_FR.txt`
    - `media/lua/shared/Translate/EN/IG_UI_EN.txt`
    puis validée avec `tools/check_translation_keys.ps1 -FailOnDuplicate`.

Depuis la v1.0.3:
- Les profils globaux de tuning sont centralisés dans `media/lua/shared/NPCTuningProfiles.lua`.
- Toute modification d'équilibrage doit passer par des multiplicateurs de profil avant d'introduire de nouvelles constantes locales.
- Les profils supportés sont: `realistic`, `hardcore`, `narrative`, `ultra_hardcore`, `rp_soft`.
- Le switch runtime admin passe par `AdminAction:setGameplayProfile` et doit rester global serveur.
- Le HUD admin client (`NPC_UI.lua`) est la référence UX pour le changement de profil en un clic.

Règle de contribution tuning:
- Éviter les valeurs hardcodées non multipliées dans `NPCMemory.lua`, `NPCBrain.lua`, `NPC_BiteManagement.lua`, `NPC_ObservationLearning.lua`.
- Pour chaque nouveau levier gameplay, ajouter un multiplicateur de profil avec valeur `1.0` dans `realistic`.
- Documenter l'impact attendu dans `VALIDATION_CHECKLIST.md` avec métrique mesurable.

### 1. Le Contexte PNJ (npcData)

Chaque PNJ est une table `npcData` avec cette structure:

```lua
npcData = {
    id = "npc_001",
    name = "Alice",
    
    -- Stats & Health
    stats = {
        hunger = 65,
        thirst = 42,
        morale = 78,
        courage = 55,
        intelligence = 65,
        craftSkill = 42,
        -- ...
    },
    
    health = {
        current = 92,
        isBitten = false,
        biteLocation = nil,  -- "torso", "leg", "arm" (future)
        infectionProgress = 0,
    },
    
    -- Profession & Économie
    profession = {
        role = "artisan",
        level = 2,
        tradeMode = "broker",
        sells = {"materials", "tools"},
        buys = {"food", "water"},
    },
    
    economy = {
        cash = 250,
        strategy = "accumulate",
        marketBias = 1.0,  -- 1.0 = neutral, 1.1 = high prices, 0.9 = low
    },
    
    -- Inventaire
    inventory = {
        items = {
            {type = "Base.Sheet", quantity = 5, condition = 100},
            {type = "Base.Screwdriver", quantity = 1, condition = 80},
        },
        currentWeight = 6,
        maxWeight = 14,
    },
    
    -- Mémoire sociale & apprentissage
    memory = {
        reputationByActor = {
            ["player1"] = {trust = 45, fear = 0, gratitude = 10},
            ["npc_002"] = {trust = 65, fear = 0},
        },
        recentEvents = {
            {type = "exchange_done", tick = 1000, payload = {...}},
        },
        observationLog = {
            {skillType = "carpentry", multiplier = 1.2, tick = 950},
        },
    },
    
    -- Faction (clan)
    faction = "faction_builders_001",
    
    -- Sauvegarde
    __version = 2,
}
```

### 2. Le FSM du Serveur (NPCBrain.lua)

`NPCBrain` gère la boucle principale du serveur pour chaque PNJ.

```lua
function NPCBrain:updateOne(npcId, npcEntry)
    -- 1. Degrade besoins (faim +0.02, thirst +0.03)
    self:degradeNeeds(npcData)
    
    -- 2. Calcul contexte: professions, marché, besoins clan
    local profession = NPCMemory.UpdateProfessionStrategy(npcData, {...})
    
    -- 3. Exécute ordre en cours (STUDY, BUILD, COOK, etc)
    local consumed = self:executeOrder(npcId, npcEntry, npcData, ctx)
    
    -- 4. Si pas d'ordre, génère ordre autonome ou idle/wander
    if not consumed then
        local autoOrder = NPCFactionManager:suggestAutonomousOrder(npcId, npcData)
        if autoOrder then
            self:executeOrderObject(npcEntry, npcData, ctx, autoOrder)
        end
    end
    
    -- 5. Sync vers clients (throttled 0.5s)
    self:syncDebugModData(npcId, npcEntry, ctx)
end
```

### 3. Transactions Inventaire (NPCInteractionHooks.lua)

Les échanges passent par le serveur pour éviter duplication/exploit:

```lua
-- Flow d'un échange joueur → PNJ
1. Joueur demande devis via client
   → sendClientCommand("BusinessQuoteRequest", {...})

2. Serveur reçoit commande
   → handleBusinessQuoteRequest(player, args)
   → Calcule devis avec CalculatePriceProfile + ResolveProductionPlan
   → Retourne devis au client
   → sendServerCommand(player, "BusinessQuoteResponse", {quote})

3. Joueur confirme paiement
   → sendClientCommand("BusinessOrderRequest", {...})

4. Serveur valide:
   ✓ Paiement suffisant?
   ✓ PNJ en stock?
   ✓ Capacité inventaire?
   → Sinon: abort avec message

5. Serveur exécute transaction:
   - collectPlayerCurrencyPayment() → items retirés de joueur
   - addNPCCash() → cash ajouté PNJ
   - removeItemFromNPCInventory() → stock réduit
   - addItemToPlayerInventory() → items donnés joueur
   - RecordDirectedExchange() → mémoire mis à jour

6. Send ActionResult avec OK/NOK au client
```

---

## Ajouter une Feature

### Use Case 1: Ajouter une Nouvelle Profession

**Fichiers à modifier**: `media/lua/shared/NPCDataModel.lua`, `media/lua/shared/NPCMemory.lua`

**Étapes**:

```lua
-- 1. Ajouter profession au catalog (NPCDataModel.lua)
local professionCatalog = {
    -- ... existing
    alchemist = {
        role = "alchemist",
        isMerchant = false,
        sells = {"potions", "elixirs"},
        buys = {"herbs", "mushrooms", "water"},
        tradeMode = "premium",
    },
}

-- 2. Ajouter service correspondant (NPCMemory.lua)
local serviceCatalog = {
    -- ... existing
    potion_brew = { baseCost = 45, category = "potions", label = "Alchimie" },
}

-- 3. Ajouter recette de production (NPCMemory.lua)
local productionRecipes = {
    -- ... existing
    brew = {
        workUnits = 8,
        ingredients = {
            herbs = 2,
            water = 1,
        },
        resultByCategory = {
            potions = { itemType = "Base.Potion_Health", quantity = 2 },
        },
    },
}

-- 4. Tester:
-- Ouvrir le HUD ADMIN PNJ et verifier que le snapshot affiche la profession attendue.
-- Verifier aussi le comportement via ActionResult et snapshot apres update.
```

### Use Case 2: Ajouter un Nouvel Ordre PNJ

**Fichiers**: `media/lua/server/NPCBrain.lua`

```lua
-- Dans executeOrderObject(), ajouter case:
elseif orderType == "teach" then
    return self:runTeachOrder(npcEntry, npcData, ctx, order)

-- Implémenter le handler:
function NPCBrain:runTeachOrder(npcEntry, npcData, ctx, order)
    self:setState(ctx, self.STATE_IDLE)
    ctx.activeGoal = self.GOAL_EXPLORE
    
    local params = order.params or {}
    local studentId = params.studentId
    local skillType = params.skillType or "carpentry"
    
    -- Logique: enseigne pendant N ticks
    params.teachProgress = (tonumber(params.teachProgress) or 0) + 1
    if params.teachProgress >= 10 then
        -- Mark complete, mets à jour student skill
        if NPCMemory then
            local studentData = self:getNPCData(studentId)
            if studentData then
                NPCMemory.RecordObservation(studentData, skillType, 1.5)
            end
        end
    end
    
    return true
end

-- 5. Tester avec:
-- Envoyer un OrderAction depuis le HUD (ou client) avec orderType="teach"
-- puis verifier progression dans les snapshots serveur/admin.
```

### Use Case 3: Modifier l'UI (NPC_UI.lua)

L'UI est côté client. Modifications typiques: ajouter boutons, onglets, affichages.

```lua
-- Ajouter nouveau bouton dans NPCPlayerHUD:initialise()
self.btnSpecialAction = ISButton:new(
    12, 500, 200, 24,
    "Special Action",
    self,
    self.onSpecialActionClick
)
self.btnSpecialAction:initialise()
self.btnSpecialAction:instantiate()
self:addChild(self.btnSpecialAction)

-- Implémenter handler
function NPCPlayerHUD:onSpecialActionClick()
    if not self.npcId then return end
    
    -- Envoyer commande serveur
    PHNPCInteractionClient:sendAdminAction(self.npcId, "special_action", {
        param1 = "value1",
    })
end

-- Écouter réponse serveur
if Events and Events.OnServerCommand then
    Events.OnServerCommand.Add(function(module, command, args)
        if module == "PH_NPC_INTERACT" and command == "ActionResult" then
            -- Mettre à jour UI basée sur response
        end
    end)
end

-- Tester: Devrait voir bouton apparaître dans HUD
```

### Use Case 4: Ajouter un Nouveau Event Système

Events permettent communication entre modules.

```lua
-- Dans NPCMemory.lua (shared), quand apprentissage nouveau
local observation = {skillType = "carpentry", multiplier = 1.2}
if Events and Events.OnBroadcast then
    Events.OnBroadcast("NPCLearned", {
        npcId = npcData.id,
        skillType = observation.skillType,
        multiplier = observation.multiplier,
    })
end

-- Dans NPC_UI.lua (client), écouter l'event
if Events and Events.OnBroadcast then
    Events.OnBroadcast.Add(function(eventName, data)
        if eventName == "NPCLearned" then
            print("NPC " .. data.npcId .. " learned " .. data.skillType)
            -- Met à jour UI si nécessaire
        end
    end)
end
```

---

## Best Practices

### 1. Respect du SRP (Single Responsibility Principle)

❌ **DON'T**: Mettre UI dans serveur
```lua
-- media/lua/server/NPCBrain.lua
function NPCBrain:updateOne(...)
    ISButton:new(...) -- ❌ UI en serveur!
end
```

✅ **DO**: Logique serveur, UI côté client
```lua
-- media/lua/server/NPCBrain.lua
function NPCBrain:updateOne(...)
    -- Logique pure
    local profession = NPCMemory.UpdateProfessionStrategy(npcData, {...})
    -- Envoyer vers client via sync
    self:syncDebugModData(...)
end

-- media/lua/client/NPC_UI.lua
function NPCPlayerHUD:refreshUI()
    -- Reçoit data synced du serveur
    self.lblProfession:setText(npcSnapshot.profession)
end
```

### 2. Nil Safety & Error Handling

```lua
-- ❌ Risky
local value = npcData.stats.hunger + 10

-- ✅ Safe
local hunger = npcData and npcData.stats and npcData.stats.hunger or 0
local value = hunger + 10

-- Encore mieux: fonction helper
local function getHunger(npcData)
    return (npcData and npcData.stats and npcData.stats.hunger) or 0
end
```

### 3. Serialization for Network

```lua
-- ❌ Not serializable
local player = getPlayer()
sendClientCommand("MyModule", "MyCommand", {player = player})

-- ✅ Serializable (primitives only)
local playerId = getPlayer():getUsername()
sendClientCommand("MyModule", "MyCommand", {playerId = playerId})
```

### 4. Performance Considerations

```lua
-- ❌ Called every tick = lag
function NPCBrain:updateOne(...)
    for i = 1, #(hugeTable or {}) do
        expensiveCalculation(hugeTable[i])
    end
end

-- ✅ Throttle or cache
function NPCBrain:updateOne(...)
    if (self.tickCounter % 30) == 0 then  -- Run every 30 ticks instead
        self:doExpensiveCalculation(npcData)
    end
end
```

---

## Testing Your Changes

### Unit Test Approach (Manual)

```lua
-- In NPCMemory.lua, add test function
function NPCMemory.TEST_CalculatePrice()
    local mockNPC = {stats = {intelligence = 60}}
    local result = NPCMemory.CalculatePriceProfile(mockNPC, "player", "player1", {
        basePrice = 100,
        personalNeed = 50,
        clanNeed = 20,
    })
    
    print("Result: " .. tostring(result.finalPrice))
    assert(result.finalPrice > 0, "Price should be > 0")
    return true
end

-- Run: appeler la fonction depuis un script de debug Lua cote serveur
```

### Integration Test (In-Game)

```bash
# 1. Ouvrir HUD ADMIN PNJ sur un PNJ existant
# 2. Changer un profil gameplay (Realiste/Hardcore/Narratif/Ultra HC/RP Soft)
# 3. Verifier le retour ActionResult + le label "Profil gameplay" dans le snapshot
# 4. Tester actions admin: setStat, setBehavior, addItem, heal
# 5. Observer les logs/retours cote client et serveur
# Look for errors, warnings, or unexpected behavior
```

---

## Code Style Guide

- **Naming**: `functionName`, `VariableName`, `CONSTANT_NAME`
- **Comments**: Explain WHY, not WHAT. Code should be self-explanatory.
- **Functions**: Max 50 lines. Break into smaller functions if needed.
- **Tables**: Use consistent structure. Validate keys on access.
- **Error handling**: Always use `pcall()` for untrusted calls (e.g., PZ API).

```lua
-- ✅ Good
local function calculateDiscount(basePrice, discount)
    -- Discount is percentage (0-100)
    return math.max(1, basePrice * (1 - discount / 100))
end

-- ❌ Bad
function cD(p, d)
    return p * (1 - d / 100)
end
```

---

## Submitting a PR

### Process

1. **Fork** le repo
2. **Create branch**: `feature/my-feature` ou `fix/my-bug`
3. **Make changes**: Commit régulièrement
4. **Test**: Vérifie que ça marche en-jeu
5. **Push**: vers ton fork
6. **PR**: Ouvre une PR vers `main` avec description

### PR Checklist

- [ ] Code suit style guide
- [ ] Pas de UI en serveur / logic en client
- [ ] Testé en solo et multijoueur
- [ ] Pas de performance regression (profilage tick serveur + HUD debug)
- [ ] Docs updateés si feature visible
- [ ] Aucun API PZ depreciated utilisé

### Description PR Example

```markdown
## Adds Negotiation Feature

### What
Players can now negotiate prices with NPCs to get discounts.

### How
- Added "Negotiate" button in NPC_UI.lua
- Mini-game: 3 dialogue rounds
- Success = −10% discount permanent
- Failure = −5 relation

### Testing
- Tested solo and multiplayer
- No lag added (−10% even with 50 NPCs)
- Negotiation cooldown: 24h prevents spam

### Related
Closes #45 (Feature request: player negotiation)
```

---

## Getting Help

- **Architecture Questions**: Ouvre une Discussion
- **Bug Help**: Ouvre une Issue avec steps to reproduce
- **Code Review**: Demande dans PR
- **Ollama Integration**: Voir `OllamaBridge.lua` comments

---

## Roadmap for Contributors

**Easy** (Good first PR):
- Add new profession (copy existing)
- Add new production recipe
- Tweak prices/coefficients
- Improve documentation

**Medium**:
- Add new order type (follow STUDY/BUILD pattern)
- Add UI feature (add button/tab)
- Implement new memory type

**Hard**:
- Refactor core FSM logic
- Implement Tier 2 professions
- Cross-mod integration

---

## Final Notes

- **Be kind**: Review others' PRs constructively
- **Iterate**: Your first version won't be perfect
- **Document**: Good code + good docs = good mod
- **Have fun**: This is a passion project for enjoyment

Welcome aboard! 🚀


---
Mise a jour configuration unifiee: voir [CONFIG_UNIFIEE.md](CONFIG_UNIFIEE.md).

---
Reference patch notes: [PATCH_v1.0.4.md](PATCH_v1.0.4.md)
