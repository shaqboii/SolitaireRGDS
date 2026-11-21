local Ui = require("src.ui")
-- Menu: the pause menu and every pop-up box (confirmations, hints, "winnable?", victory).
--
-- It is drawn on the table screen (bottom) and works with the D-pad and with touch.
-- On the top screen the game shows a matching, read-only view (see topContent()).

local Stats = require("src.stats")

local Menu = {}
Menu.__index = Menu

local CONTROL_LINES = {
    { "D-Pad", "Move the cursor" },
    { "A", "Pick up a card / put it down" },
    { "B", "Cancel the selection" },
    { "Y", "Draw from the deck" },
    { "X", "Hint" },
    { "SELECT", "Undo" },
    { "START", "Pause menu" },
    { "L (tap)", "Is this game winnable?" },
    { "R (tap)", "Finish (when it appears)" },
    { "Hold L or R + A", "Send the card up automatically" },
    { "Touch: tap, drag", "Pick up and move cards" },
    { "Touch: double-tap", "Send the card up automatically" },
    { "Touch: buttons", "UNDO, HINT, WINNABLE?, MENU, DEAL" },
    { "SELECT + START", "Hold 2 seconds: emergency exit" },
}

function Menu.new(game)
    local self = setmetatable({}, Menu)
    self.game = game
    self.open = false
    self.screen = "main"       -- "main", "options", "controls", "stats", "dialog"
    self.index = 1
    self.dialog = nil
    self.prev = nil            -- where to go back to after a dialog closes
    self.title = false         -- true while the title screen is showing (the game hasn't started)
    self.time = 0
    return self
end

-- ========================================================
-- OPENING / CLOSING
-- ========================================================

function Menu:openMain()
    self.open = true
    self.screen = "main"
    self.index = 1
    self.dialog = nil
    self.prev = nil
end

function Menu:openTitle()
    self.open = true
    self.title = true
    self.screen = "main"
    self.index = 1
    self.dialog = nil
    self.prev = nil
    -- start on "Continue" when there's a saved game
    self.index = 1
end

function Menu:close()
    self.title = false
    self.open = false
    self.dialog = nil
    self.prev = nil
    self.screen = "main"
    self.index = 1
end

function Menu:goTo(screen)
    if screen == "options" then
        -- pick up songs / pictures that were added since the game started
        self.game.assets:refreshMusic()
        self.game.background:refresh()
    end
    self.screen = screen
    self.index = 1
end

function Menu:back()
    if self.screen == "dialog" then
        local cancel = self.dialog and self.dialog.cancel
        self:closeDialog()
        if cancel then cancel() end
    elseif self.screen == "main" then
        if not self.title then self:close() end
    else
        self.screen = "main"
        self.index = 1
    end
end

-- spec: { title, lines = {text...}, buttons = { { label, action }... }, default = 1, cancel = fn }
function Menu:showDialog(spec)
    if self.open and self.screen ~= "dialog" then
        self.prev = { screen = self.screen, index = self.index }
    elseif not self.open then
        self.prev = nil
    end
    self.open = true
    self.screen = "dialog"
    self.dialog = spec
    self.index = spec.default or 1
end

function Menu:closeDialog()
    self.dialog = nil
    if self.prev then
        self.screen = self.prev.screen
        self.index = self.prev.index
        self.prev = nil
    else
        if self.title then
            self.screen = "main"
            self.open = true
        else
            self.open = false
            self.screen = "main"
        end
        self.index = 1
    end
end

function Menu:pressDialogButton(i)
    local b = self.dialog and self.dialog.buttons[i]
    if not b then return end
    local action = b.action
    self:closeDialog()
    if action then action() end
end

-- ========================================================
-- ITEMS
-- ========================================================

local function percent(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end

function Menu:confirm(title, line, yesLabel, onYes)
    self:showDialog({
        title = title,
        lines = { line },
        buttons = { { label = yesLabel, action = onYes }, { label = "Cancel" } },
        default = 2,
    })
end

function Menu:items()
    local g = self.game
    if self.screen == "main" then
        local function askNewGame()
            if g:needsConfirm() then
                self:confirm("Start a new game?", "Your current game will be given up.", "New game", function() g:newGame() end)
            else
                g:newGame()
            end
        end
        local list = {}
        local function add(item) list[#list + 1] = item end

        if self.title then
            local sum = g:hasSavedGame() and require("src.savegame").summary() or nil
            if sum then
                add({ label = "Continue", kind = "action",
                      desc = string.format("Saved game: %s, %d moves, score %d", Stats.formatTime(sum.time), sum.moves, sum.score),
                      run = function() g:continueSaved() end })
            end
            add({ label = "New game", kind = "action", desc = "Deal a fresh game", run = function() g:newGame() end })
        else
            add({ label = "Resume", kind = "action", desc = "Back to your game", run = function() self:close() end })
            add({ label = "New game", kind = "action", desc = "Deal a fresh game", run = askNewGame })
            add({ label = "Restart this deal", kind = "action", desc = "Replay the same shuffle from the start",
                  run = function()
                      if g:needsConfirm() then
                          self:confirm("Restart this deal?", "You will start over with the same cards.", "Restart", function() g:restartDeal() end)
                      else
                          g:restartDeal()
                      end
                  end })
        end
        add({ label = "Options", kind = "action", desc = "Music, volume, brightness and backgrounds",
              run = function() self:goTo("options") end })
        add({ label = "Controls", kind = "action", desc = "See what every button does",
              run = function() self:goTo("controls") end })
        add({ label = "Check for updates", kind = "action",
              desc = "Installed: v" .. require("src.updater").localVersion() .. "  (needs wifi)",
              run = function() g:checkForUpdates() end })
        add({ label = "All-time stats", kind = "action", desc = "Best times, win streaks and more",
              run = function() self:goTo("stats") end })
        add({ label = "Exit game", kind = "action", desc = self.title and "Quit to the launcher" or "Save your game and quit, or just quit",
              run = function()
                  if not self.title and g:canSave() then
                      self:showDialog({
                          title = "Exit the game?",
                          lines = { "Save your game to pick it up later", "from the title screen (Continue)." },
                          buttons = {
                              { label = "Save & exit", action = function() g:saveAndExit() end },
                              { label = "Exit, no save", action = function() love.event.quit() end },
                              { label = "Cancel" },
                          },
                          default = 1,
                      })
                  elseif self.title then
                      love.event.quit()
                  else
                      self:confirm("Exit the game?", "Nothing to save yet.", "Exit", function() love.event.quit() end)
                  end
              end })
        return list
    elseif self.screen == "options" then
        return {
            { label = "Music", kind = "choice", desc = "Songs go in SolitairProject/assets/music",
              value = function() return g.assets:musicLabel() end,
              change = function(dir) g:changeMusic(dir) end },
            { label = "Music volume", kind = "choice", desc = "How loud the music is",
              value = function() return percent(g.assets.musicVolume) end,
              change = function(dir) g:changeMusicVolume(dir) end },
            { label = "Effects volume", kind = "choice", desc = "How loud card sounds are",
              value = function() return percent(g.assets.sfxVolume) end,
              change = function(dir) g:changeSfxVolume(dir) end },
            { label = "Top screen motion", kind = "choice", desc = "Animate the top-screen wallpaper (Off = smoother play)",
              value = function() return g.settings.topAnimation == "off" and "Off" or "On" end,
              change = function() g:toggleTopAnimation() end },
            { label = "Brightness", kind = "choice", desc = "Screen brightness, in 5% steps",
              value = function() return percent(g.settings.brightness or 1) end,
              change = function(dir) g:changeBrightness(dir) end },
            { label = "Detect lost games", kind = "choice", desc = "Quietly checks if the deal can still be won",
              value = function() return (g.settings.autoDetect == "off") and "Off" or "On" end,
              change = function() g:toggleAutoDetect() end },
            { label = "Background", kind = "choice", desc = "Pictures go in SolitairProject/assets/backgrounds",
              value = function() return g.background.selectedLabel or "XMB Purple" end,
              change = function(dir) g:changeBackground(dir) end },
            { label = "Back", kind = "action", desc = "", run = function() self:back() end },
        }
    elseif self.screen == "controls" then
        return { { label = "Back", kind = "action", desc = "", run = function() self:back() end } }
    elseif self.screen == "stats" then
        return {
            { label = "Reset stats", kind = "action", desc = "",
              run = function()
                  self:confirm("Reset all stats?", "Best times and streaks will be erased.", "Reset", function() g:resetStats() end)
              end },
            { label = "Back", kind = "action", desc = "", run = function() self:back() end },
        }
    end
    return {}
end

-- ========================================================
-- INPUT
-- ========================================================

function Menu:activate(i)
    local items = self:items()
    local item = items[i]
    if not item then return end
    self.index = i
    if item.kind == "choice" then
        item.change(1)
    elseif item.run then
        item.run()
    end
end

-- name: up, down, left, right, a, b, start
function Menu:press(name)
    if self.screen == "dialog" then
        local n = #self.dialog.buttons
        if name == "left" or name == "up" then
            self.index = (self.index - 2) % n + 1
        elseif name == "right" or name == "down" then
            self.index = self.index % n + 1
        elseif name == "a" then
            self:pressDialogButton(self.index)
        elseif name == "b" or name == "start" then
            self:back()
        end
        return
    end

    local items = self:items()
    local n = #items
    if name == "up" then
        self.index = (self.index - 2) % n + 1
    elseif name == "down" then
        self.index = self.index % n + 1
    elseif name == "left" or name == "right" then
        local item = items[self.index]
        if item and item.kind == "choice" then item.change(name == "right" and 1 or -1) end
    elseif name == "a" then
        self:activate(self.index)
    elseif name == "b" then
        self:back()
    elseif name == "start" then
        if not self.title then self:close() end
    end
end

local function inRect(x, y, rx, ry, rw, rh)
    return x >= rx and x <= rx + rw and y >= ry and y <= ry + rh
end

-- Touch / mouse press in the 1024x768 table space
function Menu:pointer(x, y)
    if self.screen == "dialog" then
        local rects = self:dialogButtonRects()
        for i, r in ipairs(rects) do
            if inRect(x, y, r.x, r.y, r.w, r.h) then
                self.index = i
                self:pressDialogButton(i)
                return
            end
        end
        return
    end

    local p = self:panelRect()
    if not inRect(x, y, p.x, p.y, p.w, p.h) then
        -- tapping outside the box goes back / resumes
        self:back()
        return
    end

    for i, item in ipairs(self:items()) do
        local r = self:itemRect(i)
        if inRect(x, y, r.x, r.y, r.w, r.h) then
            if item.kind == "choice" then
                self.index = i
                local left = r.x + r.w - 330
                local right = r.x + r.w - 60
                if x >= left and x <= left + 50 then
                    item.change(-1)
                elseif x >= right and x <= right + 50 then
                    item.change(1)
                else
                    item.change(1)
                end
            else
                self:activate(i)
            end
            return
        end
    end
end

-- ========================================================
-- LAYOUT
-- ========================================================

function Menu:panelRect()
    local w, h = 600, 0
    local n = #self:items()
    if self.screen == "controls" then
        w = 780
        h = 100 + #CONTROL_LINES * 28 + 70
    elseif self.screen == "stats" then
        h = 100 + #Stats.rows(self.game.stats) * 32 + n * 58 + 30
    else
        h = 100 + n * 58 + 24
    end
    return { x = (1024 - w) / 2, y = math.floor((768 - h) / 2), w = w, h = h }
end

-- Where the list of items starts (below the title and any content)
function Menu:listTop()
    local p = self:panelRect()
    if self.screen == "controls" then
        return p.y + 100 + #CONTROL_LINES * 28 + 6
    elseif self.screen == "stats" then
        return p.y + 100 + #Stats.rows(self.game.stats) * 32 + 6
    end
    return p.y + 86
end

function Menu:itemRect(i)
    local p = self:panelRect()
    return { x = p.x + 20, y = self:listTop() + (i - 1) * 58, w = p.w - 40, h = 46 }
end

function Menu:dialogMetrics()
    local d = self.dialog
    local w = 640
    local lineCount = #(d.lines or {})
    local h = 70 + lineCount * 30 + 28 + 56 + 26
    return { x = (1024 - w) / 2, y = math.floor((768 - h) / 2), w = w, h = h, lineCount = lineCount }
end

function Menu:dialogButtonRects()
    local m = self:dialogMetrics()
    local n = #self.dialog.buttons
    local gap = 18
    local bw = math.min(190, (m.w - 40 - gap * (n - 1)) / n)
    local total = bw * n + gap * (n - 1)
    local x0 = m.x + (m.w - total) / 2
    local y = m.y + m.h - 26 - 56
    local rects = {}
    for i = 1, n do
        rects[i] = { x = x0 + (i - 1) * (bw + gap), y = y, w = bw, h = 56 }
    end
    return rects
end

-- ========================================================
-- DRAWING (table screen)
-- ========================================================

local function triangle(x, y, size, dir)
    -- dir = -1 points left, 1 points right
    love.graphics.polygon("fill", x, y - size, x, y + size, x + dir * size * 1.2, y)
end

function Menu:update(dt)
    self.time = self.time + dt
end

function Menu:draw(r)
    if not self.open then return end

    love.graphics.setColor(0, 0, 0, 0.62)
    love.graphics.rectangle("fill", 0, 0, r.width, r.height)

    if self.screen == "dialog" then
        self:drawDialog(r)
        return
    end

    local p = self:panelRect()
    Ui.panel(p.x, p.y, p.w, p.h)

    local titles = { main = self.title and "SOLITAIRE" or "PAUSED", options = "OPTIONS", controls = "CONTROLS", stats = "ALL-TIME STATS" }
    local title = titles[self.screen] or ""
    Ui.centered(r.fontTitle, title, p.x + p.w / 2, p.y + 18, Ui.colors.gold, Ui.colors.ink, 3)

    -- content above the item list
    if self.screen == "controls" then
        love.graphics.setFont(r.fontButton)
        for i, line in ipairs(CONTROL_LINES) do
            local y = p.y + 84 + (i - 1) * 28
            Ui.text(r.fontButton, line[1], p.x + 30, y, { 1, 0.92, 0.35 }, Ui.colors.ink, 1)
            Ui.text(r.fontButton, line[2], p.x + 270, y, { 1, 1, 1 }, Ui.colors.ink, 1)
        end
    elseif self.screen == "stats" then
        love.graphics.setFont(r.fontButton)
        for i, row in ipairs(Stats.rows(self.game.stats)) do
            local y = p.y + 84 + (i - 1) * 32
            Ui.text(r.fontButton, row[1], p.x + 40, y, { 1, 1, 1 }, Ui.colors.ink, 1)
            Ui.text(r.fontButton, row[2], p.x + p.w - 40 - r.fontButton:getWidth(row[2]), y, { 1, 0.92, 0.35 }, Ui.colors.ink, 1)
        end
    end

    -- items
    local items = self:items()
    for i, item in ipairs(items) do
        local rc = self:itemRect(i)
        local selected = (i == self.index)
        Ui.button(rc.x, rc.y, rc.w, rc.h, selected, selected and (0.5 + 0.5 * math.sin(self.time * 5)) or nil)
        local txt = selected and { 1, 1, 1 } or { 1, 1, 1 }
        local ink = selected and { 0.62, 0.30, 0.02 } or Ui.colors.ink
        if item.kind == "choice" then
            Ui.text(r.fontMedium, item.label, rc.x + 20, rc.y + 12, txt, ink, 2)
            local left = rc.x + rc.w - 330
            local right = rc.x + rc.w - 60
            love.graphics.setColor(1, 1, 1, 1)
            triangle(left + 12, rc.y + rc.h / 2, 9, -1)
            triangle(right + 22, rc.y + rc.h / 2, 9, 1)
            local val = item.value()
            local maxW = right - left - 50
            if r.fontButton:getWidth(val) > maxW then
                -- shorten long names so they stay between the arrows
                while #val > 3 and r.fontButton:getWidth(val .. "...") > maxW do val = val:sub(1, -2) end
                val = val .. "..."
            end
            Ui.text(r.fontButton, val, left + 50 + (maxW - r.fontButton:getWidth(val)) / 2, rc.y + 14, { 1, 1, 0.8 }, ink, 2)
        else
            Ui.text(r.fontMedium, item.label, rc.x + (rc.w - r.fontMedium:getWidth(item.label)) / 2, rc.y + 12, txt, ink, 2)
        end
    end

    -- one-line description of the highlighted item, under the box
    local cur = items[self.index]
    if cur and cur.desc and cur.desc ~= "" then
        local w = r.fontSmall:getWidth(cur.desc)
        Ui.text(r.fontSmall, cur.desc, (r.width - w) / 2, math.min(p.y + p.h + 16, r.height - 30), { 1, 1, 1 }, Ui.colors.ink, 2)
    end
end

function Menu:drawDialog(r)
    local d = self.dialog
    local m = self:dialogMetrics()

    Ui.panel(m.x, m.y, m.w, m.h)
    Ui.centered(r.fontTitle, d.title, m.x + m.w / 2, m.y + 16, d.accent and { d.accent[1], d.accent[2], d.accent[3] } or Ui.colors.gold, Ui.colors.ink, 3)

    for i, line in ipairs(d.lines or {}) do
        Ui.centered(r.fontButton, line, m.x + m.w / 2, m.y + 74 + (i - 1) * 30, { 1, 1, 1 }, Ui.colors.ink, 2)
    end

    local rects = self:dialogButtonRects()
    for i, b in ipairs(d.buttons) do
        local rc = rects[i]
        local selected = (i == self.index)
        Ui.button(rc.x, rc.y, rc.w, rc.h, selected, selected and (0.5 + 0.5 * math.sin(self.time * 5)) or nil)
        local ink = selected and { 0.62, 0.30, 0.02 } or Ui.colors.ink
        Ui.centered(r.fontButton, b.label, rc.x + rc.w / 2, rc.y + (rc.h - r.fontButton:getHeight()) / 2, { 1, 1, 1 }, ink, 2)
    end
end

-- ========================================================
-- TOP SCREEN VIEW
-- ========================================================

-- What the top screen shows while a menu or box is open: { title, subtitle, lines = { {left, right} or {text} } }
function Menu:topContent()
    if not self.open then return nil end
    local g = self.game

    if self.screen == "dialog" then
        local d = self.dialog
        local lines = {}
        for _, l in ipairs(d.lines or {}) do lines[#lines + 1] = { l } end
        return { title = d.title, lines = lines }
    elseif self.screen == "controls" then
        local lines = {}
        for _, l in ipairs(CONTROL_LINES) do lines[#lines + 1] = { l[1], l[2] } end
        return { title = "CONTROLS", lines = lines }
    elseif self.screen == "stats" then
        local lines = {}
        for _, row in ipairs(Stats.rows(g.stats)) do lines[#lines + 1] = { row[1], row[2] } end
        return { title = "ALL-TIME STATS", lines = lines }
    end

    local items = self:items()
    local item = items[self.index]
    local content = { title = (self.screen == "options") and "OPTIONS" or (self.title and "SOLITAIRE" or "PAUSED"), subtitle = item and item.desc or "" }
    if self.screen == "options" then
        local lines = {}
        for _, it in ipairs(items) do
            if it.kind == "choice" then lines[#lines + 1] = { it.label, it.value() } end
        end
        content.lines = lines
    end
    return content
end

-- Changes whenever the top screen needs to be redrawn
function Menu:key()
    if not self.open then return "closed" end
    local g = self.game
    return table.concat({
        self.screen, self.index, self.dialog and self.dialog.title or "",
        g.assets:musicLabel(), math.floor(g.assets.musicVolume * 100), math.floor(g.assets.sfxVolume * 100),
        g.background.selectedName or "", g.stats.gamesPlayed, g.stats.gamesWon,
        math.floor((g.settings.brightness or 1) * 100), self.title and "T" or "G",
    }, "|")
end

return Menu
