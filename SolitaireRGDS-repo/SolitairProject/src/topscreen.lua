-- TopScreen: drives the TOP panel of the RG DS Plus as a second SDL window.
--
-- LOVE can only open one window, so we ask SDL (through LuaJIT FFI) for a second
-- window on the other display. The top-screen picture is drawn with normal LOVE
-- drawing code into a Canvas, read back, and copied to that second window.
-- This only happens when the picture changes (about once a second), so it is cheap.
--
-- If anything fails the game keeps working on one screen (self.active stays false).

local ffi = require("ffi")

local TopScreen = {}
TopScreen.__index = TopScreen
TopScreen.SPEED = { 1, 0.75, 0.5, 0.35 }     -- share of the wanted pictures/s that is still sent

local CDEF = [[
    typedef struct SDL_Window SDL_Window;
    typedef struct SDL_Renderer SDL_Renderer;
    typedef struct SDL_Texture SDL_Texture;
    typedef void *SDL_GLContext;
    typedef struct { int x, y, w, h; } SDL_Rect;
    const char *SDL_GetError(void);
    int SDL_GetNumVideoDisplays(void);
    SDL_Window *SDL_GL_GetCurrentWindow(void);
    SDL_GLContext SDL_GL_GetCurrentContext(void);
    int SDL_GL_MakeCurrent(SDL_Window *window, SDL_GLContext context);
    int SDL_GetWindowDisplayIndex(SDL_Window *window);
    SDL_Window *SDL_CreateWindow(const char *title, int x, int y, int w, int h, uint32_t flags);
    void SDL_DestroyWindow(SDL_Window *window);
    SDL_Renderer *SDL_CreateRenderer(SDL_Window *window, int index, uint32_t flags);
    void SDL_DestroyRenderer(SDL_Renderer *renderer);
    uint32_t SDL_MasksToPixelFormatEnum(int bpp, uint32_t rmask, uint32_t gmask, uint32_t bmask, uint32_t amask);
    SDL_Texture *SDL_CreateTexture(SDL_Renderer *renderer, uint32_t format, int access, int w, int h);
    void SDL_DestroyTexture(SDL_Texture *texture);
    int SDL_UpdateTexture(SDL_Texture *texture, const SDL_Rect *rect, const void *pixels, int pitch);
    int SDL_RenderClear(SDL_Renderer *renderer);
    int SDL_RenderCopy(SDL_Renderer *renderer, SDL_Texture *texture, const SDL_Rect *src, const SDL_Rect *dst);
    void SDL_RenderPresent(SDL_Renderer *renderer);
]]

local function cstr(p)
    if p == nil then return "(null)" end
    return ffi.string(p)
end

function TopScreen.new(width, height)
    local self = setmetatable({}, TopScreen)
    self.active = false
    self.width = width or 1024
    self.height = height or 768
    self.lastKey = nil

    if os.getenv("DUAL_SCREEN") ~= "1" then
        print("TopScreen: disabled (single-screen launch)")
        return self
    end

    local ok, err = pcall(function() self:open() end)
    if not ok then
        print("TopScreen: FAILED, continuing on one screen: " .. tostring(err))
        self:close()
    end
    return self
end

function TopScreen:open()
    local okc, cerr = pcall(ffi.cdef, CDEF)
    if not okc then print("TopScreen: cdef note: " .. tostring(cerr)) end

    -- LOVE already loaded SDL2, so its functions are normally visible directly
    local sdl
    if pcall(function() return ffi.C.SDL_GetNumVideoDisplays end) then
        sdl = ffi.C
    else
        for _, name in ipairs({ "SDL2", "SDL2-2.0", "libSDL2-2.0.so.0", "/usr/lib/libSDL2-2.0.so.0" }) do
            local okL, lib = pcall(ffi.load, name)
            if okL then sdl = lib; break end
        end
    end
    if not sdl then error("cannot reach SDL2 from Lua") end
    self.sdl = sdl

    local n = sdl.SDL_GetNumVideoDisplays()
    if n < 2 then error("only " .. tostring(n) .. " display(s) detected") end

    self.loveWin = sdl.SDL_GL_GetCurrentWindow()
    self.loveCtx = sdl.SDL_GL_GetCurrentContext()
    if self.loveWin == nil then error("no current LOVE window") end

    local mine = sdl.SDL_GetWindowDisplayIndex(self.loveWin)
    local other = tonumber(os.getenv("TOP_DISPLAY_INDEX")) or ((mine == 0) and 1 or 0)
    print(string.format("TopScreen: LOVE window on SDL display %d, opening 2nd window on display %d", mine, other))

    -- SDL_WINDOWPOS_UNDEFINED_DISPLAY(n) = 0x1FFF0000 + n
    -- flags: FULLSCREEN_DESKTOP (0x1001) | OPENGL (0x2)
    local pos = 0x1FFF0000 + other
    self.win = sdl.SDL_CreateWindow("Solitaire top", pos, pos, self.width, self.height, 0x1003)
    if self.win == nil then error("SDL_CreateWindow: " .. cstr(sdl.SDL_GetError())) end

    self.ren = sdl.SDL_CreateRenderer(self.win, -1, 2) -- 2 = accelerated
    if self.ren == nil then error("SDL_CreateRenderer: " .. cstr(sdl.SDL_GetError())) end

    -- Byte order R,G,B,A in memory = what LOVE's ImageData uses
    local fmt = sdl.SDL_MasksToPixelFormatEnum(32, 0x000000FF, 0x0000FF00, 0x00FF0000, 0xFF000000)
    if fmt == 0 then error("no matching SDL pixel format") end
    self.tex = sdl.SDL_CreateTexture(self.ren, fmt, 0, self.width, self.height) -- 0 = static
    if self.tex == nil then error("SDL_CreateTexture: " .. cstr(sdl.SDL_GetError())) end

    -- Creating the renderer made its own GL context current; give LOVE its context back
    if sdl.SDL_GL_MakeCurrent(self.loveWin, self.loveCtx) ~= 0 then
        error("could not restore LOVE GL context: " .. cstr(sdl.SDL_GetError()))
    end

    self.canvas = love.graphics.newCanvas(self.width, self.height)
    self.active = true
    print("TopScreen: second screen ready")
end

-- Puts the pixels of the canvas on the second window. Returns true when it worked.
function TopScreen:present(data)
    local sdl = self.sdl
    local r1 = sdl.SDL_UpdateTexture(self.tex, nil, data:getPointer(), self.width * 4)
    local r2 = sdl.SDL_RenderClear(self.ren)
    local r3 = sdl.SDL_RenderCopy(self.ren, self.tex, nil, nil)
    sdl.SDL_RenderPresent(self.ren)
    if r1 ~= 0 or r2 ~= 0 or r3 ~= 0 then
        print(string.format("TopScreen: SDL returned UpdateTexture=%d RenderClear=%d RenderCopy=%d (%s)",
            r1, r2, r3, cstr(sdl.SDL_GetError())))
        return false
    end
    return true
end

-- Average brightness of a few pixels (0..255): 0 means the picture is black
local function sample(data)
    local sum, n = 0, 0
    for _, fx in ipairs({ 0.2, 0.5, 0.8 }) do
        for _, fy in ipairs({ 0.2, 0.5, 0.8 }) do
            local r, g, b = data:getPixel(math.floor(fx * (data:getWidth() - 1)), math.floor(fy * (data:getHeight() - 1)))
            sum = sum + (r + g + b) / 3 * 255
            n = n + 1
        end
    end
    return sum / n
end

-- Draws the top-screen picture when the game state changed. drawFn does the drawing;
-- fallbackFn (optional) is a plain picture used if drawFn fails, so the screen is never left black.
-- extraKey: any other text that changes what the picture shows (menu open, background name, ...)
function TopScreen:update(solitaire, drawFn, extraKey, fallbackFn, animate, dt)
    if not self.active then return end

    local now = love.timer.getTime()
    local found = 0
    for f = 1, 4 do found = found + #solitaire.foundations[f] end
    local key = table.concat({
        solitaire.score, solitaire.moves, math.floor(solitaire.time), found,
        solitaire.isWon and 1 or 0, extraKey or ""
    }, "|")

    local changed = (key ~= self.lastKey)

    -- Smooth animation: redraw the moving background several times a second. Copying a whole picture to the
    -- other screen is the expensive part, so the rate adapts: if drawing it costs too much time, or the
    -- bottom screen starts to lag, it steps down (30 -> 20 -> 12 -> 8 -> 4 pictures a second).
    local animFrame = false
    local rate = 0
    if animate then
        local tiers = TopScreen.SPEED
        self.tier = self.tier or 1
        local wanted = (type(animate) == "number") and animate or 15
        rate = wanted * tiers[self.tier]
        if now - (self.lastAnim or 0) >= 1 / rate - 0.004 then
            animFrame = true
            changed = true
        end
        if dt then
            self.dtSum = (self.dtSum or 0) + dt
            self.dtN = (self.dtN or 0) + 1
        end
    end
    local drawStart = now

    -- On this handheld SDL's KMSDRM drops the first frames it is given (Banana Player documents the same),
    -- so a picture that doesn't change must be sent again and again: every 0.1 s for the first 8 s after
    -- start (and for 2 s after any change), then every 2 s.
    self.freshUntil = self.freshUntil or (now + 8)
    if changed then self.freshUntil = math.max(self.freshUntil, now + 2) end
    local every = (now < self.freshUntil) and 0.1 or 2
    if not changed then
        if self.data and now - (self.lastPresent or 0) > every then
            self.lastPresent = now
            local sdl = self.sdl
            pcall(function() self:present(self.data) end)
            sdl.SDL_GL_MakeCurrent(self.loveWin, self.loveCtx)
        end
        return
    end
    self.lastKey = key
    self.lastPresent = now

    local sdl = self.sdl
    local ok, err = pcall(function()
        local function render(fn)
            love.graphics.push("all")
            love.graphics.setCanvas(self.canvas)
            love.graphics.origin()
            love.graphics.setScissor()
            love.graphics.setShader()
            love.graphics.setBlendMode("alpha")
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.clear(0, 0, 0, 1)
            local okd, errd = pcall(fn)
            love.graphics.pop()
            love.graphics.setCanvas()
            return okd, errd
        end

        -- 1) draw into the canvas with normal LOVE calls
        local okd, errd = render(drawFn)
        if not okd then
            self.drawErrors = (self.drawErrors or 0) + 1
            if self.drawErrors <= 3 then
                print("TopScreen: picture failed to draw, using plain background: " .. tostring(errd))
            end
            if fallbackFn then render(fallbackFn) end
        end

        -- 2) read the pixels back
        local data = self.canvas:newImageData()
        if self.data then self.data:release() end
        self.data = data

        -- 3) hand them to the second window (this switches the GL context...)
        local good = self:present(data)

        if not self.reported then
            self.reported = true
            print(string.format("TopScreen: first picture sent. brightness=%.1f/255 present=%s",
                sample(data), tostring(good)))
        end
    end)

    -- ...so always give LOVE its context back, even after an error
    sdl.SDL_GL_MakeCurrent(self.loveWin, self.loveCtx)

    if animFrame then
        self.lastAnim = now
        local cost = love.timer.getTime() - drawStart
        self.costSum = (self.costSum or 0) + cost
        self.costN = (self.costN or 0) + 1
        if self.costN >= 30 then
            local avgCost = self.costSum / self.costN
            local avgDt = (self.dtN and self.dtN > 0) and (self.dtSum / self.dtN) or 0
            local tiers = TopScreen.SPEED
            if (avgCost > 0.012 or avgDt > 0.026) and self.tier < #tiers then
                self.tier = self.tier + 1
                print(string.format("TopScreen: animation slowed to %.1f pictures/s (picture cost %.1f ms, frame %.1f ms)",
                    (type(animate) == "number" and animate or 15) * tiers[self.tier], avgCost * 1000, avgDt * 1000))
                self.good = 0
            elseif avgCost < 0.007 and avgDt < 0.020 then
                -- a long stretch without trouble: try a faster rate again
                self.good = (self.good or 0) + 1
                if self.good >= 8 and self.tier > 1 then
                    self.tier = self.tier - 1
                    self.good = 0
                end
            end
            self.costSum, self.costN, self.dtSum, self.dtN = 0, 0, 0, 0
        end
    end
    if not ok then
        self.errors = (self.errors or 0) + 1
        print("TopScreen: error (" .. self.errors .. "): " .. tostring(err))
        self.lastKey = nil           -- try again on the next frame
        if self.errors >= 20 then
            print("TopScreen: too many errors, turning second screen off")
            self.active = false
        end
    end
end

function TopScreen:close()
    local sdl = self.sdl
    if not sdl then return end
    if self.tex ~= nil then sdl.SDL_DestroyTexture(self.tex); self.tex = nil end
    if self.ren ~= nil then sdl.SDL_DestroyRenderer(self.ren); self.ren = nil end
    if self.win ~= nil then sdl.SDL_DestroyWindow(self.win); self.win = nil end
    if self.loveWin ~= nil then sdl.SDL_GL_MakeCurrent(self.loveWin, self.loveCtx) end
    self.active = false
end

return TopScreen
