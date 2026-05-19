# Commandes Serveur Admin - Dynamic NPC Overhaul

**Standard editorial**: v1  
**Type**: Developpement (interne)  
**Audience**: Administrateurs serveur, testeurs, moddeurs  
**Version doc**: v1.6  
**Confidentialite**: Interne  
**Derniere mise a jour**: 12 mai 2026

Ce document reference uniquement les commandes verifiees dans le code actuel, incluant le workflow Lua Command Line en solo.

---

## 1) Commandes Chat `/phnpc` (implementees)

Ces commandes sont parsees dans `NPCSpawner:tryHandleChatCommand`.

Condition: joueur admin requis (sinon `ok=false`, `reason=not_admin`).

### Liste supportee

- `/phnpc help`
- `/phnpc debug on|off|toggle`
- `/phnpc heatmap on|off|toggle`
- `/phnpc fsm on|off|toggle`
- `/phnpc fsmrange 20|40|60`
- `/phnpc fsmlimit 5|10|15`
- `/phnpc status`
- `/phnpc diag [1..30]`
- `/phnpc spawn 1..20`
- `/phnpc clear`
- `/phnpc respawn 1..20`
- `/phnpc mark on|off|toggle|status`
- `/phnpc map on|off|toggle|status`

### Effets reels

- `debug`: active/desactive/toggle l'overlay debug global joueur.
- `heatmap`: active/desactive/toggle la heatmap (implique overlay actif).
- `fsm`: active/desactive/toggle l'affichage FSM dans l'overlay.
- `fsmrange`: fixe la portee FSM autorisee (`20`, `40`, `60`).
- `fsmlimit`: fixe la limite d'entrees FSM (`5`, `10`, `15`).
- `status`: renvoie l'etat courant overlay/heatmap/fsm/range/limit + compte actif/dormant + fallback spawn + derniere raison d'echec spawn.
- `diag`: renvoie un diagnostic runtime detaille (resume global + lignes par PNJ: type, state, order, goal, position, distance).
- `spawn`: force le spawn d'un nombre de PNJ dynamiques autour du joueur.
- `spawn`: prefere des cases interieures de maisons/batiments autour du joueur, avec fallback exterieur si aucun interieur valide n'est trouve.
- `clear`: supprime tous les PNJ dynamiques actifs et efface les enregistrements dormants.
- `respawn`: fait `clear` puis force un nouveau spawn immediat.
- `mark`: active/desactive/toggle le marquage visuel debug (outline + halo best effort) des PNJ dynamiques proches.

### Identification visuelle PNJ

- Les PNJ dynamiques du mod utilisent maintenant une tenue forcee unique: `Fireman`.
- Le marquage visuel debug est applique de facon periodique pour les admins avec `mark=on`.

### Reponse serveur

Les retours passent par:

- Module: `PH_NPC`
- Commande ACK: `AdminDebugAck`

Et un retour texte complementaire est envoye via:

- Module: `PH_NPC_CONSOLE`
- Commande: `Result`

Payload typique:

```lua
{
    ok = true,
    overlayEnabled = true,
    heatmapEnabled = false,
    fsmEnabled = true,
    fsmRange = 40,
    fsmLimit = 10
}
```

En cas de syntaxe invalide:

```lua
{
    ok = false,
    reason = "invalid_command",
    usage = "/phnpc help ; /phnpc status ; /phnpc diag [1..30] ; /phnpc spawn 1..20 ; /phnpc clear ; /phnpc respawn 1..20 ; /phnpc mark on|off|toggle|status ; /phnpc map on|off|toggle|status ; /phnpc debug on|off|toggle ; /phnpc heatmap on|off|toggle ; /phnpc fsm on|off|toggle ; /phnpc fsmrange 20|40|60 ; /phnpc fsmlimit 5|10|15"
}
```

---

## 2) Actions Admin Reseau (HUD ADMIN PNJ)

Ces actions ne sont pas des commandes chat. Elles sont envoyees par le client via:

- Module: `PH_NPC_INTERACT`
- Commande client: `AdminAction`
- Handler serveur: `NPCInteractionHooks:handleAdminAction`

Condition: joueur admin requis.

### Actions gameplay profile (global serveur)

- `listGameplayProfiles`
- `getGameplayProfile`
- `setGameplayProfile` (payload: `profile`)

Profils disponibles (code):

- `realistic`
- `hardcore`
- `narrative`
- `ultra_hardcore`
- `rp_soft`

### Actions edition PNJ

- `setStat` (`statName`, `value`)
- `setBehavior` (`preset`: `friendly|hostile|survivor`)
- `setPersonality` (`socialDrive`, `loneWolf`, `adaptability`, `brutality`, `opportunism`)
- `addItem` (`itemType`, `quantity`, `condition` optionnel)
- `clearInventory`
- `heal`
- `toggleBitten`

Les retours passent par `ActionResult` (module `PH_NPC_INTERACT`).

---

## 3) Utilisation via Lua Command Line (solo)

Si la touche chat ne fonctionne pas, utiliser la passerelle Lua.

Exemples:

- `PHNPC.help()`
- `PHNPC.run('/phnpc status')`
- `PHNPC.run('/phnpc diag')`
- `PHNPC.run('/phnpc diag 20')`
- `PHNPC.run('/phnpc spawn 10')`
- `PHNPC.run('/phnpc clear')`
- `PHNPC.run('/phnpc respawn 10')`
- `PHNPC.run('/phnpc mark on')`
- `PHNPC.run('/phnpc mark status')`
- `PHNPC.dialogueOpenNearest(4)`
- `PHNPC.dialogueSendNearest('Salut, test dialogue', 4)`
- `PHNPC.tradeOpenNearest(4)`
- `PHNPC.tradeBuyNearest('Base.CannedSardines', 1, 12, 4)`
- `PHNPC.tradeSellNearest('Base.Bandage', 1, 8, 4)`
- `PHNPC.questJournalOpen()`
- `PHNPC.questJournalRefresh()`
- `PHNPC.questJournalReset()`
- `PHNPC.testSuiteQuick()`
- `PHNPC.logOn()`
- `PHNPC.logOff()`
- `PHNPC.logLevel('DEBUG')`
- `PHNPC.logRecent(80)`

### Quetes SSR minimales (journal)

- Requete journal: `PHNPCInteractionClient:requestQuestJournal()` (client) -> `QuestJournalRequest` (serveur).
- Reset journal: `PHNPCInteractionClient:resetQuestJournal()` (client) -> `QuestResetRequest` (serveur).
- Reponse serveur: module `PH_NPC_INTERACT`, commande `QuestJournal`.
- Progression automatique: `RequestIntel` reussi -> `first_contact`, `TradeEvent` reussi (hors gift) -> `market_runner`, `TradeEvent` gift reussi -> `goodwill`.

### Cooldown devis metier

- Les demandes `BusinessQuoteRequest` sont limitees par paire `joueur + npc`.
- Cooldown par defaut: `6s` (configurable via `quoteCooldownSec`).
- En cas de spam: `ActionResult` type `BusinessQuote` avec message `Attendez Xs avant un nouveau devis`.

Bridges charges:

- client: `media/lua/client/PHNPC_ConsoleBridge.lua`
- serveur: `media/lua/server/PHNPC_ConsoleBridgeServer.lua`

### Logger complet PHNPC

- Fichier source logger: `media/lua/shared/PHNPC_Logger.lua`
- Format d'une ligne:
  - `[PHNPC][YYYY-MM-DD HH:MM:SS.mmm][T+Xh][SV|CL|SH][Module.Action][LEVEL] message | key=value ...`
- Suffixes de niveau utilises:
  - `TRACE`, `DEBUG`, `INFO`, `OK`, `WARN`, `ERROR`, `FAIL`
- Objectif debug:
  - tracer ce qui fonctionne (`OK`) et ce qui casse (`ERROR`/`FAIL`)
  - relier un bug a son declencheur via `Module.Action` + `key=value`
  - conserver un historique en memoire consultable via `PHNPC.logRecent(n)`

## 4) Important - Commandes non implementees

Les commandes ci-dessous ne sont pas parsees par le chat `/phnpc` actuellement:

- `/phnpc help`
- `/phnpc info`
- `/phnpc stats`
- `/phnpc reset`
- `/phnpc kill`
- `/phnpc profession`
- `/phnpc order`
- `/phnpc setcash`
- `/phnpc addcash`
- `/phnpc market ...`
- `/phnpc config ...`
- `/phnpc performance`
- `/phnpc dialogue ...`
- `/phnpc trade ...`
- `/phnpc test scenario ...`
- `/phnpc ban` / `/phnpc unban`

Si necessaire, les demandes pour ces commandes doivent rester dans le backlog/roadmap tant que le parser chat ne les supporte pas.

---

## 5) Diagnostic rapide

### `/phnpc` ne fait rien

Verifier:

- que le message est bien saisi dans le chat (module `chat`/`Chat`)
- que le joueur est admin
- que la syntaxe est strictement une commande supportee (voir liste section 1)

### Retour `invalid_command`

Utiliser exactement la grammaire supportee ci-dessus (`on|off|toggle`, valeurs autorisees).

---
Mise a jour configuration unifiee: voir [CONFIG_UNIFIEE.md](CONFIG_UNIFIEE.md).

---
Reference patch notes: [PATCH_v1.0.4.md](PATCH_v1.0.4.md)
