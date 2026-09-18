-- Copy one class or all classes between the two local players (or within one
-- profile). Items are copied slot by slot with Engine.Get/SetClassItem, the
-- slot list is the stock "clear loadout" list, so no raw profile data is touched.
-- Opened from the lobby (KLASSEN KOPIEREN), the player 2 card and the split menu.
require("ui.qol.util")
require("ui.qol.ui")

local QoL = CoD.QoL
local UI = QoL.ui
local ClassCopy = {}
QoL.classCopy = ClassCopy

local EXTRA_SLOTS = {
    "primarypaintjobslot", "primarypaintjobindex", "secondarypaintjobslot", "secondarypaintjobindex",
    "primarygadgetcount", "secondarygadgetcount", "specialgadgetcount"
}

local function unlockMode()
    local ok, mode = pcall(CoD.PrestigeUtility.GetPermanentUnlockMode)
    return ok and mode or Enum.eModes.MODE_MULTIPLAYER
end

local function prepare(controller)
    pcall(CoD.CACUtility.SetDefaultCACRoot, controller)
end

function ClassCopy.classCount(controller)
    local ok, count = pcall(Engine.GetCustomClassCount, controller)
    return (ok and count) or CoD.CACUtility.maxCustomClass or 5
end

function ClassCopy.className(controller, classNum)
    prepare(controller)
    local ok, name = pcall(function()
        return CoD.CACUtility.GetLoadoutNameFromIndex(controller, classNum):get()
    end)
    if ok and type(name) == "string" and name ~= "" then
        return name
    end
    return "Klasse " .. tostring(classNum + 1)
end

local function itemName(controller, classNum, slot)
    local ok, index = pcall(Engine.GetClassItem, controller, classNum, slot, unlockMode())
    if not ok or not index or index == CoD.CACUtility.EmptyItemIndex then
        return "-"
    end
    local okName, name = pcall(Engine.GetItemName, index, unlockMode())
    if okName and name then
        return Engine.Localize(name)
    end
    return "?"
end

function ClassCopy.preview(controller, classNum)
    return itemName(controller, classNum, "primary") .. " / " .. itemName(controller, classNum, "secondary")
end

local function copySlots(sourceController, sourceClass, targetController, targetClass)
    local mode = unlockMode()
    if sourceController == targetController then
        Engine.ExecNow(targetController, "copyClass " .. sourceClass .. " " .. targetClass)
        return
    end
    local slots = {}
    for _, slot in ipairs(CoD.CACUtility.clearLoadoutSlotOrder) do
        table.insert(slots, slot)
    end
    for _, slot in ipairs(EXTRA_SLOTS) do
        table.insert(slots, slot)
    end
    for _, slot in ipairs(slots) do
        local ok, value = pcall(Engine.GetClassItem, sourceController, sourceClass, slot, mode)
        if ok and value ~= nil then
            pcall(Engine.SetClassItem, targetController, targetClass, slot, value)
        end
    end
    local name = ClassCopy.className(sourceController, sourceClass)
    prepare(targetController)
    pcall(function()
        CoD.CACUtility.GetLoadoutNameFromIndex(targetController, targetClass):set(name)
    end)
end

local function finish(targetController)
    pcall(CoD.CACUtility.UpdateAllClasses, targetController)
    pcall(Engine.Exec, targetController, "saveLoadout " .. tostring(CoD.CCUtility.customizationMode or unlockMode()))
end

function ClassCopy.copy(sourceController, sourceClass, targetController, targetClass)
    copySlots(sourceController, sourceClass, targetController, targetClass)
    finish(targetController)
    QoL.log("Klasse " .. (sourceClass + 1) .. " kopiert")
end

-- Copies every class the target profile has room for; returns the count.
function ClassCopy.copyAll(sourceController, targetController)
    local count = math.min(ClassCopy.classCount(sourceController), ClassCopy.classCount(targetController))
    for classNum = 0, count - 1 do
        copySlots(sourceController, classNum, targetController, classNum)
    end
    finish(targetController)
    QoL.log("Alle " .. count .. " Klassen kopiert")
    return count
end

-- Preview --------------------------------------------------------------------

local function localizeName(text)
    if type(text) ~= "string" or text == "" then
        return nil
    end
    local ok, result = pcall(Engine.Localize, text)
    if ok and type(result) == "string" and result ~= "" then
        return result
    end
    return text
end

-- Reads one class through the stock class model (the same data the class
-- editor shows): slot images, names and whether a slot is empty.
function ClassCopy.classInfo(controller, classNum)
    prepare(controller)
    local model = Engine.CreateModel(Engine.GetModelForController(controller), "qolClassPreview")
    CoD.CACUtility.GetCustomClassModel(controller, classNum, model)
    local function value(path)
        return CoD.SafeGetModelValue(model, path)
    end
    local emptyIndex = CoD.CACUtility.EmptyItemIndex or 0
    local function slot(name, imageSuffix)
        local index = value(name .. ".itemIndex")
        if type(index) ~= "number" or index <= emptyIndex then
            return { empty = true }
        end
        return {
            image = (imageSuffix and value(name .. "." .. imageSuffix)) or value(name .. ".image"),
            name = localizeName(value(name .. ".name")) or "?"
        }
    end
    local info = { name = ClassCopy.className(controller, classNum), attachments = { primary = {}, secondary = {} },
        perks = {}, wildcards = {} }
    info.primary = slot("primary", "image_big")
    info.secondary = slot("secondary", "image_big")
    for index = 1, 6 do
        info.attachments.primary[index] = slot("primaryattachment" .. index)
        info.attachments.secondary[index] = slot("secondaryattachment" .. index)
        info.perks[index] = slot("specialty" .. index)
    end
    for index = 1, 3 do
        info.wildcards[index] = slot("bonuscard" .. index)
    end
    info.lethal = slot("primarygadget", "image_big")
    info.tactical = slot("secondarygadget", "image_big")
    return info
end

local function names(slots)
    local result = {}
    for _, entry in ipairs(slots) do
        if not entry.empty then
            table.insert(result, entry.name)
        end
    end
    return result
end

-- Panel with pictures of one class (x..x+400, y..y+300) or, for "all
-- classes", a text list of every class.
local function newPreview(parent, x, y)
    local preview = {}
    UI.panel(parent, x - 8, y - 6, 416, 314, 0.7)
    local header = UI.text(parent, "", x, y, 400, 22, UI.ORANGE)
    local className = UI.text(parent, "", x, y + 24, 400, 22, UI.WHITE)

    local single = LUI.UIElement.new()
    single:setLeftRight(true, true, 0, 0)
    single:setTopBottom(true, true, 0, 0)
    parent:addElement(single)
    local weapons = {}
    for index, key in ipairs({ "primary", "secondary" }) do
        local top = y + 52 + (index - 1) * 88
        local weapon = {
            image = UI.image(single, x, top, 160, 80),
            name = UI.text(single, "", x + 170, top + 2, 230, 20, UI.WHITE),
            attachments = {}
        }
        for slotIndex = 1, 6 do
            weapon.attachments[slotIndex] = UI.image(single, x + 170 + (slotIndex - 1) * 38, top + 28, 34, 34)
        end
        weapons[key] = weapon
    end
    local lethal = UI.image(single, x, y + 230, 44, 44)
    local tactical = UI.image(single, x + 50, y + 230, 44, 44)
    local perks = {}
    for index = 1, 6 do
        perks[index] = UI.image(single, x + 110 + (index - 1) * 40, y + 232, 38, 38)
    end
    local wildcardRow = {}
    for index = 1, 3 do
        wildcardRow[index] = UI.image(single, x + (index - 1) * 34, y + 278, 30, 30)
    end
    local details = UI.text(single, "", x + 110, y + 284, 290, 16, UI.GREY)

    local listRows = {}
    for index = 1, 10 do
        listRows[index] = UI.text(parent, "", x, y + 52 + (index - 1) * 25, 400, 20, UI.WHITE)
    end

    local function clearList()
        for _, row in ipairs(listRows) do
            row:setText("")
        end
    end

    function preview.hide(title, text)
        header:setText(title or "")
        className:setText(text or "")
        single:setAlpha(0)
        clearList()
    end

    function preview.showClass(title, controller, classNum)
        clearList()
        header:setText(title)
        local ok, info = pcall(ClassCopy.classInfo, controller, classNum)
        if not ok or not info then
            className:setText("Vorschau nicht verfügbar")
            single:setAlpha(0)
            return
        end
        single:setAlpha(1)
        className:setText((classNum + 1) .. ".  " .. tostring(info.name))
        for key, weapon in pairs(weapons) do
            local slot = info[key]
            UI.setImage(weapon.image, slot.image)
            weapon.name:setText(slot.empty and "- leer -" or slot.name)
            for index, image in ipairs(weapon.attachments) do
                UI.setImage(image, info.attachments[key][index].image)
            end
        end
        UI.setImage(lethal, info.lethal.image)
        UI.setImage(tactical, info.tactical.image)
        for index, image in ipairs(perks) do
            UI.setImage(image, info.perks[index].image)
        end
        for index, image in ipairs(wildcardRow) do
            UI.setImage(image, info.wildcards[index].image)
        end
        local parts = {}
        for _, name in ipairs(names({ info.lethal, info.tactical })) do table.insert(parts, name) end
        for _, name in ipairs(names(info.wildcards)) do table.insert(parts, name) end
        details:setText(table.concat(parts, ", "))
    end

    function preview.showAll(title, controller)
        single:setAlpha(0)
        header:setText(title)
        className:setText("Alle Klassen")
        clearList()
        local count = math.min(ClassCopy.classCount(controller), #listRows)
        for classNum = 0, count - 1 do
            local ok, info = pcall(ClassCopy.classInfo, controller, classNum)
            local text = (classNum + 1) .. ".  " .. ClassCopy.className(controller, classNum)
            if ok and info then
                text = text .. "  -  " .. (info.primary.empty and "-" or info.primary.name) .. " / "
                    .. (info.secondary.empty and "-" or info.secondary.name)
            end
            listRows[classNum + 1]:setText(text)
        end
    end

    return preview
end

-- Menu --------------------------------------------------------------------

local function playerLabel(localClient)
    local name = QoL.data and QoL.safe("classCopy.name", QoL.data.displayName, localClient)
    return "Spieler " .. (localClient + 1) .. (name and ("  (" .. name .. ")") or "")
end

LUI.createMenu.QoLClassCopy = function(controller, userData)
    local self = UI.newMenu("QoLClassCopy", controller)
    UI.fullscreenGround(self, 0.97)

    local ownPlayer = userData and userData.player or QoL.safe("classCopy.own", Engine.GetLocalClientNum, controller) or 0
    local otherPlayer = ownPlayer == 0 and 1 or 0
    local state = {
        all = false,
        sourcePlayer = otherPlayer, sourceClass = 0,
        targetPlayer = ownPlayer, targetClass = 0,
        row = 1, confirming = false
    }
    local ROWS = 6

    -- Everything stays within menu x 50..903: that part is visible in a
    -- half of the split screen.
    UI.text(self, "KLASSEN KOPIEREN", 70, 28, 800, 40, UI.ORANGE)
    local rows = {}
    for index = 1, ROWS do
        rows[index] = UI.text(self, "", 70, 76 + (index - 1) * 37, 820, 30)
    end
    local message = UI.text(self, "", 70, 304, 820, 24, UI.WHITE)
    local sourcePreview = newPreview(self, 70, 344)
    local targetPreview = newPreview(self, 490, 344)
    UI.text(self, "Hoch/Runter: Zeile   Links/Rechts oder Klick: ändern   A/Enter: auswählen   B/Esc: zurück", 70, 668, 620, 18, UI.GREY)

    local function controllerOf(player)
        return QoL.controllerForLocalClient(player)
    end

    local function clampClass(player, classNum)
        local c = controllerOf(player)
        local count = c and ClassCopy.classCount(c) or 1
        return (classNum % count + count) % count
    end

    local function classText(player, classNum)
        local c = controllerOf(player)
        if not c then
            return "- (Spieler nicht angemeldet)"
        end
        if state.all then
            return "alle " .. ClassCopy.classCount(c) .. " Klassen"
        end
        return "< " .. (classNum + 1) .. "  " .. ClassCopy.className(c, classNum) .. " >"
    end

    local function paint()
        local sc, tc = controllerOf(state.sourcePlayer), controllerOf(state.targetPlayer)
        local texts = {
            "Umfang:  < " .. (state.all and "Alle Klassen" or "Eine Klasse") .. " >",
            "Von:   < " .. playerLabel(state.sourcePlayer) .. " >",
            "Klasse:  " .. classText(state.sourcePlayer, state.sourceClass),
            "Nach:  < " .. playerLabel(state.targetPlayer) .. " >",
            "Klasse:  " .. classText(state.targetPlayer, state.targetClass),
            "KOPIEREN"
        }
        for index, row in ipairs(rows) do
            local selected = index == state.row
            row:setText((selected and "> " or "  ") .. texts[index])
            local color = selected and UI.ORANGE or UI.WHITE
            if index == ROWS and not selected then
                color = UI.GREEN
            end
            row:setRGB(color[1], color[2], color[3])
        end
        -- Reading a class model is not free: only when the selection changed.
        local key = table.concat({ tostring(state.all), state.sourcePlayer, state.sourceClass,
            state.targetPlayer, state.targetClass, state.version or 0 }, ":")
        if key ~= state.previewKey then
            state.previewKey = key
            local sourceTitle = "VON: " .. playerLabel(state.sourcePlayer)
            local targetTitle = "NACH: " .. playerLabel(state.targetPlayer) .. "  (wird überschrieben)"
            if not sc then
                sourcePreview.hide(sourceTitle, "Spieler nicht angemeldet")
            elseif state.all then
                sourcePreview.showAll(sourceTitle, sc)
            else
                sourcePreview.showClass(sourceTitle, sc, state.sourceClass)
            end
            if not tc then
                targetPreview.hide(targetTitle, "Spieler nicht angemeldet")
            elseif state.all then
                targetPreview.showAll(targetTitle, tc)
            else
                targetPreview.showClass(targetTitle, tc, state.targetClass)
            end
        end
        if state.confirming then
            local what = state.all and "ALLE Klassen" or ("Klasse " .. (state.targetClass + 1))
            message:setText(what .. " von Spieler " .. (state.targetPlayer + 1) .. " überschreiben?   A/Enter/KOPIEREN: Ja   B/Esc: Nein")
            message:setRGB(UI.RED[1], UI.RED[2], UI.RED[3])
        end
    end

    local function change(delta)
        if state.confirming then return end
        if state.row == 1 then
            state.all = not state.all
        elseif state.row == 2 then
            state.sourcePlayer = state.sourcePlayer == 0 and 1 or 0
            state.sourceClass = clampClass(state.sourcePlayer, state.sourceClass)
        elseif state.row == 3 and not state.all then
            state.sourceClass = clampClass(state.sourcePlayer, state.sourceClass + delta)
        elseif state.row == 4 then
            state.targetPlayer = state.targetPlayer == 0 and 1 or 0
            state.targetClass = clampClass(state.targetPlayer, state.targetClass)
        elseif state.row == 5 and not state.all then
            state.targetClass = clampClass(state.targetPlayer, state.targetClass + delta)
        end
        message:setText("")
        paint()
    end

    local function runCopy()
        local sc, tc = controllerOf(state.sourcePlayer), controllerOf(state.targetPlayer)
        if not sc or not tc then
            message:setText("Beide Spieler müssen angemeldet sein (Splitscreen aktivieren).")
        elseif sc == tc and (state.all or state.sourceClass == state.targetClass) then
            message:setText("Quelle und Ziel sind gleich.")
        elseif state.all then
            local count = ClassCopy.copyAll(sc, tc)
            message:setText(count .. " Klassen von Spieler " .. (state.sourcePlayer + 1) .. " nach Spieler "
                .. (state.targetPlayer + 1) .. " kopiert.")
            message:setRGB(UI.GREEN[1], UI.GREEN[2], UI.GREEN[3])
        else
            ClassCopy.copy(sc, state.sourceClass, tc, state.targetClass)
            message:setText("Kopiert: " .. ClassCopy.className(tc, state.targetClass))
            message:setRGB(UI.GREEN[1], UI.GREEN[2], UI.GREEN[3])
        end
    end

    local handlers = {
        up = function() if not state.confirming then state.row = (state.row + ROWS - 2) % ROWS + 1; paint() end end,
        down = function() if not state.confirming then state.row = state.row % ROWS + 1; paint() end end,
        left = function() change(-1) end,
        right = function() change(1) end,
        confirm = function()
            if state.confirming then
                state.confirming = false
                message:setRGB(UI.WHITE[1], UI.WHITE[2], UI.WHITE[3])
                runCopy()
                -- The target changed: read its preview again.
                state.version = (state.version or 0) + 1
                paint()
            elseif state.row == ROWS then
                state.confirming = true
                paint()
            else
                change(1)
            end
        end,
        back = function()
            if state.confirming then
                state.confirming = false
                message:setText("")
                paint()
            else
                UI.close(self)
            end
        end
    }
    UI.bindButtons(self, controller, handlers)

    -- Mouse: left click = select row and change / copy, right click = change back.
    for index, row in ipairs(rows) do
        UI.onClick(row, function(button)
            if state.confirming then
                if index == ROWS and button == "left" then
                    handlers.confirm()
                else
                    handlers.back()
                end
                return
            end
            state.row = index
            if index == ROWS then
                handlers.confirm()
            else
                change(button == "right" and -1 or 1)
            end
        end)
    end
    -- Inside the split screen only menu x 50..903 is visible.
    UI.button(self, "ZURÜCK", 700, 660, 170, handlers.back)

    paint()
    return self
end

-- Opens the copy screen over the lobby for one local player (0 or 1).
function ClassCopy.open(menu, localClient)
    localClient = localClient or 0
    local controller = QoL.controllerForLocalClient(localClient)
    if controller == nil or not menu or menu.occludedBy then
        return false
    end
    OpenOverlay(menu, "QoLClassCopy", controller, { player = localClient })
    return true
end
