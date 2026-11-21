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
    self.selectedName = "xmb_purple"
    self.sceneWanted = "purple"
    self:refresh()
    self:select("auto")
    return self
end

-- Scan assets/backgrounds for pictures the player can choose from
function Background:refresh()
    self.entries = {}
    for _, key in ipairs({ "purple", "green", "pink", "blue" }) do
        self.entries[#self.entries + 1] = { name = "xmb_" .. key, label = ({ purple = "XMB Purple", green = "XMB Green", pink = "XMB Rose", blue = "XMB Blue" })[key], kind = "procedural", key = key }
    end
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
    if pick.kind == "procedural" then self.sceneWanted = pick.key end
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
    return #self.customFrames > 1
end

-- ---------------------------------------------------------------------------------------------
-- Built-in scenes: four STILL backgrounds in the style of the PlayStation 3 home menu (XMB):
-- a soft gradient with a few wide, silky light waves. Each one is painted ONCE into a picture
-- and then just drawn, so it costs almost nothing (and the top screen never has to re-send it).
-- ---------------------------------------------------------------------------------------------

local XMB = {
    purple = { label = "XMB Purple",    top = {0.10, 0.03, 0.22}, mid = {0.36, 0.14, 0.58}, bot = {0.62, 0.30, 0.80}, wave = {0.85, 0.65, 1.00} },
    green  = { label = "XMB Green",     top = {0.02, 0.12, 0.10}, mid = {0.06, 0.38, 0.28}, bot = {0.25, 0.66, 0.42}, wave = {0.70, 1.00, 0.80} },
    pink   = { label = "XMB Rose",      top = {0.20, 0.03, 0.10}, mid = {0.62, 0.14, 0.32}, bot = {0.92, 0.38, 0.45}, wave = {1.00, 0.75, 0.78} },
    blue   = { label = "XMB Blue",      top = {0.02, 0.06, 0.20}, mid = {0.08, 0.30, 0.66}, bot = {0.30, 0.62, 0.92}, wave = {0.70, 0.88, 1.00} },
}
local XMB_ORDER = { "purple", "green", "pink", "blue" }

local function mix(a, b, t) return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t } end

local function gradientMesh(w, h, p)
    local verts = {}
    for i = 0, 8 do
        local t = i / 8
        local c = (t < 0.5) and mix(p.top, p.mid, t * 2) or mix(p.mid, p.bot, (t - 0.5) * 2)
        verts[#verts + 1] = { 0, t * h, 0, 0, c[1], c[2], c[3], 1 }
        verts[#verts + 1] = { w, t * h, 0, 0, c[1], c[2], c[3], 1 }
    end
    return love.graphics.newMesh(verts, "strip", "static")
end

-- one silky wave: a band that is bright in the middle and fades out at both edges
local function waveMesh(w, yBase, amp, half, f1, f2, phase, color, alpha)
    local verts = {}
    local steps = 48
    for i = 0, steps do
        local x = (i / steps) * w
        local u = i / steps
        local y = yBase + math.sin(u * math.pi * f1 + phase) * amp + math.sin(u * math.pi * f2 + phase * 1.7) * amp * 0.45
        local fade = math.sin(u * math.pi) ^ 0.6          -- thins out towards the screen edges
        local h = half * (0.35 + 0.65 * fade)
        verts[#verts + 1] = { x, y - h, 0, 0, color[1], color[2], color[3], 0 }
        verts[#verts + 1] = { x, y,     0, 0, color[1], color[2], color[3], alpha * fade }
        verts[#verts + 1] = { x, y + h, 0, 0, color[1], color[2], color[3], 0 }
    end
    -- build as three-wide strip rows -> triangles
    local tris = {}
    for i = 0, steps - 1 do
        local a = i * 3 + 1
        local b = a + 3
        tris[#tris + 1] = verts[a];     tris[#tris + 1] = verts[a + 1]; tris[#tris + 1] = verts[b]
        tris[#tris + 1] = verts[a + 1]; tris[#tris + 1] = verts[b + 1]; tris[#tris + 1] = verts[b]
        tris[#tris + 1] = verts[a + 1]; tris[#tris + 1] = verts[a + 2]; tris[#tris + 1] = verts[b + 1]
        tris[#tris + 1] = verts[a + 2]; tris[#tris + 1] = verts[b + 2]; tris[#tris + 1] = verts[b + 1]
    end
    return love.graphics.newMesh(tris, "triangles", "static")
end

local function paintScene(w, h, p)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(gradientMesh(w, h, p))
    love.graphics.setBlendMode("add")
    local waves = {
        { 0.58, 70, 220, 1.6, 3.1, 0.3, 0.16 },
        { 0.64, 55, 150, 2.1, 4.3, 1.9, 0.14 },
        { 0.52, 90, 260, 1.2, 2.6, 3.4, 0.10 },
        { 0.70, 40, 110, 2.8, 5.0, 5.0, 0.12 },
        { 0.46, 60, 180, 1.9, 3.7, 2.4, 0.07 },
    }
    for _, wv in ipairs(waves) do
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(waveMesh(w, wv[1] * h, wv[2], wv[3], wv[4], wv[5], wv[6], p.wave, wv[7]))
    end
    love.graphics.setBlendMode("alpha")
end

-- paints the chosen scene once into a picture (falls back to a plain gradient if that fails)
function Background:buildScene(key)
    local p = XMB[key] or XMB.purple
    self.scene = nil
    local ok, canvas = pcall(function()
        local c = love.graphics.newCanvas(self.width, self.height)
        local prev = love.graphics.getCanvas()
        love.graphics.push("all")
        love.graphics.setCanvas(c)
        love.graphics.clear(0, 0, 0, 1)
        paintScene(self.width, self.height, p)
        love.graphics.pop()
        love.graphics.setCanvas(prev)
        return c
    end)
    if ok and canvas then
        self.scene = { canvas = canvas }
    else
        print("Background: scene canvas failed, using a plain gradient: " .. tostring(canvas))
        local ok2, mesh = pcall(gradientMesh, self.width, self.height, p)
        self.scene = ok2 and { mesh = mesh } or { flat = p.mid }
    end
    self.sceneKey = key
end

function Background:drawScene()
    if not self.scene or self.sceneKey ~= self.sceneWanted then self:buildScene(self.sceneWanted) end
    local sc = self.scene
    love.graphics.setColor(1, 1, 1, 1)
    if sc.canvas then love.graphics.draw(sc.canvas, 0, 0)
    elseif sc.mesh then love.graphics.draw(sc.mesh)
    else
        love.graphics.setColor(sc.flat[1], sc.flat[2], sc.flat[3], 1)
        love.graphics.rectangle("fill", 0, 0, self.width, self.height)
    end
end

-- How many pictures a second the top screen should be sent (nil = it doesn't move)
function Background:animationFps()
    if #self.customFrames > 1 then return math.min(self.fps, 12) end
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
        self:drawScene()

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
