-- Shared helpers for the QoL modules. Everything lives in CoD.QoL; the
-- frontend calls DisableGlobals() after loading, so no new globals later.
CoD.QoL = CoD.QoL or {}
local QoL = CoD.QoL

-- build-dev.ps1 -Release rewrites these two lines in the packaged copy.
QoL.VERSION = "dev 0.7.0"
QoL.DEV = true
QoL.errors = QoL.errors or {}
QoL.logLines = QoL.logLines or {}

-- Development builds write the console to console_mp.log (unbuffered, so the
-- tail survives a fatal error) to diagnose crashes on the user's PC.
if QoL.DEV then
    pcall(Engine.Exec, nil, "logfile 2")
end

function QoL.log(text)
    table.insert(QoL.logLines, tostring(text))
    while #QoL.logLines > 6 do
        table.remove(QoL.logLines, 1)
    end
    pcall(Engine.PrintInfo, Enum.consoleLabel.LABEL_DEFAULT, "[QoL] " .. tostring(text) .. "\n")
end

function QoL.reportError(where, err)
    -- The engine appends a stack trace; the first line is what matters.
    local firstLine = string.match(tostring(err), "^[^\n]*") or tostring(err)
    local message = tostring(where) .. ": " .. firstLine
    table.insert(QoL.errors, message)
    QoL.log("FEHLER " .. message)
    pcall(Engine.PrintError, Enum.consoleLabel.LABEL_DEFAULT, "[QoL] FEHLER " .. message .. "\n")
end

-- Runs fn with pcall so a mod bug never takes down a stock menu.
function QoL.safe(where, fn, ...)
    local ok, result = pcall(fn, ...)
    if not ok then
        QoL.reportError(where, result)
        return nil
    end
    return result
end

function QoL.label(parent, text, x, y, width, height)
    local element = LUI.UIText.new()
    element:setLeftRight(true, false, x, x + width)
    element:setTopBottom(true, false, y, y + height)
    element:setTTF("fonts/default.ttf")
    element:setAlignment(Enum.LUIAlignment.LUI_ALIGNMENT_LEFT)
    element:setText(text)
    parent:addElement(element)
    return element
end

-- Width of the UI root in layout units (height is always 720). Changes with
-- the window's aspect ratio, e.g. after resizing a windowed game.
function QoL.rootWidth()
    local ok, aspect = pcall(Engine.GetAspectRatio)
    if ok and type(aspect) == "number" and aspect > 0.5 and aspect < 5 then
        return 720 * aspect
    end
    return 1280
end

-- Controller currently driving local client 0 (host) or 1 (guest).
function QoL.controllerForLocalClient(localClient)
    if localClient == 1 and Engine.GetUsedControllerCount() < 2 then
        return nil
    end
    for controller = 0, LuaEnums.MAX_CONTROLLER_COUNT - 1 do
        if Engine.IsControllerBeingUsed(controller)
            and Engine.GetLocalClientNum(controller) == localClient then
            return controller
        end
    end
    return nil
end

-- Offline LAN lobby or "Eigenes Spiel": the only places the mod changes.
function QoL.isSplitscreenLobby()
    local nav = LobbyData.GetLobbyNav()
    return nav == LobbyData.UITargets.UI_MPLOBBYLANGAME.id
        or nav == LobbyData.UITargets.UI_MPLOBBYONLINECUSTOMGAME.id
end

-- Integer dvar access that tolerates a missing dvar.
function QoL.getDvarInt(name, default)
    local ok, value = pcall(Engine.DvarInt, nil, name)
    if ok and type(value) == "number" then
        return value
    end
    return default
end

-- Session values survive the reload of the menu scripts between lobby and
-- match (dvars live in the engine) but not a restart of the game. A copy is
-- kept in Lua in case the engine refuses to create the dvar.
QoL.session = QoL.session or {}

function QoL.setSessionValue(name, value)
    value = tostring(value or "")
    QoL.session[name] = value
    pcall(Engine.SetDvar, name, value)
    local ok, stored = pcall(Engine.DvarString, nil, name)
    if ok and stored == value then
        return true
    end
    pcall(Engine.Exec, nil, "set " .. name .. " \"" .. string.gsub(value, "\"", "") .. "\"")
    ok, stored = pcall(Engine.DvarString, nil, name)
    return ok and stored == value
end

function QoL.getSessionValue(name)
    local ok, stored = pcall(Engine.DvarString, nil, name)
    if ok and type(stored) == "string" and stored ~= "" then
        return stored
    end
    return QoL.session[name] or ""
end
