io.stdout:setvbuf("no")
print("Solitaire: Starting up on Love2D...")

local Solitaire = require("src.solitaire")
local Assets = require("src.assets")
local Background = require("src.background")
local Cursor = require("src.cursor")
local Renderer = require("src.renderer")
local TopScreen = require("src.topscreen")
local Settings = require("src.settings")
local Stats = require("src.stats")
local Game = require("src.game")

local solitaire
local assets
local background
local cursor
local renderer
local topscreen
local game
local settings
local stats
local lastTouchTime = -10
local crashed = false

-- Native panel resolution: 1024x768
local VIRTUAL_WIDTH = 1024
local VIRTUAL_HEIGHT = 768
local scale = 1
local offsetX = 0
local offsetY = 0

-- If something goes wrong, write the error to log.txt and quit instead of freezing on a blank screen
local function guard(name, fn)
    return function(...)
        if crashed then return end
        local ok, err = xpcall(fn, debug.traceback, ...)
        if not ok then
            crashed = true
            print("FATAL ERROR in " .. name .. ":\n" .. tostring(err))
            love.event.quit(1)
        end
    end
end

local function updateScaling()
    local winW, winH = love.graphics.getDimensions()
    scale = math.min(winW / VIRTUAL_WIDTH, winH / VIRTUAL_HEIGHT)
    offsetX = math.floor((winW - VIRTUAL_WIDTH * scale) / 2)
    offsetY = math.floor((winH - VIRTUAL_HEIGHT * scale) / 2)
end

local function toVirtualCoords(screenX, screenY)
    local vx = (screenX - offsetX) / scale
    local vy = (screenY - offsetY) / scale
    return vx, vy
end

love.load = guard("load", function()
    print("=== Display Enumeration ===")
    local displayCount = love.window.getDisplayCount()
    print("Total displays detected by SDL2: " .. tostring(displayCount))
    for i = 1, displayCount do
        local dw, dh = love.window.getDesktopDimensions(i)
        local dname = love.window.getDisplayName(i)
        print(string.format("  Display %d: %s (%dx%d)", i, dname or "unknown", dw or 0, dh or 0))
    end

    love.graphics.setDefaultFilter("linear", "linear")

    settings = Settings.load()
    stats = Stats.load()

    assets = Assets.new()
    assets:setSfxVolume(settings.sfxVolume)
    assets:setMusicVolume(settings.musicVolume)
    assets:setMusic(settings.music)

    background = Background.new(VIRTUAL_WIDTH, VIRTUAL_HEIGHT)
    if settings.background ~= "auto" then
        for _, e in ipairs(background.entries) do
            if e.name == settings.background then
                background:select(settings.background)
                break
            end
        end
    end

    solitaire = Solitaire.new()
    cursor = Cursor.new()
    renderer = Renderer.new(assets, background)

    game = Game.new({
        solitaire = solitaire, assets = assets, background = background,
        cursor = cursor, renderer = renderer, settings = settings, stats = stats,
    })

    -- Try to light up the top screen as a second window (only when launched in dual-screen mode)
    topscreen = TopScreen.new(VIRTUAL_WIDTH, VIRTUAL_HEIGHT)
    if topscreen.active then
        renderer.dualMode = true
    end

    updateScaling()
    game:applyBrightness()
    game:showTitle()      -- nothing is dealt until the player picks Continue or New game
    print("Solitaire: Ready to play!")
end)

love.resize = function(w, h)
    updateScaling()
end

love.update = guard("update", function(dt)
    dt = math.min(dt, 0.1)
    game:update(dt)
    background:update(dt)

    if topscreen and topscreen.active then
        topscreen:update(solitaire, function()
            background:draw(solitaire, renderer.fontTitle, renderer.fontMedium, renderer.fontSmall, true, game:topInfo())
        end, game:topKey(), function()
            background:drawPlain(solitaire, renderer.fontTitle, renderer.fontMedium, renderer.fontSmall, game:topInfo())
        end)
    end
end)

love.quit = function()
    if topscreen then pcall(function() topscreen:close() end) end
    return false
end

love.draw = guard("draw", function()
    love.graphics.push()
    love.graphics.translate(offsetX, offsetY)
    love.graphics.scale(scale, scale)

    renderer:draw(game)

    love.graphics.pop()
end)

-- ========================================================
-- INPUT ROUTING
-- ========================================================

love.gamepadpressed = guard("gamepadpressed", function(joystick, button)
    game.controls:gamepadpressed(joystick, button)
end)

love.gamepadreleased = guard("gamepadreleased", function(joystick, button)
    game.controls:gamepadreleased(joystick, button)
end)

love.keypressed = guard("keypressed", function(key)
    if key == "f11" then
        love.window.setFullscreen(not love.window.getFullscreen())
        updateScaling()
    else
        game.controls:keypressed(key)
    end
end)

love.keyreleased = guard("keyreleased", function(key)
    game.controls:keyreleased(key)
end)

-- Some systems send BOTH touch events and mouse events for one finger. If a real touch
-- event was seen a moment ago, ignore the mouse copy so every tap is handled once.
local function isTouchEcho(istouch)
    return istouch and (love.timer.getTime() - lastTouchTime) < 0.5
end

love.mousepressed = guard("mousepressed", function(x, y, button, istouch)
    if isTouchEcho(istouch) then return end
    local vx, vy = toVirtualCoords(x, y)
    game.controls:mousepressed(vx, vy, button)
end)

love.mousemoved = guard("mousemoved", function(x, y, dx, dy, istouch)
    if isTouchEcho(istouch) then return end
    local vx, vy = toVirtualCoords(x, y)
    game.controls:mousemoved(vx, vy)
end)

love.mousereleased = guard("mousereleased", function(x, y, button, istouch)
    if isTouchEcho(istouch) then return end
    local vx, vy = toVirtualCoords(x, y)
    game.controls:mousereleased(vx, vy, button)
end)

-- Touch coordinates may arrive as 0..1 fractions of the screen or as pixels
local function touchToVirtual(x, y)
    local winW, winH = love.graphics.getDimensions()
    local px = (x <= 1.0 and y <= 1.0) and (x * winW) or x
    local py = (x <= 1.0 and y <= 1.0) and (y * winH) or y
    return toVirtualCoords(px, py)
end

love.touchpressed = guard("touchpressed", function(id, x, y, dx, dy, pressure)
    lastTouchTime = love.timer.getTime()
    local vx, vy = touchToVirtual(x, y)
    game.controls:touchpressed(id, vx, vy)
end)

love.touchmoved = guard("touchmoved", function(id, x, y, dx, dy, pressure)
    lastTouchTime = love.timer.getTime()
    local vx, vy = touchToVirtual(x, y)
    game.controls:touchmoved(id, vx, vy)
end)

love.touchreleased = guard("touchreleased", function(id, x, y, dx, dy, pressure)
    lastTouchTime = love.timer.getTime()
    local vx, vy = touchToVirtual(x, y)
    game.controls:touchreleased(id, vx, vy)
end)
