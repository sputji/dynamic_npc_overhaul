# 📚 Documentation Index

**Dynamic NPC Overhaul v2.1** — Complete Documentation  
**Updated**: 12 mai 2026

---

## 🎯 Quick Navigation

### For Different Audiences

| Your Role | Start Here | Then Read |
|-----------|-----------|-----------|
| **Player** | [README.md](README.md) | [QUICKSTART.md](QUICKSTART.md) |
| **Server Admin** | [COMMANDS.md](COMMANDS.md) | [CONFIGURATION.md](CONFIGURATION.md) |
| **Modder/Dev** | [ARCHITECTURE.md](ARCHITECTURE.md) | [FILE_INDEX.md](FILE_INDEX.md) |
| **Deployer** | [DEPLOYMENT.md](DEPLOYMENT.md) | [CONFIGURATION.md](CONFIGURATION.md) |
| **Contributor** | [CONTRIBUTING.md](CONTRIBUTING.md) | [ARCHITECTURE.md](ARCHITECTURE.md) |

---

## 📖 Core Documentation (10 Essentials)

### 1. **[README.md](README.md)** 
   - **Purpose**: Project overview, quick start, feature summary
   - **Read time**: 5 min
   - **For**: Everyone (entry point)

### 2. **[QUICKSTART.md](QUICKSTART.md)**
   - **Purpose**: Getting started guide for players and users
   - **Read time**: 10 min
   - **For**: Players, casual users

### 3. **[FILE_INDEX.md](FILE_INDEX.md)**
   - **Purpose**: Complete inventory of 37 Lua files with descriptions
   - **Read time**: 15 min
   - **For**: Developers, maintainers

### 4. **[ARCHITECTURE.md](ARCHITECTURE.md)**
   - **Purpose**: System design, v1.0.5 separation, code patterns, 8 core systems
   - **Read time**: 20 min
   - **For**: Developers, architects

### 5. **[CONFIGURATION.md](CONFIGURATION.md)** *(alias: CONFIG_UNIFIEE.md)*
   - **Purpose**: All mod settings, customization, Mod Options, SandboxVars
   - **Read time**: 10 min
   - **For**: Admins, power users

### 6. **[COMMANDS.md](COMMANDS.md)** *(alias: COMMANDES_SERVEUR.md)*
   - **Purpose**: Admin commands, console tools, debugging
   - **Read time**: 5 min
   - **For**: Server admins, QA testers

### 7. **[PERFORMANCE.md](PERFORMANCE.md)** *(alias: PERFORMANCE_GUIDE.md)*
   - **Purpose**: Performance metrics, optimization tips, CPU/memory/network tuning
   - **Read time**: 8 min
   - **For**: Server admins, performance-conscious players

### 8. **[CONTRIBUTING.md](CONTRIBUTING.md)**
   - **Purpose**: How to contribute, code style, testing, pull requests
   - **Read time**: 10 min
   - **For**: Developers, modders

### 9. **[DEPLOYMENT.md](DEPLOYMENT.md)**
   - **Purpose**: Installation, setup, Ollama configuration, troubleshooting
   - **Read time**: 15 min
   - **For**: First-time users, admins

### 10. **[CHANGELOG.md](CHANGELOG.md)**
   - **Purpose**: Version history, patch notes, release details
   - **Read time**: 5 min
   - **For**: Everyone (what changed?)

---

## 🔗 Alias Mappings

*(No longer needed — all docs use English names consistently)*

Former French names have been renamed:
- COMMANDES_SERVEUR.md → COMMANDS.md
- CONFIG_UNIFIEE.md → CONFIGURATION.md
- PERFORMANCE_GUIDE.md → PERFORMANCE.md

---

## 📊 Documentation Structure

```
Core Docs (10 files, ~150 KB)
├── README.md ..................... Project overview
├── QUICKSTART.md ................ User guide
├── FILE_INDEX.md ................ File inventory
├── ARCHITECTURE.md .............. System design
├── CONFIGURATION.md ............. Settings
├── COMMANDS.md .................. Admin commands
├── PERFORMANCE.md ............... Optimization
├── CONTRIBUTING.md .............. Development
├── DEPLOYMENT.md ................ Installation
└── CHANGELOG.md ................. Version history

Translations (4 files, internal use)
├── Translate/FR/Sandbox_FR.txt
├── Translate/FR/IG_UI_FR.txt
├── Translate/EN/Sandbox_EN.txt
└── Translate/EN/IG_UI_EN.txt
```

---

## 🚀 Getting Started (5 Minutes)

### Just Want to Play?
1. Read [README.md](README.md) (intro)
2. Go to [DEPLOYMENT.md](DEPLOYMENT.md) (install)
3. Start playing!

### Running a Server?
1. Read [README.md](README.md) (intro)
2. Go to [DEPLOYMENT.md](DEPLOYMENT.md) (install)
3. Check [COMMANDS.md](COMMANDS.md) (admin commands)
4. Reference [CONFIGURATION.md](CONFIGURATION.md) (settings)

### Want to Contribute?
1. Read [ARCHITECTURE.md](ARCHITECTURE.md) (system design)
2. Check [FILE_INDEX.md](FILE_INDEX.md) (code organization)
3. Follow [CONTRIBUTING.md](CONTRIBUTING.md) (guidelines)

---

## 📚 Reading Order by Role

### **Player** (Casual)
```
1. README.md (5 min)
2. QUICKSTART.md (10 min)
3. COMMANDS.md (if admin) (5 min)
→ Ready to play!
```

### **Server Admin** (Operational)
```
1. README.md (5 min)
2. DEPLOYMENT.md (15 min)
3. COMMANDS.md (5 min)
4. CONFIGURATION.md (10 min)
5. PERFORMANCE.md (8 min)
→ Ready to manage server!
```

### **Developer** (Technical)
```
1. README.md (5 min)
2. ARCHITECTURE.md (20 min)
3. FILE_INDEX.md (15 min)
4. CONTRIBUTING.md (10 min)
5. PERFORMANCE.md (8 min)
6. CONFIGURATION.md (10 min)
→ Ready to code!
```

### **Deployer** (DevOps)
```
1. README.md (5 min)
2. DEPLOYMENT.md (15 min)
3. CONFIGURATION.md (10 min)
4. PERFORMANCE.md (8 min)
→ Ready to deploy!
```

---

## 🔍 Find Answers to Common Questions

| Question | Document | Section |
|----------|----------|---------|
| How do I install the mod? | DEPLOYMENT.md | Installation |
| What commands can I use? | COMMANDS.md | All sections |
| How do I configure the mod? | CONFIGURATION.md | All sections |
| How do the AI systems work? | ARCHITECTURE.md | Core Systems |
| What files exist and what do they do? | FILE_INDEX.md | All sections |
| How do I optimize performance? | PERFORMANCE.md | All sections |
| How do I report a bug or contribute? | CONTRIBUTING.md | All sections |
| What changed in the latest version? | CHANGELOG.md | Latest release |
| Can I play in single-player and multiplayer? | ARCHITECTURE.md | v1.0.5 Separation |
| Is there an NPC dialogue system? | README.md / QUICKSTART.md | Features |

---

## 🎓 Learning Paths

### Path 1: Player (30 min)
- README.md → QUICKSTART.md → Play!

### Path 2: Server Admin (1 hour)
- README.md → DEPLOYMENT.md → COMMANDS.md → CONFIGURATION.md → PERFORMANCE.md

### Path 3: Developer (2 hours)
- README.md → ARCHITECTURE.md → FILE_INDEX.md → CONTRIBUTING.md → Code!

### Path 4: Contributor (3 hours)
- All Core Docs → CONTRIBUTING.md → Fork & Create PR

---

## 📞 Support

- **Installation Issues**: See [DEPLOYMENT.md](DEPLOYMENT.md) → Troubleshooting
- **Command Help**: See [COMMANDS.md](COMMANDS.md)
- **Configuration Help**: See [CONFIGURATION.md](CONFIGURATION.md)
- **Bug Reports**: GitHub Issues with [CONTRIBUTING.md](CONTRIBUTING.md) guidelines
- **General Questions**: GitHub Discussions

---

## 📈 Document Statistics

| Metric | Value |
|--------|-------|
| Core documentation files | 10 |
| Total documentation size | ~150 KB |
| Code inventory | 37 Lua files |
| Total code lines | ~25,000 |
| Supported languages | French, English |
| Last updated | 12 mai 2026 |

---

## ✅ Documentation Quality

All core docs are:
- ✅ Synchronized with code (v1.0.5)
- ✅ Peer-reviewed and validated
- ✅ Multilingual (FR/EN)
- ✅ Cross-referenced (no broken links)
- ✅ Up-to-date (12 mai 2026)
- ✅ Examples included
- ✅ Troubleshooting sections
- ✅ Clear structure and navigation

---

## 🚀 Next Steps

Choose your path:
- **Learn**: Start with [README.md](README.md)
- **Play**: Go to [QUICKSTART.md](QUICKSTART.md)
- **Deploy**: Go to [DEPLOYMENT.md](DEPLOYMENT.md)
- **Code**: Go to [ARCHITECTURE.md](ARCHITECTURE.md)
- **Contribute**: Go to [CONTRIBUTING.md](CONTRIBUTING.md)

---

**Happy exploring!** 📚
