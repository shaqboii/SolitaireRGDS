-- Stats: all-time records, saved between sessions.
local Store = require("src.store")

local Stats = {}

local FILE = "stats.txt"
local DEFAULTS = {
    gamesPlayed = 0, gamesWon = 0,
    bestTime = 0, bestMoves = 0, bestScore = 0,    -- 0 = none yet
    totalWinTime = 0, totalTime = 0,
    currentStreak = 0, bestStreak = 0,
}
local KEYS = { "gamesPlayed", "gamesWon", "bestTime", "bestMoves", "bestScore",
               "totalWinTime", "totalTime", "currentStreak", "bestStreak" }

function Stats.load()
    return Store.load(FILE, DEFAULTS)
end

-- Erase everything (keeps the same table so the game keeps using it)
function Stats.reset(st)
    for k, v in pairs(DEFAULTS) do st[k] = v end
    Stats.save(st)
end

function Stats.save(st)
    Store.save(FILE, st, KEYS)
end

function Stats.formatTime(sec)
    sec = math.floor(sec or 0)
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    local s = sec % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
    return string.format("%02d:%02d", m, s)
end

-- Returns which records were beaten: { time=bool, moves=bool, score=bool }
function Stats.recordWin(st, time, moves, score)
    local beat = { time = false, moves = false, score = false }
    st.gamesPlayed = st.gamesPlayed + 1
    st.gamesWon = st.gamesWon + 1
    st.totalWinTime = st.totalWinTime + time
    st.totalTime = st.totalTime + time
    st.currentStreak = st.currentStreak + 1
    if st.currentStreak > st.bestStreak then st.bestStreak = st.currentStreak end
    if st.bestTime == 0 or time < st.bestTime then st.bestTime = time; beat.time = true end
    if st.bestMoves == 0 or moves < st.bestMoves then st.bestMoves = moves; beat.moves = true end
    if score > st.bestScore then st.bestScore = score; beat.score = true end
    Stats.save(st)
    return beat
end

-- A game that was started and played, then abandoned for a new deal
function Stats.recordAbandon(st, time)
    st.gamesPlayed = st.gamesPlayed + 1
    st.totalTime = st.totalTime + time
    st.currentStreak = 0
    Stats.save(st)
end

-- Rows for the stats screen: { label, value }
function Stats.rows(st)
    local none = "--"
    local winRate = (st.gamesPlayed > 0) and string.format("%d%%", math.floor(st.gamesWon * 100 / st.gamesPlayed + 0.5)) or none
    local avg = (st.gamesWon > 0) and Stats.formatTime(st.totalWinTime / st.gamesWon) or none
    return {
        { "Games played", tostring(st.gamesPlayed) },
        { "Games won", tostring(st.gamesWon) },
        { "Win rate", winRate },
        { "Best time", st.bestTime > 0 and Stats.formatTime(st.bestTime) or none },
        { "Fewest moves", st.bestMoves > 0 and tostring(st.bestMoves) or none },
        { "High score", st.bestScore > 0 and tostring(st.bestScore) or none },
        { "Average winning time", avg },
        { "Current win streak", tostring(st.currentStreak) },
        { "Best win streak", tostring(st.bestStreak) },
        { "Total time played", Stats.formatTime(st.totalTime) },
    }
end

return Stats
