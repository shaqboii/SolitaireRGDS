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

    self.entries = {}
    self.selectedName = "builtin"
    self:refresh()
    self:select("auto")
    return self
end

-- Scan assets/backgrounds for pictures the player can choose from
function Background:refresh()
    self.entries = { { name = "builtin", label = "Frutiger Aurora", kind = "procedural" } }
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

-- true when the picture changes by itself (the built-in scene, or an animated picture)
function Background:isAnimated()
    if #self.customFrames > 1 then return true end
    return #self.customFrames == 0 and self.customImage == nil
end

-- ---------------------------------------------------------------------------------------------
-- Built-in scene: "Frutiger Aurora" (glossy sky, drifting aurora ribbons, bubbles, soft hills).
-- Built once into pictures/meshes; each frame only draws a few big shapes, so it is cheap.
-- ---------------------------------------------------------------------------------------------

-- small repeatable random numbers (the scene looks the same every launch)
local function lcg(seed)
    local state = seed
    return function()
        state = (state * 1103515245 + 12345) % 2147483648
        return state / 2147483648
    end
end

local function verticalGradient(w, h, stops)
    local verts = {}
    for _, st in ipairs(stops) do
        local y = st[1] * h
        verts[#verts + 1] = { 0, y, 0, 0, st[2], st[3], st[4], 1 }
        verts[#verts + 1] = { w, y, 0, 0, st[2], st[3], st[4], 1 }
    end
    return love.graphics.newMesh(verts, "strip", "static")
end

-- a hill: a strip from a wavy crest down to the bottom edge
local function hill(w, h, baseY, amp, f1, f2, phase, crest, foot)
    local verts = {}
    local n = 32
    for i = 0, n do
        local x = i * w / n
        local y = baseY + amp * math.sin(i / n * f1 + phase) + amp * 0.4 * math.sin(i / n * f2 + phase * 2)
        verts[#verts + 1] = { x, y, 0, 0, crest[1], crest[2], crest[3], 1 }
        verts[#verts + 1] = { x, h, 0, 0, foot[1], foot[2], foot[3], 1 }
    end
    return love.graphics.newMesh(verts, "strip", "static")
end

-- one soft aurora ribbon: bright in the middle, fading to nothing at the top and bottom
local function ribbon(w, yBase, amp, halfWidth, phase, color, alpha)
    local verts = {}
    local n = 36
    local function point(i)
        local t = i / n
        local x = t * w
        local yc = yBase + amp * math.sin(t * 5.2 + phase) + amp * 0.5 * math.sin(t * 11 + phase * 1.7)
        local hw = halfWidth * (0.75 + 0.25 * math.sin(t * 7 + phase * 0.6))
        return x, yc, hw
    end
    for i = 0, n - 1 do
        local x1, y1, h1 = point(i)
        local x2, y2, h2 = point(i + 1)
        local c, a = color, alpha
        local function v(x, y, al) return { x, y, 0, 0, c[1], c[2], c[3], al } end
        -- upper half
        verts[#verts + 1] = v(x1, y1 - h1, 0); verts[#verts + 1] = v(x2, y2 - h2, 0); verts[#verts + 1] = v(x1, y1, a)
        verts[#verts + 1] = v(x2, y2 - h2, 0); verts[#verts + 1] = v(x2, y2, a);      verts[#verts + 1] = v(x1, y1, a)
        -- lower half
        verts[#verts + 1] = v(x1, y1, a);      verts[#verts + 1] = v(x2, y2, a);      verts[#verts + 1] = v(x1, y1 + h1, 0)
        verts[#verts + 1] = v(x2, y2, a);      verts[#verts + 1] = v(x2, y2 + h2, 0); verts[#verts + 1] = v(x1, y1 + h1, 0)
    end
    return love.graphics.newMesh(verts, "triangles", "static")
end

function Background:buildAurora()
    local W, H = self.width, self.height
    local rnd = lcg(2007)
    local scene = {}

    -- the still part (sky, sun rays, clouds, bubbles, hills) is drawn once into a picture
    local base = love.graphics.newCanvas(W, H)
    local prev = love.graphics.getCanvas()
    love.graphics.setCanvas(base)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setBlendMode("alpha")

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(verticalGradient(W, H, {
        { 0.00, 0.10, 0.45, 0.85 },     -- deep sky blue
        { 0.40, 0.30, 0.72, 0.95 },
        { 0.66, 0.62, 0.92, 0.95 },     -- pale aqua
        { 0.82, 0.80, 0.97, 0.70 },     -- lime glow at the horizon
        { 1.00, 0.55, 0.90, 0.55 },
    }))

    -- soft light rays from the top left
    for i = 1, 6 do
        local a0 = 0.10 + i * 0.13
        love.graphics.setColor(1, 1, 1, 0.05 + 0.02 * (i % 2))
        love.graphics.polygon("fill", W * 0.05, -20, W * (a0 - 0.05), H, W * (a0 + 0.04), H)
    end

    -- clouds: stacked translucent circles give soft edges
    for c = 1, 7 do
        local cx, cy = rnd() * W, 120 + rnd() * 300
        local size = 40 + rnd() * 50
        for puff = 1, 6 do
            local px = cx + (puff - 3.5) * size * 0.8
            local py = cy + math.sin(puff * 1.7) * size * 0.25
            local r = size * (0.7 + 0.5 * math.sin(puff * 2.1) ^ 2)
            for layer = 1, 3 do
                love.graphics.setColor(1, 1, 1, 0.10)
                love.graphics.circle("fill", px, py, r * (1.35 - layer * 0.25))
            end
        end
    end

    -- glossy bubbles
    for _ = 1, 22 do
        local bx, by = rnd() * W, 60 + rnd() * 560
        local br = 12 + rnd() * rnd() * 70
        love.graphics.setColor(1, 1, 1, 0.07)
        love.graphics.circle("fill", bx, by, br)
        love.graphics.setColor(1, 1, 1, 0.45)
        love.graphics.setLineWidth(2)
        love.graphics.circle("line", bx, by, br)
        love.graphics.setColor(1, 1, 1, 0.55)
        love.graphics.ellipse("fill", bx - br * 0.35, by - br * 0.4, br * 0.28, br * 0.16)
    end

    -- rolling hills at the bottom
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(hill(W, H, H * 0.86, 26, 5.0, 9.0, 0.6, { 0.45, 0.85, 0.55 }, { 0.20, 0.62, 0.40 }))
    love.graphics.draw(hill(W, H, H * 0.92, 20, 4.0, 8.0, 2.4, { 0.32, 0.75, 0.42 }, { 0.12, 0.50, 0.32 }))

    love.graphics.setCanvas(prev)
    scene.base = base

    -- two sets of aurora ribbons; the picture fades between them to make the light drift
    local colors = {
        { 0.25, 1.00, 0.85 },   -- teal
        { 0.60, 1.00, 0.55 },   -- green
        { 0.40, 0.70, 1.00 },   -- blue
        { 0.80, 0.65, 1.00 },   -- violet
    }
    scene.layers = {}
    for layer = 1, 2 do
        local meshes = {}
        for i, col in ipairs(colors) do
            local phase = (i * 1.3) + (layer - 1) * 2.4
            meshes[i] = ribbon(W, 110 + i * 62, 34 + i * 6, 70 + i * 8, phase, col, 0.34)
        end
        scene.layers[layer] = meshes
    end
    self.scene = scene
end

-- draws the Frutiger Aurora scene; falls back to a plain gradient if the pieces can't be built
function Background:drawAurora()
    if not self.scene and not self.sceneFailed then
        local ok, err = pcall(self.buildAurora, self)
        if not ok then
            self.sceneFailed = true
            print("Background: aurora scene failed, using a plain gradient: " .. tostring(err))
        end
    end
    if not self.scene then
        love.graphics.setColor(0.25, 0.65, 0.9, 1)
        love.graphics.rectangle("fill", 0, 0, self.width, self.height)
        return
    end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.scene.base, 0, 0)

    -- slow breathing between the two ribbon sets
    local k = 0.5 + 0.5 * math.sin(self.time * 0.45)
    love.graphics.setBlendMode("add")
    for layer = 1, 2 do
        local alpha = (layer == 1) and (1 - k) or k
        love.graphics.setColor(1, 1, 1, 0.25 + 0.75 * alpha)
        for _, m in ipairs(self.scene.layers[layer]) do love.graphics.draw(m) end
    end
    love.graphics.setBlendMode("alpha")
end

-- How many pictures a second the top screen should be sent (nil = it doesn't move)
function Background:animationFps()
    if #self.customFrames > 1 then return math.min(self.fps, 12) end
    if #self.customFrames == 0 and self.customImage == nil then return 8 end
    return nil
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
        self:drawAurora()

        love.graphics.setFont(fontTitle)
        local titleText = "KLONDIKE SOLITAIRE"
        local tw = fontTitle:getWidth(titleText)
        local titleY = 100

        love.graphics.setColor(0.0, 0.25, 0.4, 0.45)
        love.graphics.print(titleText, (self.width - tw) / 2 + 2, titleY + 3)

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(titleText, (self.width - tw) / 2, titleY)

        love.graphics.setFont(fontSmall)
        local sub = "ANBERNIC RG DS PLUS • BANANA OS"
        local sw = fontSmall:getWidth(sub)
        love.graphics.setColor(0.9, 1, 1, 0.95)
        love.graphics.print(sub, (self.width - sw) / 2, titleY + 54)
    end

    -- 2. Glassmorphic Statistics Panel (HUD)
    local panelW = 860
    local panelH = 130
    local panelX = (self.width - panelW) / 2
    local panelY = 460

    local aurora = (#self.customFrames == 0 and self.customImage == nil)
    if aurora then
        love.graphics.setColor(0.04, 0.22, 0.38, 0.55)        -- frosted glass
    else
        love.graphics.setColor(0.05, 0.08, 0.14, 0.75)
    end
    love.graphics.rectangle("fill", panelX, panelY, panelW, panelH, 16, 16)
    if aurora then
        love.graphics.setColor(0.85, 1, 1, 0.75)
    else
        love.graphics.setColor(0.35, 0.55, 0.85, 0.6)
    end
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
