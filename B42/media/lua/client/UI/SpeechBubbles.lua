--[[
    Project Humain : Dynamic NPC Overhaul — B42
    client/UI/SpeechBubbles.lua

    Bulles de dialogue affichées au-dessus des PNJ.
    Utilise TextDrawObject (B42) pour le rendu 3D.
    Les bulles disparaissent après DISPLAY_DURATION ticks.
]]

if not isClient() then return end

local NPC_SpeechBubbles = {
    _bubbles = {},  -- { [npcId] = { text, timer, textObj, type } }
}

local DISPLAY_DURATION = 180  -- ticks (~6 s à 30fps)
local BUBBLE_TYPES = {
    normal = { r = 1,   g = 1,   b = 1   },
    cough  = { r = 0.8, g = 0.4, b = 0.4 },
    quest  = { r = 1,   g = 0.9, b = 0.2 },
    trade  = { r = 0.4, g = 0.8, b = 1   },
}

-- ============================================================
-- Affichage d'une bulle
-- ============================================================

--- Affiche une bulle de dialogue au-dessus d'un PNJ.
-- @param npcId   string
-- @param name    string   Nom du PNJ
-- @param text    string   Texte à afficher
-- @param bubbleType  string?  "normal"|"cough"|"quest"|"trade"
function NPC_SpeechBubbles.show(npcId, name, text, bubbleType)
    if not npcId or not text then return end
    bubbleType = bubbleType or "normal"

    -- Trouver l'objet ISO correspondant
    local isoObj = nil
    local cell   = getCell and getCell()
    if cell then
        -- Recherche parmi les characters de la cellule
        local chars = cell:getCharacters and cell:getCharacters()
        if chars then
            for i = 0, chars:size() - 1 do
                local c  = chars:get(i)
                local ok, id = pcall(function()
                    return c:getModData().PHNPC_id
                end)
                if ok and id == npcId then
                    isoObj = c
                    break
                end
            end
        end
    end

    -- Créer ou mettre à jour la bulle
    local colors = BUBBLE_TYPES[bubbleType] or BUBBLE_TYPES.normal
    local textObj = TextDrawObject.new()
    textObj:setAllowAnyImage(true)
    textObj:setDefaultFont(UIFont.Small)
    textObj:setDefaultColors(
        math.floor(colors.r * 255),
        math.floor(colors.g * 255),
        math.floor(colors.b * 255)
    )
    textObj:ReadString(name .. ": " .. text)

    NPC_SpeechBubbles._bubbles[npcId] = {
        text    = text,
        timer   = DISPLAY_DURATION,
        textObj = textObj,
        isoObj  = isoObj,
        type    = bubbleType,
    }
end

-- ============================================================
-- Rendu (OnRenderTick B42)
-- ============================================================

local function onRenderTick()
    local toRemove = {}

    for npcId, bubble in pairs(NPC_SpeechBubbles._bubbles) do
        bubble.timer = bubble.timer - 1
        if bubble.timer <= 0 then
            toRemove[#toRemove + 1] = npcId
        else
            local iso = bubble.isoObj
            if iso then
                local ok, _ = pcall(function()
                    local tx = iso:getX()
                    local ty = iso:getY()
                    local tz = iso:getZ()
                    bubble.textObj:renderText(tx, ty, tz + 1.2)
                end)
                if not ok then
                    toRemove[#toRemove + 1] = npcId
                end
            end
        end
    end

    for _, id in ipairs(toRemove) do
        NPC_SpeechBubbles._bubbles[id] = nil
    end
end

Events.OnRenderTick.Add(onRenderTick)

PHNPC.registerModule("NPC_SpeechBubbles", NPC_SpeechBubbles)
return NPC_SpeechBubbles
