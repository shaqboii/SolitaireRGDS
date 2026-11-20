-- Game: ties the rules, the animations, the menu and the controls together.

local Solitaire = require("src.solitaire")
local Hint = require("src.hint")
local Solver = require("src.solver")
local Stats = require("src.stats")
local Settings = require("src.settings")
local Anim = require("src.anim")
local Controls = require("src.controls")
local Menu = require("src.menu")
local Savegame = require("src.savegame")
local Brightness = require("src.brightness")
local Updater = require("src.updater")

local Game = {}
Game.__index = Game

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- parts: solitaire, assets, background, cursor, renderer, settings, stats
function Game.new(parts)
    local self = setmetatable({}, Game)
    self.solitaire = parts.solitaire
    self.assets = parts.assets
    self.background = parts.background
    self.cursor = parts.cursor
    self.renderer = parts.renderer
    self.settings = parts.settings
    self.stats = parts.stats

    self.anim = Anim.new()
    self.flash = { id = nil, t = 0 }
    self.toastText = nil
    self.toastTime = 0
    self.hint = nil
    self.task = nil              -- a running solver: { kind, solver, version }
    self.cache = nil             -- last solver answer for this position
    self.finishTimer = 0
    self.winHandled = false
    self.winDialogDelay = nil
    self.winBeat = nil
    self.musicPausedForWin = false

    self.controls = Controls.new(self)
    self.menu = Menu.new(self)
    self.softDim = 0             -- picture dimming used when the real backlight can't be changed
    self.updater = Updater.new()
    self.quitIn = nil            -- seconds until the game closes itself after an update
    return self
end

-- ========================================================
-- SMALL HELPERS
-- ========================================================

function Game:toast(text, seconds)
    self.toastText = text
    self.toastTime = seconds or 3
end

function Game:clearHint()
    self.hint = nil
end

-- True while the table should ignore play input (cards flying in / finishing / game over)
function Game:locked()
    local s = self.solitaire
    return s.finishing or self.anim:isDealing() or s.isWon
end

function Game:finishAvailable()
    local s = self.solitaire
    return not self.menu.open and not s.finishing and not s.isWon and self.task == nil
        and not self.anim:isDealing() and s:isFinishable()
end

function Game:needsConfirm()
    local s = self.solitaire
    return not s.isWon and s.moves > 0
end

-- ========================================================
-- ANIMATED CHANGES
-- ========================================================

-- Runs fn (which changes the game) and glides every card that moved from where it was drawn to where it is now.
function Game:change(fn, opts)
    local before_x, before_y = self.renderer:visualPositions(self.solitaire, self.controls, self.anim)
    local version = self.solitaire.version
    local result = fn()
    local after_x, after_y = self.renderer:layout(self.solitaire)
    self.anim:retarget(before_x, before_y, after_x, after_y, opts)
    if self.solitaire.version ~= version then self.hint = nil end
    return result
end

-- Like change, plus a sound when it worked
function Game:act(fn, sound, opts)
    local ok = self:change(fn, opts)
    if ok and sound then self.assets:playSound(sound) end
    return ok
end

-- A card was dropped / placed somewhere it doesn't belong: error sound (assets/audio/error.mp3) and a short hint
function Game:reject()
    local now = love.timer.getTime()
    if now - (self.lastReject or -1) < 0.25 then return end     -- no machine-gun errors
    self.lastReject = now
    self.assets:playSound("error")
    self:toast("Can't go there", 1.2)
end

function Game:drawOne()
    local s = self.solitaire
    local ok = self:change(function() return s:drawOne() end)
    if ok then
        self.assets:playSound("draw")
    else
        self:toast("The deck is empty")
    end
    return ok
end

function Game:undo()
    local s = self.solitaire
    local ok = self:change(function() return s:undo() end)
    if ok then
        self.assets:playSound("undo")
    else
        self:toast("Nothing to undo")
    end
    return ok
end

-- ========================================================
-- NEW DEAL
-- ========================================================

-- Called after the rules engine dealt: resets the interface and plays the deal animation
function Game:afterDeal(skipAnimation)
    local s = self.solitaire
    self.hint = nil
    self.task = nil
    self.cache = nil
    self.winHandled = false
    self.winDialogDelay = nil
    self.winBeat = nil
    self.finishTimer = 0
    s.finishing = false

    self.cursor.zone = "tableau"
    self.cursor.tableauCol = 1
    self.cursor.cardIndex = 1

    if self.musicPausedForWin then
        self.musicPausedForWin = false
        self.assets:stopSound("win")
        self.assets:resumeMusic()
    end

    if skipAnimation then
        self.anim:clear()
    else
        self:startDealAnimation()
    end
end

-- Cards glide from the deck (top left) to their places, one after another, in time with the shuffle sound
function Game:startDealAnimation()
    local s = self.solitaire
    local anim = self.anim
    anim:clear()

    local sx, sy = self.renderer:getStockRect()
    local dur = 0.32
    local total = self.assets:soundLength("shuffle") or 1.6
    total = clamp(total, 1.0, 3.0)
    local step = math.max(0.02, (total - dur) / 27)

    local k = 0
    for row = 1, 7 do
        for col = row, 7 do
            local card = s.tableau[col][row]
            if card then
                anim:add(card.id, sx, sy, { delay = k * step, dur = dur, ease = "out", back = true })
                k = k + 1
            end
        end
    end
    anim.dealUntil = anim.t + math.max(0, k - 1) * step + dur
    self.assets:playSound("shuffle")
end

function Game:newGame()
    local s = self.solitaire
    self.menu:close()
    if not s.isWon and s.moves > 0 then
        Stats.recordAbandon(self.stats, s.time)
    end
    s:deal()
    self:afterDeal()
end

-- ========================================================
-- TITLE SCREEN, SAVE AND RESUME
-- ========================================================

-- Shown when the game starts: nothing is dealt until the player picks Continue or New game
function Game:showTitle()
    self.menu:openTitle()
end

function Game:hasSavedGame()
    return Savegame.exists()
end

function Game:continueSaved()
    local ok = Savegame.load(self.solitaire)
    if not ok then
        self.menu:showDialog({
            title = "Can't load the saved game",
            lines = { "The save file is missing or damaged.", "Start a new game instead." },
            buttons = { { label = "OK" } },
        })
        return false
    end
    self.menu:close()
    self:afterDeal(true)
    self:toast("Welcome back!", 2)
    return true
end

-- Can the current game be saved? (a game that hasn't started or has been won has nothing to resume)
function Game:canSave()
    local s = self.solitaire
    return s.moves > 0 and not s.isWon
end

function Game:saveGame()
    if not self:canSave() then return false end
    return Savegame.save(self.solitaire)
end

function Game:saveAndExit()
    if self:saveGame() then
        love.event.quit()
    else
        self.menu:showDialog({
            title = "Could not save",
            lines = { "The game could not write its save file." },
            buttons = { { label = "OK" } },
        })
    end
end

function Game:restartDeal()
    self.menu:close()
    self.solitaire:restart()
    self:afterDeal()
end

-- ========================================================
-- MENU / BUTTONS
-- ========================================================

function Game:openMenu()
    self.menu:openMain()
end

function Game:pressButton(id)
    local s = self.solitaire
    self.flash = { id = id, t = 0.2 }

    if id == "menu" then
        self:openMenu()
        return
    end
    if s.finishing or self.anim:isDealing() then return end

    if id == "undo" then
        self:undo()
    elseif id == "hint" then
        self:hintMove()
    elseif id == "winnable" then
        self:checkWinnable()
    elseif id == "finish" then
        self:finish()
    elseif id == "deal" then
        if self:needsConfirm() then
            self.menu:confirm("Start a new game?", "Your current game will be given up.", "New game", function() self:newGame() end)
        else
            self:newGame()
        end
    end
end

-- ========================================================
-- HINTS AND "WINNABLE?"
-- ========================================================

local function sourceToCursor(cursor, source)
    if source.zone == "stock" then
        cursor.zone, cursor.topIndex = "top", 1
    elseif source.zone == "waste" then
        cursor.zone, cursor.topIndex = "top", 2
    elseif source.zone == "tableau" then
        cursor.zone, cursor.tableauCol, cursor.cardIndex = "tableau", source.col, source.index or 1
    end
end

function Game:showHint(h)
    local s = self.solitaire
    self.hint = { version = s.version, kind = h.kind, source = h.source, dest = h.dest, text = h.text, t = 8 }
    self:toast(h.text, 6)
    sourceToCursor(self.cursor, h.source)
    s.selection = nil
end

function Game:hintMove()
    local s = self.solitaire
    if s.isWon then return end
    if s:isFinishable() then
        self:toast("Everything is face up. Press FINISH!", 4)
        return
    end
    local h = Hint.find(s)
    if h then
        self:showHint(h)
        return
    end
    -- Nothing obvious: ask the solver whether anything useful is left
    self:startTask("hint")
end

function Game:checkWinnable()
    local s = self.solitaire
    if s.isWon then return end
    self:startTask("winnable")
end

function Game:startTask(kind)
    local s = self.solitaire
    local c = self.cache
    if c and c.version == s.version then
        self:onSolverDone(kind, c.result, c.solver)
        return
    end
    self.task = { kind = kind, solver = Solver.new(s), version = s.version }
end

function Game:cancelTask()
    self.task = nil
    self:toast("Cancelled")
end

function Game:updateTask(dt)
    local t = self.task
    if not t then return end
    local res = t.solver:step(0.008)
    if res then
        self.task = nil
        if t.version == self.solitaire.version then
            self.cache = { version = t.version, result = res, solver = t.solver }
            self:onSolverDone(t.kind, res, t.solver)
        end
    end
end

-- Buttons for the "game over" style boxes
function Game:stuckButtons()
    local s = self.solitaire
    local buttons = {
        { label = "Restart deal", action = function() self:restartDeal() end },
        { label = "New deal", action = function() self:newGame() end },
    }
    if #s.undoStack > 0 then
        buttons[#buttons + 1] = { label = "Undo", action = function() self:undo() end }
    end
    buttons[#buttons + 1] = { label = "Close" }
    return buttons
end

function Game:onSolverDone(kind, res, solver)
    local menu = self.menu
    if kind == "winnable" then
        if res == "win" then
            menu:showDialog({ title = "Yes!", accent = { 0.4, 0.9, 0.5 },
                lines = { "This game can still be won." },
                buttons = { { label = "OK" } } })
        elseif res == "lose" then
            menu:showDialog({ title = "Not winnable", accent = { 0.95, 0.45, 0.4 },
                lines = { "There is no way to win from here." },
                buttons = self:stuckButtons() })
        else
            menu:showDialog({ title = "Can't tell", accent = { 0.9, 0.8, 0.4 },
                lines = { "Too many possibilities to check them all.", "There may still be a way to win." },
                buttons = { { label = "OK" } } })
        end
        return
    end

    -- kind == "hint": the simple hints found nothing
    if res == "win" and solver and solver.path and self:hintFromPath(solver.path) then
        return
    end
    if res == "lose" then
        menu:showDialog({ title = "No more moves", accent = { 0.95, 0.45, 0.4 },
            lines = { "This game can't be won anymore.", "Restart this deal or start a new one?" },
            buttons = self:stuckButtons() })
    else
        menu:showDialog({ title = "No more moves", accent = { 0.9, 0.8, 0.4 },
            lines = { "I can't find a useful move.", "This game may not be winnable anymore." },
            buttons = self:stuckButtons() })
    end
end

local RANK_NAME = { [1] = "Ace", [11] = "Jack", [12] = "Queen", [13] = "King" }
local function cardName(card)
    return (RANK_NAME[card.rank] or tostring(card.rank)) .. " of " .. card.suit
end

-- Turns the first move of a winning line (from the solver) into a hint
function Game:hintFromPath(path)
    local s = self.solitaire
    local m = path[1]
    if not m then return false end
    local t = m[1]
    local h = nil

    local function talonCard()
        local suit = Solitaire.SUITS[math.floor((m.card - 1) / 13) + 1]
        local rank = (m.card - 1) % 13 + 1
        return suit, rank
    end
    local function drawHint()
        local verb = (#s.stock > 0) and "Draw from the deck" or "Turn the deck over"
        return { kind = "draw", source = { zone = "stock" }, text = verb }
    end

    if t == 1 then
        local pile = s.tableau[m[2]]
        local card = pile[#pile]
        local f = card and s:foundationFor(card)
        if f then
            h = { kind = "move", source = { zone = "tableau", col = m[2], index = #pile },
                  dest = { zone = "foundation", col = f }, text = "Move the " .. cardName(card) .. " up to a foundation" }
        end
    elseif t == 3 then
        local card = s.tableau[m[2]][m[3]]
        if card then
            h = { kind = "move", source = { zone = "tableau", col = m[2], index = m[3] },
                  dest = { zone = "tableau", col = m[4] }, text = "Move the " .. cardName(card) .. " to another column" }
        end
    elseif t == 2 or t == 4 then
        local suit, rank = talonCard()
        local w = s.waste[#s.waste]
        if w and w.suit == suit and w.rank == rank then
            if t == 2 then
                local f = s:foundationFor(w)
                if f then
                    h = { kind = "move", source = { zone = "waste" }, dest = { zone = "foundation", col = f },
                          text = "Move the " .. cardName(w) .. " up to a foundation" }
                end
            else
                h = { kind = "move", source = { zone = "waste" }, dest = { zone = "tableau", col = m[3] },
                      text = "Play the " .. cardName(w) .. " from the waste pile" }
            end
        else
            h = drawHint()
        end
    elseif t == 5 then
        local suit = Solitaire.SUITS[m[2]]
        for f = 1, 4 do
            local pile = s.foundations[f]
            if #pile > 0 and pile[1].suit == suit then
                h = { kind = "move", source = { zone = "foundation", col = f }, dest = { zone = "tableau", col = m[3] },
                      text = "Move the " .. cardName(pile[#pile]) .. " back down to a column" }
            end
        end
    end

    if h then
        self:showHint(h)
        return true
    end
    return false
end

-- ========================================================
-- FINISH
-- ========================================================

function Game:finish()
    local s = self.solitaire
    if s.finishing or s.isWon then return end
    if not s:isFinishable() then
        self:toast("Turn over every card on the table first")
        return
    end
    self.hint = nil
    s.selection = nil
    s.finishing = true
    self.finishTimer = 0
end

function Game:updateFinish(dt)
    local s = self.solitaire
    if not s.finishing then return end
    self.finishTimer = self.finishTimer - dt
    if self.finishTimer > 0 then return end

    local moved = self:change(function() return s:finishStep() end, { dur = 0.4, ease = "out" })
    if moved then
        self.assets:playSound("place")
        self.finishTimer = 0.17
    else
        s.finishing = false
    end
end

-- ========================================================
-- WINNING
-- ========================================================

function Game:onWin()
    local s = self.solitaire
    self.winHandled = true
    Savegame.clear()
    self.winBeat = Stats.recordWin(self.stats, s.time, s.moves, s.score)
    self.hint = nil
    self.assets:pauseMusic()
    self.musicPausedForWin = true
    self.assets:playSound("win")
    self.winDialogDelay = 1.0
end

function Game:showVictory()
    local s = self.solitaire
    local lines = { string.format("Time %s     Moves %d     Score %d", Stats.formatTime(s.time), s.moves, s.score) }
    local beat = self.winBeat or {}
    if beat.time then lines[#lines + 1] = "New best time!" end
    if beat.moves then lines[#lines + 1] = "New fewest moves!" end
    if beat.score then lines[#lines + 1] = "New high score!" end
    self.menu:showDialog({
        title = "VICTORY!", accent = { 1, 0.85, 0.2 }, lines = lines,
        buttons = {
            { label = "New game", action = function() self:newGame() end },
            { label = "Menu", action = function() self.menu:openMain() end },
        },
    })
end

function Game:updateWin(dt)
    local s = self.solitaire
    if s.isWon and not self.winHandled then self:onWin() end
    if self.winDialogDelay and not self.anim:isBusy() then
        self.winDialogDelay = self.winDialogDelay - dt
        if self.winDialogDelay <= 0 then
            self.winDialogDelay = nil
            if not self.menu.open then self:showVictory() end
        end
    end
end

-- ========================================================
-- OPTIONS (saved as they change)
-- ========================================================

function Game:changeMusic(dir)
    local name = self.assets:cycleMusic(dir)
    self.settings.music = name
    Settings.save(self.settings)
end

function Game:changeMusicVolume(dir)
    local v = clamp(math.floor((self.assets.musicVolume + dir * 0.1) * 10 + 0.5) / 10, 0, 1)
    self.assets:setMusicVolume(v)
    self.settings.musicVolume = v
    Settings.save(self.settings)
end

function Game:changeSfxVolume(dir)
    local v = clamp(math.floor((self.assets.sfxVolume + dir * 0.1) * 10 + 0.5) / 10, 0, 1)
    self.assets:setSfxVolume(v)
    self.settings.sfxVolume = v
    Settings.save(self.settings)
    self.assets:playSound("flip")
end

function Game:changeBackground(dir)
    local name = self.background:cycle(dir)
    self.settings.background = name
    Settings.save(self.settings)
end

-- ========================================================
-- UPDATES (menu > Check for updates)
-- ========================================================

function Game:checkForUpdates()
    if self.updater.busy then return end
    self.updater:check()
    self.menu:showDialog({
        title = "Checking for updates",
        lines = { "Installed: v" .. Updater.localVersion(), "Contacting GitHub..." },
        buttons = { { label = "Cancel", action = function() self.updater:cancel() end } },
        cancel = function() self.updater:cancel() end,
    })
end

local function updateFailed(self, message)
    local lines = {}
    -- keep lines short enough for the box
    local line = ""
    for word in tostring(message):gmatch("%S+") do
        if #line + #word + 1 > 46 and line ~= "" then lines[#lines + 1] = line; line = word
        else line = (line == "" and word or (line .. " " .. word)) end
    end
    if line ~= "" then lines[#lines + 1] = line end
    self.menu:showDialog({
        title = "Update failed",
        lines = lines,
        buttons = { { label = "OK" } },
    })
    print("Updater: " .. tostring(message))
end

function Game:onUpdateEvent(e)
    local cur = Updater.localVersion()
    if e.kind == "progress" then
        if self.menu.dialog then self.menu.dialog.lines = { "Update v" .. (self.pendingVersion or "?"), e.message } end
    elseif e.kind == "checked" then
        if Updater.compare(e.remote, cur) > 0 then
            self.pendingVersion = e.remote
            self.menu:showDialog({
                title = "Update available",
                lines = { "Installed: v" .. cur, "Available: v" .. e.remote, "Download and install it now?" },
                buttons = {
                    { label = "Install", action = function()
                        self.updater:install()
                        self.menu:showDialog({
                            title = "Updating",
                            lines = { "Update v" .. e.remote, "Downloading..." },
                            buttons = { { label = "Cancel", action = function() self.updater:cancel() end } },
                            cancel = function() self.updater:cancel() end,
                        })
                    end },
                    { label = "Later" },
                },
                default = 1,
            })
        else
            self.menu:showDialog({
                title = "You're up to date",
                lines = { "Version " .. cur .. " is the newest." },
                buttons = { { label = "OK" } },
            })
        end
    elseif e.kind == "downloaded" then
        local ok, msg = Updater.swap()
        if not ok then return updateFailed(self, msg) end
        local lines = { "Updated to v" .. (self.pendingVersion or "?") .. "." }
        if self:canSave() and self:saveGame() then
            lines[#lines + 1] = "Your game was saved (Continue)."
        end
        lines[#lines + 1] = "The game will now quit."
        lines[#lines + 1] = "Start it again to play the new version."
        self.updateDone = true
        self.quitIn = 8
        self.menu:showDialog({
            title = "Update installed",
            lines = lines,
            buttons = { { label = "Quit now", action = function() love.event.quit() end } },
            default = 1,
            cancel = function() love.event.quit() end,
        })
        self.quitLine = #lines + 1
    elseif e.kind == "error" then
        local m = e.message or "Unknown error."
        if e.hint == "network" then m = "Couldn't reach GitHub. Check that wifi is on and try again. (" .. m .. ")" end
        if e.hint == "noversion" or e.hint == "nosha" then
            m = "No update has been published yet."
        end
        updateFailed(self, m)
    end
end

function Game:updateUpdater(dt)
    local e = self.updater:poll()
    if e then self:onUpdateEvent(e) end
    if self.quitIn then
        self.quitIn = self.quitIn - dt
        local d = self.menu.dialog
        if d and self.updateDone then
            d.lines[self.quitLine or #d.lines] = string.format("Closing in %d...", math.max(0, math.ceil(self.quitIn)))
        end
        if self.quitIn <= 0 then
            self.quitIn = nil
            love.event.quit()
        end
    end
end

function Game:toggleTopAnimation()
    self.settings.topAnimation = (self.settings.topAnimation == "off") and "on" or "off"
    Settings.save(self.settings)
end

-- Should the top screen keep moving right now? Not while the bottom screen needs every bit of speed.
function Game:topShouldAnimate()
    if self.settings.topAnimation == "off" then return false end
    if not self.background:isAnimated() then return false end
    if self.anim:isBusy() or self.controls.dragging or self.solitaire.finishing then return false end
    return true
end

function Game:applyBrightness()
    local level = Brightness.clamp(self.settings.brightness or 1)
    local ok = Brightness.apply(level)
    -- if the backlight can't be controlled, dim the picture instead
    self.softDim = ok and 0 or (1 - level)
    self.renderer.softDim = self.softDim
end

function Game:changeBrightness(dir)
    local v = Brightness.clamp((self.settings.brightness or 1) + dir * Brightness.STEP)
    self.settings.brightness = v
    Settings.save(self.settings)
    self:applyBrightness()
end

function Game:resetStats()
    Stats.reset(self.stats)
end

-- ========================================================
-- TOP SCREEN
-- ========================================================

function Game:bestLine()
    local st = self.stats
    local parts = {}
    if st.bestTime > 0 then parts[#parts + 1] = "Best time " .. Stats.formatTime(st.bestTime) end
    if st.bestMoves > 0 then parts[#parts + 1] = "Fewest moves " .. st.bestMoves end
    if st.gamesPlayed > 0 then parts[#parts + 1] = "Won " .. st.gamesWon .. " of " .. st.gamesPlayed end
    if #parts == 0 then return nil end
    return table.concat(parts, "     |     ")
end

function Game:topInfo()
    local info = {}
    if self.assets.musicName ~= "off" then info.nowPlaying = self.assets:musicLabel() end
    info.overlay = self.menu:topContent()
    info.best = self:bestLine()
    info.dim = self.softDim
    return info
end

-- Changes whenever the top screen needs redrawing
function Game:topKey()
    return table.concat({
        self.menu:key(), self.background.selectedName or "", self.assets.musicName,
        self.stats.bestTime, self.stats.bestMoves, self.stats.gamesPlayed, self.stats.gamesWon,
        math.floor(self.softDim * 100),
    }, "|")
end

-- ========================================================
-- FRAME UPDATE
-- ========================================================

function Game:update(dt)
    local s = self.solitaire
    self:updateUpdater(dt)
    self.anim:update(dt)
    s.paused = self.menu.open or self.anim:isDealing() or self.task ~= nil
    s:update(dt)
    self.cursor:update(dt)
    self.renderer:update(dt, self)
    self.menu:update(dt)

    self:updateTask(dt)
    self:updateFinish(dt)
    self:updateWin(dt)

    if self.toastTime > 0 then self.toastTime = self.toastTime - dt end
    if self.flash.t > 0 then self.flash.t = self.flash.t - dt end
    if self.hint then
        self.hint.t = self.hint.t - dt
        if self.hint.t <= 0 then self.hint = nil end
    end

    self.controls:update(dt)
end

return Game
