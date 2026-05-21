# CHANGELOG B42 — Dynamic NPC Overhaul

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
