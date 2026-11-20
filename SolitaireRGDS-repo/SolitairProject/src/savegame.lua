-- Savegame: remembers a game in progress so it can be resumed later (Title screen > Continue).
-- Saved as a small text file (savegame.txt) next to the other settings files.

local Store = require("src.store")
local Solitaire = require("src.solitaire")

local Savegame = {}

local FILE = "savegame.txt"
local VERSION = 1

local SUIT_CODE = { hearts = "h", diamonds = "d", clubs = "c", spades = "s" }
local CODE_SUIT = { h = "hearts", d = "diamonds", c = "clubs", s = "spades" }

local function packPile(pile)
    local out = {}
    for i, c in ipairs(pile) do
        out[i] = SUIT_CODE[c.suit] .. c.rank .. (c.faceUp and "u" or "d")
    end
    return table.concat(out, ",")
end

local function unpackPile(text, ids)
    local pile = {}
    for tok in (text or ""):gmatch("[^,]+") do
        local code, rank, face = tok:match("^(%a)(%d+)(%a)$")
        local suit = CODE_SUIT[code or ""]
        rank = tonumber(rank)
        if not suit or not rank or rank < 1 or rank > 13 then return nil end
        local key = suit .. rank
        if ids[key] then return nil end          -- duplicate card = corrupt file
        local id = (rank + 13 * (({ hearts = 0, diamonds = 1, clubs = 2, spades = 3 })[suit]))
        ids[key] = true
        pile[#pile + 1] = { id = id, suit = suit, rank = rank, color = Solitaire.COLORS[suit], faceUp = (face == "u") }
    end
    return pile
end

local function parse()
    local content = Store.read(FILE)
    if not content then return nil end
    local t = {}
    for line in content:gmatch("[^\r\n]+") do
        local k, v = line:match("^([%w_]+)=(.*)$")
        if k then t[k] = v end
    end
    if tonumber(t.version) ~= VERSION then return nil end
    return t
end

-- Returns { time=, moves=, score= } of the saved game, or nil if there isn't a valid one
function Savegame.summary()
    local t = parse()
    if not t then return nil end
    local time, moves, score = tonumber(t.time), tonumber(t.moves), tonumber(t.score)
    if not (time and moves and score) then return nil end
    return { time = time, moves = moves, score = score }
end

function Savegame.exists()
    return Savegame.summary() ~= nil
end

function Savegame.save(s)
    local lines = {
        "version=" .. VERSION,
        "time=" .. string.format("%.2f", s.time),
        "moves=" .. s.moves,
        "score=" .. s.score,
        "stock=" .. packPile(s.stock),
        "waste=" .. packPile(s.waste),
    }
    for i = 1, 4 do lines[#lines + 1] = "f" .. i .. "=" .. packPile(s.foundations[i]) end
    for i = 1, 7 do lines[#lines + 1] = "t" .. i .. "=" .. packPile(s.tableau[i]) end
    local order = {}
    for i, o in ipairs(s.dealOrder or {}) do order[i] = SUIT_CODE[o.suit] .. o.rank end
    lines[#lines + 1] = "order=" .. table.concat(order, ",")
    return Store.write(FILE, table.concat(lines, "\n") .. "\n")
end

-- Puts the saved game into the rules engine. Returns true on success; on any problem the
-- engine is left untouched and false is returned.
function Savegame.load(s)
    local t = parse()
    if not t then return false end
    local ids = {}
    local stock = unpackPile(t.stock, ids)
    local waste = unpackPile(t.waste, ids)
    local foundations, tableau = {}, {}
    if not stock or not waste then return false end
    for i = 1, 4 do foundations[i] = unpackPile(t["f" .. i], ids); if not foundations[i] then return false end end
    for i = 1, 7 do tableau[i] = unpackPile(t["t" .. i], ids); if not tableau[i] then return false end end
    local count = 0
    for _ in pairs(ids) do count = count + 1 end
    if count ~= 52 then return false end

    local order = {}
    for tok in (t.order or ""):gmatch("[^,]+") do
        local code, rank = tok:match("^(%a)(%d+)$")
        if CODE_SUIT[code or ""] and tonumber(rank) then
            order[#order + 1] = { suit = CODE_SUIT[code], rank = tonumber(rank) }
        end
    end
    if #order ~= 52 then order = nil end

    s.stock, s.waste, s.foundations, s.tableau = stock, waste, foundations, tableau
    s.time = tonumber(t.time) or 0
    s.moves = tonumber(t.moves) or 0
    s.score = tonumber(t.score) or 0
    s.dealOrder = order or s.dealOrder
    s.undoStack = {}
    s.undoCount = 0
    s.selection = nil
    s.isWon = false
    s.finishing = false
    s.winClock = 0
    s.version = (s.version or 0) + 1
    return true
end

function Savegame.clear()
    Store.remove(FILE)
end

return Savegame
