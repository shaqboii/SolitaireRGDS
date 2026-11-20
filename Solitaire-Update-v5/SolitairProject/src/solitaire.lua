local Solitaire = {}
Solitaire.__index = Solitaire

Solitaire.SUITS = {"hearts", "diamonds", "clubs", "spades"}
Solitaire.COLORS = {
    hearts = "red",
    diamonds = "red",
    clubs = "black",
    spades = "black"
}
Solitaire.RANK_NAMES = {
    [1] = "A", [2] = "2", [3] = "3", [4] = "4", [5] = "5",
    [6] = "6", [7] = "7", [8] = "8", [9] = "9", [10] = "10",
    [11] = "J", [12] = "Q", [13] = "K"
}

function Solitaire.new()
    local self = setmetatable({}, Solitaire)
    self:init()
    return self
end

function Solitaire:init()
    self.stock = {}
    self.waste = {}
    self.foundations = {{}, {}, {}, {}} -- 1: Hearts, 2: Diamonds, 3: Clubs, 4: Spades
    self.tableau = {{}, {}, {}, {}, {}, {}, {}} -- 7 columns
    self.score = 0
    self.moves = 0
    self.time = 0
    self.isWon = false
    self.undoStack = {}
    self.undoCount = 0
    self.dealSerial = 0   -- increases on every new deal (the renderer uses it to play the deal animation)
    self.paused = false   -- true while the menu is open / cards are being dealt: the clock stops
    self.winClock = 0
    self.selection = nil -- { source = "waste"|"tableau"|"foundation", col = index, cardIndex = index, cards = {...} }
    self:deal()
end

-- Deep copy of game state for unlimited undo
function Solitaire:saveState()
    self.version = (self.version or 0) + 1
    local function copyCard(c)
        if not c then return nil end
        return {
            suit = c.suit,
            rank = c.rank,
            color = c.color,
            faceUp = c.faceUp,
            id = c.id
        }
    end

    local function copyPile(pile)
        local cp = {}
        for i, card in ipairs(pile) do
            cp[i] = copyCard(card)
        end
        return cp
    end

    local snapshot = {
        stock = copyPile(self.stock),
        waste = copyPile(self.waste),
        foundations = {
            copyPile(self.foundations[1]),
            copyPile(self.foundations[2]),
            copyPile(self.foundations[3]),
            copyPile(self.foundations[4])
        },
        tableau = {
            copyPile(self.tableau[1]),
            copyPile(self.tableau[2]),
            copyPile(self.tableau[3]),
            copyPile(self.tableau[4]),
            copyPile(self.tableau[5]),
            copyPile(self.tableau[6]),
            copyPile(self.tableau[7])
        },
        score = self.score,
        moves = self.moves,
        isWon = self.isWon
    }

    table.insert(self.undoStack, snapshot)
end

function Solitaire:undo()
    if self.isWon then return false end
    if #self.undoStack == 0 then return false end
    local prev = table.remove(self.undoStack)
    self.version = (self.version or 0) + 1

    self.stock = prev.stock
    self.waste = prev.waste
    self.foundations = prev.foundations
    self.tableau = prev.tableau
    self.score = prev.score
    self.moves = prev.moves
    self.isWon = prev.isWon
    self.selection = nil
    self.undoCount = self.undoCount + 1
    return true
end

-- order (optional): list of {suit=, rank=} to reuse an earlier shuffle ("restart this deal")
function Solitaire:deal(order)
    self.stock = {}
    self.waste = {}
    self.foundations = {{}, {}, {}, {}}
    self.tableau = {{}, {}, {}, {}, {}, {}, {}}
    self.score = 0
    self.moves = 0
    self.time = 0
    self.isWon = false
    self.undoStack = {}
    self.undoCount = 0
    self.selection = nil
    self.winClock = 0
    self.finishing = false
    self.dealSerial = (self.dealSerial or 0) + 1
    self.version = (self.version or 0) + 1

    -- Create 52 card deck
    local deck = {}
    local idCounter = 1
    for _, suit in ipairs(Solitaire.SUITS) do
        for rank = 1, 13 do
            table.insert(deck, {
                id = idCounter,
                suit = suit,
                rank = rank,
                color = Solitaire.COLORS[suit],
                faceUp = false
            })
            idCounter = idCounter + 1
        end
    end

    if order then
        -- Rebuild the deck in the remembered order
        local byKey = {}
        for _, c in ipairs(deck) do byKey[c.suit .. c.rank] = c end
        deck = {}
        for _, o in ipairs(order) do table.insert(deck, byKey[o.suit .. o.rank]) end
    else
        -- Fisher-Yates shuffle with love.math.random
        for i = #deck, 2, -1 do
            local j = love.math.random(i)
            deck[i], deck[j] = deck[j], deck[i]
        end
    end

    self.dealOrder = {}
    for i, c in ipairs(deck) do self.dealOrder[i] = { suit = c.suit, rank = c.rank } end

    -- Deal to 7 tableau columns
    for col = 1, 7 do
        for row = 1, col do
            local card = table.remove(deck)
            if row == col then
                card.faceUp = true
            else
                card.faceUp = false
            end
            table.insert(self.tableau[col], card)
        end
    end

    -- Remaining cards go to stock (face down)
    while #deck > 0 do
        local card = table.remove(deck)
        card.faceUp = false
        table.insert(self.stock, card)
    end
end

-- Draw 1 card from Stock to Waste (Y Button or clicking stock)
function Solitaire:drawOne()
    if #self.stock > 0 then
        self:saveState()
        local card = table.remove(self.stock)
        card.faceUp = true
        table.insert(self.waste, card)
        self.moves = self.moves + 1
        self.selection = nil
        return true
    elseif #self.waste > 0 then
        -- Recycle waste into stock (Klondike rule: cards turn facedown)
        self:saveState()
        while #self.waste > 0 do
            local card = table.remove(self.waste)
            card.faceUp = false
            table.insert(self.stock, card)
        end
        self.moves = self.moves + 1
        self.selection = nil
        return true
    end
    return false
end

-- Check if a card can be placed on a foundation pile
function Solitaire:canMoveToFoundation(card, fIndex)
    if not card or not card.faceUp then return false end
    local pile = self.foundations[fIndex]

    if #pile == 0 then
        -- Only Ace (rank 1) can start an empty foundation
        return card.rank == 1
    else
        local top = pile[#pile]
        return card.suit == top.suit and card.rank == top.rank + 1
    end
end

-- Which foundation slot would take this card? (nil if none)
-- Aces prefer the slot whose suit symbol matches (hearts, diamonds, clubs, spades), else the first empty slot.
function Solitaire:foundationFor(card)
    if not card or not card.faceUp then return nil end
    for f = 1, 4 do
        local pile = self.foundations[f]
        if #pile > 0 and pile[1].suit == card.suit then
            if self:canMoveToFoundation(card, f) then return f end
            return nil
        end
    end
    if card.rank == 1 then
        for f = 1, 4 do
            if Solitaire.SUITS[f] == card.suit and #self.foundations[f] == 0 then return f end
        end
        for f = 1, 4 do
            if #self.foundations[f] == 0 then return f end
        end
    end
    return nil
end

-- Check if a card can be placed on a tableau column
function Solitaire:canMoveToTableau(card, colIndex)
    if not card or not card.faceUp then return false end
    local col = self.tableau[colIndex]

    if #col == 0 then
        -- Only King (rank 13) can be placed in an empty tableau column
        return card.rank == 13
    else
        local top = col[#col]
        if not top.faceUp then return false end
        return card.color ~= top.color and card.rank == top.rank - 1
    end
end

-- Reveal top face-down cards in tableau columns and update score
function Solitaire:checkReveals()
    local revealed = false
    for col = 1, 7 do
        local pile = self.tableau[col]
        if #pile > 0 and not pile[#pile].faceUp then
            pile[#pile].faceUp = true
            self.score = self.score + 5
            revealed = true
        end
    end
    return revealed
end

-- Move card(s) to foundation
function Solitaire:moveToFoundation(sourceType, sourceCol, fIndex)
    local card = nil
    if sourceType == "waste" then
        if #self.waste == 0 then return false end
        card = self.waste[#self.waste]
        if self:canMoveToFoundation(card, fIndex) then
            self:saveState()
            table.remove(self.waste)
            table.insert(self.foundations[fIndex], card)
            self.score = self.score + 10
            self.moves = self.moves + 1
            self.selection = nil
            self:checkReveals()
            self:checkWin()
            return true
        end
    elseif sourceType == "tableau" then
        local col = self.tableau[sourceCol]
        if #col == 0 then return false end
        card = col[#col]
        if self:canMoveToFoundation(card, fIndex) then
            self:saveState()
            table.remove(col)
            table.insert(self.foundations[fIndex], card)
            self.score = self.score + 10
            self.moves = self.moves + 1
            self.selection = nil
            self:checkReveals()
            self:checkWin()
            return true
        end
    end
    return false
end

-- Move card(s) to tableau column
function Solitaire:moveToTableau(sourceType, sourceCol, sourceIndex, targetCol)
    if sourceType == "waste" then
        if #self.waste == 0 then return false end
        local card = self.waste[#self.waste]
        if self:canMoveToTableau(card, targetCol) then
            self:saveState()
            table.remove(self.waste)
            table.insert(self.tableau[targetCol], card)
            self.score = self.score + 5
            self.moves = self.moves + 1
            self.selection = nil
            self:checkReveals()
            return true
        end
    elseif sourceType == "foundation" then
        local fPile = self.foundations[sourceCol]
        if #fPile == 0 then return false end
        local card = fPile[#fPile]
        if self:canMoveToTableau(card, targetCol) then
            self:saveState()
            table.remove(fPile)
            table.insert(self.tableau[targetCol], card)
            self.score = math.max(0, self.score - 15)
            self.moves = self.moves + 1
            self.selection = nil
            self:checkReveals()
            return true
        end
    elseif sourceType == "tableau" then
        if sourceCol == targetCol then return false end
        local sCol = self.tableau[sourceCol]
        if sourceIndex < 1 or sourceIndex > #sCol then return false end
        local movingCard = sCol[sourceIndex]
        if not movingCard.faceUp then return false end

        if self:canMoveToTableau(movingCard, targetCol) then
            self:saveState()
            local movingCards = {}
            for i = sourceIndex, #sCol do
                table.insert(movingCards, sCol[i])
            end
            for i = #sCol, sourceIndex, -1 do
                table.remove(sCol, i)
            end
            for _, c in ipairs(movingCards) do
                table.insert(self.tableau[targetCol], c)
            end
            self.moves = self.moves + 1
            self.selection = nil
            self:checkReveals()
            return true
        end
    end
    return false
end

-- Auto-place card (Held L/R + A or double-tap)
function Solitaire:autoPlace(sourceType, colIndex, cardIndex)
    local card = nil
    if sourceType == "waste" then
        if #self.waste > 0 then card = self.waste[#self.waste] end
    elseif sourceType == "tableau" then
        local col = self.tableau[colIndex]
        if col and #col > 0 and cardIndex == #col then
            card = col[#col]
        end
    end

    if not card or not card.faceUp then return false end

    -- First try placing into foundations (Aces to Kings)
    local fSlot = self:foundationFor(card)
    if fSlot then
        return self:moveToFoundation(sourceType, colIndex, fSlot)
    end

    -- Next try placing onto another tableau column
    if sourceType == "waste" then
        for t = 1, 7 do
            if self:canMoveToTableau(card, t) then
                return self:moveToTableau("waste", nil, nil, t)
            end
        end
    end

    return false
end

function Solitaire:checkWin()
    local totalFoundations = 0
    for f = 1, 4 do
        totalFoundations = totalFoundations + #self.foundations[f]
    end
    if totalFoundations == 52 then
        self.isWon = true
        return true
    end
    return false
end

-- Replay the same shuffle from the start
function Solitaire:restart()
    self:deal(self.dealOrder)
end

-- ---------------------------------------------------------------------------
-- FINISH: when every tableau card is face up, the game is won as soon as the cards
-- are sorted onto the foundations. Deck cards can always be reached (the deck can be
-- recycled without limit), so they count as available.
-- ---------------------------------------------------------------------------

local function foundationHave(self)
    local have = { hearts = 0, diamonds = 0, clubs = 0, spades = 0 }
    for f = 1, 4 do
        local pile = self.foundations[f]
        if #pile > 0 then have[pile[1].suit] = #pile end
    end
    return have
end

-- Would sorting alone finish the game from here?
function Solitaire:computeFinishable()
    local where, topIdx = {}, {}
    for col = 1, 7 do
        local pile = self.tableau[col]
        for i, card in ipairs(pile) do
            if not card.faceUp then return false end
            where[card.suit .. card.rank] = { col, i }
        end
        topIdx[col] = #pile
    end
    local free = {}
    for _, c in ipairs(self.stock) do free[c.suit .. c.rank] = true end
    for _, c in ipairs(self.waste) do free[c.suit .. c.rank] = true end

    local have = foundationHave(self)
    local progress = true
    while progress do
        progress = false
        for _, suit in ipairs(Solitaire.SUITS) do
            local r = have[suit] + 1
            if r <= 13 then
                local key = suit .. r
                local w = where[key]
                if free[key] then
                    free[key] = nil
                    have[suit] = r
                    progress = true
                elseif w and topIdx[w[1]] == w[2] then
                    topIdx[w[1]] = w[2] - 1
                    have[suit] = r
                    progress = true
                end
            end
        end
    end
    return have.hearts + have.diamonds + have.clubs + have.spades == 52
end

function Solitaire:isFinishable()
    if self.isWon then return false end
    if self._finVer ~= self.version then
        self._finVer = self.version
        self._finVal = self:computeFinishable()
    end
    return self._finVal
end

-- Move the lowest-ranked card that can go up to its foundation. Returns true if a card moved.
function Solitaire:finishStep()
    local have = foundationHave(self)
    local best = nil
    for si, suit in ipairs(Solitaire.SUITS) do
        local r = have[suit] + 1
        if r <= 13 then
            local found = nil
            for col = 1, 7 do
                local pile = self.tableau[col]
                local c = pile[#pile]
                if c and c.suit == suit and c.rank == r then found = { kind = "tableau", col = col } end
            end
            if not found then
                for i, c in ipairs(self.waste) do
                    if c.suit == suit and c.rank == r then found = { kind = "waste", index = i } end
                end
            end
            if not found then
                for i, c in ipairs(self.stock) do
                    if c.suit == suit and c.rank == r then found = { kind = "stock", index = i } end
                end
            end
            if found and (not best or r < best.rank) then
                best = found
                best.rank = r
            end
        end
    end
    if not best then return false end

    local card
    if best.kind == "tableau" then
        local pile = self.tableau[best.col]
        card = table.remove(pile)
    elseif best.kind == "waste" then
        card = table.remove(self.waste, best.index)
    else
        card = table.remove(self.stock, best.index)
    end
    card.faceUp = true
    local f = self:foundationFor(card)
    if not f then
        -- cannot happen for a legal position; put the card back rather than lose it
        if best.kind == "tableau" then table.insert(self.tableau[best.col], card) end
        return false
    end
    table.insert(self.foundations[f], card)
    self.score = self.score + 10
    self.moves = self.moves + 1
    self.selection = nil
    self.version = (self.version or 0) + 1
    self:checkWin()
    return true
end

function Solitaire:update(dt)
    if self.isWon then
        self.winClock = self.winClock + dt
    elseif not self.paused and not self.finishing then
        self.time = self.time + dt
    end
end

return Solitaire

