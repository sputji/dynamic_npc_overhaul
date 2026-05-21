# CHANGELOG B42 — Dynamic NPC Overhaul

## [0.0.7b] — 2026-05-28

### Corrections critiques
- **Animations réparées** : `setUseless(false)` pour **tous** les NPCs (recrutés ET non-recrutés) — `setUseless(true)` bloquait les AnimSets (PHNPC_IsNPC) et `Say()`, causant animations zombie bras-tendus sur les NPCs libres
- **`Say()` réparé** : découlait du fix animations — `npc:Say()` ne fonctionnait pas avec `setUseless(true)`
- **Loot après mort** : `deleteNPC()` utilise maintenant `setHealth(1)` au lieu de `removeFromWorld()` — le NPC laisse un corpse lootable avec ses items
- **Menu simplifié** : suppression "Afficher l'état" (redondant), "Inventaire" → "Échange d'objets", "Mode combat" déplacé dans `[DEBUG]`

### Ajouts
- **NPC autonome** : comportement idle pour les NPCs non recrutés — patrouille aléatoire toutes les ~300 ticks dans un rayon de 6 tiles + bark idle occasionnel (1/4)
- **PHNPC_Manager.lua v0.6** : boucle `OnTick` séparée pour non-recrutés (`PHNPC_PatrolTick`), sécurisation de l'itération (liste `deadIdle` pour éviter modification pendant `pairs()`)

---

## [0.0.7a] — 2026-05-27

### Ajouts
- **Combat auto NPC vs zombies** : `npcCombatStep()` — détection range=8 tiles, attaque melee (Shove/FrontKick/HighKick), knockDown(true), cooldown 60 ticks
- **Fuite HP<30%** : `npcFlightStep()` — état "fleeing", direction opposée au zombie, replier sur joueur si zone dégagée
- **Dialogue contextuel** : table `PHNPC_BARKS` — 5 états (following/staying/defending/fleeing/idle), bark auto via `BARK_TICK_RATE`, bark immédiat via menu "Parler"
- **Menu clic-droit complet** : "Parler", "Mode combat : AUTO/OFF", sous-menu "[DEBUG]..." (états forcés, HP, animations)
- **PHNPC_Core.lua v0.4** : constantes `COMBAT_RANGE`, `COMBAT_ATTACK_RANGE`, `COMBAT_TICK_RATE`, `FLEE_HP_RATIO`, `FLEE_DISTANCE`, `BARK_TICK_RATE`
- **PHNPC_Manager.lua v0.5** : `npcCombatStep`, `npcFlightStep`, `talkNPC`, `dbgToggleCombat`, callbacks debug complets
- **OnTick** : appels `npcFlightStep` + `npcCombatStep` pour chaque NPC recruté à chaque tick

### Corrections
- Cleanup `_combatTimers` + `_attackCooldowns` dans `deleteNPC` et `OnTick` (NPC mort)
- Cleanup `_combatTimers` + `_attackCooldowns` dans `OnGameStart`
- Menu debug section `[DEBUG]...` uniquement si `isDebugEnabled()` — ne pollue pas le menu prod
- État "defending" ajouté dans condition stayNPC (suit → reste quand en combat)

---

## [0.0.7] — 2026-05-27

### Ajouts
- `setUseless(false)` pour tous les NPCs recrutés (pattern NPC_Helper_Mod) — empêche le freeze en hitreaction
- Inventaire NPC : `openNPCInventory()` + hook `OnRefreshInventoryWindowContainers` (injecte container dans loot panel)

### Corrections
- NPC bloqué après coup (stuck bumped) : `setUseless(false)` pour les recrutés
- Mauvaise animation "push" sur NPC : `ZSZombiePushedBack.xml` + `ZSZombiePushedFront.xml` avec condition `PHNPC_IsNPC=false`

---

## [0.0.5] — 2026-05-21

### Ajouts
- PHNPC_Stats.lua (shared) : initStats() + initInventory() par metier
- PHNPC_Health.lua (client) : systeme sante via Events.OnHitZombie
- Animations Bob_FrontKick.X, Bob_HighKick.x, Bob_PushKick.X (copiees depuis NHM)

### Modifications
- PHNPC_Core.lua : FOLLOW_DISTANCE 3->5, ajout OUTFIT_STATS + MAX_HEALTH + getOutfitStats()
- PHNPC_Manager.lua : setSpeedMod depuis md.PHNPC_SpeedMod (vitesse dynamique), appel initStats/initInventory dans convertToNPC
- PHNPC_Debug.lua : dbgAnim avec setUseless(false)+changeState avant setBumpType, HighKick dans menu, HP dans ShowState

### Corrections
- FrontKick ne jouait pas : Bob_FrontKick.X absent de vanilla B42 (copie depuis NHM)
- NPC trop collant : FOLLOW_DISTANCE 3->5
- HP NPC ne diminuait pas : hook OnHitZombie manquant

---

## [0.0.4] — 2026-05-26

### Ajouts
- Sons de pas via ZSWalk.xml events
- VoicePrefix genre-based (homme/femme differencies)
- ZSNPCPushedBack.xml (BumpType=ZombiePushedBack)

### Corrections
- stopMoving : setTarget(nil) + clearAggroList pour vraiment stopper
- ForceHitReaction crash fixe

---

## [0.0.3] — 2026-05-21

### Corrections
- Signatures callbacks (_, player) -> (player)
- setVariable(zombieWalkType) supprime (read-only B42)
- setFemaleEtc() ajoute dans convertToNPC + enforceNPC

---

## [0.0.2] — 2026-05-21

### Ajouts
- Menu DEBUG_PHNPC complet (animations, etat, spawn debug)
- Suppression NPC via menu
