# Project Humain : Dynamic NPC Overhaul

> **Mod pour Project Zomboid — Build 41 & Build 42**  
> PNJ dynamiques avec IA, factions, commerce, quêtes et mémoire persistante.

---

## Présentation

**Dynamic NPC Overhaul** transforme l'expérience de survie de Project Zomboid en peuplant le monde de PNJ vivants et réactifs. Chaque PNJ possède sa propre personnalité, profession, faction, et peut interagir avec le joueur de façon contextuelle.

### Fonctionnalités principales

| Fonctionnalité | Description |
|----------------|-------------|
| 🧠 **IA Contextuelle** | FSM 7 états (idle, wander, work, trade, defend, flee, guard) |
| 🤝 **Commerce** | Système de troc et d'échanges selon la profession du PNJ |
| ⚔️ **Factions** | 4 factions (survivants, marchands, bandits, inconnus) avec relations dynamiques |
| 📜 **Quêtes** | Journal de quêtes en jeu, récompenses, objectifs |
| 💀 **Morsure cachée** | Un PNJ mordu tousse, perd le moral, et peut se transformer |
| 🤖 **IA Ollama** | Dialogues génératifs via un serveur Ollama local (optionnel) |
| 🌐 **Solo & Multi** | Réseau transparent, aucune configuration manuelle |
| 🔧 **Debug admin** | Commandes `/phnpc` pour gérer les PNJ en jeu |

---

## État du développement

### Build 42 (branche principale)

| Phase | Composant | État |
|-------|-----------|------|
| **Phase 1 — Cerveau** | `shared/` : namespace, logger, config, FSM, data model, factions, dialogues, réseau | ✅ Complet |
| **Phase 2 — Spawn** | `server/NPC_SpawnManager.lua` + `server/00_Init.lua` | ❌ À implémenter |
| **Phase 3 — Interactions** | `client/NPC_InteractionClient.lua` + menus | ❌ À implémenter |
| **Phase 4 — UI** | Fiche PNJ, commerce, bulles de dialogue | ❌ À implémenter |
| **Phase 5 — Avancé** | Morsure, apprentissage, Ollama, quêtes | ❌ À implémenter |

### Build 41 (legacy)

La version B41 est fonctionnelle et documentée dans `Docs/B41/`.

---

## Structure du projet

```
Dynamic_NPC_Overhaul/
├── B41/                    # Mod B41 (legacy)
│   ├── mod.info
│   └── media/lua/
│       ├── client/
│       ├── server/
│       └── shared/
│
├── B42/                    # Mod B42 (actif)
│   ├── mod.info            # targetVersion=42.0
│   ├── media/
│   │   ├── sandbox-options.txt
│   │   └── lua/
│   │       ├── shared/     ← Cerveau (✅ implémenté)
│   │       ├── server/     ← Corps serveur (❌ à créer)
│   │       └── client/     ← Corps client (❌ à créer)
│
└── Docs/
    ├── B41/                # Documentation B41 complète
    └── B42/
        ├── ARCHITECTURE.md     # Architecture détaillée
        ├── GUIDE_CREATION.md   # Guide "partir de zéro"
        └── feuille de route.md # Roadmap fonctionnelle
```

---

## Installation

### Steam Workshop
> Pas encore publié — en développement actif.

### Installation manuelle

1. Télécharger ou cloner ce dépôt
2. Copier le dossier `B42/` vers :
   ```
   C:\Users\<USER>\Zomboid\mods\PH_DynamicNPCOverhaul\
   ```
3. Lancer Project Zomboid B42
4. Activer **"Project Humain : Dynamic NPC Overhaul"** dans le gestionnaire de mods
5. Créer une nouvelle partie → configurer les options dans l'onglet **Sandbox → PHNPC**

---

## Configuration Sandbox

Toutes les options sont accessibles dans le lanceur PZ → onglet **Sandbox**.

| Option clé | Défaut | Description |
|-----------|--------|-------------|
| `ActiveProfile` | 2 | Profil IA (1=RP doux … 5=Ultra hardcore) |
| `MaxActiveNPCs` | 12 | Nombre max de PNJ simultanés |
| `SpawnRadius` | 32 | Rayon d'apparition autour des joueurs (tiles) |
| `EnableOllama` | false | Active les dialogues génératifs via Ollama |
| `DebugMode` | false | Active les logs détaillés en console |

---

## Commandes admin

En jeu, avec les droits administrateur :

```
/phnpc list          → Affiche tous les PNJ actifs
/phnpc spawn         → Force un spawn près du joueur
/phnpc kill <id>     → Supprime un PNJ par ID
/phnpc bite <id>     → Simule une morsure sur un PNJ
/phnpc debug         → Bascule le mode debug
/phnpc reload        → Recharge la configuration sandbox
```

---

## IA Ollama (optionnel)

Pour des dialogues génératifs, installer [Ollama](https://ollama.ai) localement :

```bash
ollama pull neural-chat
ollama serve
```

Puis activer dans les options Sandbox : `EnableOllama = true`.

---

## Architecture technique

Voir [Docs/B42/ARCHITECTURE.md](Docs/B42/ARCHITECTURE.md) pour la documentation complète.

**Principes clés :**
- Namespace global `PHNPC` avec `registerModule()` / `getModule()`
- FSM 7 états cadencée à ~33 ms (`Events.OnTick`)
- Réseau transparent Solo/Multi via `NPC_NetworkDispatcher`
- Fichiers de traduction B42 : `Sandbox_XX.txt`, `UI_XX.txt`, `ContextMenu_XX.txt`, `IGUI_XX.txt`

---

## Documentation

| Fichier | Description |
|---------|-------------|
| [Docs/B42/ARCHITECTURE.md](Docs/B42/ARCHITECTURE.md) | Architecture, arborescence, APIs B42 |
| [Docs/B42/GUIDE_CREATION.md](Docs/B42/GUIDE_CREATION.md) | Guide complet "partir de zéro" |
| [Docs/B42/feuille de route.md](Docs/B42/feuille%20de%20route.md) | Roadmap fonctionnelle |
| [Docs/B41/](Docs/B41/) | Documentation complète B41 |

---

## Contribuer

1. Fork du dépôt
2. Créer une branche `feature/ma-fonctionnalite`
3. Respecter les conventions Lua (pas de `goto`/`continue`, pattern module, gardes de côté)
4. Tester en jeu B42 en synchronisant vers `C:\Users\<USER>\Zomboid\mods\`
5. Pull request vers `master`

---

## Licence

Projet personnel open-source. Référence aux mods exemples inclus dans `mod example/` conservés à titre de documentation uniquement.

---

## Auteur

**sputji** — Project Zomboid modder  
GitHub : [github.com/sputji/dynamic_npc_overhaul](https://github.com/sputji/dynamic_npc_overhaul)
