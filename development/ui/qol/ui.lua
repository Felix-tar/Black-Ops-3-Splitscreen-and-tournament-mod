-- Small UI toolkit for the QoL menus: menus owned by one controller, button
-- handlers with keyboard shortcuts, mouse clicks, text rows positioned
-- relative to the screen centre (so non-16:9 windows keep the layout centred).
require("ui.qol.util")

local QoL = CoD.QoL
local UI = {}
QoL.ui = UI

UI.ORANGE = { 1, 0.55, 0.12 }
UI.WHITE = { 0.92, 0.92, 0.92 }
UI.GREY = { 0.6, 0.6, 0.6 }
UI.RED = { 1, 0.35, 0.25 }
UI.GREEN = { 0.45, 0.9, 0.45 }

-- Text anchored to the horizontal centre; x is given in 1280-wide coordinates.
function UI.text(parent, text, x, y, width, height, color, align)
    local element = LUI.UIText.new()
    element:setLeftRight(false, false, x - 640, x - 640 + width)
    element:setTopBottom(true, false, y, y + height)
    element:setTTF("fonts/default.ttf")
    element:setAlignment(align or Enum.LUIAlignment.LUI_ALIGNMENT_LEFT)
    element:setText(text or "")
    if color then
        element:setRGB(color[1], color[2], color[3])
    end
    parent:addElement(element)
    return element
end

function UI.panel(parent, x, y, width, height, alpha)
    local image = LUI.UIImage.new()
    image:setLeftRight(false, false, x - 640, x - 640 + width)
    image:setTopBottom(true, false, y, y + height)
    image:setRGB(0.02, 0.025, 0.03)
    image:setAlpha(alpha or 0.9)
    parent:addElement(image)
    return image
end

-- Image anchored like UI.text; name may be nil/"" (hidden until set).
function UI.image(parent, x, y, width, height, name)
    local element = LUI.UIImage.new()
    element:setLeftRight(false, false, x - 640, x - 640 + width)
    element:setTopBottom(true, false, y, y + height)
    parent:addElement(element)
    UI.setImage(element, name)
    return element
end

local HIDDEN_IMAGES = { [""] = true, blacktransparent = true, ["$blacktransparent"] = true }

function UI.setImage(element, name)
    if type(name) ~= "string" or HIDDEN_IMAGES[name] then
        element:setAlpha(0)
        return false
    end
    local ok = pcall(function()
        element:setImage(RegisterImage(name))
    end)
    element:setAlpha(ok and 1 or 0)
    return ok
end

function UI.fullscreenGround(parent, alpha)
    local image = LUI.UIImage.new()
    image:setLeftRight(true, true, 0, 0)
    image:setTopBottom(true, true, 0, 0)
    image:setRGB(0.02, 0.025, 0.03)
    image:setAlpha(alpha or 0.95)
    parent:addElement(image)
    return image
end

-- Mouse: fn("left") / fn("right") when the element is clicked. LUI sends
-- leftmouseup/rightmouseup to elements with handleMouse after a press inside.
function UI.onClick(element, fn)
    element:setHandleMouse(true)
    element:registerEventHandler("leftmouseup", function(_, event)
        if event.inside then
            QoL.safe("ui.click", fn, "left")
            return true
        end
    end)
    element:registerEventHandler("rightmouseup", function(_, event)
        if event.inside then
            QoL.safe("ui.click", fn, "right")
            return true
        end
    end)
end

-- Clickable text, e.g. "ZURÜCK" in the bottom right corner.
function UI.button(parent, text, x, y, width, fn, color)
    local element = UI.text(parent, "[ " .. text .. " ]", x, y, width, 24, color or UI.ORANGE,
        Enum.LUIAlignment.LUI_ALIGNMENT_RIGHT)
    UI.onClick(element, fn)
    return element
end

function UI.newMenu(name, controller)
    local menu = CoD.Menu.NewForUIEditor(name)
    menu:setOwner(controller)
    menu:setLeftRight(true, true, 0, 0)
    menu:setTopBottom(true, true, 0, 0)
    menu.qolController = controller
    return menu
end

local BUTTONS = {
    up = { Enum.LUIButton.LUI_KEY_UP, "UPARROW" },
    down = { Enum.LUIButton.LUI_KEY_DOWN, "DOWNARROW" },
    left = { Enum.LUIButton.LUI_KEY_LEFT, "LEFTARROW" },
    right = { Enum.LUIButton.LUI_KEY_RIGHT, "RIGHTARROW" },
    confirm = { Enum.LUIButton.LUI_KEY_XBA_PSCROSS, "ENTER" },
    back = { Enum.LUIButton.LUI_KEY_XBB_PSCIRCLE, "ESCAPE" },
    extra = { Enum.LUIButton.LUI_KEY_XBX_PSSQUARE, "SPACE" }
}

-- handlers: { up = fn, down = fn, ... }; each handler is protected.
function UI.bindButtons(menu, controller, handlers)
    for key, fn in pairs(handlers) do
        local button = BUTTONS[key]
        if button then
            menu:AddButtonCallbackFunction(menu, controller, button[1], button[2], function()
                QoL.safe(tostring(menu.menuName) .. "." .. key, fn)
                return true
            end)
        end
    end
end

-- Vertical list of text rows. items: { { text = "...", color = {...} }, ... }
-- A click selects the row and calls list.onClick(item, button) if set.
function UI.newList(parent, x, y, width, rowHeight, visibleRows)
    local list = { rows = {}, items = {}, selected = 1, offset = 0, visible = visibleRows }
    for index = 1, visibleRows do
        local row = UI.text(parent, "", x, y + (index - 1) * rowHeight, width, rowHeight - 6)
        UI.onClick(row, function(button)
            local item = list.items[index + list.offset]
            if not item then
                return
            end
            list.selected = index + list.offset
            list.paint()
            if list.onClick then
                list.onClick(item, button)
            end
        end)
        list.rows[index] = row
    end

    function list.paint()
        if list.selected > #list.items then list.selected = math.max(1, #list.items) end
        if list.selected < list.offset + 1 then list.offset = list.selected - 1 end
        if list.selected > list.offset + list.visible then list.offset = list.selected - list.visible end
        for index, row in ipairs(list.rows) do
            local item = list.items[index + list.offset]
            if item then
                local prefix = (index + list.offset == list.selected) and "> " or "  "
                row:setText(prefix .. item.text)
                local color = item.color or UI.WHITE
                if index + list.offset == list.selected then
                    color = UI.ORANGE
                end
                row:setRGB(color[1], color[2], color[3])
            else
                row:setText("")
            end
        end
    end

    function list.setItems(items)
        list.items = items or {}
        list.paint()
    end

    function list.move(delta)
        if #list.items == 0 then return end
        list.selected = (list.selected - 1 + delta) % #list.items + 1
        list.paint()
    end

    function list.select(index)
        list.selected = math.max(1, math.min(index, #list.items))
        list.paint()
    end

    function list.current()
        return list.items[list.selected]
    end

    return list
end

-- Opens the PC text entry for `controller`; onText(text) runs on completion.
-- keyboardType: Enum.KeyboardType name, default KEYBOARD_TYPE_CUSTOM_CLASS
-- (short names); longer types allow longer text.
function UI.askText(menu, controller, onText, keyboardType)
    keyboardType = keyboardType or "KEYBOARD_TYPE_CUSTOM_CLASS"
    menu.qolPendingText = onText
    menu.qolPendingType = Enum.KeyboardType[keyboardType]
    menu:registerEventHandler("ui_keyboard_input", function(element, event)
        if element.qolPendingText and event.type == element.qolPendingType then
            local callback = element.qolPendingText
            element.qolPendingText = nil
            if event.input then
                QoL.safe("ui.askText", callback, event.input)
            end
            return true
        end
    end)
    ShowKeyboard(menu, menu, controller, keyboardType)
end

function UI.close(menu)
    GoBack(menu, menu.qolController)
end
