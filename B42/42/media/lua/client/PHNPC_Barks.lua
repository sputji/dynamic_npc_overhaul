--[[
    PHNPC_Barks.lua  v1.0  (client)
    Dialogues contextuels (barks) des NPCs.

    FIX v1.0 BUG getText() TIMING :
      Dans PZ B42, les fichiers client/ sont charges AVANT que le systeme de
      traduction soit completement initialise. Si on appelle getText() au niveau
      global (au chargement du fichier), la fonction retourne la cle brute
      ("UI_PHNPC_BarkIdle4") au lieu du texte traduit.
      SOLUTION : stocker uniquement les CLES de traduction (strings statiques),
      et appeler getText() uniquement a l'utilisation (PHNPC.getRandomBark).

    Pattern : PZ getText() lazy evaluation
    Necessite : PHNPC_Core.lua (shared) charge avant ce fichier.
]]

-- ============================================================
-- CLES DE TRADUCTION PAR ETAT
-- Uniquement des cles statiques — getText() est appele plus tard
-- ============================================================
local BARK_KEYS = {
    following = {
        "UI_PHNPC_BarkFollowing1",
        "UI_PHNPC_BarkFollowing2",
        "UI_PHNPC_BarkFollowing3",
        "UI_PHNPC_BarkFollowing4",
        "UI_PHNPC_BarkFollowing5",
        "UI_PHNPC_BarkFollowing6",
        "UI_PHNPC_BarkFollowing7",
    },
    staying = {
        "UI_PHNPC_BarkStaying1",
        "UI_PHNPC_BarkStaying2",
        "UI_PHNPC_BarkStaying3",
        "UI_PHNPC_BarkStaying4",
        "UI_PHNPC_BarkStaying5",
    },
    defending = {
        "UI_PHNPC_BarkDefending1",
        "UI_PHNPC_BarkDefending2",
        "UI_PHNPC_BarkDefending3",
        "UI_PHNPC_BarkDefending4",
        "UI_PHNPC_BarkDefending5",
    },
    fleeing = {
        "UI_PHNPC_BarkFleeing1",
        "UI_PHNPC_BarkFleeing2",
        "UI_PHNPC_BarkFleeing3",
        "UI_PHNPC_BarkFleeing4",
    },
    idle = {
        "UI_PHNPC_BarkIdle1",
        "UI_PHNPC_BarkIdle2",
        "UI_PHNPC_BarkIdle3",
        "UI_PHNPC_BarkIdle4",
    },
}

-- ============================================================
-- PHNPC.getRandomBark(state) : retourne un texte traduit
-- getText() est appele ici, au moment de l'utilisation, pas au chargement
-- => plus de probleme de timing
-- ============================================================
function PHNPC.getRandomBark(state)
    local pool = BARK_KEYS[state] or BARK_KEYS["idle"]
    local key  = pool[ZombRand(#pool) + 1]
    return getText(key)
end

-- ============================================================
-- PHNPC.sayBark(npc, state, r, g, b)
-- Raccourci : le NPC dit un bark de l'etat donne avec la couleur specifiee
-- ============================================================
function PHNPC.sayBark(npc, state, r, g, b)
    local bark = PHNPC.getRandomBark(state or "idle")
    pcall(function() npc:addLineChatElement(bark, r or 0.9, g or 0.9, b or 0.2) end)
end

print("[PHNPC] Barks v1.0 loaded")
