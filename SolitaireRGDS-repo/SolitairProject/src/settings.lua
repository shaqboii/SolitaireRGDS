-- Settings: choices from the Options menu, remembered between sessions.
local Store = require("src.store")

local Settings = {}

local FILE = "settings.txt"
local DEFAULTS = {
    music = "auto",          -- "off", "auto" (first song found) or a file name
    musicVolume = 0.5,
    sfxVolume = 1.0,
    background = "auto",     -- "auto" or a picture's file name
    brightness = 1.0,        -- 0.05 .. 1.0 in steps of 0.05
    topAnimation = "on",     -- "on" or "off": the top-screen wallpaper keeps moving
}
local KEYS = { "music", "musicVolume", "sfxVolume", "background", "brightness", "topAnimation" }

function Settings.load()
    return Store.load(FILE, DEFAULTS)
end

function Settings.save(t)
    Store.save(FILE, t, KEYS)
end

return Settings
