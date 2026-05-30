--[[
    PHNPC_Stats.lua  v0.0.16  (shared)
    Initialisation des stats et de l'inventaire par metier.
    Systeme de progression XP / niveaux de competences.
    Project Humain : Dynamic NPC Overhaul

    v0.0.16 :
      - Ajout du systeme de progression : chaque NPC possede des competences
        avec un niveau (0-10) et des points d'experience (XP).
      - PHNPC.initSkills(zombie, outfit) : initialise les competences par metier.
      - PHNPC.getNPCSkillLevel(npc, skillName) : lit le niveau d'une competence.
      - PHNPC.addNPCXP(npc, skillName, xpAmount) : ajoute de l'XP et fait monter
        de niveau si le seuil est atteint.
      - Competences disponibles : Strength, Fitness, Aiming, Blunt, SmallBlade,
        Maintenance, Nimble, Sneaking, Doctor, Cooking, Carpentry, Farming, Axe.

    Appelé depuis PHNPC_Manager.lua convertToNPC()
    Nécessite PHNPC_Core.lua chargé avant (namespace PHNPC + PHNPC.OUTFIT_STATS)
]]

-- ============================================================
-- CONFIGURATION SYSTEME DE PROGRESSION
-- ============================================================

-- XP requis pour passer du niveau N au niveau N+1
-- Formule : XP_BASE * (niveau_actuel + 1) ^ XP_EXPONENT
local XP_BASE     = 150
local XP_EXPONENT = 1.5
local MAX_LEVEL   = 10

-- Competences de depart par metier (niveau initial, 0-10)
-- Format : { SkillName = niveau, ... }
local OUTFIT_SKILLS = {
    Police          = { Aiming=4, Nimble=4, Fitness=4, Strength=4, Blunt=3 },
    Sheriff_Deputy  = { Aiming=4, Nimble=4, Fitness=4, Strength=4, Blunt=3 },
    Detective       = { Aiming=3, Nimble=3, Fitness=3, Strength=3 },
    Security        = { Aiming=2, Nimble=3, Fitness=3, Strength=3, Blunt=3 },
    MallSecurity    = { Aiming=2, Nimble=2, Fitness=3, Strength=3, Blunt=2 },
    PrisonGuard     = { Aiming=3, Nimble=3, Fitness=4, Strength=5, Blunt=4 },
    Veteran         = { Aiming=6, Nimble=5, Fitness=5, Strength=5, SmallBlade=4 },
    ArmyCamoGreen   = { Aiming=6, Nimble=5, Fitness=6, Strength=6, SmallBlade=4 },
    ArmyCamoDesert  = { Aiming=6, Nimble=5, Fitness=6, Strength=6, SmallBlade=4 },
    PrivateMilitia  = { Aiming=5, Nimble=4, Fitness=5, Strength=5, Blunt=4 },
    BountyHunter    = { Aiming=5, Nimble=4, Fitness=4, Strength=4, SmallBlade=3 },
    Fireman         = { Fitness=6, Strength=6, Axe=4, Carpentry=2 },
    Doctor          = { Doctor=6, Fitness=2, Strength=2 },
    Nurse           = { Doctor=5, Fitness=2, Strength=1 },
    AmbulanceDriver = { Doctor=3, Fitness=3, Strength=2 },
    Pharmacist      = { Doctor=4, Fitness=1 },
    Farmer          = { Farming=5, Carpentry=3, Fitness=3, Strength=4 },
    Chef            = { Cooking=6, SmallBlade=3, Fitness=2 },
    Mechanic        = { Maintenance=5, Carpentry=3, Strength=4 },
    ConstructionWorker = { Carpentry=5, Strength=5, Fitness=4, Blunt=3 },
    Trucker         = { Fitness=3, Strength=4, Maintenance=2 },
    Woodcut         = { Fitness=4, Strength=5, Axe=4 },
    MetalWorker     = { Strength=5, Fitness=3, Maintenance=3 },
    Ranger          = { Aiming=4, Farming=3, Fitness=5, Sneaking=4, SmallBlade=3 },
    Hunter          = { Aiming=5, Fitness=4, Sneaking=4, SmallBlade=3 },
    Fisherman       = { Fitness=3, Strength=3 },
    Camper          = { Farming=2, Fitness=3, Sneaking=2 },
    Survivalist     = { Fitness=4, Strength=4, Carpentry=2, Farming=2, Sneaking=3 },
    Teacher         = { Fitness=1 },
    IT              = { Fitness=1, Maintenance=2 },
    OfficeWorker    = { Fitness=1 },
    Resident        = { Fitness=2, Strength=2 },
    Retiree         = { Fitness=1 },
    Student         = { Fitness=2 },
    Tourist         = { Fitness=2 },
    Biker           = { Fitness=3, Strength=4, Maintenance=2, Blunt=2 },
    Redneck         = { Aiming=3, Fitness=3, Strength=4, Axe=2 },
    Hobbo           = { Fitness=2, Strength=2, Sneaking=3 },
    Inmate          = { Fitness=4, Strength=4, SmallBlade=2, Blunt=3 },
    Priest          = { Fitness=1, Doctor=2 },
    FitnessInstructor = { Fitness=6, Strength=5, Nimble=4 },
    Generic01       = { Fitness=2, Strength=2 },
    Generic02       = { Fitness=2, Strength=2 },
    Generic03       = { Fitness=2, Strength=2 },
    Generic04       = { Fitness=2, Strength=2 },
    Generic05       = { Fitness=2, Strength=2 },
    Survivor        = { Fitness=3, Strength=3 },
}

-- Liste de toutes les competences supportees
local ALL_SKILLS = {
    "Strength", "Fitness", "Aiming", "Blunt", "SmallBlade", "Axe",
    "Maintenance", "Nimble", "Sneaking", "Doctor", "Cooking",
    "Carpentry", "Farming",
}

-- ============================================================
-- XP_FOR_LEVEL : XP total requis pour atteindre un niveau
-- ============================================================
local function xpForLevel(level)
    if level <= 0 then return 0 end
    local total = 0
    for i = 0, level - 1 do
        total = total + math.floor(XP_BASE * ((i + 1) ^ XP_EXPONENT))
    end
    return total
end

-- ============================================================
-- PHNPC.initSkills : initialise les competences par metier
-- Stocke dans ModData : PHNPC_Skill_<Name> (niveau) + PHNPC_XP_<Name> (xp)
-- ============================================================
function PHNPC.initSkills(zombie, outfit)
    if not zombie then return end
    local md     = zombie:getModData()
    local skills = OUTFIT_SKILLS[outfit] or OUTFIT_SKILLS["Survivor"] or {}

    -- Initialiser toutes les competences a 0
    for _, skillName in ipairs(ALL_SKILLS) do
        md["PHNPC_Skill_" .. skillName] = 0
        md["PHNPC_XP_"    .. skillName] = 0
    end

    -- Appliquer les niveaux initiaux du metier
    for skillName, level in pairs(skills) do
        local clampedLevel = math.min(math.max(level, 0), MAX_LEVEL)
        md["PHNPC_Skill_" .. skillName] = clampedLevel
        md["PHNPC_XP_"    .. skillName] = xpForLevel(clampedLevel)
    end

    PHNPC.Log.debug("Stats", string.format("%s skills initialises (outfit=%s)",
        tostring(md.PHNPC_Name or "?"), tostring(outfit)))
end

-- ============================================================
-- PHNPC.getNPCSkillLevel : lit le niveau d'une competence
-- Retourne 0 si non initialise
-- ============================================================
function PHNPC.getNPCSkillLevel(npc, skillName)
    if not npc or not skillName then return 0 end
    local md = npc:getModData()
    return md["PHNPC_Skill_" .. skillName] or 0
end

-- ============================================================
-- PHNPC.addNPCXP : ajoute de l'XP pour une competence
-- Fait monter de niveau automatiquement si seuil atteint.
-- Retourne true si montee de niveau
-- ============================================================
function PHNPC.addNPCXP(npc, skillName, xpAmount)
    if not npc or not skillName or not xpAmount then return false end
    local md       = npc:getModData()
    local xpKey    = "PHNPC_XP_"    .. skillName
    local skillKey = "PHNPC_Skill_" .. skillName

    local currentLevel = md[skillKey] or 0
    if currentLevel >= MAX_LEVEL then return false end  -- deja au max

    local currentXP = (md[xpKey] or 0) + xpAmount
    md[xpKey] = currentXP

    -- Verifier si montee de niveau
    local xpNeeded = xpForLevel(currentLevel + 1)
    if currentXP >= xpNeeded then
        md[skillKey] = currentLevel + 1
        local npcName = md.PHNPC_Name or "NPC"
        PHNPC.Log.info("Stats", string.format("%s %s niveau %d !",
            npcName, skillName, currentLevel + 1))

        -- Bark de montee de niveau (si recrute)
        if md.PHNPC_Recruited and PHNPC.sayBark then
            pcall(function() PHNPC.sayBark(npc, "levelup", 0.2, 0.9, 0.4) end)
        end
        return true
    end

    return false
end

-- ============================================================
-- PHNPC.getSkillSummary : retourne un resume des competences (debug)
-- ============================================================
function PHNPC.getSkillSummary(npc)
    if not npc then return "" end
    local md = npc:getModData()
    local parts = {}
    for _, skillName in ipairs(ALL_SKILLS) do
        local lvl = md["PHNPC_Skill_" .. skillName] or 0
        parts[#parts+1] = skillName .. ":" .. lvl
    end
    return table.concat(parts, " ")
end

-- ============================================================
-- INITIALISATION DES STATS PAR METIER
-- Applique vitesse, sante, speedMod selon le metier du NPC
-- ============================================================

function PHNPC.initStats(zombie, outfit, isFemale)
    if not zombie then return end
    local stats = PHNPC.getOutfitStats(outfit)
    local md    = zombie:getModData()

    -- Sante : stocker dans ModData (systeme PHNPC, pas le compteur PZ)
    md.PHNPC_Health    = stats.health
    md.PHNPC_MaxHealth = stats.health
    md.PHNPC_SpeedMod  = stats.speed   -- lu par enforceNPC chaque tick
    md.PHNPC_Strength  = stats.strength

    -- Vitesse de deplacement (variables AnimSet)
    -- v0.0.9f : multiplicateurs reduits (1.04 etait trop rapide)
    pcall(function()
        local walkSpeed = stats.speed * 0.85
        local runSpeed  = stats.speed * 0.60
        local limpSpeed = stats.speed * 0.65
        zombie:setVariable("WalkSpeed", walkSpeed)
        zombie:setVariable("RunSpeed",  runSpeed)
        zombie:setVariable("LimpSpeed", limpSpeed)
    end)

    -- v0.0.16 : initialiser les competences par metier
    PHNPC.initSkills(zombie, outfit)

    print(string.format("[PHNPC][STATS] %s outfit=%s HP=%d speed=%.2f skills=[%s]",
        tostring(md.PHNPC_Name or "?"), outfit, stats.health, stats.speed,
        PHNPC.getSkillSummary(zombie)))
end

-- ============================================================
-- INITIALISATION DE L'INVENTAIRE PAR METIER
-- Donne les items de depart et fixe le poids max
-- ============================================================

function PHNPC.initInventory(zombie, outfit)
    if not zombie then return end
    local stats = PHNPC.getOutfitStats(outfit)
    local md    = zombie:getModData()

    pcall(function()
        local inv = zombie:getInventory()
        if not inv then return end

        -- Poids max selon le metier
        inv:setCapacity(stats.maxWeight or 15.0)

        -- Items de depart
        -- v0.0.9f : support groupes alternatifs { {"TypeA","TypeB"}, "TypeC" }
        -- Si un groupe est une table, on essaie chaque type jusqu'au premier succes.
        for _, itemEntry in ipairs(stats.items or {}) do
            local itemList = type(itemEntry) == "table" and itemEntry or { itemEntry }
            local added = false
            for _, itemType in ipairs(itemList) do
                if not added then
                    local item = nil
                    local ok2 = pcall(function() item = inv:AddItem(itemType) end)
                    if ok2 and item then
                        added = true
                        print("[PHNPC][INV] " .. (md.PHNPC_Name or "?") .. " += " .. itemType)
                    end
                end
            end
            if not added then
                print("[PHNPC][INV] Aucun item disponible : " .. table.concat(itemList, "/"))
            end
        end

        -- v0.0.9e : Synchronisation nom NPC <-> items d'identification
        local npcName = md.PHNPC_Name or "NPC"
        local items = inv:getItems()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if item then
                local ft = ""
                pcall(function() ft = tostring(item:getFullType() or "") end)
                if ft:find("Badge") or ft:find("Officer") or ft:find("IDCard") or ft:find("Wallet") then
                    pcall(function() item:setCustomName(npcName) end)
                end
            end
        end
    end)
end

print("[PHNPC] Stats v0.0.19 loaded")
