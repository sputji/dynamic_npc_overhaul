# Dynamic NPC Overhaul v2.1
## Project Zomboid Advanced NPC System

**Version**: 2.1  
**Release**: v1.0.5 (SOLO vs MULTI Separation)  
**Last Updated**: 12 mai 2026  
**License**: Check LICENSE file  
**Repository**: https://github.com/sputji/dynamic_npc_overhaul

---

## 🎯 Overview

Dynamic NPC Overhaul is a comprehensive NPC system for Project Zomboid that brings intelligent, autonomous NPCs to both single-player and multiplayer servers with:

- **AI-Driven Behavior**: Autonomous decision-making based on needs, professions, and strategic priorities
- **Ollama Integration**: Dynamic dialogue generation with intelligent fallback system
- **Profession System**: NPCs master 5 professions (Artisan, Cook, Builder, Merchant, Explorer) with real production
- **Multiplayer Support**: Full network synchronization with v1.0.5 clean architecture separation
- **Hidden Bite Mechanic**: Dramatic survival tension with cough/isolation signs
- **Passive Learning**: NPCs learn skills invisibly from player observation
- **Rich UI**: In-game HUD for interaction, trading, and NPC status

---

## 🚀 Quick Start

### For Players
1. **Install the mod** into your `Zomboid/mods/` folder
2. **Start your game** (single-player or multiplayer server)
3. **Find an NPC** and right-click → "Open NPC HUD"
4. **Chat via AI** or trade items/services

See [QUICKSTART.md](QUICKSTART.md) for detailed user guide.

### For Admins
- Use `/phnpc` commands to spawn, clear, or manage NPCs
- Adjust gameplay profiles (realistic, hardcore, narrative, etc.)
- Monitor NPC state with debug overlay

See [COMMANDS.md](COMMANDS.md) for complete command reference.

### For Developers
- Mod system is fully modular with clean SOLO/MULTI separation
- All configuration in `CONFIGURATION.md`
- Architecture explained in `ARCHITECTURE.md`
- File structure in `FILE_INDEX.md`

See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines.

---

## 📚 Documentation Structure

| Document | Purpose |
|----------|---------|
| [QUICKSTART.md](QUICKSTART.md) | Getting started guide for users |
| [FILE_INDEX.md](FILE_INDEX.md) | Complete Lua file inventory (37 files) |
| [ARCHITECTURE.md](ARCHITECTURE.md) | System design, SOLO/MULTI separation, patterns |
| [CONFIGURATION.md](CONFIGURATION.md) | All mod settings and customization |
| [COMMANDS.md](COMMANDS.md) | Admin commands and console tools |
| [PERFORMANCE.md](PERFORMANCE.md) | Performance tuning and optimization |
| [CHANGELOG.md](CHANGELOG.md) | Version history and patch notes |
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to contribute or modify the mod |
| [DEPLOYMENT.md](DEPLOYMENT.md) | Installation and deployment guide |

---

## 🎮 Key Features

### 1. **Intelligent AI System**
- Server-centric decision loop (33ms cycle)
- Need calculation (hunger, thirst, morale, survival)
- Trade strategy based on professions
- Order execution (STUDY, BUILD, COOK, TRADE, DEFEND, GUARD)
- Environmental interaction (door opening, pathfinding)

### 2. **Profession System**
- **Artisan**: Crafts tools and materials
- **Cook**: Prepares meals with ingredient consumption
- **Builder**: Constructs structures and fortifications
- **Merchant**: Trades items for currency
- **Explorer**: Scouts distant locations for resources

### 3. **Dialogue Engine**
- **Ollama Integration**: Real-time AI dialogue (async, non-blocking)
- **Smart Fallback**: 16+ contextual responses if Ollama unavailable
- **Multilingual**: French/English with locale detection
- **Contextual**: Dialogue considers NPC emotion, recent events, player relationship

### 4. **Multiplayer Architecture (v1.0.5)**
```
Game Startup → GameModeDetector:detectMode()
    ├─ "SOLO" → NPCSpawner_SOLO.lua (no network)
    └─ "MULTI" → NPCSpawner_MULTI.lua (full network sync)
```
- **Zero Cross-Contamination**: Completely isolated code paths
- **Automatic Routing**: No configuration needed
- **Performance**: SOLO mode has zero network overhead

### 5. **Hidden Bite Mechanic**
- NPCs can become infected without revealing it
- Toss probability based on infection %
- Isolation when anxious
- Dramatic tension in multiplayer scenarios

### 6. **Passive Learning**
- NPCs observe player skills (7 types: carpentry, farming, cooking, medical, etc.)
- Award bonus XP silently
- Reference observations in dialogue: "I watched you build..."

---

## 📦 Installation

### Requirements
- Project Zomboid Build 41.78+
- Ollama (optional, system falls back to hardcoded responses if unavailable)
- Multi-world support (SP and MP)

### Steps
1. Download from [GitHub](https://github.com/sputji/dynamic_npc_overhaul)
2. Extract to `C:\Users\<YourUser>\Zomboid\mods\Dynamic_NPC_Overhaul\`
3. Activate in mod menu
4. Restart game

See [DEPLOYMENT.md](DEPLOYMENT.md) for detailed setup.

---

## ⚙️ Configuration

All mod options are configurable via:
- **Mod Options** (in-game menu if Build 41)
- **SandboxVars** (server authority in multiplayer)
- **Gameplay Profiles** (realistic, hardcore, narrative, ultra_hardcore, rp_soft)

Examples:
```lua
-- Adjust max active NPCs
NPCSpawner.maxActiveNPCs = 12

-- Change spawn radius
NPCSpawner.spawnRadius = 32

-- Switch profile (admin command)
/phnpc profile hardcore
```

See [CONFIGURATION.md](CONFIGURATION.md) for all settings.

---

## 🛠️ Admin Commands

```bash
/phnpc help              # Show all commands
/phnpc status            # Show current NPC counts & overlay state
/phnpc spawn 5           # Spawn 5 NPCs around player
/phnpc clear             # Delete all NPCs and dormant records
/phnpc debug on|off      # Toggle debug overlay
/phnpc profile hardcor   # Switch gameplay profile
/phnpc mark on|off       # Visual debug markers
```

Full command reference in [COMMANDS.md](COMMANDS.md).

---

## 🏗️ Architecture

### v1.0.5 Highlights
- **Clean Dispatcher**: NPCSpawner.lua routes to SOLO or MULTI implementation
- **SOLO Mode**: 692 lines, zero network code, lightweight
- **MULTI Mode**: 506+ lines, full network sync, multi-player targeting
- **Shared Utilities**: GameModeDetector for mode detection

### Code Organization
```
media/lua/
├── shared/               # Common code
│   ├── GameModeDetector.lua
│   ├── NPCDataModel.lua
│   ├── NPCMemory.lua
│   ├── PHNPC_ConfigManager.lua
│   └── ... (22 shared files)
├── server/               # Server-side logic
│   ├── NPCSpawner.lua (dispatcher)
│   ├── NPCSpawner_SOLO.lua
│   ├── NPCSpawner_MULTI.lua
│   ├── NPCBrain.lua (AI decisions)
│   ├── OllamaBridge.lua (dialogue)
│   └── ... (12 server files)
└── client/               # Client UI
    ├── NPC_UI.lua (HUD)
    ├── OllamaChatUI.lua (dialogue UI)
    ├── PHNPC_SpeechBubbles.lua
    └── ... (5 client files)
```

Total: **37 Lua files**, ~25K lines of code

See [FILE_INDEX.md](FILE_INDEX.md) and [ARCHITECTURE.md](ARCHITECTURE.md) for details.

---

## 📊 Performance

| Mode | CPU | Memory | Network |
|------|-----|--------|---------|
| SOLO (12 NPCs) | ~0.5ms/tick | ~500KB | 0 bytes |
| MULTI (10 NPCs) | <1ms/tick | ~800KB | ~6.4 kbps |

See [PERFORMANCE.md](PERFORMANCE.md) for optimization tips.

---

## 🐛 Common Issues

**NPCs not spawning?**
- Check server console: `/phnpc status`
- Verify Ollama running if using AI dialogue
- Check player is not in indoor-only zone

**Dialogue not working?**
- Ollama optional — system falls back to hardcoded responses
- Check network settings if multiplayer
- Verify language in game settings

**Game crashes?**
- See [ARCHITECTURE.md](ARCHITECTURE.md) → Known Limitations
- Report with server log

---

## 📝 Changelog

### v1.0.5 (12 mai 2026)
- 🆕 Clean SOLO/MULTI separation via dispatcher pattern
- 🆕 GameModeDetector utility for automatic mode routing
- ✅ Zero cross-contamination between modes
- ✅ Fixed isoToScreenX/Y signature (playerIndex first)

### v1.0.4 (Recent)
- Added visual/audio feedback (NPCFx system)
- Enhanced network robustness (requestId correlation, timeouts)
- Expanded dialogue translation system

See [CHANGELOG.md](CHANGELOG.md) for full history.

---

## 🤝 Contributing

Want to improve the mod? Great! See [CONTRIBUTING.md](CONTRIBUTING.md) for:
- How to set up development environment
- Code style and patterns
- Testing procedures
- Pull request guidelines

---

## 📄 License

See LICENSE file in repository.

---

## 🔗 Links

- **GitHub**: https://github.com/sputji/dynamic_npc_overhaul
- **Steam Workshop**: [Link if published]
- **Bug Reports**: GitHub Issues
- **Discussions**: GitHub Discussions

---

## 📞 Support

- Check [QUICKSTART.md](QUICKSTART.md) for user questions
- Check [COMMANDS.md](COMMANDS.md) for admin issues
- Check [CONFIGURATION.md](CONFIGURATION.md) for mod settings
- File GitHub issue for bugs

---

**Happy NPC managing!** 🎮
