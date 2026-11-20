-- Runs in a LÖVE thread (so the game keeps drawing while it waits for the network).
-- Arguments: id, command ("check" | "install"), base url (ends with "/"), destination file (install only)
-- Replies on the "updater_out" channel with tables: { id=, kind="checked"|"downloaded"|"error"|"progress", ... }
--
-- Needs curl or wget on the device. All downloads are HTTPS from GitHub; certificates are NOT skipped.

local id, command, base, dest = ...
local out = love.thread.getChannel("updater_out")

local function reply(t) t.id = id; out:push(t) end

local function ok(status)
    return status == true or status == 0
end

local function have(tool)
    return ok(os.execute("command -v " .. tool .. " >/dev/null 2>&1"))
end

local function q(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local tool = have("curl") and "curl" or (have("wget") and "wget" or nil)

local function readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local d = f:read("*a")
    f:close()
    return d
end

local function firstLine(s)
    s = (s or ""):gsub("^%s+", "")
    return (s:match("^[^\r\n]*")) or ""
end

-- Downloads url. If file is given it is saved there, otherwise the text is returned.
local function fetch(url, file)
    if not tool then return nil, "Neither curl nor wget is installed on this device." end
    local errPath = os.tmpname()
    local cmd
    if tool == "curl" then
        cmd = "curl -fsSL --connect-timeout 8 --max-time " .. (file and 900 or 25) .. " "
            .. (file and ("-o " .. q(file) .. " ") or "") .. q(url) .. " 2>" .. q(errPath)
    else
        cmd = "wget -q -T 15 -O " .. (file and q(file) or "-") .. " " .. q(url) .. " 2>" .. q(errPath)
    end
    local text
    local status
    if file then
        status = os.execute(cmd)
    else
        local p = io.popen(cmd, "r")
        if not p then os.remove(errPath); return nil, "Could not start " .. tool .. "." end
        text = p:read("*a")
        status = p:close()
    end
    local err = firstLine(readFile(errPath))
    os.remove(errPath)
    if not ok(status) then
        if file then os.remove(file) end
        return nil, (err ~= "" and err) or "The download failed."
    end
    return text or true
end

local function sha256(path)
    local p = io.popen("sha256sum " .. q(path) .. " 2>/dev/null", "r")
    if not p then return nil end
    local line = p:read("*l") or ""
    p:close()
    return line:match("^(%x+)")
end

if command == "check" then
    local text, err = fetch(base .. "VERSION")
    if not text then
        return reply({ kind = "error", message = err, hint = tostring(err):find("404") and "noversion" or "network" })
    end
    local v = firstLine(text):match("^v?(%d+%.%d+%.%d+)")
    if not v then
        return reply({ kind = "error", message = "The release has no VERSION file yet.", hint = "noversion" })
    end
    return reply({ kind = "checked", remote = v })

elseif command == "install" then
    -- the published checksum first (so a tampered download can't pass)
    local shaText, err = fetch(base .. "SHA256")
    local expected = shaText and tostring(shaText):match("(%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x)")
    if not expected then
        return reply({ kind = "error", message = "The release has no SHA256 file.", hint = "nosha" })
    end
    reply({ kind = "progress", message = "Downloading..." })
    local good, derr = fetch(base .. "Solitaire.love", dest)
    if not good then
        return reply({ kind = "error", message = derr, hint = "network" })
    end
    local f = io.open(dest, "rb")
    local magic, size
    if f then magic = f:read(4); size = f:seek("end"); f:close() end
    if magic ~= "PK\3\4" or not size or size < 50000 then
        os.remove(dest)
        return reply({ kind = "error", message = "The downloaded file is not a game package.", hint = "bad" })
    end
    local actual = sha256(dest)
    if not actual then
        os.remove(dest)
        return reply({ kind = "error", message = "Can't check the download (no sha256sum on this device).", hint = "nosum" })
    end
    if actual:lower() ~= expected:lower() then
        os.remove(dest)
        return reply({ kind = "error", message = "The download is damaged (checksum mismatch). Nothing was changed.", hint = "bad" })
    end
    return reply({ kind = "downloaded", size = size })
end

reply({ kind = "error", message = "Unknown updater command." })
