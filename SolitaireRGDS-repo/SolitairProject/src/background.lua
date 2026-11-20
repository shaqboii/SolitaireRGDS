local Library = require("src.library")

local Background = {}
Background.__index = Background

function Background.new(width, height)
    local self = setmetatable({}, Background)
    self.width = width or 1024
    self.height = height or 768
    self.time = 0

    self.customImage = nil
    self.customFrames = {}
    self.currentFrame = 1
    self.frameTimer = 0
    self.fps = 20

    -- Procedural ambient particles (Wallpaper Engine aesthetic)
    self.particles = {}
    self:initParticles(35)

    self.entries = {}
    self.selectedName = "builtin"
    self:refresh()
    self:select("auto")
    return self
end

function Background:initParticles(count)
    local colors = {
        {"♥", {0.85, 0.2, 0.25, 0.35}},
        {"♦", {0.9, 0.35, 0.15, 0.35}},
        {"♣", {0.3, 0.45, 0.7, 0.35}},
        {"♠", {0.45, 0.35, 0.75, 0.35}}
    }

    for i = 1, count do
        local pick = colors[love.math.random(#colors)]
        table.insert(self.particles, {
            symbol = pick[1],
            color = pick[2],
            x = love.math.random(0, self.width),
            y = love.math.random(0, self.height),
            vx = (love.math.random() - 0.5) * 20,
            vy = -love.math.random(15, 45),
            size = love.math.random(18, 48),
            rotation = love.math.random() * math.pi * 2,
            vRot = (love.math.random() - 0.5) * 1.5,
            alpha = love.math.random(25, 60) / 100
        })
    end
end

-- Scan assets/backgrounds for pictures the player can choose from
function Background:refresh()
    self.entries = { { name = "builtin", label = "Built-in scene", kind = "procedural" } }
    for _, e in ipairs(Library.list("backgrounds", { "png", "jpg", "jpeg" })) do
        self.entries[#self.entries + 1] = { name = e.name, label = e.label, kind = "image", entry = e }
    end
    local frames = Library.list("backgrounds/animated", { "png", "jpg", "jpeg" })
    if #frames > 0 then
        self.entries[#self.entries + 1] = { name = "animated", label = "Animated", kind = "frames", frames = frames }
    end
end

-- name: "auto" or an entry name. Auto = animated frames if present, else top_bg.*, else the first picture.
function Background:select(name)
    local pick = nil
    if name == "auto" or name == nil then
        for _, e in ipairs(self.entries) do
            if e.kind == "frames" then pick = e end
        end
        if not pick then
            for _, e in ipairs(self.entries) do
                if e.kind == "image" and e.name:lower():match("^top_bg%.") then pick = e break end
            end
        end
        if not pick then
            for _, e in ipairs(self.entries) do
                if e.kind == "image" then pick = e break end
            end
        end
    else
        for _, e in ipairs(self.entries) do
            if e.name == name then pick = e end
        end
    end
    pick = pick or self.entries[1]

    self.customImage = nil
    self.customFrames = {}
    self.currentFrame = 1
    self.frameTimer = 0

    if pick.kind == "image" then
        local ok, img = pcall(Library.loadImage, pick.entry)
        if ok and img then
            self.customImage = img
        else
            print("Background: could not load " .. pick.name .. ": " .. tostring(img))
            pick = self.entries[1]
        end
    elseif pick.kind == "frames" then
        for _, f in ipairs(pick.frames) do
            local ok, img = pcall(Library.loadImage, f)
            if ok and img then table.insert(self.customFrames, img) end
        end
        if #self.customFrames == 0 then pick = self.entries[1] end
    end
    self.selectedName = pick.name
    self.selectedLabel = pick.label
    print("Background: using '" .. pick.name .. "'")
    return pick.name
end

function Background:cycle(dir)
    local idx = 1
    for i, e in ipairs(self.entries) do
        if e.name == self.selectedName then idx = i end
    end
    idx = ((idx - 1 + dir) % #self.entries) + 1
    return self:select(self.entries[idx].name)
end

-- Draw a picture so it fills w x h (keeps proportions, crops the overflow)
local function drawCover(img, w, h)
    local iw, ih = img:getDimensions()
    local sc = math.max(w / iw, h / ih)
    love.graphics.draw(img, (w - iw * sc) / 2, (h - ih * sc) / 2, 0, sc, sc)
end

function Background:update(dt)
    self.time = self.time + dt

    if #self.customFrames > 1 then
        self.frameTimer = self.frameTimer + dt
        if self.frameTimer >= (1 / self.fps) then
            self.frameTimer = self.frameTimer - (1 / self.fps)
            self.currentFrame = (self.currentFrame % #self.customFrames) + 1
        end
    end

    for _, p in ipairs(self.particles) do
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        p.rotation = p.rotation + p.vRot * dt

        if p.y < -50 then
            p.y = self.height + 40
            p.x = love.math.random(0, self.width)
        elseif p.y > self.height + 50 then
            p.y = -40
        end

        if p.x < -50 then p.x = self.width + 40 end
        if p.x > self.width + 50 then p.x = -40 end
    end
end

-- Cache fonts by size (the old code created a new font for every particle on every frame)
function Background:getFont(size)
    self.fontCache = self.fontCache or {}
    local f = self.fontCache[size]
    if not f then
        f = love.graphics.newFont(size)
        self.fontCache[size] = f
    end
    return f
end

-- topMode = true when this is drawn onto the dedicated top screen (not the single-screen wallpaper view)
function Background:draw(solitaire, fontTitle, fontMedium, fontSmall, topMode, info)
    love.graphics.push()

    -- 1. Draw Custom Background or Procedural Ambient Scene
    if #self.customFrames > 0 then
        local frame = self.customFrames[self.currentFrame]
        love.graphics.setColor(1, 1, 1, 1)
        drawCover(frame, self.width, self.height)
    elseif self.customImage then
        love.graphics.setColor(1, 1, 1, 1)
        drawCover(self.customImage, self.width, self.height)
    else
        local steps = 32
        local hStep = self.height / steps
        for i = 0, steps do
            local t = i / steps
            local wave = math.sin(self.time * 0.8 + t * 4) * 0.05
            local r = 0.04 + 0.03 * math.sin(self.time * 0.5 + t * 2)
            local g = 0.12 + 0.08 * math.sin(self.time * 0.4 + t * 3 + 1) + wave
            local b = 0.22 + 0.15 * math.cos(self.time * 0.6 + t * 2)
            love.graphics.setColor(r, g, b, 1)
            love.graphics.rectangle("fill", 0, i * hStep, self.width, hStep + 1)
        end

        for _, p in ipairs(self.particles) do
            local pulse = math.sin(self.time * 2 + p.x) * 0.15
            love.graphics.setColor(p.color[1], p.color[2], p.color[3], math.max(0.1, p.alpha + pulse))
            local pFont = self:getFont(p.size)
            love.graphics.setFont(pFont)
            local sw = pFont:getWidth(p.symbol)
            local sh = pFont:getHeight()
            love.graphics.print(p.symbol, p.x, p.y, p.rotation, 1, 1, sw / 2, sh / 2)
        end

        love.graphics.setFont(fontTitle)
        local titleText = "KLONDIKE SOLITAIRE"
        local tw = fontTitle:getWidth(titleText)
        local titleY = 100

        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.print(titleText, (self.width - tw) / 2 + 2, titleY + 2)

        love.graphics.setColor(0.95, 0.82, 0.35, 1)
        love.graphics.print(titleText, (self.width - tw) / 2, titleY)

        love.graphics.setFont(fontSmall)
        local sub = "ANBERNIC RG DS PLUS • BANANA OS"
        local sw = fontSmall:getWidth(sub)
        love.graphics.setColor(0.8, 0.85, 0.95, 0.8)
        love.graphics.print(sub, (self.width - sw) / 2, titleY + 54)
    end

    -- 2. Glassmorphic Statistics Panel (HUD)
    local panelW = 860
    local panelH = 130
    local panelX = (self.width - panelW) / 2
    local panelY = 460

    love.graphics.setColor(0.05, 0.08, 0.14, 0.75)
    love.graphics.rectangle("fill", panelX, panelY, panelW, panelH, 16, 16)
    love.graphics.setColor(0.35, 0.55, 0.85, 0.6)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", panelX, panelY, panelW, panelH, 16, 16)

    local minutes = math.floor(solitaire.time / 60)
    local seconds = math.floor(solitaire.time % 60)
    local timeStr = string.format("%02d:%02d", minutes, seconds)

    local totalInFoundations = 0
    for f = 1, 4 do totalInFoundations = totalInFoundations + #solitaire.foundations[f] end

    local stats = {
        {label = "SCORE", val = tostring(solitaire.score), color = {0.98, 0.85, 0.3}},
        {label = "TIME", val = timeStr, color = {0.4, 0.85, 0.95}},
        {label = "MOVES", val = tostring(solitaire.moves), color = {0.75, 0.95, 0.55}},
        {label = "FOUNDATIONS", val = string.format("%d / 52", totalInFoundations), color = {0.95, 0.65, 0.85}}
    }

    local colW = panelW / #stats
    for i, s in ipairs(stats) do
        local cx = panelX + (i - 1) * colW
        love.graphics.setFont(fontSmall)
        love.graphics.setColor(0.7, 0.75, 0.85, 0.9)
        local lw = fontSmall:getWidth(s.label)
        love.graphics.print(s.label, cx + (colW - lw) / 2, panelY + 20)

        love.graphics.setFont(fontMedium)
        love.graphics.setColor(s.color[1], s.color[2], s.color[3], 1)
        local vw = fontMedium:getWidth(s.val)
        love.graphics.print(s.val, cx + (colW - vw) / 2, panelY + 56)

        if i < #stats then
            love.graphics.setColor(1, 1, 1, 0.15)
            love.graphics.line(cx + colW, panelY + 16, cx + colW, panelY + panelH - 16)
        end
    end

    -- 3. Bottom Controls / Return helper
    local pillW = 860
    local pillH = 46
    local pillX = (self.width - pillW) / 2
    local pillY = 660

    love.graphics.setColor(0.05, 0.08, 0.12, 0.85)
    love.graphics.rectangle("fill", pillX, pillY, pillW, pillH, 10, 10)
    love.graphics.setColor(0.4, 0.65, 0.85, 0.7)
    love.graphics.rectangle("line", pillX, pillY, pillW, pillH, 10, 10)

    love.graphics.setFont(fontSmall)
    love.graphics.setColor(1, 0.92, 0.4, 1)
    local helper = "Tap anywhere or press L2 to return to the Solitaire table"
    if topMode then
        helper = "Play on the bottom screen   |   START opens the menu"
    end
    local hw = fontSmall:getWidth(helper)
    love.graphics.print(helper, (self.width - hw) / 2, pillY + 14)

    -- Now-playing line (top screen only)
    if topMode and info and info.nowPlaying then
        love.graphics.setFont(fontSmall)
        local np = "Music: " .. info.nowPlaying
        local nw = fontSmall:getWidth(np)
        love.graphics.setColor(0, 0, 0, 0.45)
        love.graphics.rectangle("fill", self.width - nw - 36, 14, nw + 24, 28, 8, 8)
        love.graphics.setColor(0.9, 0.95, 1, 0.9)
        love.graphics.print(np, self.width - nw - 24, 18)
    end

    -- Win celebration banner
    if solitaire.isWon then
        local winW = 700
        local winH = 180
        local winX = (self.width - winW) / 2
        local winY = 220

        love.graphics.setColor(0.08, 0.12, 0.08, 0.94)
        love.graphics.rectangle("fill", winX, winY, winW, winH, 20, 20)
        love.graphics.setColor(0.9, 0.8, 0.2, 0.9)
        love.graphics.setLineWidth(4)
        love.graphics.rectangle("line", winX, winY, winW, winH, 20, 20)

        love.graphics.setFont(fontTitle)
        local winText = "VICTORY!"
        local wtw = fontTitle:getWidth(winText)
        love.graphics.setColor(1, 0.9, 0.3, 1)
        love.graphics.print(winText, (self.width - wtw) / 2, winY + 30)

        love.graphics.setFont(fontMedium)
        local subWin = "Press START on the bottom screen for a new game"
        local sww = fontMedium:getWidth(subWin)
        love.graphics.setColor(0.9, 0.95, 1, 0.95)
        love.graphics.print(subWin, (self.width - sww) / 2, winY + 105)
    end

    -- Best-of line under the stats panel
    if topMode and info and info.best then
        love.graphics.setFont(fontSmall)
        local bw = fontSmall:getWidth(info.best)
        love.graphics.setColor(0, 0, 0, 0.45)
        love.graphics.rectangle("fill", (self.width - bw) / 2 - 14, 606, bw + 28, 30, 8, 8)
        love.graphics.setColor(0.95, 0.9, 0.65, 0.95)
        love.graphics.print(info.best, (self.width - bw) / 2, 612)
    end

    -- Menu / box mirror (the menu itself is on the bottom screen)
    if info and info.overlay then
        local o = info.overlay
        love.graphics.setColor(0, 0, 0, 0.62)
        love.graphics.rectangle("fill", 0, 0, self.width, self.height)

        local lines = o.lines or {}
        local rowH = 34
        local panelW = 760
        local contentH = #lines * rowH
        local panelH = 110 + contentH + ((o.subtitle and o.subtitle ~= "") and 44 or 0) + 24
        panelH = math.min(panelH, self.height - 40)
        local px = (self.width - panelW) / 2
        local py = math.floor((self.height - panelH) / 2)

        love.graphics.setColor(0.07, 0.09, 0.15, 0.95)
        love.graphics.rectangle("fill", px, py, panelW, panelH, 18, 18)
        love.graphics.setColor(0.4, 0.6, 0.9, 0.9)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", px, py, panelW, panelH, 18, 18)

        love.graphics.setFont(fontTitle)
        local tw = fontTitle:getWidth(o.title or "")
        love.graphics.setColor(1, 0.92, 0.45, 1)
        love.graphics.print(o.title or "", (self.width - tw) / 2, py + 22)

        local y = py + 90
        if o.subtitle and o.subtitle ~= "" then
            love.graphics.setFont(fontMedium)
            local stw = fontMedium:getWidth(o.subtitle)
            love.graphics.setColor(0.85, 0.92, 1, 0.95)
            love.graphics.print(o.subtitle, (self.width - stw) / 2, y)
            y = y + 44
        end

        love.graphics.setFont(fontMedium)
        for _, line in ipairs(lines) do
            if line[2] then
                love.graphics.setColor(0.55, 0.85, 1, 1)
                love.graphics.print(line[1], px + 40, y)
                love.graphics.setColor(1, 0.92, 0.5, 1)
                love.graphics.print(line[2], px + 300, y)
            else
                local lw = fontMedium:getWidth(line[1])
                love.graphics.setColor(0.9, 0.95, 1, 1)
                love.graphics.print(line[1], (self.width - lw) / 2, y)
            end
            y = y + rowH
        end
    end

    -- Software brightness (only used when the real backlight can't be changed)
    if info and info.dim and info.dim > 0 then
        love.graphics.setColor(0, 0, 0, info.dim)
        love.graphics.rectangle("fill", 0, 0, self.width, self.height)
    end

    love.graphics.pop()
end

-- Same picture without the custom wallpaper: the safety net if the wallpaper or an overlay breaks drawing
function Background:drawPlain(solitaire, fontTitle, fontMedium, fontSmall, info)
    local img, frames = self.customImage, self.customFrames
    self.customImage, self.customFrames = nil, {}
    local ok, err = pcall(self.draw, self, solitaire, fontTitle, fontMedium, fontSmall, true, info)
    self.customImage, self.customFrames = img, frames
    if not ok then
        print("Background: plain draw failed too: " .. tostring(err))
        love.graphics.setColor(0.05, 0.15, 0.25, 1)
        love.graphics.rectangle("fill", 0, 0, self.width, self.height)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setFont(fontTitle)
        love.graphics.print(string.format("Score %d   Moves %d   Time %d:%02d", solitaire.score, solitaire.moves,
            math.floor(solitaire.time / 60), math.floor(solitaire.time % 60)), 80, 340)
    end
end

return Background
