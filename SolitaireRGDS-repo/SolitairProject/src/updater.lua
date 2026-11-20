-- Updater: "Check for updates" from the menu.
--
-- The newest release of the GitHub repo holds three files:
--   VERSION        the version number, e.g. 0.3.0
--   SHA256         the checksum of Solitaire.love
--   Solitaire.love the game itself
-- The game compares VERSION with its own (src/version.lua), downloads Solitaire.love next to the running
-- one, checks it against SHA256, then swaps it in (the old one is kept as Solitaire.love.old).

local Updater = {}
Updater.__index = Updater

Updater.REPO = "shaqboii/SolitaireRGDS"
Updater.BASE = "https://github.com/shaqboii/SolitaireRGDS/releases/latest/download/"

function Updater.localVersion()
    local ok, v = pcall(require, "src.version")
    return ok and v.number or "0.0.0"
end

-- 1 if a is newer than b, -1 if older, 0 if the same
function Updater.compare(a, b)
    local function parts(s)
        local t = {}
        for n in tostring(s):gmatch("%d+") do t[#t + 1] = tonumber(n) end
        return t
    end
    local pa, pb = parts(a), parts(b)
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x > y then return 1 end
        if x < y then return -1 end
    end
    return 0
end

function Updater.new(base)
    local self = setmetatable({}, Updater)
    self.base = base or Updater.BASE
    self.id = 0
    self.busy = false
    self.thread = nil
    return self
end

-- Where the downloaded game is put before it replaces the running one. nil when the game isn't running
-- from a Solitaire.love file (e.g. from a folder while developing), because then there's nothing to swap.
function Updater.packagePath()
    local src = love.filesystem.getSource and love.filesystem.getSource() or nil
    if src and src:match("%.love$") then return src end
    return nil
end

local counter = 0     -- request numbers never repeat, so a late reply to a cancelled request is always ignored
local function nextId()
    counter = counter + 1
    return counter
end

local function start(self, command, dest)
    self.id = nextId()
    self.busy = true
    self.thread = love.thread.newThread("src/updater_thread.lua")
    self.thread:start(self.id, command, self.base, dest)
end

function Updater:check()
    start(self, "check")
end

function Updater:install()
    local pkg = Updater.packagePath()
    if not pkg then
        self.id = nextId()
        self.pending = { kind = "error", message = "Updates only work when the game runs from Solitaire.love.", hint = "nopkg", id = self.id }
        self.busy = true
        return
    end
    start(self, "install", pkg .. ".new")
end

-- ignore whatever the running request says from now on
function Updater:cancel()
    self.id = nextId()
    self.busy = false
    self.pending = nil
end

-- Returns the next event for the current request, or nil.
--   { kind="checked", remote="x.y.z" } | { kind="downloaded" } | { kind="progress", message } | { kind="error", message }
function Updater:poll()
    if self.pending then
        local e = self.pending
        self.pending = nil
        if e.id == self.id then self.busy = false; return e end
    end
    if not self.busy then return nil end
    local ch = love.thread.getChannel("updater_out")
    while true do
        local e = ch:pop()
        if not e then break end
        if e.id == self.id then
            if e.kind ~= "progress" then self.busy = false end
            return e
        end
    end
    if self.thread and not self.thread:isRunning() then
        local err = self.thread:getError()
        if err then
            self.busy = false
            print("Updater: thread error: " .. tostring(err))
            return { kind = "error", message = "The updater crashed.", id = self.id }
        end
    end
    return nil
end

-- Swaps the downloaded file in. Returns true, or false and a message.
function Updater.swap()
    local pkg = Updater.packagePath()
    if not pkg then return false, "Not running from Solitaire.love." end
    local new, old = pkg .. ".new", pkg .. ".old"
    local f = io.open(new, "rb")
    if not f then return false, "The downloaded file is missing." end
    f:close()
    os.remove(old)
    if not os.rename(pkg, old) then
        return false, "Could not move the old game aside (is the card read-only?)."
    end
    if not os.rename(new, pkg) then
        os.rename(old, pkg)       -- put the old game back
        return false, "Could not put the new game in place. The old one was kept."
    end
    return true
end

return Updater
