# Configuration Unifiee - Dynamic NPC Overhaul v2.1

**Standard editorial**: v1  
**Type**: Developpement (interne)  
**Audience**: Mainteneurs, admins serveur, moddeurs  
**Version doc**: v1.1  
**Confidentialite**: Interne  
**Derniere mise a jour**: 12 mai 2026

---

## Objectif

Unifier toute la configuration du mod avec une priorite claire des sources:

1. Mod Options (Build 41) en solo client
2. SandboxVars
3. Difficulte native du jeu (fallback)

En multijoueur, la logique serveur reste autoritaire et ignore les reglages clients Mod Options.

Compatibilite ciblee Mod Options: Build 41 v1.4.4 (Steam Workshop, hotfix du 17 oct. 2022).

Note dependance: le moteur Mod Options est embarque dans ce mod
(`media/lua/shared/!ModOptionsEngine.lua` et `media/lua/client/!!CustomOptions.lua`).
L'installation du mod Workshop "Mod Options" n'est pas requise.

---

## Fichiers Ajoutes

- `media/lua/shared/Sandbox/PHNPC_SandboxVars.lua`
- `media/lua/shared/SandboxVars.lua`
- `media/lua/shared/PHNPC_ConfigManager.lua`
- `media/lua/client/PHNPC_ModOptionsUI.lua`
- `media/lua/shared/Translate/FR/Sandbox_FR.txt`
- `media/lua/shared/Translate/EN/Sandbox_EN.txt`

---

## Priorite de Configuration

### Solo client

- Si Mod Options est actif: Mod Options ecrase Sandbox
- Sinon: Sandbox
- Sinon: mapping difficulte native -> profil interne

Mapping fallback:

- Apocalypse -> `hardcore`
- Survival/Survivor -> `realistic`
- Builder -> `rp_soft`
- Autre -> `realistic`

### Serveur / hebergement multijoueur

- Source autoritaire: SandboxVars serveur
- Les options client Mod Options ne pilotent pas la logique serveur

---

## Themes Configures

### Theme 1 - Global & Profils

- Profil actif: `realistic`, `hardcore`, `narrative`, `ultra_hardcore`, `rp_soft`

### Theme 2 - Reseau & Performance

- Intervalle sync reseau: 0.1s -> 2.0s (defaut 0.5)
- Limite entrees FSM: 5 -> 15 (defaut 10)
- Portee FSM: 20 -> 60 (defaut 40)
- NPC actifs max: 4 -> 48 (defaut 12)
- Budget NPC par joueur: 1 -> 16 (defaut 4)
- Rayon de spawn: 18 -> 80 (defaut 32)
- Rayon de despawn: 24 -> 120 (defaut 48)
- Tentatives de spawn / cycle: 2 -> 20 (defaut 6)
- Autoriser fallback zombie: bool (defaut false)

### Theme 3 - IA de Dialogue (Ollama)

- Activer Ollama: bool (defaut true)
- URL API: texte (defaut `http://localhost:11434`)
- Modele: texte (defaut `neural-chat`)
- Timeout: 2000 -> 15000 ms (defaut 8000)
- Taille cache: 10 -> 100 (defaut 50)

### Theme 4 - Infection (Bite Management)

- Intervalle toux: 10 -> 60 s (defaut 30)
- Probabilite toux cachee: 0 -> 100% (defaut 15%)
- Seuil isolement anxiete: 0 -> 100 (defaut 60)

### Theme 5 - Apprentissage Passif

- Portee observation: 5 -> 20 (defaut 12)
- Intervalle verification: 1 -> 10 s (defaut 2)

### Theme 6 - Survie & Economie

- Desactiver degradation faim/soif: bool (defaut false)
- Multiplicateur prix services: 0.1 -> 5.0 (defaut 1.0)

---

## Branches Runtime

Les systemes impactes:

- `NPCSpawner`: `replicationFSMRange`, `replicationMaxFSMPerPlayer`
- `NPCSpawner`: `maxActiveNPCs`, `perPlayerBudget`, `spawnRadius`, `despawnRadius`, `spawnAttemptsPerCycle`, `allowZombieFallback`
- `NPC_NetworkServer`: `syncInterval`
- `OllamaBridge`: `enabled`, `baseUrl`, `model`, `timeout`, `maxCacheSize`
- `NPC_BiteManagement`: `coughInterval`, `coughProbability`, `isolationAnxietyThreshold`
- `NPC_ObservationLearning`: `observationRange`, `observationTickInterval`
- `NPCBrain`: `disableNeedsDecay`
- `NPCBrain`: mutualisation du scan zombie par tick + adaptation de `zombieVisionRange`
- `NPCMemory`: `globalServicePriceMultiplier`
- `NPCTuningProfiles`: profil actif applique globalement

---

## Notes d'Implementation

- Le manager est defensif sur les valeurs `nil` et hors bornes.
- Les bornes numeriques sont clamp.
- Les bool sont normalises (`true/1/"1"/"true"`).
- Le manager publie la config cachee et peut forcer une re-resolution.

---

## Validation Recommandee

1. Solo sans Mod Options: verifier fallback Sandbox puis difficulte native
2. Solo avec Mod Options: verifier surcharge live des 6 themes
3. Serveur dedie: verifier que Sandbox serveur domine
4. Client MP non admin: verifier qu'aucun reglage local n'altere la logique serveur

---
Reference patch notes: [PATCH_v1.0.4.md](PATCH_v1.0.4.md)
