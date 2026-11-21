-- Ui: shared look for boxes, buttons and labels, inspired by New Super Mario Bros. U:
-- chunky rounded boxes with thick white borders, glossy colour fills, bold outlined text.
local Ui = {}

local function lerp(a, b, t) return a + (b - a) * t end

-- Text with a dark outline (so it stays readable on any colour). color = {r,g,b}, outline = {r,g,b}
function Ui.text(font, str, x, y, color, outline, thick)
    love.graphics.setFont(font)
    local o = outline or { 0.10, 0.12, 0.30 }
    local t = thick or 2
    love.graphics.setColor(o[1], o[2], o[3], 1)
    for _, d in ipairs({ { -t, 0 }, { t, 0 }, { 0, -t }, { 0, t }, { -t, -t }, { t, -t }, { -t, t }, { t, t } }) do
        love.graphics.print(str, x + d[1], y + d[2])
    end
    local c = color or { 1, 1, 1 }
    love.graphics.setColor(c[1], c[2], c[3], c[4] or 1)
    love.graphics.print(str, x, y)
end

function Ui.centered(font, str, cx, y, color, outline, thick)
    Ui.text(font, str, cx - font:getWidth(str) / 2, y, color, outline, thick)
end

-- A glossy rounded box: dark rim, thick white border, vertical colour fill, shine on the top half.
-- top / bottom: fill colours {r,g,b}; border defaults to white.
function Ui.box(x, y, w, h, top, bottom, opts)
    opts = opts or {}
    local r = opts.radius or math.min(18, h / 2.2)
    local bw = opts.border or 4
    local alpha = opts.alpha or 1
    local border = opts.borderColor or { 1, 1, 1 }

    -- soft drop shadow
    love.graphics.setColor(0, 0, 0, 0.30 * alpha)
    love.graphics.rectangle("fill", x + 2, y + 5, w, h, r + bw, r + bw)
    -- dark rim around the white border
    love.graphics.setColor(0.08, 0.10, 0.28, alpha)
    love.graphics.rectangle("fill", x - bw - 2, y - bw - 2, w + (bw + 2) * 2, h + (bw + 2) * 2, r + bw + 2, r + bw + 2)
    -- white border
    love.graphics.setColor(border[1], border[2], border[3], alpha)
    love.graphics.rectangle("fill", x - bw, y - bw, w + bw * 2, h + bw * 2, r + bw, r + bw)
    -- fill: bottom colour, then the top colour over the upper part (a cheap 3-step gradient)
    love.graphics.setColor(bottom[1], bottom[2], bottom[3], alpha)
    love.graphics.rectangle("fill", x, y, w, h, r, r)
    local mid = { lerp(top[1], bottom[1], 0.5), lerp(top[2], bottom[2], 0.5), lerp(top[3], bottom[3], 0.5) }
    love.graphics.setColor(mid[1], mid[2], mid[3], alpha)
    love.graphics.rectangle("fill", x, y, w, h * 0.7, r, r)
    love.graphics.setColor(top[1], top[2], top[3], alpha)
    love.graphics.rectangle("fill", x, y, w, h * 0.42, r, r)
    -- shine
    if not opts.flat then
        love.graphics.setColor(1, 1, 1, 0.22 * alpha)
        love.graphics.rectangle("fill", x + 6, y + 4, w - 12, math.max(4, h * 0.18), r * 0.6, r * 0.6)
    end
end

Ui.colors = {
    panelTop = { 0.30, 0.55, 0.95 }, panelBottom = { 0.10, 0.28, 0.72 },     -- sky blue
    yellowTop = { 1.00, 0.90, 0.30 }, yellowBottom = { 0.98, 0.65, 0.10 },   -- coin yellow / orange
    greyTop = { 0.55, 0.68, 0.92 }, greyBottom = { 0.30, 0.42, 0.75 },        -- idle buttons
    red = { 0.90, 0.20, 0.20 },
    gold = { 1.00, 0.92, 0.35 },
    ink = { 0.10, 0.12, 0.30 },
}

function Ui.panel(x, y, w, h, accent)
    local c = Ui.colors
    Ui.box(x, y, w, h, c.panelTop, c.panelBottom, { radius = 22, border = 5, alpha = 0.97, flat = true })
end

-- selected = bright yellow with a pulse; otherwise a calm blue button
function Ui.button(x, y, w, h, selected, pulse)
    local c = Ui.colors
    if selected then
        Ui.box(x, y, w, h, c.yellowTop, c.yellowBottom, { border = 4 })
        if pulse then
            love.graphics.setColor(1, 1, 1, 0.25 + 0.2 * pulse)
            love.graphics.setLineWidth(3)
            love.graphics.rectangle("line", x - 9, y - 9, w + 18, h + 18, h / 2 + 4, h / 2 + 4)
        end
    else
        Ui.box(x, y, w, h, c.greyTop, c.greyBottom, { border = 3 })
    end
end

return Ui
