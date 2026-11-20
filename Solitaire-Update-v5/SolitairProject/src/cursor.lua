local Cursor = {}
Cursor.__index = Cursor

function Cursor.new()
    local self = setmetatable({}, Cursor)
    self.zone = "tableau"     -- "top" or "tableau"
    self.topIndex = 1         -- 1: Stock, 2: Waste, 3: F1, 4: F2, 5: F3, 6: F4
    self.tableauCol = 1       -- 1..7
    self.cardIndex = 1        -- Card index inside tableau column
    self.cursorAnim = 0       -- Pulsing animation counter
    return self
end

function Cursor:update(dt)
    self.cursorAnim = (self.cursorAnim + dt * 4) % (math.pi * 2)
end

function Cursor:getFocused(solitaire)
    if self.zone == "top" then
        if self.topIndex == 1 then
            local card = #solitaire.stock > 0 and solitaire.stock[#solitaire.stock] or nil
            return { zone = "stock", col = nil, cardIndex = #solitaire.stock, card = card }
        elseif self.topIndex == 2 then
            local card = #solitaire.waste > 0 and solitaire.waste[#solitaire.waste] or nil
            return { zone = "waste", col = nil, cardIndex = #solitaire.waste, card = card }
        else
            local fIndex = self.topIndex - 2
            local pile = solitaire.foundations[fIndex]
            local card = #pile > 0 and pile[#pile] or nil
            return { zone = "foundation", col = fIndex, cardIndex = #pile, card = card }
        end
    else
        local col = solitaire.tableau[self.tableauCol]
        local count = #col
        if count == 0 then
            return { zone = "tableau", col = self.tableauCol, cardIndex = 0, card = nil }
        end
        -- Clamp cardIndex
        if self.cardIndex > count then self.cardIndex = count end
        if self.cardIndex < 1 then self.cardIndex = count end
        return { zone = "tableau", col = self.tableauCol, cardIndex = self.cardIndex, card = col[self.cardIndex] }
    end
end

function Cursor:moveLeft(solitaire)
    if self.zone == "top" then
        if self.topIndex > 1 then
            self.topIndex = self.topIndex - 1
        end
    else
        if self.tableauCol > 1 then
            self.tableauCol = self.tableauCol - 1
            local col = solitaire.tableau[self.tableauCol]
            self.cardIndex = math.max(1, #col)
        end
    end
end

function Cursor:moveRight(solitaire)
    if self.zone == "top" then
        if self.topIndex < 6 then
            self.topIndex = self.topIndex + 1
        end
    else
        if self.tableauCol < 7 then
            self.tableauCol = self.tableauCol + 1
            local col = solitaire.tableau[self.tableauCol]
            self.cardIndex = math.max(1, #col)
        end
    end
end

function Cursor:moveUp(solitaire)
    if self.zone == "tableau" then
        local col = solitaire.tableau[self.tableauCol]
        -- If we can move up within face-up cards in this tableau column
        if self.cardIndex > 1 and col[self.cardIndex - 1] and col[self.cardIndex - 1].faceUp then
            self.cardIndex = self.cardIndex - 1
        else
            -- Move to top row
            self.zone = "top"
            if self.tableauCol <= 2 then
                self.topIndex = self.tableauCol -- 1 = Stock, 2 = Waste
            elseif self.tableauCol == 3 then
                self.topIndex = 2 -- Waste
            else
                self.topIndex = self.tableauCol - 1 -- Maps 4, 5, 6, 7 to foundations 1, 2, 3, 4 (topIndex 3..6)
            end
        end
    end
end

function Cursor:moveDown(solitaire)
    if self.zone == "top" then
        self.zone = "tableau"
        if self.topIndex <= 2 then
            self.tableauCol = self.topIndex
        else
            self.tableauCol = math.min(7, self.topIndex + 1)
        end
        local col = solitaire.tableau[self.tableauCol]
        self.cardIndex = math.max(1, #col)
    else
        local col = solitaire.tableau[self.tableauCol]
        if self.cardIndex < #col then
            self.cardIndex = self.cardIndex + 1
        end
    end
end

return Cursor

