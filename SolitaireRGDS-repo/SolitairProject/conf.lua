function love.conf(t)
    t.identity = "SolitaireRGDS"
    t.version = "11.5"
    t.console = true

    t.window.title = "Solitaire - RG DS Plus (BananaOS)"
    t.window.icon = nil

    -- Native single-screen resolution (each panel is 1024x768)
    t.window.width = 1024
    t.window.height = 768
    t.window.borderless = true
    t.window.resizable = false
    t.window.minwidth = 1024
    t.window.minheight = 768

    -- Target display can be overridden via environment variable LOVE_TARGET_DISPLAY
    local envDisplay = os.getenv("LOVE_TARGET_DISPLAY")
    t.window.display = tonumber(envDisplay) or 1

    local os = love.system and love.system.getOS() or "Linux"
    if os == "Linux" then
        t.window.fullscreen = true
    else
        t.window.fullscreen = false
    end

    t.window.fullscreentype = "desktop"
    t.window.vsync = 1
    t.window.msaa = 0

    t.modules.audio = true
    t.modules.data = true
    t.modules.event = true
    t.modules.font = true
    t.modules.graphics = true
    t.modules.image = true
    t.modules.joystick = true
    t.modules.keyboard = true
    t.modules.math = true
    t.modules.mouse = true
    t.modules.physics = false
    t.modules.sound = true
    t.modules.system = true
    t.modules.thread = false
    t.modules.timer = true
    t.modules.touch = true
    t.modules.video = false
    t.modules.window = true
end
