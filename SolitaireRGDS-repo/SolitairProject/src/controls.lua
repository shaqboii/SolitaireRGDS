local Controls = {}
Controls.__index = Controls

local EMPTY = {}

local PAD_NAMES = {
    dpup = "up", dpdown = "down", dpleft = "left", dpright = "right",
    a = "a", b = "b", x = "x", y = "y",
    back = "select", start = "start", guide = "start",
}

local KEY_NAMES = {
    up = "up", down = "down", left = "left", right = "right",
    w = "up", s = "down", a = "left", d = "right",
    ["return"] = "a", space = "a", backspace = "b",
    y = "y", x = "x", h = "x",
    u = "select", z = "select",
    escape = "start", tab = "start",
    v = "winnable", f = "finish",
}

function Controls.new(game)
    local self = setmetatable({}, Controls)
    self.game = game
    self.solitaire = game.solitaire
    self.cursor = game.cursor
    self.renderer = game.renderer
    self.assets = game.assets

    -- Shoulder buttons: held = auto-place with A; a quick tap on its own = shortcut
    self.lHeld = false
    self.rHeld = false
    self.shoulder = nil
    self.exitHold = 0

    -- Touch & drag state
    self.dragging = false
    self.dragSource = nil
    self.dragCards = nil
    self._dragMap = nil
    self.dragOffX = 0
    self.dragOffY = 0
    self.dragX = 0
    self.dragY = 0
    self.dragStep = 0
    self.dragStartX = 0
    self.dragStartY = 0
    self.dragMoved = false

    -- Double-tap detection
    self.lastTapTime = 0
    self.lastTapTarget = nil

    return self
end

-- ========================================================
-- DRAG HELPERS (used by the renderer)
-- ========================================================

-- card id -> position in the dragged stack
function Controls:dragIndexMap()
    return self._dragMap or EMPTY
end

-- Where card number i of the dragged stack is drawn
function Controls:dragPos(i)
    return self.dragX - self.dragOffX, self.dragY - self.dragOffY + (i - 1) * self.dragStep
end

function Controls:update(dt)
    local joysticks = love.joystick.getJoysticks()
    if #joysticks > 0 then
        local joy = joysticks[1]

        -- Emergency exit: hold SELECT + START for 2 seconds
        if joy:isGamepadDown("back") and joy:isGamepadDown("start") then
            self.exitHold = self.exitHold + dt
            if self.exitHold >= 2 then
                print("Solitaire: SELECT + START held. Quitting...")
                love.event.quit()
                return
            end
        else
            self.exitHold = 0
        end

        self.lHeld = joy:isGamepadDown("leftshoulder")
        self.rHeld = joy:isGamepadDown("rightshoulder") or joy:getGamepadAxis("triggerright") > 0.3
    end
end

-- ========================================================
-- ONE PLACE FOR EVERY BUTTON PRESS
-- ========================================================

-- name: up down left right a b x y select start winnable finish
function Controls:press(name)
    local g = self.game
    local s = self.solitaire

    if g.menu.open then
        g.menu:press(name)
        return
    end
    if g.task then
        if name == "b" or name == "start" then g:cancelTask() end
        return
    end
    if name == "start" then
        g:openMenu()
        return
    end
    if g:locked() then return end

    if name == "up" then
        self.cursor:moveUp(s)
    elseif name == "down" then
        self.cursor:moveDown(s)
    elseif name == "left" then
        self.cursor:moveLeft(s)
    elseif name == "right" then
        self.cursor:moveRight(s)
    elseif name == "a" then
        self:handleAButton()
    elseif name == "b" then
        s.selection = nil
        g:clearHint()
    elseif name == "x" then
        g:hintMove()
    elseif name == "y" then
        g:drawOne()
    elseif name == "select" then
        g:undo()
    elseif name == "winnable" then
        g:checkWinnable()
    elseif name == "finish" then
        g:finish()
    end
end

-- ========================================================
-- GAMEPAD
-- ========================================================

function Controls:gamepadpressed(joystick, button)
    if button == "leftshoulder" or button == "rightshoulder" then
        if button == "leftshoulder" then self.lHeld = true else self.rHeld = true end
        self.shoulder = { name = button, t = love.timer.getTime(), used = false }
        return
    end
    -- any other button while a shoulder is held means "auto-place", not a shortcut tap
    if self.shoulder then self.shoulder.used = true end

    local name = PAD_NAMES[button]
    if name then self:press(name) end
end

function Controls:gamepadreleased(joystick, button)
    if button == "leftshoulder" or button == "rightshoulder" then
        if button == "leftshoulder" then self.lHeld = false else self.rHeld = false end
        local sh = self.shoulder
        if sh and sh.name == button and not sh.used and (love.timer.getTime() - sh.t) < 0.5 then
            self:press(button == "leftshoulder" and "winnable" or "finish")
        end
        if sh and sh.name == button then self.shoulder = nil end
    end
end

-- ========================================================
-- KEYBOARD (testing on a PC)
-- ========================================================

function Controls:keypressed(key)
    if key == "lshift" or key == "l" then self.lHeld = true end
    if key == "rshift" or key == "r" then self.rHeld = true end
    local name = KEY_NAMES[key]
    if name then self:press(name) end
end

function Controls:keyreleased(key)
    if key == "lshift" or key == "l" then self.lHeld = false end
    if key == "rshift" or key == "r" then self.rHeld = false end
end

-- ========================================================
-- A BUTTON: SELECT / MOVE / AUTO-PLACE
-- ========================================================

function Controls:handleAButton()
    local g = self.game
    local s = self.solitaire
    local focus = self.cursor:getFocused(s)

    -- Case 1: L or R held -> AUTO-PLACE
    if self.lHeld or self.rHeld then
        if s.selection then
            local sel = s.selection
            g:act(function() return s:autoPlace(sel.source, sel.col, sel.cardIndex) end, "place")
        elseif focus.zone == "waste" then
            g:act(function() return s:autoPlace("waste", nil, nil) end, "place")
        elseif focus.zone == "tableau" and focus.card and focus.card.faceUp then
            g:act(function() return s:autoPlace("tableau", focus.col, focus.cardIndex) end, "place")
        end
        return
    end

    -- Case 2: stock focused -> draw
    if focus.zone == "stock" then
        g:drawOne()
        return
    end

    -- Case 3: a card is selected -> try to move it to the focused spot
    if s.selection then
        local sel = s.selection
        local moved = false
        if focus.zone == "foundation" then
            moved = g:act(function() return s:moveToFoundation(sel.source, sel.col, focus.col) end, "place")
        elseif focus.zone == "tableau" then
            moved = g:act(function() return s:moveToTableau(sel.source, sel.col, sel.cardIndex, focus.col) end, "place")
        end
        if moved then return end
        -- tried to place it on a different pile and it doesn't fit
        if (focus.zone == "foundation" or focus.zone == "tableau")
            and not (sel.source == "tableau" and focus.zone == "tableau" and sel.col == focus.col) then
            g:reject()
        end

        if focus.card and focus.card.faceUp then
            self:selectFromFocus(focus)
        else
            s.selection = nil
        end
        return
    end

    -- Case 4: nothing selected -> pick up the focused card
    self:selectFromFocus(focus)
end

function Controls:selectFromFocus(focus)
    local s = self.solitaire
    if focus.zone == "waste" and focus.card then
        s.selection = { source = "waste", col = nil, cardIndex = focus.cardIndex, card = focus.card }
        self.assets:playSound("flip")
    elseif focus.zone == "tableau" and focus.card and focus.card.faceUp then
        s.selection = { source = "tableau", col = focus.col, cardIndex = focus.cardIndex, card = focus.card }
        self.assets:playSound("flip")
    elseif focus.zone == "foundation" and focus.card then
        s.selection = { source = "foundation", col = focus.col, cardIndex = focus.cardIndex, card = focus.card }
        self.assets:playSound("flip")
    end
end

-- ========================================================
-- TOUCH / MOUSE (native 1024x768 table space)
-- ========================================================

local function inside(x, y, rx, ry, rw, rh)
    return x >= rx and x <= rx + rw and y >= ry and y <= ry + rh
end

function Controls:hitTest(x, y)
    local r = self.renderer
    local s = self.solitaire

    -- On-screen buttons
    if self.game:finishAvailable() and inside(x, y, r:getButtonRect("finish")) then
        return { type = "button", id = "finish" }
    end
    for _, id in ipairs({ "undo", "hint", "winnable", "menu", "deal" }) do
        if inside(x, y, r:getButtonRect(id)) then return { type = "button", id = id } end
    end

    -- Stock
    local sx, sy, sw, sh = r:getStockRect()
    if inside(x, y, sx, sy, sw, sh) then return { type = "stock" } end

    -- Waste
    local wx, wy, ww, wh = r:getWasteRect()
    if inside(x, y, wx, wy, ww, wh) then
        return { type = "waste", cardX = wx, cardY = wy }
    end

    -- Foundations 1..4
    for f = 1, 4 do
        local fx, fy, fw, fh = r:getFoundationRect(f)
        if inside(x, y, fx, fy, fw, fh) then
            return { type = "foundation", col = f, cardX = fx, cardY = fy }
        end
    end

    -- Tableau columns 1..7
    for col = 1, 7 do
        local tx = r:getTableauX(col)
        local pile = s.tableau[col]
        if x >= tx and x <= tx + r.cardW then
            if #pile == 0 then
                if y >= r.tableauStartY and y <= r.tableauStartY + r.cardH then
                    return { type = "tableau", col = col, cardIndex = 0 }
                end
            else
                local _, _, faceDownStep, faceUpStep = r:getTableauCardRect(col, 1, #pile)
                local currentY = r.tableauStartY
                local cardHit, cardTop = nil, nil
                for i = 1, #pile do
                    local nextY = currentY + (pile[i].faceUp and faceUpStep or faceDownStep)
                    local bottomY = (i == #pile) and (currentY + r.cardH) or nextY
                    if y >= currentY and y <= bottomY then
                        cardHit = i
                        cardTop = currentY
                    end
                    currentY = nextY
                end
                if cardHit then
                    return { type = "tableau", col = col, cardIndex = cardHit, card = pile[cardHit],
                             cardX = tx, cardY = cardTop }
                end
            end
        end
    end

    return nil
end

function Controls:touchpressed(id, x, y) self:pointerPressed(x, y) end
function Controls:touchmoved(id, x, y) self:pointerMoved(x, y) end
function Controls:touchreleased(id, x, y) self:pointerReleased(x, y) end

function Controls:mousepressed(x, y, button)
    if button == 1 then self:pointerPressed(x, y) end
end
function Controls:mousemoved(x, y) self:pointerMoved(x, y) end
function Controls:mousereleased(x, y, button)
    if button == 1 then self:pointerReleased(x, y) end
end

function Controls:startDrag(hit, cards, x, y, step)
    self.dragging = true
    self.dragSource = hit
    self.dragCards = cards
    self._dragMap = {}
    for i, c in ipairs(cards) do self._dragMap[c.id] = i end
    self.dragOffX = x - hit.cardX
    self.dragOffY = y - hit.cardY
    self.dragX, self.dragY = x, y
    self.dragStep = step or 0
    self.dragStartX, self.dragStartY = x, y
    self.dragMoved = false
end

function Controls:endDrag()
    self.dragging = false
    self.dragSource = nil
    self.dragCards = nil
    self._dragMap = nil
    self.dragMoved = false
end

function Controls:pointerPressed(x, y)
    local g = self.game
    local s = self.solitaire

    if g.menu.open then
        g.menu:pointer(x, y)
        return
    end
    if g.task then
        g:cancelTask()
        return
    end

    local hit = self:hitTest(x, y)
    if hit and hit.type == "button" then
        g:pressButton(hit.id)
        return
    end
    if g:locked() then return end

    if not hit then
        s.selection = nil
        g:clearHint()
        return
    end

    -- Stock tap -> draw 1
    if hit.type == "stock" then
        g:drawOne()
        return
    end

    -- Double-tap -> auto-place
    local now = love.timer.getTime()
    if (now - self.lastTapTime) < 0.35 and self.lastTapTarget
        and self.lastTapTarget.type == hit.type and self.lastTapTarget.col == hit.col then
        if hit.type == "waste" then
            if g:act(function() return s:autoPlace("waste", nil, nil) end, "place") then return end
        elseif hit.type == "tableau" and hit.card and hit.card.faceUp and hit.cardIndex == #s.tableau[hit.col] then
            if g:act(function() return s:autoPlace("tableau", hit.col, hit.cardIndex) end, "place") then return end
        end
    end
    self.lastTapTime = now
    self.lastTapTarget = hit

    -- A card is already selected: try to move it to what was tapped
    if s.selection then
        local sel = s.selection
        local moved = false
        if hit.type == "foundation" then
            moved = g:act(function() return s:moveToFoundation(sel.source, sel.col, hit.col) end, "place")
        elseif hit.type == "tableau" then
            moved = g:act(function() return s:moveToTableau(sel.source, sel.col, sel.cardIndex, hit.col) end, "place")
        end
        if moved then return end
        if (hit.type == "foundation" or hit.type == "tableau")
            and not (sel.source == "tableau" and hit.type == "tableau" and sel.col == hit.col) then
            g:reject()
        end
    end

    -- Pick up the tapped card (and start a drag)
    if hit.type == "waste" and #s.waste > 0 then
        local card = s.waste[#s.waste]
        s.selection = { source = "waste", col = nil, cardIndex = #s.waste, card = card }
        self:startDrag(hit, { card }, x, y, 0)
        self.assets:playSound("flip")
    elseif hit.type == "tableau" and hit.card and hit.card.faceUp then
        local pile = s.tableau[hit.col]
        local cards = {}
        for i = hit.cardIndex, #pile do cards[#cards + 1] = pile[i] end
        s.selection = { source = "tableau", col = hit.col, cardIndex = hit.cardIndex, card = hit.card }
        local _, _, _, faceUpStep = self.renderer:getTableauCardRect(hit.col, 1, #pile)
        self:startDrag(hit, cards, x, y, faceUpStep)
        self.assets:playSound("flip")
    elseif hit.type == "foundation" and #s.foundations[hit.col] > 0 then
        local fPile = s.foundations[hit.col]
        local card = fPile[#fPile]
        s.selection = { source = "foundation", col = hit.col, cardIndex = #fPile, card = card }
        self:startDrag(hit, { card }, x, y, 0)
        self.assets:playSound("flip")
    end
end

function Controls:pointerMoved(x, y)
    if not self.dragging then return end
    self.dragX, self.dragY = x, y
    if not self.dragMoved then
        local dx, dy = x - self.dragStartX, y - self.dragStartY
        if dx * dx + dy * dy > 64 then self.dragMoved = true end
    end
end

-- Which pile did the dragged card land on? Uses how much the card overlaps each pile,
-- so it does not matter exactly where the finger is.
function Controls:findDropTarget()
    local s = self.solitaire
    local r = self.renderer
    local sel = s.selection
    if not sel or not self.dragCards then return nil end
    local card = self.dragCards[1]
    local dx, dy = self:dragPos(1)
    local cw, ch = r.cardW, r.cardH

    local function overlap(x, y)
        local w = math.min(dx + cw, x + cw) - math.max(dx, x)
        local h = math.min(dy + ch, y + ch) - math.max(dy, y)
        if w <= 0 or h <= 0 then return 0 end
        return w * h
    end

    local best, bestArea = nil, cw * ch * 0.1
    if #self.dragCards == 1 then
        for f = 1, 4 do
            local fx, fy = r:getFoundationRect(f)
            local a = overlap(fx, fy)
            if a > bestArea and s:canMoveToFoundation(card, f) then
                best, bestArea = { type = "foundation", col = f }, a
            end
        end
    end
    for t = 1, 7 do
        if not (sel.source == "tableau" and sel.col == t) then
            local tx, ty = r:zoneRect(s, "tableau", t)
            local a = overlap(tx, ty)
            if a > bestArea and s:canMoveToTableau(card, t) then
                best, bestArea = { type = "tableau", col = t }, a
            end
        end
    end
    if best then return best end

    -- Fallback: wherever the finger is
    local hit = self:hitTest(self.dragX, self.dragY)
    if hit and hit.type == "tableau" and not (sel.source == "tableau" and sel.col == hit.col)
        and s:canMoveToTableau(card, hit.col) then
        return { type = "tableau", col = hit.col }
    elseif hit and hit.type == "foundation" and #self.dragCards == 1 and s:canMoveToFoundation(card, hit.col) then
        return { type = "foundation", col = hit.col }
    end
    return nil
end

function Controls:pointerReleased(x, y)
    if not self.dragging then return end
    local g = self.game
    local s = self.solitaire
    self.dragX, self.dragY = x, y

    local target = self:findDropTarget()
    local sel = s.selection
    local moved = false
    -- (still "dragging" here, so the card glides on from where the finger let go)
    moved = g:act(function()
        if not target or not sel then return false end
        if target.type == "foundation" then
            return s:moveToFoundation(sel.source, sel.col, target.col)
        end
        return s:moveToTableau(sel.source, sel.col, sel.cardIndex, target.col)
    end, "place")

    local wasRealDrag = self.dragMoved
    -- dropped on a pile it doesn't fit (not its own pile, not empty felt)?
    if not moved and wasRealDrag and sel then
        local over = self:hitTest(x, y)
        if over and (over.type == "foundation" or over.type == "tableau")
            and not (sel.source == "tableau" and over.type == "tableau" and sel.col == over.col) then
            g:reject()
        end
    end
    self:endDrag()
    -- a drag that went nowhere puts the card back and drops the selection
    if not moved and wasRealDrag then s.selection = nil end
end

return Controls
