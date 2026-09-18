-- Lobby additions: player 2 panel (dev3 prototype), input watchdog and a
-- debug line. Stock menus keep their initialization; all profile actions get
-- the controller resolved from the local-client mapping, never hardware IDs.
require("ui.uieditor.menus.Lobby.Lobby")
require("ui.qol.util")
require("ui.qol.lang")

local QoL = CoD.QoL
local label = QoL.label

local stockLobby = LUI.createMenu.Lobby
local stockButtonPress = CoD.Menu.HandleButtonPress
CoD.Menu.HandleButtonPress = function(menu, controller, button, model)
    if menu.qolGuestInput then
        local ok, consumed = pcall(menu.qolGuestInput, controller, button)
        if not ok then
            QoL.reportError("splitlobby.guestInput", consumed)
        elseif consumed then
            if model then Engine.SetModelValue(model, 0) end
            return true
        end
    end
    return stockButtonPress(menu, controller, button, model)
end

local function guestController()
    if Engine.GetUsedControllerCount() < 2 then return nil end
    for controller = 0, LuaEnums.MAX_CONTROLLER_COUNT - 1 do
        if Engine.IsControllerBeingUsed(controller)
            and Engine.GetLocalClientNum(controller) == 1 then
            return controller
        end
    end
    return nil
end

local function customLobby()
    local nav = LobbyData.GetLobbyNav()
    return nav == LobbyData.UITargets.UI_MPLOBBYLANGAME.id
        or nav == LobbyData.UITargets.UI_MPLOBBYONLINECUSTOMGAME.id
end

local function attachGuestPanel(menu)
    local panel = LUI.UIElement.new()
    -- Anchored to the right edge so it follows wider or narrower windows.
    panel:setLeftRight(false, true, -610, -70)
    panel:setTopBottom(true, false, 245, 565)
    panel:setAlpha(0)
    panel:setHandleMouse(true)
    menu:addElement(panel)
    menu.qolGuestPanel = panel

    local background = LUI.UIImage.new()
    background:setLeftRight(true, true, 0, 0)
    background:setTopBottom(true, true, 0, 0)
    background:setRGB(0.025, 0.035, 0.045)
    background:setAlpha(0.85)
    panel:addElement(background)
    local titleLabel = label(panel, QoL.L("panel_title"), 20, 16, 480, 28)
    local status = label(panel, QoL.L("panel_assigning"), 20, 54, 490, 19)
    local hintLabel = label(panel, QoL.L("hint_panel"), 20, 292, 490, 18)

    local selected = 1
    local buttons = {}
    local ENTRY_KEYS = { "entry_profile", "entry_cac", "entry_specialists", "entry_scorestreaks", "entry_classcopy" }
    local names = {}
    for index, key in ipairs(ENTRY_KEYS) do
        names[index] = QoL.L(key)
    end
    local function paint()
        for index, button in ipairs(buttons) do
            if index == selected then button.text:setRGB(1, 0.55, 0.12)
            else button.text:setRGB(0.9, 0.9, 0.9) end
        end
    end
    local splitIds = {"profiles", "cac", "specialists", "scorestreaks"}
    local function open(index)
        local guest = guestController()
        if not guest or not customLobby() or menu.occludedBy then return end
        if index == 5 then
            if QoL.classCopy then
                QoL.safe("classCopy.open", QoL.classCopy.open, menu, 1)
            end
            return
        end
        if QoL.split and QoL.safe("split.open", QoL.split.open, menu, 1, splitIds[index]) then
            return
        end
        -- These are the same entry points used by stock lobby buttons.
        if index == 1 then
            return
        elseif index == 2 then
            CoD.LobbyBase.OpenCAC(menu, guest)
        elseif index == 3 then
            CoD.CCUtility.customizationMode = Enum.eModes.MODE_MULTIPLAYER
            CoD.LobbyBase.OpenChooseCharacterLoadout(menu, guest,
                LuaEnums.CHOOSE_CHARACTER_OPENED_FROM.LOBBY)
        else
            CoD.LobbyBase.OpenScorestreaks(menu, guest)
        end
    end
    for index, name in ipairs(names) do
        local row = LUI.UIElement.new()
        row:setLeftRight(true, true, 16, -16)
        row:setTopBottom(true, false, 84 + (index - 1) * 40, 120 + (index - 1) * 40)
        row:setHandleMouse(true)
        row.text = label(row, name, 8, 6, 470, 25)
        row:registerEventHandler("leftmouseup", function(element, event)
            if event.inside then selected = index; paint(); open(index); return true end
        end)
        panel:addElement(row)
        buttons[index] = row
    end
    paint()

    local function active(controller)
        return customLobby() and controller == guestController() and not menu.occludedBy
    end
    -- Stock UI subscribes to ButtonBits for every active controller. Route at
    -- HandleButtonPress, before it dispatches into the host's focused element.
    menu.qolGuestInput = function(controller, button)
        if not active(controller) then return false end
        if button == Enum.LUIButton.LUI_KEY_UP then selected = (selected + #names - 2) % #names + 1
        elseif button == Enum.LUIButton.LUI_KEY_DOWN then selected = selected % #names + 1
        elseif button == Enum.LUIButton.LUI_KEY_XBA_PSCROSS then open(selected) end
        paint()
        return true
    end
    -- Suppress duplicate legacy events. ButtonBits above owns guest actions.
    local originalProcess = menu.processEvent
    menu.processEvent = function(self, event)
        if event.name == "gamepad_button" then
            local ok, isGuest = pcall(active, event.controller)
            if ok and isGuest then
                return true
            end
        end
        return originalProcess(self, event)
    end

    -- After a language change every text of the card is written again.
    menu.qolApplyPanelTexts = function()
        titleLabel:setText(QoL.L("panel_title"))
        hintLabel:setText(QoL.L("hint_panel"))
        for index, key in ipairs(ENTRY_KEYS) do
            names[index] = QoL.L(key)
            if buttons[index] then
                buttons[index].text:setText(names[index])
            end
        end
    end

    return function()
        local guest = guestController()
        panel:setAlpha(customLobby() and 1 or 0)
        if guest then
            local name = QoL.data and QoL.safe("data.displayName", QoL.data.displayName, 1) or ""
            status:setText(QoL.L("panel_status", tostring(name), tostring(guest)))
        else
            status:setText(QoL.L("panel_join"))
        end
    end
end

local function attach(menu)
    local refreshPanel = attachGuestPanel(menu)
    -- Top strip between the menu title and the "Mod geladen" hint; the
    -- bottom edge is taken by the chat box.
    -- Development builds always show it; release builds only on errors.
    local debugBackground = LUI.UIImage.new()
    debugBackground:setLeftRight(true, false, 396, 1120)
    debugBackground:setTopBottom(true, false, 2, 20)
    debugBackground:setRGB(0, 0, 0)
    debugBackground:setAlpha(0)
    menu:addElement(debugBackground)
    local debugLine = label(menu, "", 400, 4, 720, 14)
    debugLine:setRGB(1, 0.85, 0.2)

    -- Load stored profiles once per menu load (menus are reloaded after every
    -- match) and count game starts: a rising counter proves the store persists.
    if QoL.data and not QoL.dataStarted then
        QoL.dataStarted = true
        QoL.safe("data.boot", function()
            local state = QoL.data.load()
            -- The stored language is known only now: check it again.
            QoL.safe("lang.reset", QoL.lang.reset)
            if QoL.getSessionValue("qol_started") == "" then
                QoL.setSessionValue("qol_started", "1")
                state.boots = state.boots + 1
                QoL.data.save()
            end
            QoL.data.publishNames()
        end)
    end
    if QoL.profiles then
        QoL.safe("profiles.applyLobbyNames", QoL.profiles.applyLobbyNames)
    end
    -- A finished match leaves its report in a dvar; evaluate it now.
    if QoL.stats then
        QoL.safe("stats.consume", QoL.stats.consumePendingReport)
    end

    -- Development builds: find out where "exec" loads cfg files from (for the
    -- tournament preset file). Probe files: qol_exec_test.cfg.
    if QoL.DEV and QoL.presets and not QoL.fileTestStarted then
        QoL.fileTestStarted = true
        QoL.safe("presets.detectFileLocation", QoL.presets.detectFileLocation, menu)
    end

    local languageVersion = QoL.lang and QoL.lang.version or 0

    local function refresh()
        -- Language changed in the settings: redraw the texts of this screen.
        if QoL.lang and QoL.lang.version ~= languageVersion then
            languageVersion = QoL.lang.version
            QoL.safe("splitlobby.panelTexts", menu.qolApplyPanelTexts)
            QoL.safe("lobbyButtons.language", function()
                LuaUtils.ForceLobbyButtonUpdate()
            end)
        end
        QoL.safe("splitlobby.panel", refreshPanel)
        if QoL.data and QoL.data.tick then
            QoL.safe("data.tick", QoL.data.tick)
        end
        if QoL.lobbyButtons then
            local joined = QoL.safe("lobbyButtons.refresh", QoL.lobbyButtons.refreshIfGuestChanged)
            if joined and QoL.profiles then
                -- Give the stock sign-in overlay a moment to close.
                menu:addElement(LUI.UITimer.newElementTimer(1500, true, function()
                    QoL.safe("profiles.autoOpen", QoL.profiles.open, menu)
                end))
            end
        end
        local text
        if QoL.DEV then
            text = QoL.VERSION
            if QoL.input then
                text = QoL.safe("input.debugText", QoL.input.debugText) or text
            end
            if QoL.storage and QoL.data and QoL.data.state then
                text = text .. " | Speicher " .. QoL.storage.status .. (QoL.data.available and (" Start #" .. QoL.data.state.boots) or "")
            end
            if QoL.selftest and QoL.selftest.summary then
                text = text .. " | " .. QoL.selftest.summary
            end
            if QoL.bigStore then
                text = text .. " | Vorlagen " .. tostring(QoL.bigStore.state or QoL.bigStore.status)
            end
            if QoL.presets and QoL.presets.fileTest then
                text = text .. " | Datei " .. QoL.presets.fileTest
            end
        end
        local problem = nil
        if #QoL.errors > 0 then
            problem = QoL.L("st_error", QoL.errors[#QoL.errors])
        elseif QoL.data and QoL.data.lastSaveError then
            problem = QoL.L("st_not_saved", QoL.data.lastSaveError)
        end
        if problem then
            text = (text and (text .. " | ") or ("Splitscreen QoL " .. QoL.VERSION .. " | ")) .. problem
        end
        debugLine:setText(text or "")
        debugLine:setAlpha(text and 1 or 0)
        debugBackground:setAlpha(text and 0.75 or 0)
    end
    local timer = LUI.UITimer.newElementTimer(500, false, refresh)
    menu:addElement(timer)
    if QoL.input then
        QoL.input.attachWatchdog(menu)
    end
    refresh()

    -- After a tournament match: load the next round and show the standings.
    -- Only for matches the tournament has just scored, not for every match.
    local tournament = QoL.tournament
    if tournament and (tournament.justScored or tournament.pendingApply) then
        menu:addElement(LUI.UITimer.newElementTimer(2000, true, function()
            QoL.safe("tournament.afterMatch", function()
                if not tournament.current() then
                    return
                end
                if tournament.pendingApply then
                    tournament.pendingApply = false
                    tournament.applyRound()
                end
                if tournament.justScored then
                    tournament.justScored = false
                    tournament.open(menu)
                end
            end)
        end))
    end
end

LUI.createMenu.Lobby = function(controller)
    local menu = stockLobby(controller)
    local ok, err = pcall(attach, menu)
    if not ok then
        QoL.reportError("splitlobby.attach", err)
        -- Expose initialization failure instead of hiding it behind a blank UI.
        label(menu, "QoL UI error: " .. tostring(err), 70, 640, 1130, 22)
    end
    return menu
end
