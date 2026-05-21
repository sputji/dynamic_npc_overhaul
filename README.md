<div align="center">

![Project Humain : Dynamic NPC Overhaul](icon.png)

# Project Humain : Dynamic NPC Overhaul

**Mod pour Project Zomboid — Build 42**

*Des survivants humains autonomes avec IA, professions, inventaire et système de santé*

[![Version](https://img.shields.io/badge/version-0.0.9a-blue)](https://github.com/sputji/dynamic_npc_overhaul/releases)
[![PZ Build](https://img.shields.io/badge/Project%20Zomboid-B42-green)](https://store.steampowered.com/app/108600)
[![Statut](https://img.shields.io/badge/statut-en%20d%C3%A9veloppement-orange)]()

</div>

---

## Présentation

**Dynamic NPC Overhaul** ajoute des PNJ humains autonomes dans Project Zomboid. Chaque PNJ a une **profession**, des **stats propres**, un **inventaire réaliste** et peut être **recruté** pour vous suivre ou rester en place. Ils encaissent les coups, jouent des animations de douleur, et meurent si leurs points de vie tombent à zéro.

> Ce mod est en développement actif. Les fonctionnalités ci-dessous sont fonctionnelles en **v0.0.9a**.

---

## Fonctionnalités actuelles (v0.0.9a)

### PNJ & Professions

7 professions disponibles, chacune avec ses propres statistiques, vitesse et équipement de départ :

| Profession | Vitesse | PV | Poids max | Équipement de départ |
|------------|---------|-----|-----------|----------------------|
| 👨‍🌾 Fermier | 0.75 | 90 | 15 kg | Pelle, Truelle |
| 👮 Police | 0.85 | 110 | 20 kg | Matraque, Lampe torche |
| 🚒 Pompier | 0.80 | 120 | 25 kg | Hache |
| 🩺 Médecin | 0.78 | 100 | 15 kg | Bandage, Analgésiques |
| 🌲 Ranger | 0.90 | 105 | 18 kg | Couteau de chasse, Lampe torche |
| 👨‍🍳 Chef | 0.75 | 90 | 15 kg | Couteau de cuisine, Ouvre-boîte |
| 🧍 Survivant | 0.80 | 100 | 18 kg | Pied-de-biche |

### Interactions joueur

- **Recruter** un PNJ via clic droit → il vous suit
- **Ordonner** : *Suis-moi*, *Reste ici*, *Attaque les zombies !*, *Mets-toi à l'abri*, *Tu peux partir*
- Distance de suivi réaliste — le PNJ s'arrête à 3 tiles du joueur
- **Échange d'inventaire** : accès à l'inventaire du PNJ via le menu
- **Dialogue localisé** : toutes les bulles de texte passent par le système de traduction PZ (`getText()`), EN et FR supportés (B42.18+)

### Système de santé

- Les PNJ **encaissent les coups** du joueur (dégâts calculés selon l'arme)
- **Animations de douleur** déclenchées (PainHead / PainTorso)
- **Coup critique** sur la tête → dégâts doublés
- Le PNJ **meurt** quand ses PV tombent à 0 → **corpse lootable** avec tout son inventaire

### Combat & survie

- **Combat auto** contre les zombies proches (range 8 tiles) — Shove / FrontKick / HighKick
- **Fuite** si HP < 30% — direction opposée au zombie, repli vers le joueur si zone dégagée
- **Barks contextuels** automatiques selon l'état (following, staying, defending, fleeing, idle)

### Animations

Animations humaines complètes grâce à un système d'AnimSets custom :

| Animation | Déclencheur |
|-----------|-------------|
| Marche / Idle | Déplacement et repos |
| WalkToIdle / IdleToWalk | Transitions fluides (override vanilla via `PHNPC_IsNPC=true`) |
| StaggerBack (NPC) | Repoussé — `Bob_RunStumble` (rig humain) |
| PainHead / PainTorso | Coup reçu |
| FrontKick / HighKick | Combat auto NPC |
| Shove | Repoussé |
| WaveHi / Shrug / Yes / No | Expressions sociales |

> Animations masculines (Bob) et féminines (Kate) supportées.

---

## Installation

### Pré-requis
- **Project Zomboid Build 42** (version ≥ 42.0)
- Solo ou Multijoueur (côté client)

### Étapes

**1 — Télécharger le mod**

```
git clone https://github.com/sputji/dynamic_npc_overhaul.git
```

ou télécharger le ZIP depuis GitHub → **Code → Download ZIP**

**2 — Copier le dossier dans Zomboid**

Copier **uniquement** le contenu du dossier `B42/42/` vers :

```
C:\Users\<VOTRE_NOM>\Zomboid\mods\PH_DynamicNPCOverhaul\
```

Résultat attendu :

```
C:\Users\<VOTRE_NOM>\Zomboid\mods\PH_DynamicNPCOverhaul\
├── mod.info
├── icon.png
├── poster.png
└── media/
    └── lua/
        ├── shared/
        └── client/
```

> ⚠️ Ne pas copier le dossier `B42/` entier — copier seulement le contenu de `B42/42/`.

**3 — Activer le mod**

1. Lancer Project Zomboid
2. Menu principal → **Mods**
3. Activer **"Project Humain : Dynamic NPC Overhaul"**
4. Lancer ou créer une partie

**4 — Utiliser le mod en jeu**

- **Clic droit sur le sol** → *Spawner un NPC* pour faire apparaître un PNJ
- **Clic droit sur un NPC** → menu d'interaction (Recruter, Suivre, Rester, Congédier)

---

## Menu DEBUG

Un sous-menu **DEBUG_PHNPC** est disponible via clic droit (pour les tests) :

| Option | Action |
|--------|--------|
| Spawn NPC debug | Crée un PNJ à côté du joueur |
| Afficher l'état | Affiche les stats du NPC le plus proche (HP, vitesse, métier…) |
| Animations → FrontKick | Déclenche l'animation FrontKick |
| Animations → HighKick | Déclenche l'animation HighKick |
| Animations → WaveHi / Shrug / Yes / No | Expressions |
| Supprimer NPC | Retire le PNJ le plus proche |

---

## Structure du projet

```
Dynamic_NPC_Overhaul/
├── B42/
│   ├── 42/                          ← Dossier du mod (à copier dans Zomboid/mods/)
│   │   ├── mod.info                 ← Métadonnées du mod (id, version, auteur)
│   │   ├── icon.png / poster.png
│   │   └── media/lua/
│   │       ├── shared/
│   │       │   ├── PHNPC_Core.lua    ← Namespace PHNPC, constantes, OUTFIT_STATS
│   │       │   ├── PHNPC_Stats.lua   ← Stats et inventaire par profession
│   │       │   └── Translate/        ← Traductions EN/FR (.txt + .json B42.18)
│   │       └── client/
│   │           ├── PHNPC_Actions.lua  ← Déplacement NPC
│   │           ├── PHNPC_Barks.lua    ← Système de barks
│   │           ├── PHNPC_Combat.lua   ← Combat auto vs zombies
│   │           ├── PHNPC_Convert.lua  ← Conversion zombie → NPC
│   │           ├── PHNPC_Debug.lua    ← Menu DEBUG_PHNPC
│   │           ├── PHNPC_Enforce.lua  ← Boucle OnZombieUpdate
│   │           ├── PHNPC_Health.lua   ← Système de santé
│   │           ├── PHNPC_Inventory.lua ← Inventaire NPC
│   │           ├── PHNPC_Manager.lua  ← Spawn + registres
│   │           ├── PHNPC_Menu.lua     ← Menu contextuel
│   │           ├── PHNPC_Orders.lua   ← Ordres joueur
│   │           └── PHNPC_Update.lua   ← OnTick principal
│   └── common/media/
│       ├── AnimSets/zombie/         ← AnimSets custom (idle, bumped, walk…)
│       └── anims_X/Zombie/          ← Animations .X custom (FrontKick, HighKick…)
└── Docs/
    └── B42/
        ├── ARCHITECTURE.md          ← Architecture technique détaillée
        ├── CHANGELOG.md             ← Historique des versions
        └── feuille de route.md      ← Roadmap complète
```

---

## Roadmap

| Phase | Fonctionnalité | État |
|-------|----------------|------|
| v0.0.9a | Traductions B42.18 (JSON), fix StaggerBack NPC, tous dialogues via getText() | ✅ |
| v0.0.9 | Refacto 9 modules, fix proximité, fix getText() timing, fix anim coupée | ✅ |
| v0.0.8b | Fix pathToCharacter, fix setHealth conditionnel | ✅ |
| v0.1.0 | Dialogue avancé, ordre "Va là-bas", réaction aux zombies | 🔜 |
| v0.1.1 | Loot de bâtiments, échange d'items amélioré | 🔜 |
| v0.1.5 | Persistance (sauvegarde/rechargement des PNJ) | 🔜 |
| v0.2.0 | Factions, patrouille, commerce | 🔜 |
| v0.4.0 | Cerveau IA avancé, mémoire, réputation, moralité | 🔜 |

Roadmap complète : [Docs/B42/feuille de route.md](Docs/B42/feuille%20de%20route.md)

---

## Documentation technique

| Fichier | Description |
|---------|-------------|
| [Docs/B42/ARCHITECTURE.md](Docs/B42/ARCHITECTURE.md) | Architecture complète, flux de création NPC, variables ModData |
| [Docs/B42/CHANGELOG.md](Docs/B42/CHANGELOG.md) | Historique des versions |
| [Docs/B42/feuille de route.md](Docs/B42/feuille%20de%20route.md) | Roadmap fonctionnelle avec toutes les phases |

---

## Contribuer

1. Forker le dépôt
2. Créer une branche `feature/ma-fonctionnalite`
3. Respecter les conventions Lua PZ (pas de `goto`/`continue`, `pcall` sur les APIs fragiles)
4. Tester en jeu B42
5. Pull request vers `master`

---

## Licence

Projet personnel open-source.

---

<div align="center">

**sputji** — Project Zomboid modder  
[github.com/sputji/dynamic_npc_overhaul](https://github.com/sputji/dynamic_npc_overhaul)

</div>
