-- Hint: suggests one useful move, or tells us nothing useful is left (returns nil).
--
-- Priority:
--   1. a card that can go to a foundation
--   2. a move that turns over a face-down card
--   3. the top waste card onto the tableau
--   4. other useful tableau moves (frees a column for a King, or uncovers a foundation card)
--   5. "draw from the deck" if some card in the deck could be played
-- Moves that would only shuffle cards around without progress are not suggested.

local Hint = {}

local RANK_NAME = { [1] = "Ace", [11] = "Jack", [12] = "Queen", [13] = "King" }
local function rankName(r) return RANK_NAME[r] or tostring(r) end
local function cardName(c) return rankName(c.rank) .. " of " .. c.suit end

local function firstFaceUp(pile)
    for i, c in ipairs(pile) do
        if c.faceUp then return i end
    end
    return nil
end

-- Same checks as Solitaire:canMoveTo*, but ignoring faceUp (for cards still in the deck)
local function deckCardPlayable(s, card)
    for f = 1, 4 do
        local pile = s.foundations[f]
        if #pile == 0 then
            if card.rank == 1 then return true end
        else
            local top = pile[#pile]
            if top.suit == card.suit and card.rank == top.rank + 1 then return true end
        end
    end
    for col = 1, 7 do
        local pile = s.tableau[col]
        if #pile == 0 then
            if card.rank == 13 then return true end
        else
            local top = pile[#pile]
            if top.faceUp and top.color ~= card.color and card.rank == top.rank - 1 then return true end
        end
    end
    return false
end

local function tableauDest(s, col, card)
    local pile = s.tableau[col]
    if #pile == 0 then
        return { zone = "tableau", col = col, empty = true }
    end
    return { zone = "tableau", col = col }
end

function Hint.find(s)
    -- 1. Foundation moves
    if #s.waste > 0 then
        local c = s.waste[#s.waste]
        local f = s:foundationFor(c)
        if f then
            return { kind = "move", source = { zone = "waste" }, dest = { zone = "foundation", col = f },
                     text = "Move the " .. cardName(c) .. " up to a foundation" }
        end
    end
    for col = 1, 7 do
        local pile = s.tableau[col]
        local c = pile[#pile]
        if c and c.faceUp then
            local f = s:foundationFor(c)
            if f then
                return { kind = "move", source = { zone = "tableau", col = col, index = #pile },
                         dest = { zone = "foundation", col = f },
                         text = "Move the " .. cardName(c) .. " up to a foundation" }
            end
        end
    end

    -- 2. Moves that turn over a face-down card (move the whole face-up run)
    for col = 1, 7 do
        local pile = s.tableau[col]
        local fu = firstFaceUp(pile)
        if fu and fu > 1 then
            local card = pile[fu]
            for t = 1, 7 do
                if t ~= col and s:canMoveToTableau(card, t) then
                    return { kind = "move", source = { zone = "tableau", col = col, index = fu },
                             dest = tableauDest(s, t, card),
                             text = "Move the " .. cardName(card) .. " to turn over a hidden card" }
                end
            end
        end
    end

    -- 3. Waste card onto the tableau
    if #s.waste > 0 then
        local c = s.waste[#s.waste]
        for t = 1, 7 do
            if s:canMoveToTableau(c, t) then
                return { kind = "move", source = { zone = "waste" }, dest = tableauDest(s, t, c),
                         text = "Play the " .. cardName(c) .. " from the waste pile" }
            end
        end
    end

    -- Is a King available to fill an empty column?
    local kingAvailable = false
    for _, c in ipairs(s.waste) do if c.rank == 13 then kingAvailable = true end end
    for _, c in ipairs(s.stock) do if c.rank == 13 then kingAvailable = true end end
    for col = 1, 7 do
        local pile = s.tableau[col]
        local fu = firstFaceUp(pile)
        if fu then
            for i = fu, #pile do
                if pile[i].rank == 13 and i > 1 then kingAvailable = true end
            end
        end
    end

    -- 4. Other useful tableau moves
    for col = 1, 7 do
        local pile = s.tableau[col]
        local fu = firstFaceUp(pile)
        if fu then
            -- 4a. Move a whole column onto another card to open an empty column (only if a King can use it)
            if fu == 1 and kingAvailable then
                local card = pile[1]
                for t = 1, 7 do
                    if t ~= col and #s.tableau[t] > 0 and s:canMoveToTableau(card, t) then
                        return { kind = "move", source = { zone = "tableau", col = col, index = 1 },
                                 dest = tableauDest(s, t, card),
                                 text = "Move the " .. cardName(card) .. " stack to empty a column" }
                    end
                end
            end
            -- 4b. Move part of a run so the card underneath can go to a foundation
            for i = math.max(fu + 1, 2), #pile do
                local exposed = pile[i - 1]
                if exposed.faceUp and s:foundationFor(exposed) then
                    local card = pile[i]
                    for t = 1, 7 do
                        if t ~= col and s:canMoveToTableau(card, t) then
                            return { kind = "move", source = { zone = "tableau", col = col, index = i },
                                     dest = tableauDest(s, t, card),
                                     text = "Move the " .. cardName(card) .. " to free the " .. cardName(exposed) }
                        end
                    end
                end
            end
        end
    end

    -- 5. Something in the deck could be played: suggest drawing
    if #s.stock > 0 or #s.waste > 0 then
        local playable = false
        for _, c in ipairs(s.stock) do
            if deckCardPlayable(s, c) then playable = true break end
        end
        if not playable then
            -- waste cards other than the top one come around again after a recycle
            for i = 1, #s.waste - 1 do
                if deckCardPlayable(s, s.waste[i]) then playable = true break end
            end
        end
        if playable then
            return { kind = "draw", source = { zone = "stock" }, text = "Draw from the deck" }
        end
    end

    return nil
end

return Hint
