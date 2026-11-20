-- Library: finds user-added files (music, backgrounds) in assets/<kind>/.
--
-- It looks in two places so you can add files WITHOUT rebuilding Solitaire.love:
--   1. inside the game (the .love file / game folder)
--   2. the real folder next to Solitaire.love:  <game folder>/assets/<kind>/
-- A file with the same name in the real folder wins over the one inside the .love.

local Library = {}

local function ext(name)
    return (name:match("%.([^.]+)$") or ""):lower()
end

local function pretty(name)
    local n = name:gsub("%.[^.]+$", "")
    n = n:gsub("[_%-]+", " ")
    return n
end

local function shellQuote(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

-- Returns a sorted array of { name=, label=, path=, external= }
function Library.list(kind, exts)
    local set = {}
    for _, e in ipairs(exts) do set[e] = true end

    local byName, order = {}, {}
    local function add(entry)
        if not byName[entry.name] then order[#order + 1] = entry.name end
        byName[entry.name] = entry
    end

    -- 1. inside the game
    local dir = "assets/" .. kind
    local okInfo, info = pcall(love.filesystem.getInfo, dir)
    if okInfo and info then
        for _, f in ipairs(love.filesystem.getDirectoryItems(dir)) do
            if set[ext(f)] then
                add({ name = f, label = pretty(f), path = dir .. "/" .. f, external = false })
            end
        end
    end

    -- 2. real folder next to the .love file
    local okBase, base = pcall(love.filesystem.getSourceBaseDirectory)
    if okBase and base and base ~= "" then
        local extDir = base .. "/assets/" .. kind
        local okP, p = pcall(io.popen, "ls -1 " .. shellQuote(extDir) .. " 2>/dev/null")
        if okP and p then
            for line in p:lines() do
                if set[ext(line)] then
                    add({ name = line, label = pretty(line), path = extDir .. "/" .. line, external = true })
                end
            end
            p:close()
        end
    end

    table.sort(order, function(a, b) return a:lower() < b:lower() end)
    local list = {}
    for _, n in ipairs(order) do list[#list + 1] = byName[n] end
    return list
end

local function readExternal(entry)
    local f = io.open(entry.path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

function Library.loadImage(entry)
    if entry.external then
        local data = readExternal(entry)
        if not data then return nil end
        local fd = love.filesystem.newFileData(data, entry.name)
        return love.graphics.newImage(love.image.newImageData(fd))
    end
    return love.graphics.newImage(entry.path)
end

-- kind: "stream" (music) or "static" (short effects)
function Library.loadSource(entry, kind)
    if entry.external then
        local data = readExternal(entry)
        if not data then return nil end
        local fd = love.filesystem.newFileData(data, entry.name)
        return love.audio.newSource(fd, kind)
    end
    return love.audio.newSource(entry.path, kind)
end

return Library
