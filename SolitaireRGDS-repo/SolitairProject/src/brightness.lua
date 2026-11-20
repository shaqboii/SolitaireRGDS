-- Brightness: sets the screen backlight in 5% steps.
--
-- It writes to /sys/class/backlight/*/brightness (works because the launcher runs as root).
-- If the device does not allow that, apply() returns false and the game dims the picture
-- itself (software dimming) so the option still does something.

local Brightness = {}

Brightness.STEP = 0.05
Brightness.MIN = 0.05

local lights = nil

local function scan()
    lights = {}
    local ok, p = pcall(io.popen, "ls -1 /sys/class/backlight 2>/dev/null")
    if not ok or not p then return end
    for name in p:lines() do
        local dir = "/sys/class/backlight/" .. name
        local f = io.open(dir .. "/max_brightness", "r")
        if f then
            local max = tonumber(f:read("*l"))
            f:close()
            if max and max > 0 then lights[#lights + 1] = { dir = dir, max = max } end
        end
    end
    p:close()
end

function Brightness.clamp(v)
    v = math.floor(v / Brightness.STEP + 0.5) * Brightness.STEP
    if v < Brightness.MIN then v = Brightness.MIN end
    if v > 1 then v = 1 end
    return math.floor(v * 100 + 0.5) / 100
end

-- BananaOS keeps both panels' levels in /data/banana/backlight ("<top> <bottom>", thousandths of the maximum)
-- and restores them at boot. It throws that file away if a level is under 10%, so 5% is only written to the
-- backlights themselves, never to that file.
local STORE = "/data/banana/backlight"

local function writeStore(permille)
    if permille < 100 then return end
    local f = io.open(STORE, "w")
    if f then f:write(string.format("%d %d\n", permille, permille)); f:close() end
end

-- level: 0.05 .. 1. Returns true if at least one real backlight was changed.
function Brightness.apply(level)
    if not lights then scan() end
    local changed = 0
    for _, l in ipairs(lights) do
        local f = io.open(l.dir .. "/brightness", "w")
        if f then
            local value = math.max(1, math.floor(l.max * level + 0.5))
            local okw = f:write(tostring(value))
            f:close()
            if okw then changed = changed + 1 end
        end
    end
    if changed > 0 then writeStore(math.floor(level * 1000 + 0.5)) end
    return changed > 0, #lights
end

return Brightness
