-- Fonts: uses your own TTF/OTF for the whole UI if one is in assets/fonts/, else LÖVE's built-in font.
--   Put the file at  <game folder>/assets/fonts/  (e.g. ui.ttf). "ui.ttf/otf" is preferred, otherwise
--   the first .ttf/.otf found (alphabetical). No rebuild of Solitaire.love needed.
local Library = require("src.library")

local Fonts = {}
local data, tried, cache = nil, false, {}

local function findFont()
    tried = true
    local ok, list = pcall(Library.list, "fonts", { "ttf", "otf" })
    if not ok or not list or #list == 0 then return end
    local pick = list[1]
    for _, e in ipairs(list) do
        if e.name:lower():match("^ui%.[to]tf$") then pick = e break end
    end
    local ok2, fd = pcall(function()
        if pick.external then
            local f = io.open(pick.path, "rb")
            if not f then return nil end
            local bytes = f:read("*a")
            f:close()
            return love.filesystem.newFileData(bytes, pick.name)
        end
        return love.filesystem.newFileData(pick.path)
    end)
    if ok2 and fd then
        data = fd
        print("Fonts: using custom font " .. pick.name)
    else
        print("Fonts: could not read " .. pick.name)
    end
end

-- A font of the given pixel size (cached). Falls back to the default font on any problem.
function Fonts.get(size)
    if cache[size] then return cache[size] end
    if not tried then findFont() end
    local font
    if data then
        local ok, f = pcall(love.graphics.newFont, data, size)
        if ok and f then
            font = f
            -- symbols the custom font lacks come from the default font instead of empty boxes
            pcall(function() f:setFallbacks(love.graphics.newFont(size)) end)
        else
            print("Fonts: custom font failed to load, using default: " .. tostring(f))
            data = nil
        end
    end
    font = font or love.graphics.newFont(size)
    cache[size] = font
    return font
end

return Fonts
