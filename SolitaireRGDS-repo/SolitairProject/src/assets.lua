local Library = require("src.library")

local Assets = {}
Assets.__index = Assets

function Assets.new()
    local self = setmetatable({}, Assets)
    self.cards = {}            -- [suit][rank] = Image or Canvas
    self.cardBack = nil        -- Image or Canvas
    self.emptySlot = nil       -- Image or Canvas for empty foundations / tableaus
    self.audio = {}
    self.sfxVolume = 1
    self.musicVolume = 0.5
    self.music = nil            -- the Source that is playing right now
    self.musicName = "off"      -- name of the selected track, or "off"
    self.musicEntries = {}      -- tracks found in assets/music
    self.cardWidth = 116
    self.cardHeight = 164
    self.cornerRadius = 8
    self:init()
    return self
end

function Assets:init()
    self:generateProceduralPlaceholders()
    self:loadCustomCards()
    self:loadAudio()
    self:refreshMusic()
end

-- Generate crisp procedural cards so the game runs out of the box
function Assets:generateProceduralPlaceholders()
    local w = self.cardWidth
    local h = self.cardHeight
    local r = self.cornerRadius

    local suits = {"hearts", "diamonds", "clubs", "spades"}
    local suitSymbols = {
        hearts = "♥",
        diamonds = "♦",
        clubs = "♣",
        spades = "♠"
    }
    local suitColors = {
        hearts = {0.85, 0.15, 0.15},
        diamonds = {0.85, 0.15, 0.15},
        clubs = {0.12, 0.12, 0.14},
        spades = {0.12, 0.12, 0.14}
    }
    local rankTexts = {
        [1] = "A", [2] = "2", [3] = "3", [4] = "4", [5] = "5",
        [6] = "6", [7] = "7", [8] = "8", [9] = "9", [10] = "10",
        [11] = "J", [12] = "Q", [13] = "K"
    }

    local fontSmall = love.graphics.newFont(18)
    local fontLarge = love.graphics.newFont(36)

    for _, suit in ipairs(suits) do
        self.cards[suit] = {}
        for rank = 1, 13 do
            local canvas = love.graphics.newCanvas(w, h)
            love.graphics.setCanvas(canvas)
            love.graphics.clear(0, 0, 0, 0)

            -- Card base & subtle shadow / border
            love.graphics.setColor(0.97, 0.97, 0.97, 1)
            love.graphics.rectangle("fill", 1, 1, w - 2, h - 2, r, r)

            love.graphics.setLineWidth(2)
            love.graphics.setColor(0.7, 0.7, 0.75, 1)
            love.graphics.rectangle("line", 1, 1, w - 2, h - 2, r, r)

            -- Inner border
            love.graphics.setLineWidth(1)
            love.graphics.setColor(0.9, 0.9, 0.9, 1)
            love.graphics.rectangle("line", 5, 5, w - 10, h - 10, r - 3, r - 3)

            -- Rank & Suit text
            local color = suitColors[suit]
            local symbol = suitSymbols[suit]
            local rankText = rankTexts[rank]

            love.graphics.setColor(color[1], color[2], color[3], 1)
            love.graphics.setFont(fontSmall)

            -- Top-left corner
            love.graphics.print(rankText, 10, 8)
            love.graphics.print(symbol, 10, 26)

            -- Center large suit icon
            love.graphics.setFont(fontLarge)
            local symW = fontLarge:getWidth(symbol)
            local symH = fontLarge:getHeight()
            love.graphics.print(symbol, math.floor((w - symW) / 2), math.floor((h - symH) / 2) - 4)

            -- Bottom-right corner (inverted/mirrored position)
            love.graphics.setFont(fontSmall)
            local rw = fontSmall:getWidth(rankText)
            love.graphics.print(symbol, w - 10 - fontSmall:getWidth(symbol), h - 46)
            love.graphics.print(rankText, w - 10 - rw, h - 26)

            love.graphics.setCanvas()
            self.cards[suit][rank] = canvas
        end
    end

    -- Card back (Ornate pattern)
    local backCanvas = love.graphics.newCanvas(w, h)
    love.graphics.setCanvas(backCanvas)
    love.graphics.clear(0, 0, 0, 0)

    -- Outer border
    love.graphics.setColor(0.95, 0.95, 0.95, 1)
    love.graphics.rectangle("fill", 1, 1, w - 2, h - 2, r, r)
    love.graphics.setColor(0.7, 0.7, 0.75, 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", 1, 1, w - 2, h - 2, r, r)

    -- Inner blue/pattern fill
    love.graphics.setColor(0.12, 0.28, 0.55, 1)
    love.graphics.rectangle("fill", 5, 5, w - 10, h - 10, r - 2, r - 2)

    -- Diagonal diamond lattice pattern
    love.graphics.setColor(0.18, 0.38, 0.72, 1)
    love.graphics.setLineWidth(1)
    for step = -h, w + h, 14 do
        love.graphics.line(step, 5, step + h, h - 5)
        love.graphics.line(step + h, 5, step, h - 5)
    end

    -- Inner gold border
    love.graphics.setColor(0.85, 0.72, 0.25, 0.9)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", 8, 8, w - 16, h - 16, r - 4, r - 4)

    love.graphics.setCanvas()
    self.cardBack = backCanvas

    -- Empty slot outline (for foundations / empty tableau)
    local emptyCanvas = love.graphics.newCanvas(w, h)
    love.graphics.setCanvas(emptyCanvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setColor(0, 0, 0, 0.25)
    love.graphics.rectangle("fill", 1, 1, w - 2, h - 2, r, r)
    love.graphics.setColor(1, 1, 1, 0.35)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", 1, 1, w - 2, h - 2, r, r)
    love.graphics.setCanvas()
    self.emptySlot = emptyCanvas

    -- Reset draw state
    love.graphics.setColor(1, 1, 1, 1)
end

-- Try loading user PNG cards if placed in assets/cards/
function Assets:loadCustomCards()
    local cardDir = "assets/cards"
    if not love.filesystem.getInfo(cardDir) then return end

    -- Custom back
    local backFiles = {"back_light.png", "card_back.png", "back.png", "Card_Back.png", "back_dark.png"}
    for _, fname in ipairs(backFiles) do
        local path = cardDir .. "/" .. fname
        if love.filesystem.getInfo(path) then
            pcall(function()
                self.cardBack = love.graphics.newImage(path)
            end)
            break
        end
    end

    -- If no standard back found, search for any file containing "back"
    if not self.cardBack or self.cardBack == backCanvas then
        local files = love.filesystem.getDirectoryItems(cardDir)
        for _, file in ipairs(files) do
            if file:lower():match("back") and file:lower():match("%.png$") then
                pcall(function()
                    self.cardBack = love.graphics.newImage(cardDir .. "/" .. file)
                end)
                break
            end
        end
    end

    local suits = {"hearts", "diamonds", "clubs", "spades"}
    local suitInitials = {hearts = "H", diamonds = "D", clubs = "C", spades = "S"}
    local rankInitials = {[1] = "A", [11] = "J", [12] = "Q", [13] = "K"}

    for _, suit in ipairs(suits) do
        local sInit = suitInitials[suit]
        for rank = 1, 13 do
            local rInit = rankInitials[rank] or tostring(rank)
            local candidates = {
                string.format("%s/%d_%s.png", cardDir, rank, suit),
                string.format("%s/%s_%d.png", cardDir, suit, rank),
                string.format("%s/%s_%s.png", cardDir, rank, sInit),
                string.format("%s/%s%s.png", cardDir, rInit, sInit),
                string.format("%s/%s_%s.png", cardDir, suit, rInit),
                string.format("%s/%d_%s.png", cardDir, rank, sInit:lower()),
                string.format("%s/%s_%d.png", cardDir, sInit:lower(), rank)
            }
            for _, path in ipairs(candidates) do
                if love.filesystem.getInfo(path) then
                    pcall(function()
                        self.cards[suit][rank] = love.graphics.newImage(path)
                    end)
                    break
                end
            end
        end
    end
end

function Assets:loadAudio()
    local sounds = {"flip", "place", "shuffle", "undo", "win", "draw", "error"}
    local found = {}
    for _, e in ipairs(Library.list("audio", {"wav", "ogg", "mp3"})) do
        found[e.name:lower()] = e
    end
    for _, name in ipairs(sounds) do
        for _, ext in ipairs({".wav", ".ogg", ".mp3"}) do
            local entry = found[name .. ext]
            if entry then
                local ok, src = pcall(Library.loadSource, entry, "static")
                if ok and src then
                    self.audio[name] = src
                    print("Assets: loaded sound '" .. name .. "' from " .. entry.path)
                else
                    print("Assets: could not load sound '" .. name .. "': " .. tostring(src))
                end
                break
            end
        end
    end
    -- optional extras: a song after the win jingle (win_song.*) and a "no way to win" sound (lose.*)
    for _, name in ipairs({ "win_song", "lose" }) do
        for _, ext in ipairs({ ".mp3", ".ogg", ".wav" }) do
            local entry = found[name .. ext]
            if entry then
                local ok, src = pcall(Library.loadSource, entry, name == "win_song" and "stream" or "static")
                if ok and src then self.audio[name] = src print("Assets: loaded '" .. name .. "' from " .. entry.path) end
                break
            end
        end
    end
    if not self.audio.win then print("Assets: no win sound found (assets/audio/win.mp3/.ogg/.wav)") end
end

function Assets:playSound(name)
    local now = love.timer.getTime()
    -- the pickup "flip" right after a rejected move must not drown out the error sound
    if name ~= "error" and self.errorAt and now - self.errorAt < 0.45 and (name == "flip" or name == "place") then return end
    if name == "error" then self.errorAt = now end
    local src = self.audio[name]
    if not src and name == "undo" then src = self.audio["flip"] end
    if src then
        pcall(function()
            src:setVolume(name == "error" and math.max(self.sfxVolume, 0.5) or self.sfxVolume)
            src:stop()
            src:play()
        end)
    end
end

-- The song that follows the win jingle. Loops until stopped. Returns true if there is one.
function Assets:playWinSong()
    local src = self.audio.win_song
    if not src then return false end
    pcall(function()
        src:setLooping(true)
        src:setVolume(self.musicVolume)
        src:stop()
        src:play()
    end)
    return true
end

function Assets:stopWinSong()
    local src = self.audio.win_song
    if src then pcall(function() src:stop() end) end
end

function Assets:stopSound(name)
    local src = self.audio[name]
    if src then pcall(function() src:stop() end) end
end

-- Length of a sound effect in seconds (nil if not loaded)
function Assets:soundLength(name)
    local src = self.audio[name]
    if not src then return nil end
    local ok, d = pcall(function() return src:getDuration() end)
    if ok and type(d) == "number" and d > 0 then return d end
    return nil
end

function Assets:setSfxVolume(v)
    self.sfxVolume = math.max(0, math.min(1, v))
end

-- ------------------------------------------------------------------
-- BACKGROUND MUSIC  (files in assets/music/: mp3, ogg, wav, flac)
-- ------------------------------------------------------------------

function Assets:refreshMusic()
    self.musicEntries = Library.list("music", {"mp3", "ogg", "wav", "flac"})
end

-- name: "off", "auto" (first track), or a file name
function Assets:setMusic(name)
    if self.music then
        pcall(function() self.music:stop() end)
        self.music = nil
    end
    local entry = nil
    if name == "auto" then
        entry = self.musicEntries[1]
    elseif name ~= "off" then
        for _, e in ipairs(self.musicEntries) do
            if e.name == name then entry = e end
        end
    end
    if not entry then
        self.musicName = "off"
        return
    end
    local ok, src = pcall(Library.loadSource, entry, "stream")
    if ok and src then
        pcall(function()
            src:setLooping(true)
            src:setVolume(self.musicVolume)
            src:play()
        end)
        self.music = src
        self.musicName = entry.name
        print("Assets: playing music '" .. entry.name .. "'")
    else
        print("Assets: could not load music '" .. entry.name .. "': " .. tostring(src))
        self.musicName = "off"
    end
end

function Assets:setMusicVolume(v)
    self.musicVolume = math.max(0, math.min(1, v))
    if self.music then pcall(function() self.music:setVolume(self.musicVolume) end) end
end

function Assets:pauseMusic()
    if self.music then pcall(function() self.music:pause() end) end
end

function Assets:resumeMusic()
    if self.music then pcall(function() self.music:play() end) end
end

-- Label shown in the options menu
function Assets:musicLabel()
    if self.musicName == "off" then
        if #self.musicEntries == 0 then return "Off (no files in assets/music)" end
        return "Off"
    end
    for _, e in ipairs(self.musicEntries) do
        if e.name == self.musicName then return e.label end
    end
    return self.musicName
end

-- Step through: Off, track 1, track 2, ... dir = +1 / -1. Returns the new name.
function Assets:cycleMusic(dir)
    local names = { "off" }
    for _, e in ipairs(self.musicEntries) do names[#names + 1] = e.name end
    local idx = 1
    for i, n in ipairs(names) do
        if n == self.musicName then idx = i end
    end
    idx = ((idx - 1 + dir) % #names) + 1
    self:setMusic(names[idx])
    return names[idx]
end

return Assets

