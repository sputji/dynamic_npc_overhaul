# Architecture - Dynamic NPC Overhaul v2.1

**Type**: Technical Reference  
**Audience**: Developers, architects, maintainers  
**Updated**: 12 mai 2026

---

## 🏗️ System Overview

Dynamic NPC Overhaul combines **8 integrated systems** working in harmony:

```
┌─────────────────────────────────────────┐
│ 1. AI Decision Engine (NPCBrain)        │
│    - Autonomous bycycle ~33ms           │
│    - Needs calculation, strategy exec   │
└────────────┬────────────────────────────┘
             ▼
┌─────────────────────────────────────────┐
│ 2. Multiplayer Network (v1.0.5 Arch)    │
│    - SOLO: 0 network overhead           │
│    - MULTI: Full sync (300 tick)        │
└────────────┬────────────────────────────┘
             ▼
┌─────────────────────────────────────────┐
│ 3. Dialogue Engine (Ollama + Fallback)  │
│    - AI or hardcoded responses          │
└────────────┬────────────────────────────┘
             ▼
┌─────────────────────────────────────────┐
│ 4. Professional Systems                 │
│    - Production, trading, crafting      │
└────────────┬────────────────────────────┘
             ▼
┌─────────────────────────────────────────┐
│ 5. Survival & Emotional States          │
│    - Trauma, disease, bite mechanic     │
└────────────┬────────────────────────────┘
             ▼
┌─────────────────────────────────────────┐
│ 6. Learning & Memory Systems            │
│    - Passive skill learning             │
│    - NPC personality & relationship     │
└────────────┬────────────────────────────┘
             ▼
┌─────────────────────────────────────────┐
│ 7. User Interface (Client-side)         │
│    - HUD, dialogue UI, debug overlay    │
└────────────┬────────────────────────────┘
             ▼
┌─────────────────────────────────────────┐
│ 8. Profile System (Runtime Tuning)      │
│    - realistic, hardcore, narrative     │
└─────────────────────────────────────────┘
```

---

## 🆕 v1.0.5: SOLO vs MULTI Separation

### The Problem
- Original NPCSpawner.lua: 2400+ lines
- Mixed SOLO and MULTI code paths
- Risk of cross-contamination
- Hard to maintain and test

### The Solution: Dispatcher Pattern

```
Game Startup
    ↓
GameModeDetector:detectMode()
    ├─ SOLO: Load NPCSpawner_SOLO.lua ✅
    └─ MULTI: Load NPCSpawner_MULTI.lua ✅
```

**Key Benefits:**
- ✅ Clean separation (100% isolated)
- ✅ No network overhead in SOLO
- ✅ Full network sync in MULTI
- ✅ Easy testing and maintenance
- ✅ Zero risk of cross-contamination

### File Organization

| File | Purpose | Lines | Network |
|------|---------|-------|---------|
| NPCSpawner.lua | Router/Dispatcher | 95 | ❌ ZERO |
| NPCSpawner_SOLO.lua | Single-player impl | 692 | ❌ ZERO |
| NPCSpawner_MULTI.lua | Multiplayer impl | 506+ | ✅ FULL |
| GameModeDetector.lua | Mode detection | ~100 | ❌ ZERO |

### Implementation Details

**NPCSpawner.lua (Dispatcher)**
```lua
local mode = GameModeDetector:detectMode()
if mode == "SOLO" then
    return require("server/NPCSpawner_SOLO")
else
    return require("server/NPCSpawner_MULTI")
end
```

**NPCSpawner_SOLO.lua**
- `create3DHumanProxy()` — Spawn and humanize
- `spawnBudgeted()` — Managed spawn (max 6/tick)
- `despawnFarFromPlayers()` — Cleanup far NPCs
- `saveState()`/`loadState()` — ModData persistence
- **Key Guarantee**: Only `getPlayer(0)`, ZERO network calls

**NPCSpawner_MULTI.lua**
- All SOLO functions (inherited)
- `collectChunkCounts()` — Prep state for replication
- `replicateDebugState()` — Admin overlay (v1.1)
- `onClientCommand()` — Admin command routing
- **Key Guarantee**: Uses `getOnlinePlayerList()`, 4x `transmitModData()` with guards

---

## 🎮 Core Systems

### 1. AI Decision Engine (NPCBrain.lua)

**Cycle**: ~33ms (server-authoritative)

**Decision Flow**:
```
Calculate Needs (hunger, thirst, morale, survival)
    ↓
Select Profession Strategy
    ↓
Generate or Execute Order
    ├─ STUDY (learn skills)
    ├─ BUILD (construct items)
    ├─ COOK (prepare meals)
    ├─ TRADE (exchange items)
    ├─ DEFEND (fight threats)
    └─ GUARD (watch area)
    ↓
Move/Act Autonomously
    ↓
Broadcast State Changes
```

**Key Variables**:
- `needs`: hunger, thirst, morale, energy, survival
- `profession`: Artisan, Cook, Builder, Merchant, Explorer
- `disposition`: friendly, neutral, wary, fearful, hostile
- `recentEvents`: last 30 actions for context

### 2. Multiplayer Network System

**Architecture (v1.0.5)**:
- Server-authoritative (all logic server-side)
- Clients receive display commands only
- No client-side prediction
- Synchronized state every 300 ticks (~5 sec)

**Network Flow**:
```
Server: NPCSpawner_MULTI:update()
    ├─ Spawn/despawn locally
    ├─ Collect chunk state
    └─ transmitModData() to all clients
        ↓
Client: OnNPCSyncState event
    ├─ Update position
    ├─ Update animation
    └─ Update health/mood display
```

**Guards**:
- `initialSyncDone` flag per NPC (prevents -1 spam)
- `getOnlineID() != -1` check before sync
- Replication throttled (300 ticks = 5 sec)

### 3. Dialogue Engine (OllamaBridge + NPC_NetworkServer)

**Priority**:
1. **Ollama (HTTP)**: Real-time AI dialogue (async, 2-8s)
2. **Fallback**: 16+ hardcoded contextual responses (<1ms)
3. **Cache**: 50 recent responses (reuse <1ms)

**Context Sources**:
- NPC mood/profession/disposition
- Recent events (trade, combat, social)
- Player relationship
- Hidden bite status
- Observable skills

**Multilingual**:
- Detects player language (getText)
- Ollama responds in detected language
- Fallback uses FR/EN getText keys

### 4. Professional Systems

**5 Professions**:
| Profession | Produces | Consumes | Skill |
|-----------|----------|----------|-------|
| **Artisan** | Tools | Materials | Crafting |
| **Cook** | Meals | Ingredients | Cooking |
| **Builder** | Structures | Wood/Metal | Construction |
| **Merchant** | Currency | Inventory | Trading |
| **Explorer** | Resources | Time/Food | Navigation |

**Production Cycle**:
1. Receive order from player
2. Check ingredients
3. Generate quote (cost + time)
4. Player pays upfront
5. NPC produces (non-linear progression)
6. Deliver result
7. Update skill

### 5. Survival & Emotional States

**Bite Mechanic**:
- Hidden infection possible
- Toss probability: 0.15 base, 2x if infection >40%
- Isolation if anxiety >60%
- Inspection forces revelation
- Creates dramatic tension

**Emotional States**:
- Trauma (freeze, rage)
- Loneliness (seeking interaction)
- Fear (running, hiding)
- Confidence (assertive)

**Modifiers**:
- Weather (cold, rain, storm)
- Injuries (localized, mobility penalty)
- Hunger/thirst (fatigue, decision quality)
- Relationships (trust in player)

### 6. Learning & Memory

**Observable Skills**:
- Carpentry (1.2x bonus)
- Farming (1.0x)
- Cooking (0.9x)
- Crafting (1.1x)
- Medical (1.3x)
- Mechanics (1.25x)
- Fishing (1.0x)

**Memory Types**:
- **Personal**: NPC's own experiences
- **Social**: Relationship with player/other NPCs
- **Procedural**: How to execute tasks
- **Episodic**: Recent events

**Persistence**:
- ModData save every 1800 ticks (30 sec)
- Dormant NPC records (up to 2000)
- TTL: 21600 ticks (36 min)

### 7. User Interface (Client-Side)

**Main HUD**:
- NPC status (mood, profession, health)
- Profession details (current task, progress)
- Inventory (what NPC has)
- Dialogue log

**Dialogue UI**:
- Text input for chat
- Response display (green = AI, blue = you)
- Pending state (animated dots while waiting)
- Fallback response notification

**Debug Overlay** (admin only):
- FSM state display
- Heatmap of NPC density
- Distance/range visualization
- Performance metrics

### 8. Gameplay Profile System

**5 Preset Profiles**:
- **realistic**: Balanced (default)
- **hardcore**: NPCs tough, need frequent resupply
- **narrative**: Focus on story, less combat
- **ultra_hardcore**: Extreme survival
- **rp_soft**: Light survival, focus on RP

**What Profiles Tune**:
- NPC health/resistance
- Need decay rates
- Skill progression speed
- Profession profitability
- Trauma/disease risk
- Expedition success rates

**Admin Control**:
```lua
/phnpc profile hardcore   -- Switch profile
PHNPC.getFactor("health") -- Query multiplier
```

---

## 📁 File Organization

### Shared Code (10 files)
```
media/lua/shared/
├── GameModeDetector.lua ← Mode detection (NEW v1.0.5)
├── NPCDataModel.lua
├── NPCDialogueLocalization.lua
├── NPCFactionManager.lua
├── NPCMemory.lua
├── NPCTuningProfiles.lua
├── PHNPC_ConfigManager.lua
├── PHNPC_Logger.lua
├── SandboxVars.lua
└── !ModOptionsEngine.lua
```

### Server Code (13 files)
```
media/lua/server/
├── NPCSpawner.lua ← DISPATCHER (NEW v1.0.5)
├── NPCSpawner_SOLO.lua ← SOLO impl (NEW v1.0.5)
├── NPCSpawner_MULTI.lua ← MULTI impl (NEW v1.0.5)
├── NPC_NetworkServer.lua
├── NPC_BiteManagement.lua
├── NPC_ObservationLearning.lua
├── NPCBrain.lua
├── NPCEnvironmentHooks.lua
├── NPCInteractionHooks.lua
├── NPCMemoryRuntime.lua
├── NPCQuestRuntime.lua
├── OllamaBridge.lua
└── PHNPC_ConsoleBridgeServer.lua
```

### Client Code (5 files)
```
media/lua/client/
├── NPC_NetworkClient.lua
├── NPC_UI.lua
├── OllamaChatUI.lua
├── PHNPC_SpeechBubbles.lua
├── PHNPC_ConsoleBridge.lua
└── !!CustomOptions.lua
```

### Translations (4 files)
```
media/lua/shared/Translate/
├── FR/
│   ├── Sandbox_FR.txt
│   └── IG_UI_FR.txt
└── EN/
    ├── Sandbox_EN.txt
    └── IG_UI_EN.txt
```

**Total**: 37 Lua files, ~25K lines, fully documented

---

## ⚡ Performance

### CPU Usage
| Scenario | CPU/Tick | Notes |
|----------|----------|-------|
| SOLO (0 NPCs) | 0.1ms | Idle baseline |
| SOLO (6 NPCs) | 0.3ms | Normal gameplay |
| SOLO (12 NPCs) | 0.5ms | Max active |
| MULTI (10 NPCs) | <1ms | Multi-player (300 tick sync) |

### Memory
- Per NPC: ~40KB (data + state)
- Dormancy pool: ~400KB (2000 records)
- UI overhead: ~50KB
- Cache: ~100KB (50 dialogue responses)

### Network
- SOLO: 0 bytes/sec (no network)
- MULTI: ~6.4 kbps (10 NPCs, throttled 0.5s)

---

## 🔐 Security & Sanity

### Server Authority
- All critical logic runs server-side
- No client-side prediction
- No RPC code injection possible
- Admin commands require server-side verification

### Validation
- Inventory duplication checks
- Payment verification before trade
- NPC capacity checks
- Pathfinding obstacle validation

### Error Recovery
- Try-catch wrappers on Ollama HTTP
- Health check (5 min interval)
- Auto-fallback if Ollama unavailable
- Graceful NPC spawn/despawn

---

## 🐛 Known Limitations

1. **NPC Pathfinding**: Uses base PZ pathfinding (no custom A*)
2. **NPC Animations**: Limited control over motion capture
3. **Multiplayer Ping**: High ping (>500ms) may cause sync delays
4. **Ollama Latency**: Dialogue can delay 2-8 seconds (acceptable for async)
5. **Simultaneous Orders**: NPCs cannot execute multiple orders at once

---

## 🔄 Code Patterns

### Mode-Aware Code
```lua
if GameModeDetector:isSolo() then
    -- SOLO-only logic
elseif GameModeDetector:isMulti() then
    -- MULTI-only logic
end
```

### Network Guards
```lua
if npc:getOnlineID() ~= -1 then
    transmitModData(...)  -- Only sync if online
end
```

### Safe UI Rendering
```lua
local okX, sx = pcall(isoToScreenX, playerIndex, x, y, z)
if okX then
    -- Render at (sx, sy)
end
```

### Profile-Based Tuning
```lua
local factor = NPCTuningProfiles:getFactor("health")
npc.health = baseHealth * factor
```

---

## 📚 See Also

- [FILE_INDEX.md](FILE_INDEX.md) — Detailed file inventory
- [CONFIGURATION.md](CONFIGURATION.md) — All settings
- [PERFORMANCE.md](PERFORMANCE.md) — Optimization guide
- [COMMANDS.md](COMMANDS.md) — Admin commands
