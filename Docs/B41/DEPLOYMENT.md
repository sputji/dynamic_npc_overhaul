# Deployment Guide

**Type**: Setup & Installation  
**Updated**: 12 mai 2026

---

## 📦 Installation

### Requirements
- Project Zomboid **Build 41.78+**
- Windows / Mac / Linux
- ~500MB disk space
- Optional: Ollama for AI dialogue

### Step 1: Download

**Option A: GitHub**
```bash
git clone https://github.com/sputji/dynamic_npc_overhaul.git
cd dynamic_npc_overhaul
```

**Option B: Steam Workshop**
[Link if published - TBD]

**Option C: Manual Download**
- Download ZIP from releases
- Extract to `Zomboid/mods/`

### Step 2: Install

```
Extract to:
  C:\Users\<YourName>\Zomboid\mods\Dynamic_NPC_Overhaul\
  
Directory structure should be:
  Dynamic_NPC_Overhaul/
  ├── media/
  │   └── lua/
  │       ├── shared/
  │       ├── server/
  │       └── client/
  ├── Docs/
  └── mod.info
```

### Step 3: Activate

1. **Single-Player**:
   - Start Project Zomboid
   - Click **Mods**
   - Check **Dynamic_NPC_Overhaul**
   - Click **Play**

2. **Multiplayer Server**:
   - Add to server `mods/` folder
   - Restart server
   - Server automatically detects and loads

### Step 4: Configure (Optional)

In-game **Mod Options** (Build 41):
- Max active NPCs
- Spawn radius
- Gameplay profile
- Debug options

See [CONFIGURATION.md](CONFIGURATION.md) for all settings.

---

## 🚀 First Run

### Single-Player
1. Start new game
2. Wait ~5-10 seconds for initialization
3. You should see NPCs spawning nearby
4. Right-click on NPC → "Open HUD"

### Multiplayer
1. Join server
2. Server console should show: `[PHNPC] NPCSpawner loaded: MULTI mode`
3. Use `/phnpc spawn 5` to spawn NPCs
4. Right-click on NPC → "Open HUD"

### No NPCs Appearing?
- Check server console: `/phnpc status`
- Verify you're not in basement (no spawn underground)
- Check player has no "no NPC" mods conflicting
- See [Troubleshooting](#troubleshooting)

---

## ⚙️ Configuration

### GameplayProfiles
```lua
-- In Mod Options or command line:
/phnpc profile <name>

Available profiles:
  realistic       -- Default, balanced
  hardcore        -- Tough NPCs, rare supplies
  narrative       -- Story focus, light survival
  ultra_hardcore  -- Extreme difficulty
  rp_soft         -- Light survival, RP focus
```

### Key Settings
```lua
-- All in CONFIGURATION.md, but quick examples:
NPCSpawner.maxActiveNPCs = 12       -- Max at once
NPCSpawner.spawnRadius = 32         -- Cells from player
NPCSpawner.updateEveryTicks = 150   -- Update cycle
OllamaBridge.ollamaUrl = "http://localhost:11434"  -- Ollama endpoint
```

See [CONFIGURATION.md](CONFIGURATION.md) for **complete list**.

---

## 🖥️ Ollama Setup (Optional)

The mod works WITHOUT Ollama, but dialogue will use hardcoded responses.

### Install Ollama

1. Download from https://ollama.ai
2. Run installer
3. Start Ollama service

### Run a Model

```bash
ollama run mistral    # or any model you prefer
```

Ollama will listen on `http://localhost:11434` by default.

### Verify

In-game, chat with an NPC. If Ollama is working, you'll get AI-generated dialogue. If Ollama is down, you'll get fallback responses automatically.

---

## 📊 Post-Installation Checks

### Console Verification

```
Server console should show:
[PHNPC] NPCSpawner loaded: SOLO mode (or MULTI for multiplayer)
[PHNPC] Logger initialized
[PHNPC] ConfigManager loaded
[PHNPC] GameModeDetector initialized
```

### Mod Menu Check

- Mods → Dynamic_NPC_Overhaul should be listed
- No errors in mod loading log
- Can toggle Mod Options if Build 41+

### NPC Spawning Check

- `/phnpc status` → Shows active/dormant NPC counts
- `/phnpc spawn 1` → Should spawn 1 NPC near you
- Right-click NPC → "Open HUD" works

---

## 🔧 Troubleshooting

### NPCs not spawning
```
Check:
1. /phnpc status         -- What does it say?
2. Am I underground? (spawn only above-ground)
3. Are there hostile zombies nearby? (interference)
4. Check server log for [PHNPC] errors
5. Verify NPCSpawner.lua loaded (look at mod.info)
```

### Dialogue not working
```
Check:
1. Is Ollama running? (optional, not required)
2. What does NPC say? (AI or fallback response?)
3. Check player language setting
4. Try /phnpc debug on to see errors
```

### Game crashes
```
Check:
1. Server log for Lua errors
2. Is this a mod conflict? (disable other mods)
3. Report to GitHub with log attached
```

### Multiplayer server won't start
```
Check:
1. Server log for [PHNPC] errors
2. Is mod in server mods/ folder?
3. Restart server completely
4. Check firewall (unlikely to affect Lua mod)
```

---

## 📤 Uninstall

### Remove Mod
```
Delete folder:
  Zomboid/mods/Dynamic_NPC_Overhaul/
  
Restart game.
```

### Clean Saves
```
Delete saves with NPCs:
  Zomboid/Saves/<YourSave>/
```

(Optional - saves will still load, but NPCs will be gone)

---

## 🚀 Updating

### To Latest Version

**From GitHub:**
```bash
cd Dynamic_NPC_Overhaul
git pull origin main
```

**From Release ZIP:**
1. Backup your `Zomboid/mods/Dynamic_NPC_Overhaul/` folder
2. Download new ZIP
3. Extract, overwrite old files
4. Restart game

### Compatibility

- **SOLO saves**: Always compatible (moddata saved locally)
- **MULTI servers**: New players should rejoin (state syncs automatically)

---

## 📋 System Requirements

| Requirement | Min | Recommended |
|-------------|-----|-------------|
| PZ Build | 41.78 | Latest |
| CPU | Dual-core | Quad-core+ |
| RAM | 4GB | 8GB+ |
| Disk | 500MB | 1GB |
| Network | N/A | ≥10Mbps for MP |

---

## 🎓 Next Steps

After installation:

1. **Players**: Read [QUICKSTART.md](QUICKSTART.md)
2. **Admins**: Read [COMMANDS.md](COMMANDS.md)
3. **Developers**: Read [ARCHITECTURE.md](ARCHITECTURE.md)
4. **Customization**: Read [CONFIGURATION.md](CONFIGURATION.md)

---

## 📞 Support

- **Bugs**: GitHub Issues
- **Questions**: GitHub Discussions
- **Documentation**: See [README.md](README.md)

---

**Ready to go!** 🎮
