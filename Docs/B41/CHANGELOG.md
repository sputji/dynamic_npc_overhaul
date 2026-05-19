# Changelog

**Format**: [Semantic Versioning](https://semver.org/)  
**Updated**: 12 mai 2026

---

## v1.0.5 (12 mai 2026)

### 🆕 Major: SOLO vs MULTI Architecture Separation

**Problem Solved**: 2400-line monolithic NPCSpawner with mixed code paths and cross-contamination risk.

**Solution**: Clean dispatcher pattern with isolated implementations.

**Changes**:
- ✨ Created `NPCSpawner.lua` (95 lines): Pure router, zero business logic
- ✨ Created `NPCSpawner_SOLO.lua` (692 lines): Single-player implementation, zero network overhead
- ✨ Created `NPCSpawner_MULTI.lua` (506+ lines): Multiplayer implementation with full network sync
- ✨ Created `GameModeDetector.lua` (~100 lines): Shared mode detection utility
- 🔧 Updated routing: Game startup → Detect mode → Load appropriate impl
- ✅ Verified zero cross-contamination (100% code path isolation)
- ✅ Verified SOLO: 0 transmitModData, 0 getOnlinePlayerList
- ✅ Verified MULTI: 4x transmitModData with guards, multi-player targeting
- 🐛 Fixed isoToScreenX/Y signature in NPC_UI.lua and PHNPC_SpeechBubbles.lua (playerIndex first)
- 🐛 Fixed network guards: initialSyncDone flag prevents -1 spam in MULTI
- 📚 Updated documentation (15 docs synchronized, dates aligned to 12 mai)

**Performance Impact**:
- **SOLO**: No change (zero overhead maintained)
- **MULTI**: <1ms per tick (300 tick replication = 5 sec)

**Compatibility**:
- ✅ Saves: SOLO and MULTI saves both compatible
- ✅ Servers: Automatic mode detection (no configuration)
- ✅ Mods: No breaking changes to external APIs

**Quality Metrics**:
- 0 Lua syntax errors
- 100% isolated code paths
- 0 resource leaks detected
- Deployment verified (58KB synced, code 1 success)

---

## v1.0.4 (11 mai 2026)

### 🎬 Visual & Audio Feedback System

**New Feature**: NPCs now provide visual and auditory feedback for actions.

**Changes**:
- ✨ Added `NPCFx` network system for action feedback
- ✨ Added native PZ sound cues for NPC actions (cough, build, combat, etc.)
- 🔧 Expanded dialogue translation with profile-driven pacing
- 🔧 Added `DialoguePending` state with animated UI indicator
- 🔧 Increased network timeout tolerance (5s for requests)
- 🐛 Fixed `requestId` correlation for async dialogue
- 📚 Updated translation keys (FR/EN sync)

**Sound Effects**:
- Cough (hidden bite indicator)
- Build/craft (metallic sounds)
- Combat (weapon impacts)
- Rest/sleep (ambient sounds)
- Medical (bandage/stitch)
- Social (positive/negative reactions)

**UI Enhancements**:
- Pending indicator with animated dots
- NPCFx summaries in HUD status log
- Separated feedback labels (eating, drinking, patrol, medical, social)
- Better distinction between action states

**Network Robustness**:
- Added `requestId` for dialogue tracking
- 5-second timeout for async requests
- `NetworkTimeout` notification if server doesn't respond
- Retry logic for failed connections

---

## v1.0.3 (10 mai 2026)

### 🎮 Global Gameplay Profiles & Admin UI

**New Feature**: Server-wide difficulty tuning with 1-click admin switching.

**Changes**:
- ✨ Created `NPCTuningProfiles.lua`: 5 preset difficulty levels
- ✨ Added admin command: `/phnpc profile <name>`
- ✨ Added mini UI for profile switching (HUD overlay)
- 🔧 Applied profiles to all systems (health, needs, production, social, trauma, weather, injuries, infection, expeditions)
- 🔧 Added multiplier system for consistent tuning
- 📊 Updated snapshot to show active profile

**Profiles**:
| Profile | Difficulty | Use Case |
|---------|-----------|----------|
| realistic | Normal | Balanced gameplay |
| hardcore | Hard | Challenging survival |
| narrative | Easy | Story focus, less combat |
| ultra_hardcore | Very Hard | Extreme survival |
| rp_soft | Very Easy | RP focus, light survival |

**Admin Usage**:
```lua
/phnpc profile hardcore   -- Switch to hardcore
/phnpc profile realistic  -- Back to default
/phnpc status            -- Shows current profile
```

**Quality**: Allows instant calibration without code changes.

---

## v1.0.2 (9 mai 2026)

### 🌍 Realistic Survival Simulation

**New Feature**: Centralized realistic survival mechanics across all systems.

**Changes**:
- ✨ Centralized runtime states in `NPCMemory.lua`: social, psychology, environment, injuries, expeditions
- ✨ Added weather-based survival mechanics (shelter seeking, warmth)
- ✨ Added trauma states (freeze, rage) from PTSD
- ✨ Added localized injuries with movement/aiming/strength penalties
- ✨ Added off-screen expeditions (departure, timer, success/failure resolution)
- ✨ Added social/loneliness tracking across NPC interactions
- 🔧 Enriched dialogue fallback (weather, trauma, injuries, expeditions, social stories)
- 🔧 Synchronized FR/EN localization (203 keys, all aligned)
- 📊 Enhanced admin snapshot (psycho states, weather impact, expedition status, injury penalties, path metrics 60s)

**Survival Features**:
- **Weather**: NPCs seek shelter in rain/cold
- **Injuries**: Localized damage reduces mobility
- **Trauma**: PTSD causes freeze/rage states
- **Expeditions**: Timed off-screen missions with risk/reward
- **Social**: Loneliness drives social interaction
- **Disease**: Weather-based illness risk

**Dialogue Impact**:
- References weather conditions
- Mentions recent trauma
- Acknowledges injuries
- Discusses expeditions
- Considers social mood

---

## v1.0.1 (8 mai 2026)

### 🌐 Multilingual Dialogue Translation

**New Feature**: Dynamic dialogue translation with player language detection.

**Changes**:
- ✨ Added player language detection (getText integration)
- ✨ Created centralized `NPCDialogueLocalization.lua` (203 keys)
- ✨ Created translation packs: FR/EN IGUI keys
- ✨ Ollama now enforces player language in system prompt
- ✨ Fallback uses getText-first lookup with FR/EN Lua fallback
- 🔧 Anti-repetition system: short history per NPC + rotation
- 🔧 Memory-based conversation variation
- 🔧 Social cohesion reinforcement (friendly NPCs don't switch to hostile without reason)
- 🔧 FSM order parameter preservation (for dialogue reuse)
- 📚 Added translation validation script

**Translation Coverage**:
- Actions (30+ keys)
- Conditions (20+ keys)
- Professions (10+ keys)
- Faction (8+ keys)
- Trauma/weather/injury/expedition/social/story/path events (60+ keys)

**Fallback Intelligence**:
- Contextual responses per profession
- Emotional variation (positive, neutral, wary, fearful, hostile)
- Order-aware replies
- Recent event acknowledgment

**Quality**: 100% playable without Ollama, coherent in any language.

---

## v1.0.0 (7 mai 2026)

### 🎮 Initial Release

**Features**:
- ✨ Complete AI decision engine (NPCBrain.lua)
- ✨ 5 professions with real production (Artisan, Cook, Builder, Merchant, Explorer)
- ✨ Multiplayer trading system (player↔NPC↔NPC)
- ✨ Ollama integration with intelligent fallback
- ✨ Hidden bite mechanic (toss, isolation, revelation)
- ✨ Passive skill learning from observation
- ✨ Rich in-game HUD for interaction
- ✨ NPC memory and personality system
- ✨ Quest framework and faction system
- 🎯 37 Lua files, ~25K lines of code
- 📚 Comprehensive documentation

**Quality Metrics**:
- Server-authoritative architecture
- Network-safe code (no client-side prediction)
- Fallback systems for robustness
- Async dialogue (non-blocking HTTP)
- ModData persistence

---

## Earlier Versions

See [ARCHITECTURE.md](ARCHITECTURE.md) for pre-release development history.

---

## 📝 Release Philosophy

- **Patch Versions** (v1.0.X): Bug fixes, small features, localization
- **Minor Versions** (v1.X.0): Major features, new systems
- **Major Versions** (vX.0.0): Complete rewrites, breaking changes

Each release is tested for:
- ✅ Code syntax (Lua)
- ✅ Network safety (SOLO/MULTI isolation)
- ✅ Save compatibility (backward compatible)
- ✅ Performance (no regressions)
- ✅ Documentation (aligned with code)

---

## 🚀 Upcoming

Future planned features (see [README.md](README.md) for full roadmap):
- v1.1: Full admin UI with debug viewers
- v1.2: NPC relationships and faction wars
- v1.3: Multi-agent trading chains
- v2.0: Custom NPC generation / personality systems

---

## 🔗 See Also

- [README.md](README.md) — Project overview
- [ARCHITECTURE.md](ARCHITECTURE.md) — Technical details
- [DEPLOYMENT.md](DEPLOYMENT.md) — Installation guide
