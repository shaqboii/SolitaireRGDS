-- Store: tiny key=value files (settings, stats).
-- Saved in LOVE's save folder. If that folder is not writable on the device, falls back to
-- writing next to the game (the folder that holds Solitaire.love).
local Store = {}

local function externalPath(filename)
    local ok, base = pcall(love.filesystem.getSourceBaseDirectory)
    if ok and base and base ~= "" then return base .. "/" .. filename end
    return nil
end

local function readAll(filename)
    local ok, content = pcall(love.filesystem.read, filename)
    if ok and type(content) == "string" then return content end
    local p = externalPath(filename)
    if p then
        local f = io.open(p, "rb")
        if f then
            local data = f:read("*a")
            f:close()
            return data
        end
    end
    return nil
end

-- defaults decides each key's type (number or string); unknown keys in the file are ignored
function Store.load(filename, defaults)
    local t = {}
    for k, v in pairs(defaults) do t[k] = v end
    local content = readAll(filename)
    if type(content) == "string" then
        for line in content:gmatch("[^\r\n]+") do
            local k, v = line:match("^([%w_]+)=(.*)$")
            if k and defaults[k] ~= nil then
                if type(defaults[k]) == "number" then
                    local n = tonumber(v)
                    if n then t[k] = n end
                else
                    t[k] = v
                end
            end
        end
    end
    return t
end

function Store.save(filename, t, keys)
    local lines = {}
    for _, k in ipairs(keys) do
        lines[#lines + 1] = k .. "=" .. tostring(t[k])
    end
    local data = table.concat(lines, "\n") .. "\n"

    local ok, res = pcall(love.filesystem.write, filename, data)
    if ok and res then return true end

    local p = externalPath(filename)
    if p then
        local f = io.open(p, "wb")
        if f then
            f:write(data)
            f:close()
            return true
        end
    end
    print("Store: could not save " .. filename)
    return false
end

-- Raw text files (used for saved games)
function Store.read(filename) return readAll(filename) end

function Store.write(filename, data)
    local ok, res = pcall(love.filesystem.write, filename, data)
    if ok and res then return true end
    local p = externalPath(filename)
    if p then
        local f = io.open(p, "wb")
        if f then f:write(data); f:close(); return true end
    end
    print("Store: could not write " .. filename)
    return false
end

function Store.remove(filename)
    pcall(love.filesystem.remove, filename)
    local p = externalPath(filename)
    if p then os.remove(p) end
end

return Store
