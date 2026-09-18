-- Controller assignment for local player 1 (P1) next to the stock
-- "Eingabegeraet Spieler 2" option, plus a watchdog that restores the
-- desired mapping when BO3 loses it (controller reconnect, splitscreen join).
--
-- Engine API (PC, from startmenu_options_controls_pc and the executable):
--   GamepadsConnectedPortMapping() -> { displayName = "port" }
--   GamepadsConnectedPort(localPlayer), GamepadsConnectedIsActive(localPlayer)
--   GamepadsConnectedMap(localPlayer, port), GamepadsConnectedMapAny(localPlayer)
--   GamepadsConnectedUnMap(localPlayer), GamepadsConnectedValidPort(port)
require("ui.qol.util")
require("ui.qol.lang")

local QoL = CoD.QoL
local Input = {}
QoL.input = Input

local HOST = 0
local GUEST = 1

Input.MODE_AUTO = -2
Input.MODE_KEYBOARD = -1
local DVAR = "qol_p1_input"
-- Session copy stored as mode + 10 so an unset dvar (0) means "not set".
local DVAR_OFFSET = 10

Input.cooldown = 0
Input.lastAction = "none"

-- The choice is kept permanently in the profile store (record I, data.lua)
-- and for the running session in a dvar (menus are reloaded after a match).
function Input.getMode()
    if Input.mode == nil then
        local stored = QoL.getDvarInt(DVAR, 0)
        if stored ~= 0 then
            Input.mode = stored - DVAR_OFFSET
        else
            local ok, state = false, nil
            if QoL.data then
                ok, state = pcall(QoL.data.get)
            end
            if not (ok and state and QoL.data.available) then
                -- Store not readable yet: automatic for now, ask again later.
                return Input.MODE_AUTO
            end
            Input.mode = state.inputMode or Input.MODE_AUTO
        end
    end
    return Input.mode
end

local function storeMode(mode)
    Input.mode = mode
    QoL.setSessionValue(DVAR, mode + DVAR_OFFSET)
    if QoL.data then
        QoL.safe("input.storeMode", function()
            local state = QoL.data.get()
            if state.inputMode ~= mode then
                state.inputMode = mode
                QoL.data.save()
            end
        end)
    end
end

function Input.setMode(mode)
    storeMode(tonumber(mode) or Input.MODE_AUTO)
    Input.cooldown = 0
    QoL.log("input player 1 = " .. Input.modeName(Input.mode))
    QoL.safe("input.reconcile", Input.reconcile)
end

function Input.modeName(mode)
    if mode == Input.MODE_AUTO then
        return QoL.L("set_auto")
    elseif mode == Input.MODE_KEYBOARD then
        return QoL.L("set_keyboard")
    end
    for name, port in pairs(Engine.GamepadsConnectedPortMapping() or {}) do
        if tonumber(port) == mode then
            return tostring(name)
        end
    end
    return QoL.L("set_pad_port", mode)
end

local function connectedPorts()
    local ports = {}
    for _, port in pairs(Engine.GamepadsConnectedPortMapping() or {}) do
        local number = tonumber(port)
        if number then
            table.insert(ports, number)
        end
    end
    table.sort(ports)
    return ports
end

-- Connected means "listed in the port mapping". GamepadsConnectedValidPort is
-- not used: a port held by the other player did not count as valid, which
-- made a chosen controller look unavailable instead of triggering a swap.
local function isConnected(port)
    if type(port) ~= "number" or port < 0 then
        return false
    end
    for _, connected in ipairs(connectedPorts()) do
        if connected == port then
            return true
        end
    end
    return false
end

local function firstPortExcept(excluded)
    for _, port in ipairs(connectedPorts()) do
        if port ~= excluded then
            return port
        end
    end
    return nil
end

local function call(description, fn, ...)
    local ok, err = pcall(fn, ...)
    if ok then
        Input.lastAction = description
    else
        Input.lastAction = description .. " failed"
        QoL.reportError("input " .. description, err)
    end
    QoL.log(Input.lastAction)
    return ok
end

local function act(description, fn, ...)
    call(description, fn, ...)
    -- Give the engine time to apply the mapping before judging it again.
    Input.cooldown = 3
end

local function playerName(player)
    return "player " .. (player == HOST and "1" or "2")
end

function Input.state()
    return {
        count = Engine.GamepadsConnectedCount() or 0,
        p1Port = Engine.GamepadsConnectedPort(HOST),
        p1Active = Engine.GamepadsConnectedIsActive(HOST) == true,
        p2Port = Engine.GamepadsConnectedPort(GUEST),
        p2Active = Engine.GamepadsConnectedIsActive(GUEST) == true,
        guestSignedIn = Engine.IsControllerBeingUsed(GUEST) == true
    }
end

-- Gives `port` to `player`. If the other player holds it, the two swap:
-- the other player is unmapped first (in case the engine refuses a port that
-- is in use) and then receives the controller `player` gave up.
-- Returns the port the other player ended up with (or nil).
function Input.assign(player, port)
    local other = player == HOST and GUEST or HOST
    local s = Input.state()
    local myPort = player == HOST and s.p1Port or s.p2Port
    local myActive = player == HOST and s.p1Active or s.p2Active
    local otherPort = player == HOST and s.p2Port or s.p1Port
    local otherActive = player == HOST and s.p2Active or s.p1Active
    local otherResult = nil

    if otherActive and otherPort == port then
        pcall(Engine.GamepadsConnectedUnMap, other)
        call(playerName(player) .. " -> port " .. port, Engine.GamepadsConnectedMap, player, port)
        if myActive and isConnected(myPort) and myPort ~= port then
            call("swap: " .. playerName(other) .. " -> port " .. myPort,
                Engine.GamepadsConnectedMap, other, myPort)
            otherResult = myPort
        else
            local spare = firstPortExcept(port)
            if spare then
                call("swap: " .. playerName(other) .. " -> port " .. spare,
                    Engine.GamepadsConnectedMap, other, spare)
                otherResult = spare
            end
        end
    else
        call(playerName(player) .. " -> port " .. port, Engine.GamepadsConnectedMap, player, port)
    end
    Input.cooldown = 3
    return otherResult
end

-- Called once per second. Only acts when the current mapping contradicts the
-- chosen mode; the keyboard stays bound to player 1 in every mode.
function Input.reconcile()
    if Input.cooldown > 0 then
        Input.cooldown = Input.cooldown - 1
        return
    end
    local mode = Input.getMode()
    local s = Input.state()

    -- Player 2 is signed in but lost the controller (cable pulled): hand the
    -- first controller player 1 is not using back to player 2.
    if s.guestSignedIn and s.count > 0 and (not s.p2Active or not isConnected(s.p2Port)) then
        local spare = firstPortExcept(s.p1Active and s.p1Port or nil)
        if spare then
            act("player 2 -> port " .. spare .. " (reconnected)", Engine.GamepadsConnectedMap, GUEST, spare)
            return
        end
    end

    if mode == Input.MODE_KEYBOARD then
        if s.p1Active then
            act("player 1 -> keyboard", Engine.GamepadsConnectedUnMap, HOST)
        end
        return
    end
    if s.count <= 0 then
        return
    end

    if mode >= 0 and isConnected(mode) then
        if not (s.p1Active and s.p1Port == mode) then
            Input.assign(HOST, mode)
        end
        return
    end

    -- Automatic (also used while a fixed controller is disconnected).
    if s.p2Active and isConnected(s.p2Port) then
        if s.count >= 2 and (not s.p1Active or not isConnected(s.p1Port) or s.p1Port == s.p2Port) then
            local spare = firstPortExcept(s.p2Port)
            if spare then
                act("player 1 -> port " .. spare .. " (auto)", Engine.GamepadsConnectedMap, HOST, spare)
            end
        end
        -- With a single controller owned by player 2, player 1 keeps the keyboard.
    elseif not s.p1Active and not s.guestSignedIn then
        -- With player 2 signed in, MapAny could grab player 2's reconnected pad.
        act("player 1 -> controller (auto)", Engine.GamepadsConnectedMapAny, HOST)
    end
end

-- Replacement for the stock "Eingabegeraet Spieler 2" setter: same swap
-- behaviour, and a fixed player 1 choice follows the swap so the watchdog does
-- not immediately take the controller back.
function Input.setGuestPort(port)
    port = tonumber(port)
    if not port then
        return
    end
    local otherResult = Input.assign(GUEST, port)
    local mode = Input.getMode()
    if mode >= 0 and mode == port then
        storeMode(otherResult or Input.MODE_AUTO)
        QoL.log("player 1 follows the swap: " .. Input.modeName(Input.mode))
    end
end

function Input.debugText()
    local s = Input.state()
    return QoL.VERSION
        .. " | pads " .. tostring(s.count)
        .. " | P1 " .. Input.modeName(Input.getMode())
        .. ": port " .. tostring(s.p1Port) .. (s.p1Active and " on" or " -")
        .. " | P2: port " .. tostring(s.p2Port) .. (s.p2Active and " on" or " -")
        .. (s.guestSignedIn and " signed in" or "")
        .. " | " .. Input.lastAction
end

-- Watchdog lives on a menu element so it is cleaned up with the menu. No
-- controller_inserted handlers on the menu: they would replace stock handlers.
function Input.attachWatchdog(menu)
    local timer = LUI.UITimer.newElementTimer(1000, false, function()
        QoL.safe("input.reconcile", Input.reconcile)
    end)
    menu:addElement(timer)
    return timer
end

-- Settings: Steuerung -> Gamepad -> Splitscreen gets an extra dropdown.
DataSources.QoLGamepadMapP1 = DataSourceHelpers.ListSetup("PC.QoLGamepadMapP1", function(controller)
    local items = {
        { models = { value = Input.MODE_AUTO, valueDisplay = QoL.L("set_auto") } },
        { models = { value = Input.MODE_KEYBOARD, valueDisplay = QoL.L("set_keyboard") } }
    }
    local pads = {}
    for name, port in pairs(Engine.GamepadsConnectedPortMapping() or {}) do
        local number = tonumber(port)
        if number then
            table.insert(pads, { models = { value = number, valueDisplay = tostring(name) } })
        end
    end
    table.sort(pads, function(a, b) return a.models.value < b.models.value end)
    for _, pad in ipairs(pads) do
        table.insert(items, pad)
    end
    return items
end, true)

-- Language of the mod menus, right below the input device rows.
DataSources.QoLLanguage = DataSourceHelpers.ListSetup("PC.QoLLanguage", function(controller)
    local items = {}
    for index, code in ipairs(QoL.lang.ORDER) do
        table.insert(items, { models = { value = index, valueDisplay = QoL.lang.NAMES[code] or code } })
    end
    return items
end, true)

local function rowModels()
    return {
        input = {
            label = QoL.L("set_input_label"),
            description = QoL.L("set_input_desc"),
            profileVarName = "qol_p1_input",
            profileType = "function",
            optionController = HOST,
            datasource = "QoLGamepadMapP1",
            widgetType = "dropdown",
            getFunction = function(controller)
                return Input.getMode()
            end,
            setFunction = function(controller, value)
                QoL.safe("input.setMode", Input.setMode, value)
            end,
            disabledFunction = function()
                return false
            end
        },
        language = {
            label = QoL.L("set_lang_label"),
            description = QoL.L("set_lang_desc"),
            profileVarName = "qol_lang",
            profileType = "function",
            optionController = HOST,
            datasource = "QoLLanguage",
            widgetType = "dropdown",
            getFunction = function(controller)
                local current = QoL.lang.current()
                for index, code in ipairs(QoL.lang.ORDER) do
                    if code == current then
                        return index
                    end
                end
                return 1
            end,
            setFunction = function(controller, value)
                QoL.safe("lang.set", function()
                    QoL.lang.set(QoL.lang.ORDER[tonumber(value) or 1])
                end)
            end,
            disabledFunction = function()
                return false
            end
        }
    }
end

local function injectP1Row(controller, list)
    local items = list["PC.OptionGamepadSettingsPC"]
    if not items or #items == 0 then
        return
    end
    -- The stock player 2 row is last; route its setter through the swap logic.
    local guestRow = items[#items].model
    local guestVar = Engine.GetModel(guestRow, "profileVarName")
    if guestVar and Engine.GetModelValue(guestVar) == "splitscreen_controller" then
        Engine.SetModelValue(Engine.GetModel(guestRow, "setFunction"), function(controller, value)
            QoL.safe("input.setGuestPort", Input.setGuestPort, value)
        end)
    else
        QoL.reportError("input", "player 2 input row not found")
    end

    local base = ListHelper_GetListHelperModel(list, true)
    local rows = rowModels()
    -- Player 1 directly above the stock player 2 row, language below it.
    local function addRow(name, definition, position)
        local model = Engine.GetModel(base, name)
        if model then
            Engine.UnsubscribeAndFreeModel(model)
        end
        model = Engine.CreateModel(base, name)
        ListHelper_CreateModelsFromTable(model, definition)
        local entry = { model = model, properties = CoD.PCUtil.DependantDropdownProperties }
        if position then
            table.insert(items, position, entry)
        else
            table.insert(items, entry)
        end
    end
    addRow("qolP1Input", rows.input, #items)
    addRow("qolLanguage", rows.language)
end

local gamepadSettings = DataSources.OptionGamepadSettingsPC
if gamepadSettings and gamepadSettings.prepare then
    local stockPrepare = gamepadSettings.prepare
    gamepadSettings.prepare = function(controller, list, filter)
        stockPrepare(controller, list, filter)
        QoL.safe("input.injectP1Row", injectP1Row, controller, list)
    end
else
    QoL.reportError("input", "OptionGamepadSettingsPC not found")
end
