-- Solver: "is this game still winnable?"
--
-- Depth-first search over the real position, using the real hidden cards (perfect information).
-- Because the deck can be recycled without limit, every card in the stock/waste can be reached
-- sooner or later, so the deck is treated as a plain set of playable cards.
--
-- It runs as a coroutine in small time slices so the screen stays responsive.
-- step() returns nil while still working, then "win", "lose" or "unknown" (gave up: too big a search).

local Solver = {}
Solver.__index = Solver

local SUIT_INDEX = { hearts = 1, diamonds = 2, clubs = 3, spades = 4 }
Solver.maxNodes = 1500000
Solver.skipFoundationBack = false   -- (tests only) leave out foundation -> tableau moves

local function suitOf(id) return math.floor((id - 1) / 13) + 1 end
local function rankOf(id) return (id - 1) % 13 + 1 end
local function isRed(id) return suitOf(id) <= 2 end

function Solver.new(solitaire)
    local self = setmetatable({}, Solver)
    self.nodes = 0
    self.result = nil
    self.path = nil

    -- Snapshot of the position
    local cols, down = {}, {}
    for c = 1, 7 do
        local pile = solitaire.tableau[c]
        local ids, d = {}, 0
        for i, card in ipairs(pile) do
            ids[i] = (SUIT_INDEX[card.suit] - 1) * 13 + card.rank
            if not card.faceUp then d = i end   -- face-down cards are always at the bottom
        end
        cols[c], down[c] = ids, d
    end
    local fnd = { 0, 0, 0, 0 }
    for f = 1, 4 do
        for _, card in ipairs(solitaire.foundations[f]) do
            local si = SUIT_INDEX[card.suit]
            if card.rank > fnd[si] then fnd[si] = card.rank end
        end
    end
    local talon = {}
    for _, card in ipairs(solitaire.stock) do talon[#talon + 1] = (SUIT_INDEX[card.suit] - 1) * 13 + card.rank end
    for _, card in ipairs(solitaire.waste) do talon[#talon + 1] = (SUIT_INDEX[card.suit] - 1) * 13 + card.rank end

    self.cols, self.down, self.fnd, self.talon = cols, down, fnd, talon
    self.co = coroutine.create(function() return self:run() end)
    return self
end

-- ---------------------------------------------------------------- move application

-- remove top card of column c, flipping the new top if it was face down. returns card, flipped
local function popCol(self, c)
    local col = self.cols[c]
    local card = table.remove(col)
    local flipped = false
    if #col > 0 and self.down[c] == #col then
        self.down[c] = self.down[c] - 1
        flipped = true
    end
    return card, flipped
end

-- move types: 1 tab->found, 2 talon->found, 3 tab->tab, 4 talon->tab, 5 found->tab
local function apply(self, m)
    local t = m[1]
    if t == 1 then
        local card, flipped = popCol(self, m[2])
        self.fnd[suitOf(card)] = self.fnd[suitOf(card)] + 1
        m.flipped = flipped
    elseif t == 2 then
        local card = table.remove(self.talon, m[2])
        self.fnd[suitOf(card)] = self.fnd[suitOf(card)] + 1
        m.card = card
    elseif t == 3 then
        local src, dst = self.cols[m[2]], self.cols[m[4]]
        local from = m[3]
        local n = #src - from + 1
        for i = from, #src do dst[#dst + 1] = src[i] end
        for i = #src, from, -1 do src[i] = nil end
        m.flipped = false
        if #src > 0 and self.down[m[2]] == #src then
            self.down[m[2]] = self.down[m[2]] - 1
            m.flipped = true
        end
        m.n = n
    elseif t == 4 then
        local card = table.remove(self.talon, m[2])
        local dst = self.cols[m[3]]
        dst[#dst + 1] = card
        m.card = card
    elseif t == 5 then
        local s = m[2]
        local card = (s - 1) * 13 + self.fnd[s]
        self.fnd[s] = self.fnd[s] - 1
        local dst = self.cols[m[3]]
        dst[#dst + 1] = card
        m.card = card
    end
end

local function undo(self, m)
    local t = m[1]
    if t == 1 then
        local c = m[2]
        if m.flipped then self.down[c] = self.down[c] + 1 end
        -- the card we removed: its suit foundation top is the card
        -- find the suit whose foundation top card was it: stored on the move
        local card = m.card
        self.fnd[suitOf(card)] = self.fnd[suitOf(card)] - 1
        local col = self.cols[c]
        col[#col + 1] = card
    elseif t == 2 then
        self.fnd[suitOf(m.card)] = self.fnd[suitOf(m.card)] - 1
        table.insert(self.talon, m[2], m.card)
    elseif t == 3 then
        local src, dst = self.cols[m[2]], self.cols[m[4]]
        if m.flipped then self.down[m[2]] = self.down[m[2]] + 1 end
        local base = #dst - m.n
        for i = 1, m.n do
            src[#src + 1] = dst[base + i]
        end
        for i = #dst, base + 1, -1 do dst[i] = nil end
    elseif t == 4 then
        local dst = self.cols[m[3]]
        dst[#dst] = nil
        table.insert(self.talon, m[2], m.card)
    elseif t == 5 then
        local dst = self.cols[m[3]]
        dst[#dst] = nil
        self.fnd[m[2]] = self.fnd[m[2]] + 1
    end
end

-- type 1 needs to remember which card it moved (top of column) - record before applying
local function applyMove(self, m)
    if m[1] == 1 then
        local col = self.cols[m[2]]
        m.card = col[#col]
    end
    apply(self, m)
end

-- ---------------------------------------------------------------- state key

-- 51-bit polynomial hash of a card sequence (two moduli, all arithmetic stays exact in a double)
local P1, P2 = 2147483647, 2147483629
local M51 = 2251799813685248      -- 2^51
local function seqHash(seed, arr)
    local h1, h2 = seed % P1, (seed * 7 + 3) % P2
    for i = 1, #arr do
        local v = arr[i] + 1
        h1 = (h1 * 131 + v) % P1
        h2 = (h2 * 137 + v) % P2
    end
    return (h1 * 1048576 + (h2 % 1048576)) % M51
end

local function stateKey(self)
    -- columns are interchangeable, so add their hashes (order-independent)
    local sum = 0
    for c = 1, 7 do
        sum = (sum + seqHash(self.down[c] + 11, self.cols[c])) % M51
    end
    local th = seqHash(1000003, self.talon)
    local fh = seqHash(7777777, self.fnd)
    return (sum + th + fh) % M51
end

-- ---------------------------------------------------------------- move generation

local function canGoToTableau(self, card, c)
    local col = self.cols[c]
    if #col == 0 then return rankOf(card) == 13 end
    local top = col[#col]
    if self.down[c] == #col then return false end
    return isRed(top) ~= isRed(card) and rankOf(card) == rankOf(top) - 1
end

local function genMoves(self)
    local moves = {}
    local fnd = self.fnd

    -- is a King available to fill an empty column?
    local kingAvailable = false
    for _, card in ipairs(self.talon) do
        if rankOf(card) == 13 then kingAvailable = true break end
    end
    if not kingAvailable then
        for c = 1, 7 do
            local d = self.down[c]
            if d > 0 and rankOf(self.cols[c][d + 1]) == 13 then kingAvailable = true break end
        end
    end

    -- foundation moves from the tableau
    for c = 1, 7 do
        local col = self.cols[c]
        local card = col[#col]
        if card and self.down[c] < #col and rankOf(card) == fnd[suitOf(card)] + 1 then
            moves[#moves + 1] = { 1, c }
        end
    end
    -- foundation moves from the talon
    for k, card in ipairs(self.talon) do
        if rankOf(card) == fnd[suitOf(card)] + 1 then
            moves[#moves + 1] = { 2, k }
        end
    end

    -- tableau -> tableau (revealing moves first)
    local firstEmpty = nil
    for c = 1, 7 do if #self.cols[c] == 0 then firstEmpty = c break end end
    local later = {}
    for c = 1, 7 do
        local col = self.cols[c]
        for i = self.down[c] + 1, #col do
            local card = col[i]
            for t = 1, 7 do
                if t ~= c and canGoToTableau(self, card, t) then
                    local target = self.cols[t]
                    local skip = false
                    if #target == 0 then
                        -- only the first empty column (all empties are equivalent), and never move a King
                        -- that already sits at the bottom of its column
                        if t ~= firstEmpty or i == 1 then skip = true end
                    elseif i == 1 and not kingAvailable then
                        -- emptying a column is pointless when no King can ever use it
                        skip = true
                    end
                    if not skip then
                        local m = { 3, c, i, t }
                        if i == self.down[c] + 1 and self.down[c] > 0 then
                            moves[#moves + 1] = m      -- reveals a card
                        else
                            later[#later + 1] = m
                        end
                    end
                end
            end
        end
    end

    -- columns with the most hidden cards first: uncovering them matters most
    table.sort(moves, function(a, b)
        local ka = (a[1] == 3) and self.down[a[2]] or 99
        local kb = (b[1] == 3) and self.down[b[2]] or 99
        if a[1] ~= 3 and b[1] ~= 3 then return false end
        return ka > kb
    end)

    -- talon -> tableau
    for k, card in ipairs(self.talon) do
        for t = 1, 7 do
            if canGoToTableau(self, card, t) then
                if #self.cols[t] > 0 or t == firstEmpty then
                    moves[#moves + 1] = { 4, k, t }
                end
            end
        end
    end

    for _, m in ipairs(later) do moves[#moves + 1] = m end

    -- foundation -> tableau (rarely needed, tried last)
    for s = 1, 4 do
        if fnd[s] > 0 and not Solver.skipFoundationBack then
            local card = (s - 1) * 13 + fnd[s]
            for t = 1, 7 do
                if canGoToTableau(self, card, t) and (#self.cols[t] > 0 or t == firstEmpty) then
                    moves[#moves + 1] = { 5, s, t }
                end
            end
        end
    end
    return moves
end

-- a card that can never be needed as a tableau parent any more
local function isSafe(self, card)
    local r = rankOf(card)
    if r == 1 then return true end
    local s = suitOf(card)
    local opp1, opp2
    if s <= 2 then opp1, opp2 = 3, 4 else opp1, opp2 = 1, 2 end
    return self.fnd[opp1] >= r - 1 and self.fnd[opp2] >= r - 1
end

-- ---------------------------------------------------------------- search

function Solver:won()
    local f = self.fnd
    return f[1] == 13 and f[2] == 13 and f[3] == 13 and f[4] == 13
end

function Solver:search(visited, path)
    self.nodes = self.nodes + 1
    if self.nodes % 200 == 0 then
        if self.nodes > (self.maxNodes or Solver.maxNodes) then error("budget") end
        coroutine.yield()
    end

    -- play every "safe" foundation move straight away (never hurts)
    local auto = {}
    local progress = true
    while progress do
        progress = false
        for c = 1, 7 do
            local col = self.cols[c]
            local card = col[#col]
            if card and self.down[c] < #col and rankOf(card) == self.fnd[suitOf(card)] + 1 and isSafe(self, card) then
                local m = { 1, c }
                applyMove(self, m)
                auto[#auto + 1] = m
                path[#path + 1] = m
                progress = true
            end
        end
        for k = #self.talon, 1, -1 do
            local card = self.talon[k]
            if card and rankOf(card) == self.fnd[suitOf(card)] + 1 and isSafe(self, card) then
                local m = { 2, k }
                applyMove(self, m)
                auto[#auto + 1] = m
                path[#path + 1] = m
                progress = true
            end
        end
    end

    local function backout()
        for i = #auto, 1, -1 do
            undo(self, auto[i])
            path[#path] = nil
        end
    end

    if self:won() then return true end

    local key = stateKey(self)
    if visited[key] then backout() return false end
    visited[key] = true

    local moves = genMoves(self)
    for _, m in ipairs(moves) do
        applyMove(self, m)
        path[#path + 1] = m
        if self:search(visited, path) then return true end
        path[#path] = nil
        undo(self, m)
    end

    backout()
    return false
end

function Solver:run()
    local visited = {}
    local path = {}
    local ok, res = pcall(function() return self:search(visited, path) end)
    if not ok then
        if tostring(res):find("budget") then return "unknown" end
        error(res)
    end
    if res then
        self.path = path
        return "win"
    end
    return "lose"
end

-- Work for up to `seconds`; returns nil while unfinished, else "win" / "lose" / "unknown"
local MAX_SECONDS = 15

function Solver:step(seconds)
    if self.result then return self.result end
    self.cpu = self.cpu or 0
    if self.cpu > (self.maxSeconds or MAX_SECONDS) then self.result = "unknown" return "unknown" end
    local t0 = os.clock()
    while os.clock() - t0 < seconds do
        local ok, res = coroutine.resume(self.co)
        if not ok then
            self.result = "unknown"
            print("Solver error: " .. tostring(res))
            return self.result
        end
        if coroutine.status(self.co) == "dead" then
            self.result = res
            return res
        end
    end
    self.cpu = self.cpu + (os.clock() - t0)
    return nil
end

return Solver
