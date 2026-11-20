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

local function sq(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- The network work is done by a small shell script that runs in the background (so the game keeps
-- running and no LÖVE thread is involved). It writes ONE line to a result file when it is finished:
--     checked|<version>|          the newest version number
--     downloaded|<bytes>|         Solitaire.love was downloaded and its checksum matched
--     error|<kind>|<message>      something went wrong (kind: network, noversion, nosha, bad, nosum, nodl)
local JOB = [==[#!/bin/sh
RES="$1"; ERR="$2"; BASE="$3"; DEST="$4"; CMD="$5"
fin() { printf '%s\n' "$1" > "$RES.tmp"; mv "$RES.tmp" "$RES"; exit 0; }
if command -v curl >/dev/null 2>&1; then T=curl
elif command -v wget >/dev/null 2>&1; then T=wget
else fin "error|nodl|Neither curl nor wget is installed on this device."; fi
get() {
  if [ "$T" = curl ]; then curl -fsSL --connect-timeout 8 --max-time "$3" -o "$2" "$1" 2>"$ERR"
  else wget -q -T 15 -O "$2" "$1" 2>"$ERR"; fi
}
fail_net() {
  M=$(head -n 1 "$ERR" 2>/dev/null | tr '|' ' ')
  case "$M" in *404*) fin "error|$1|$M";; esac
  fin "error|network|${M:-The download failed.}"
}
if [ "$CMD" = check ]; then
  get "${BASE}VERSION" "$RES.v" 25 || fail_net noversion
  V=$(head -n 1 "$RES.v" 2>/dev/null | tr -d '\r ' | sed 's/^v//; s/[^0-9.].*$//')
  rm -f "$RES.v"
  case "$V" in [0-9]*.[0-9]*.[0-9]*) fin "checked|$V|";; esac
  fin "error|noversion|The release has no VERSION file yet."
fi
get "${BASE}SHA256" "$RES.s" 25 || fail_net nosha
EXPECT=$(grep -oE '[0-9a-fA-F]{64}' "$RES.s" 2>/dev/null | head -n 1 | tr 'A-F' 'a-f')
rm -f "$RES.s"
[ -n "$EXPECT" ] || fin "error|nosha|The release has no SHA256 file."
get "${BASE}Solitaire.love" "$DEST" 900 || { rm -f "$DEST"; fail_net network; }
SIZE=$(wc -c < "$DEST" 2>/dev/null | tr -d ' ')
if [ -z "$SIZE" ] || [ "$SIZE" -lt 50000 ] || [ "$(head -c 2 "$DEST")" != "PK" ]; then
  rm -f "$DEST"; fin "error|bad|The downloaded file is not a game package."
fi
if ! command -v sha256sum >/dev/null 2>&1; then rm -f "$DEST"; fin "error|nosum|Can't check the download (no sha256sum on this device)."; fi
ACTUAL=$(sha256sum "$DEST" | cut -d' ' -f1 | tr 'A-F' 'a-f')
if [ "$ACTUAL" != "$EXPECT" ]; then rm -f "$DEST"; fin "error|bad|The download is damaged (checksum mismatch). Nothing was changed."; fi
fin "downloaded|$SIZE|"
]==]

-- a folder the script can write its files into: the game's folder, or /tmp
local function scratchDir()
    local candidates = {}
    local base = love.filesystem.getSourceBaseDirectory and love.filesystem.getSourceBaseDirectory() or nil
    if base and base ~= "" then candidates[#candidates + 1] = base .. "/" end
    candidates[#candidates + 1] = "/tmp/"
    for _, dir in ipairs(candidates) do
        local f = io.open(dir .. ".updater_probe", "w")
        if f then f:close(); os.remove(dir .. ".updater_probe"); return dir end
    end
    return nil
end

local function start(self, command, dest)
    self.id = nextId()
    self.busy = true
    self.command = command
    self.startedAt = os.time()
    self.lastPoll = 0
    local dir = scratchDir()
    if not dir then
        self.pending = { kind = "error", message = "No writable folder for the update.", hint = "nodl", id = self.id }
        return
    end
    local job = dir .. ".updater_job.sh"
    local f = io.open(job, "w")
    if not f then
        self.pending = { kind = "error", message = "Could not write the update script.", hint = "nodl", id = self.id }
        return
    end
    f:write(JOB)
    f:close()
    self.res = dir .. ".updater_result_" .. self.id .. ".txt"
    -- request numbers start at 1 on every launch, so an old answer left by an earlier run must not be mistaken for this one
    os.remove(self.res)
    os.remove(self.res .. ".tmp")
    print("Updater: " .. command .. " started (folder " .. dir .. ", base " .. tostring(self.base) .. ")")
    local cmd = table.concat({ "sh", sq(job), sq(self.res), sq(dir .. ".updater_err.txt"), sq(self.base),
        sq(dest or ""), command, ">/dev/null 2>&1 &" }, " ")
    os.execute(cmd)
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
    self.res = nil
end

-- Returns the finished result of the current request, or nil while it is still working.
--   { kind="checked", remote="x.y.z" } | { kind="downloaded" } | { kind="error", message, hint }
function Updater:poll()
    if self.pending then
        local e = self.pending
        self.pending = nil
        if e.id == self.id then self.busy = false; return e end
    end
    if not self.busy or not self.res then return nil end

    local now = love.timer.getTime()
    if now - (self.lastPoll or 0) < 0.15 then return nil end
    self.lastPoll = now

    local f = io.open(self.res, "r")
    if f then
        local line = f:read("*l") or ""
        f:close()
        os.remove(self.res)
        self.busy = false
        print("Updater: answer '" .. line .. "'")
        local kind, a, b = line:match("^([^|]*)|([^|]*)|(.*)$")
        if kind == "checked" then return { kind = "checked", remote = a, id = self.id } end
        if kind == "downloaded" then return { kind = "downloaded", size = tonumber(a), id = self.id } end
        if kind == "error" then return { kind = "error", hint = a, message = b, id = self.id } end
        return { kind = "error", hint = "crash", message = "The updater gave an unreadable answer.", id = self.id }
    end

    local limit = (self.command == "install") and 1000 or 45
    if os.time() - (self.startedAt or os.time()) > limit then
        self.busy = false
        return { kind = "error", hint = "network", message = "No answer from GitHub (timed out).", id = self.id }
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
