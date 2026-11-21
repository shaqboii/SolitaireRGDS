-- Anim: smooth card movement.
--
-- The game state changes instantly (a card is simply in a different pile afterwards).
-- To make cards glide instead of teleporting, we remember where each card WAS drawn
-- (before the change) and fly it from there to where it IS now (after the change).

local Anim = {}
Anim.__index = Anim

function Anim.new()
    local self = setmetatable({}, Anim)
    self.t = 0
    self.seq = 0
    self.cards = {}        -- [card id] = { fx, fy, start, dur, seq, back }
    self.dealUntil = 0     -- while t < dealUntil the cards are being dealt
    return self
end

function Anim:clear()
    self.cards = {}
    self.dealUntil = 0
end

function Anim:update(dt)
    self.t = self.t + dt
    for id, a in pairs(self.cards) do
        if self.t >= a.start + a.dur then self.cards[id] = nil end
    end
end

function Anim:isBusy()
    return next(self.cards) ~= nil
end

function Anim:isDealing()
    return self.t < self.dealUntil
end

function Anim:isAnimating(id)
    return self.cards[id] ~= nil
end

local function easeInOut(p)
    if p < 0.5 then return 4 * p * p * p end
    local q = -2 * p + 2
    return 1 - q * q * q / 2
end

local function easeOut(p)
    local q = 1 - p
    return 1 - q * q * q
end

-- Where is this card drawn right now, given where it belongs (lx, ly)?
-- Returns x, y, flying (true while it is still on its way)
function Anim:position(id, lx, ly)
    local a = self.cards[id]
    if not a then return lx, ly, false end
    local p = (self.t - a.start) / a.dur
    if a.shake then
        if p <= 0 or p >= 1 then return lx, ly, true end
        local amp = (a.amp or 9) * (1 - p)
        return lx + math.sin(p * math.pi * 6) * amp, ly, true
    end
    if p <= 0 then return a.fx, a.fy, true end
    if p >= 1 then return lx, ly, false end
    local e = a.ease(p)
    return a.fx + (lx - a.fx) * e, a.fy + (ly - a.fy) * e, true
end

-- opts: delay, dur, ease ("out" or default in-out), back (draw face down while flying)
function Anim:add(id, fx, fy, opts)
    opts = opts or {}
    self.seq = self.seq + 1
    self.cards[id] = {
        fx = fx, fy = fy,
        start = self.t + (opts.delay or 0),
        dur = opts.dur or 0.3,
        seq = self.seq,
        ease = (opts.ease == "out") and easeOut or easeInOut,
        back = opts.back or false,
    }
end

-- Shake a card left-right in place (failed move)
function Anim:shake(id, delay, dur, amp)
    self.seq = self.seq + 1
    self.cards[id] = { fx = 0, fy = 0, start = self.t + (delay or 0), dur = dur or 0.32,
        seq = self.seq, ease = easeOut, back = false, shake = true, amp = amp }
end

-- Compare "before" and "after" positions (tables id -> number) and fly every card that moved.
function Anim:retarget(bx, by, ax, ay, opts)
    opts = opts or {}
    for id, tx in pairs(ax) do
        local fx, fy = bx[id], by[id]
        if fx and (math.abs(fx - tx) > 0.5 or math.abs(fy - ay[id]) > 0.5) then
            local o = { delay = opts.delay, ease = opts.ease, back = opts.back, dur = opts.dur }
            if not o.dur then
                local dx, dy = tx - fx, ay[id] - fy
                local dist = math.sqrt(dx * dx + dy * dy)
                o.dur = math.min(0.42, 0.2 + dist / 3200)
            end
            self:add(id, fx, fy, o)
        end
    end
end

-- Animating card ids, oldest first (so the newest flies on top)
function Anim:order()
    local list = {}
    for id, a in pairs(self.cards) do list[#list + 1] = { id = id, seq = a.seq } end
    table.sort(list, function(a, b) return a.seq < b.seq end)
    return list
end

function Anim:showsBack(id)
    local a = self.cards[id]
    return a and a.back or false
end

return Anim
