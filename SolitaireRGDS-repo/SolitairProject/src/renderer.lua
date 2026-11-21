local Fonts = require("src.fonts")
local Ui = require("src.ui")
local Renderer = {}
Renderer.__index = Renderer

local SUIT_SYMBOLS = { "♥", "♦", "♣", "♠" }

-- Double-beat pulse, 0..1 (like a heartbeat: "lub-dub", then rest)
local function heartbeat(t)
    local p = (t * 1.25) % 1
    local a = math.exp(-((p - 0.08) / 0.055) ^ 2)
    local b = 0.6 * math.exp(-((p - 0.30) / 0.07) ^ 2)
    return math.min(1, a + b)
end

Renderer.heartbeat = heartbeat

function Renderer.new(assets, background)
    local self = setmetatable({}, Renderer)
    self.assets = assets
    self.background = background

    -- Native single-screen resolution (1024x768)
    self.width = 1024
    self.height = 768
    self.time = 0
    self.dualMode = false

    -- Fonts
    self.fontTitle = Fonts.get(36)
    self.fontMedium = Fonts.get(22)
    self.fontSmall = Fonts.get(16)
    self.fontButton = Fonts.get(18)
    self.fontHud = Fonts.get(17)

    -- Card dimensions & layout positions
    self.cardW = 116
    self.cardH = 164
    self.colGap = 25
    self.colStartX = 32
    self.topRowY = 32
    self.tableauStartY = 216

    -- On-screen buttons (x, y, w, h)
    local c3 = self.colStartX + 2 * (self.cardW + self.colGap)
    self.buttons = {
        undo = { x = c3, y = 32, w = self.cardW, h = 52 },
        hint = { x = c3, y = 88, w = self.cardW, h = 52 },
        winnable = { x = c3, y = 144, w = self.cardW, h = 52 },
        menu = { x = 32, y = 716, w = 130, h = 46 },
        deal = { x = 172, y = 716, w = 130, h = 46 },
        finish = { x = 320, y = 712, w = 300, h = 52 },
    }

    -- Smoothly moving cursor rectangle
    self.cx, self.cy, self.cw, self.ch = nil, nil, self.cardW, self.cardH
    return self
end

-- ========================================================
-- GEOMETRY
-- ========================================================

function Renderer:getTableauX(col)
    return self.colStartX + (col - 1) * (self.cardW + self.colGap)
end

function Renderer:getStockRect()
    return self:getTableauX(1), self.topRowY, self.cardW, self.cardH
end

function Renderer:getWasteRect()
    return self:getTableauX(2), self.topRowY, self.cardW, self.cardH
end

function Renderer:getFoundationRect(fIndex)
    return self:getTableauX(3 + fIndex), self.topRowY, self.cardW, self.cardH
end

function Renderer:getButtonRect(id)
    local b = self.buttons[id]
    return b.x, b.y, b.w, b.h
end

function Renderer:getTableauCardRect(col, cardIndex, totalCards)
    local x = self:getTableauX(col)
    local y = self.tableauStartY

    local faceDownStep = 18
    local faceUpStep = 32

    if totalCards and totalCards > 11 then
        local excess = totalCards - 11
        faceDownStep = math.max(12, 18 - excess)
        faceUpStep = math.max(20, 32 - excess * 1.5)
    end

    return x, y, faceDownStep, faceUpStep
end

-- Y of card number `index` in a tableau column
function Renderer:tableauY(solitaire, col, index)
    local pile = solitaire.tableau[col]
    local _, _, fd, fu = self:getTableauCardRect(col, 1, #pile)
    local y = self.tableauStartY
    for i = 1, index - 1 do
        local c = pile[i]
        if not c then break end
        y = y + (c.faceUp and fu or fd)
    end
    return y
end

-- Where every card belongs right now. Returns px, py, cards (all keyed by card id)
function Renderer:layout(s)
    local px, py, cards = {}, {}, {}
    local sx, sy = self:getStockRect()
    for _, c in ipairs(s.stock) do px[c.id] = sx; py[c.id] = sy; cards[c.id] = c end
    local wx, wy = self:getWasteRect()
    for _, c in ipairs(s.waste) do px[c.id] = wx; py[c.id] = wy; cards[c.id] = c end
    for f = 1, 4 do
        local fx, fy = self:getFoundationRect(f)
        for _, c in ipairs(s.foundations[f]) do px[c.id] = fx; py[c.id] = fy; cards[c.id] = c end
    end
    for col = 1, 7 do
        local pile = s.tableau[col]
        local x = self:getTableauX(col)
        local _, _, fd, fu = self:getTableauCardRect(col, 1, #pile)
        local y = self.tableauStartY
        for _, c in ipairs(pile) do
            px[c.id] = x; py[c.id] = y; cards[c.id] = c
            y = y + (c.faceUp and fu or fd)
        end
    end
    return px, py, cards
end

-- Where every card is drawn right now (including cards in flight or held by a finger)
function Renderer:visualPositions(s, controls, anim)
    local px, py = self:layout(s)
    local vx, vy = {}, {}
    local dragIndex = controls and controls:dragIndexMap() or {}
    for id, x in pairs(px) do
        local y = py[id]
        local di = dragIndex[id]
        if di then
            x, y = controls:dragPos(di)
        elseif anim then
            x, y = anim:position(id, x, y)
        end
        vx[id], vy[id] = x, y
    end
    return vx, vy
end

-- Rectangle of one pile spot / card for hints and the cursor
function Renderer:zoneRect(s, zone, col, index)
    if zone == "stock" then
        local x, y, w, h = self:getStockRect()
        return x, y, w, h
    elseif zone == "waste" then
        local x, y, w, h = self:getWasteRect()
        return x, y, w, h
    elseif zone == "foundation" then
        local x, y, w, h = self:getFoundationRect(col)
        return x, y, w, h
    else
        local pile = s.tableau[col]
        local x = self:getTableauX(col)
        if #pile == 0 then return x, self.tableauStartY, self.cardW, self.cardH end
        index = math.max(1, math.min(index or #pile, #pile))
        return x, self:tableauY(s, col, index), self.cardW, self.cardH
    end
end

-- The cards that are currently picked up (selected)
function Renderer:selectedCards(s)
    local sel = s.selection
    if not sel then return nil end
    local list = {}
    if sel.source == "tableau" then
        local pile = s.tableau[sel.col]
        for i = sel.cardIndex, #pile do list[#list + 1] = pile[i] end
    elseif sel.source == "waste" then
        if #s.waste > 0 then list[1] = s.waste[#s.waste] end
    elseif sel.source == "foundation" then
        local pile = s.foundations[sel.col]
        if #pile > 0 then list[1] = pile[#pile] end
    end
    if #list == 0 then return nil end
    return list
end

-- ========================================================
-- UPDATE (cursor glide)
-- ========================================================

function Renderer:cursorTarget(cursor, solitaire)
    if cursor.zone == "top" then
        if cursor.topIndex == 1 then
            return self:zoneRect(solitaire, "stock")
        elseif cursor.topIndex == 2 then
            return self:zoneRect(solitaire, "waste")
        end
        return self:zoneRect(solitaire, "foundation", cursor.topIndex - 2)
    end
    local col = cursor.tableauCol
    local pile = solitaire.tableau[col]
    local idx = math.min(cursor.cardIndex, #pile)
    return self:zoneRect(solitaire, "tableau", col, idx)
end

function Renderer:update(dt, game)
    self.time = self.time + dt
    local tx, ty, tw, th = self:cursorTarget(game.cursor, game.solitaire)
    if not self.cx then
        self.cx, self.cy, self.cw, self.ch = tx, ty, tw, th
    else
        local k = 1 - math.exp(-dt * 20)
        self.cx = self.cx + (tx - self.cx) * k
        self.cy = self.cy + (ty - self.cy) * k
        self.cw = tw
        self.ch = th
    end
end

-- ========================================================
-- DRAWING HELPERS
-- ========================================================

function Renderer:drawCard(card, x, y, forceBack, lift)
    if not card then return end

    love.graphics.push()
    love.graphics.translate(x, y)

    -- Drop shadow (bigger while a card is in the air)
    local off = lift and 9 or 4
    love.graphics.setColor(0, 0, 0, lift and 0.4 or 0.35)
    love.graphics.rectangle("fill", off, off, self.cardW, self.cardH, 8, 8)

    love.graphics.setColor(1, 1, 1, 1)
    if card.faceUp and not forceBack then
        local img = self.assets.cards[card.suit] and self.assets.cards[card.suit][card.rank]
        if img then
            local sx = self.cardW / img:getWidth()
            local sy = self.cardH / img:getHeight()
            love.graphics.draw(img, 0, 0, 0, sx, sy)
        end
    else
        if self.assets.cardBack then
            local sx = self.cardW / self.assets.cardBack:getWidth()
            local sy = self.cardH / self.assets.cardBack:getHeight()
            love.graphics.draw(self.assets.cardBack, 0, 0, 0, sx, sy)
        end
    end

    love.graphics.pop()
end

function Renderer:drawSlot(x, y)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.assets.emptySlot, x, y)
end

-- Rounded button. state: { label, enabled, accent = {r,g,b}, flash = 0..1, pulse = bool }
function Renderer:drawButton(id, label, state)
    local b = self.buttons[id]
    state = state or {}
    local enabled = state.enabled ~= false
    local accent = state.accent or { 0.4, 0.6, 0.8 }
    local flash = state.flash or 0
    local a = enabled and 1 or 0.4

    local lift = 0
    if state.pulse then lift = heartbeat(self.time) end

    local function shade(k) return { math.min(1, accent[1] * k + flash * 0.4), math.min(1, accent[2] * k + flash * 0.4), math.min(1, accent[3] * k + flash * 0.4) } end
    Ui.box(b.x - lift * 3, b.y - lift * 3, b.w + lift * 6, b.h + lift * 6, shade(1.0), shade(0.55), { border = 3, radius = 14, alpha = a })

    local font = state.font or self.fontButton
    local tw = font:getWidth(label)
    local ink = { accent[1] * 0.25, accent[2] * 0.25, accent[3] * 0.25 }
    Ui.text(font, label, b.x + (b.w - tw) / 2, b.y + (b.h - font:getHeight()) / 2, { 1, 1, 1, a }, ink, 2)
end

local function drawArrow(x1, y1, x2, y2)
    love.graphics.line(x1, y1, x2, y2)
    local ang = math.atan2(y2 - y1, x2 - x1)
    local l = 16
    local a1, a2 = ang + 2.6, ang - 2.6
    love.graphics.polygon("fill", x2, y2,
        x2 + math.cos(a1) * l, y2 + math.sin(a1) * l,
        x2 + math.cos(a2) * l, y2 + math.sin(a2) * l)
end

-- ========================================================
-- MAIN DRAW
-- ========================================================

function Renderer:draw(game)
    local s = game.solitaire
    local ctl = game.controls
    local anim = game.anim
    local cursor = game.cursor
    local menuOpen = game.menu.open

    love.graphics.setScissor(0, 0, self.width, self.height)

    -- Green casino felt
    love.graphics.setColor(0.1, 0.36, 0.22, 1)
    love.graphics.rectangle("fill", 0, 0, self.width, self.height)
    love.graphics.setColor(0.05, 0.2, 0.12, 0.5)
    love.graphics.rectangle("fill", 0, 0, self.width, 18)
    love.graphics.rectangle("fill", 0, self.height - 20, self.width, 20)

    if menuOpen and game.menu.title then
        -- Title screen: just the felt and the menu, no cards yet
        game.menu:draw(self)
        self:drawDim()
        love.graphics.setScissor()
        return
    end

    local px, py, cardById = self:layout(s)
    local dragIndex = ctl:dragIndexMap()

    -- A card is "settled" when it is neither flying nor held by a finger
    local function settled(card)
        return not dragIndex[card.id] and not anim:isAnimating(card.id)
    end

    -- Single-screen mode keeps the small stats line (in dual-screen mode they live on the top screen)
    if not self.dualMode then
        local minutes = math.floor(s.time / 60)
        local seconds = math.floor(s.time % 60)
        love.graphics.setFont(self.fontHud)
        love.graphics.setColor(0.95, 0.95, 0.98, 0.9)
        love.graphics.print(string.format("SCORE: %d   |   TIME: %02d:%02d   |   MOVES: %d", s.score, minutes, seconds, s.moves), 32, 6)
    end

    -- 1. Stock
    local sx, sy, sw, sh = self:getStockRect()
    self:drawSlot(sx, sy)
    local stockTop = nil
    for i = #s.stock, 1, -1 do
        if settled(s.stock[i]) then stockTop = s.stock[i] break end
    end
    if stockTop then
        self:drawCard(stockTop, sx, sy, true)
        love.graphics.setColor(0, 0, 0, 0.75)
        love.graphics.rectangle("fill", sx + sw - 34, sy + sh - 26, 30, 22, 4, 4)
        love.graphics.setFont(self.fontSmall)
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.print(tostring(#s.stock), sx + sw - 28, sy + sh - 24)
    elseif #s.stock == 0 then
        -- recycle icon
        local cxs, cys = sx + sw / 2, sy + sh / 2
        love.graphics.setColor(1, 1, 1, 0.4)
        love.graphics.setLineWidth(5)
        love.graphics.arc("line", "open", cxs, cys, 22, -math.pi * 0.15, math.pi * 1.45)
        local ax, ay = cxs + math.cos(-math.pi * 0.15) * 22, cys + math.sin(-math.pi * 0.15) * 22
        love.graphics.polygon("fill", ax - 11, ay - 3, ax + 11, ay - 3, ax, ay + 12)
    end

    -- 2. Waste
    local wx, wy = self:getWasteRect()
    self:drawSlot(wx, wy)
    for i = #s.waste, 1, -1 do
        if settled(s.waste[i]) then self:drawCard(s.waste[i], wx, wy) break end
    end

    -- 3. Buttons (column 3)
    love.graphics.setLineWidth(2)
    local flash = game.flash
    local function fl(id) return (flash.id == id) and math.max(0, flash.t / 0.2) or 0 end
    self:drawButton("undo", "UNDO", { enabled = #s.undoStack > 0 and not s.isWon, accent = { 0.4, 0.6, 0.85 }, flash = fl("undo") })
    self:drawButton("hint", "HINT", { accent = { 0.95, 0.8, 0.3 }, flash = fl("hint") })
    self:drawButton("winnable", "WINNABLE?", { accent = { 0.6, 0.85, 0.6 }, flash = fl("winnable"), font = self.fontSmall })

    -- 4. Foundations
    local fColors = { { 0.85, 0.2, 0.2, 0.4 }, { 0.85, 0.2, 0.2, 0.4 }, { 0.1, 0.1, 0.1, 0.4 }, { 0.1, 0.1, 0.1, 0.4 } }
    for f = 1, 4 do
        local fx, fy, fw, fh = self:getFoundationRect(f)
        self:drawSlot(fx, fy)
        local pile = s.foundations[f]
        local top = nil
        for i = #pile, 1, -1 do
            if settled(pile[i]) then top = pile[i] break end
        end
        if top then
            self:drawCard(top, fx, fy)
        else
            love.graphics.setFont(self.fontTitle)
            love.graphics.setColor(fColors[f][1], fColors[f][2], fColors[f][3], fColors[f][4])
            local sym = SUIT_SYMBOLS[f]
            love.graphics.print(sym, fx + (fw - self.fontTitle:getWidth(sym)) / 2, fy + (fh - self.fontTitle:getHeight()) / 2)
        end
    end

    -- 5. Tableau
    for col = 1, 7 do
        local pile = s.tableau[col]
        local x = self:getTableauX(col)
        if #pile == 0 then
            self:drawSlot(x, self.tableauStartY)
            love.graphics.setFont(self.fontTitle)
            love.graphics.setColor(1, 1, 1, 0.15)
            local kText = "K"
            love.graphics.print(kText, x + (self.cardW - self.fontTitle:getWidth(kText)) / 2, self.tableauStartY + 50)
        else
            for _, card in ipairs(pile) do
                if settled(card) then self:drawCard(card, x, py[card.id]) end
            end
        end
    end

    -- Visual positions (needed for the selection border and the hint arrow)
    local vx, vy = {}, {}
    for id, x in pairs(px) do
        local y = py[id]
        local di = dragIndex[id]
        if di then
            x, y = ctl:dragPos(di)
        else
            x, y = anim:position(id, x, y)
        end
        vx[id], vy[id] = x, y
    end

    -- 6. Hint highlight
    if game.hint and game.hint.version == s.version then
        self:drawHint(game.hint, s)
    end

    -- 7. Cursor (glides from card to card)
    if not menuOpen and not ctl.dragging and self.cx then
        local pulse = (math.sin(game.cursor.cursorAnim) + 1) * 0.5
        local glowSize = 3 + pulse * 2
        local cx, cy, cw, ch = self.cx, self.cy, self.cw, self.ch
        love.graphics.setColor(0.2, 0.8, 1, 0.85 + pulse * 0.15)
        love.graphics.setLineWidth(glowSize)
        love.graphics.rectangle("line", cx - 3, cy - 3, cw + 6, ch + 6, 10, 10)

        love.graphics.setColor(1, 1, 1, 0.95)
        love.graphics.setLineWidth(2)
        local bLen = 14
        love.graphics.line(cx - 5, cy - 5, cx - 5 + bLen, cy - 5)
        love.graphics.line(cx - 5, cy - 5, cx - 5, cy - 5 + bLen)
        love.graphics.line(cx + cw + 5, cy - 5, cx + cw + 5 - bLen, cy - 5)
        love.graphics.line(cx + cw + 5, cy - 5, cx + cw + 5, cy - 5 + bLen)
        love.graphics.line(cx - 5, cy + ch + 5, cx - 5 + bLen, cy + ch + 5)
        love.graphics.line(cx - 5, cy + ch + 5, cx - 5, cy + ch + 5 - bLen)
        love.graphics.line(cx + cw + 5, cy + ch + 5, cx + cw + 5 - bLen, cy + ch + 5)
        love.graphics.line(cx + cw + 5, cy + ch + 5, cx + cw + 5, cy + ch + 5 - bLen)
    end

    -- 8. Cards in flight (newest on top)
    for _, e in ipairs(anim:order()) do
        local card = cardById[e.id]
        if card and not dragIndex[e.id] then
            self:drawCard(card, vx[e.id], vy[e.id], anim:showsBack(e.id), true)
        end
    end

    -- 9. Cards held by a finger
    if ctl.dragging and ctl.dragCards then
        for i, card in ipairs(ctl.dragCards) do
            local x, y = ctl:dragPos(i)
            self:drawCard(card, x, y, false, true)
        end
    end

    -- 10. Heartbeat border around the selected card(s)
    local sel = self:selectedCards(s)
    if sel and not menuOpen then
        local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
        for _, card in ipairs(sel) do
            local x, y = vx[card.id], vy[card.id]
            if x then
                minX = math.min(minX, x); minY = math.min(minY, y)
                maxX = math.max(maxX, x + self.cardW); maxY = math.max(maxY, y + self.cardH)
            end
        end
        if minX < math.huge then
            local beat = heartbeat(self.time)
            local pad = 1 + 5 * beat
            love.graphics.setColor(1, 0.85, 0.2, 0.75 + 0.25 * beat)
            love.graphics.setLineWidth(3 + 1.5 * beat)
            love.graphics.rectangle("line", minX - pad, minY - pad, (maxX - minX) + pad * 2, (maxY - minY) + pad * 2, 9 + pad, 9 + pad)
        end
    end

    -- 11. Bottom bar: MENU, DEAL, message or FINISH
    self:drawButton("menu", "MENU", { accent = { 0.7, 0.7, 0.85 }, flash = fl("menu") })
    self:drawButton("deal", "DEAL", { accent = { 0.85, 0.45, 0.45 }, flash = fl("deal") })

    local msgX = 320
    if game:finishAvailable() then
        self:drawButton("finish", "FINISH", { accent = { 0.35, 0.9, 0.45 }, pulse = true, flash = fl("finish"), font = self.fontMedium })
        msgX = 640
    end
    if game.toastText and game.toastTime > 0 then
        local alpha = math.min(1, game.toastTime / 0.4)
        love.graphics.setFont(self.fontButton)
        local text = game.toastText
        local maxW = 1000 - msgX
        local tw = self.fontButton:getWidth(text)
        if tw > maxW then
            -- too long for the bar: use the smaller font
            love.graphics.setFont(self.fontSmall)
            tw = self.fontSmall:getWidth(text)
        end
        local bx = msgX + math.max(0, (maxW - tw) / 2)
        Ui.box(bx - 14, 720, tw + 28, 38, Ui.colors.yellowTop, Ui.colors.yellowBottom, { border = 3, radius = 14, alpha = alpha })
        Ui.text((self.fontButton:getWidth(text) > maxW) and self.fontSmall or self.fontButton, text, bx, 729, { 1, 1, 1, alpha }, { 0.62, 0.30, 0.02 }, 2)
    end

    -- 12. Solver "thinking" panel
    if game.task then
        love.graphics.setColor(0, 0, 0, 0.55)
        love.graphics.rectangle("fill", 0, 0, self.width, self.height)
        local w, h = 420, 150
        local x, y = (self.width - w) / 2, (self.height - h) / 2
        Ui.panel(x, y, w, h)
        local msg = game.task.kind == "winnable" and "Checking the game..." or "Looking for a move..."
        Ui.centered(self.fontMedium, msg, x + w / 2, y + 24, { 1, 1, 1 }, Ui.colors.ink, 2)
        -- spinner
        local a0 = self.time * 6
        love.graphics.setColor(1, 0.9, 0.3, 1)
        love.graphics.setLineWidth(6)
        love.graphics.arc("line", "open", x + w / 2, y + 92, 14, a0, a0 + math.pi * 1.4)
        Ui.centered(self.fontSmall, "Tap or press B to cancel", x + w / 2, y + h - 32, { 1, 1, 1 }, Ui.colors.ink, 1)
    end

    -- 13. Menu / dialogs on top of everything
    game.menu:draw(self)
    self:drawDim()

    love.graphics.setScissor()
end

-- Software brightness (only when the real backlight can't be controlled)
function Renderer:drawDim()
    if self.softDim and self.softDim > 0 then
        love.graphics.setColor(0, 0, 0, self.softDim)
        love.graphics.rectangle("fill", 0, 0, self.width, self.height)
    end
end

function Renderer:drawHint(hint, s)
    local pulse = 0.55 + 0.45 * heartbeat(self.time * 0.8)
    local function rectFor(spec)
        if spec.zone == "tableau" then
            local x, y, w, h = self:zoneRect(s, "tableau", spec.col, spec.index)
            if spec.index then
                local pile = s.tableau[spec.col]
                local ly = self:tableauY(s, spec.col, #pile)
                h = (ly + self.cardH) - y
            end
            return x, y, w, h
        end
        return self:zoneRect(s, spec.zone, spec.col)
    end

    local sx, sy, sw, sh = rectFor(hint.source)
    love.graphics.setLineWidth(4)
    love.graphics.setColor(1, 0.85, 0.2, pulse)
    love.graphics.rectangle("line", sx - 4, sy - 4, sw + 8, sh + 8, 10, 10)

    if hint.dest then
        local dx, dy, dw, dh = rectFor(hint.dest)
        love.graphics.setColor(0.35, 1, 0.5, pulse)
        love.graphics.rectangle("line", dx - 4, dy - 4, dw + 8, dh + 8, 10, 10)
        love.graphics.setLineWidth(3)
        love.graphics.setColor(1, 1, 1, 0.45 * pulse)
        drawArrow(sx + sw / 2, sy + 20, dx + dw / 2, dy + 20)
    end
end

return Renderer
