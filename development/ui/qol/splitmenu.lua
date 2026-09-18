-- Split menus: profile choice, class editor, specialists and scorestreaks for
-- both local players at the same time, player 1 left, player 2 right.
--
-- How it works:
--   * QoLSplitScreen is an overlay over the lobby (the lobby stops taking input).
--   * Each half is a stencil-clipped element holding a scaled 1280x720 "stage".
--   * On each stage lives a QoLSplitHub menu owned by that player's controller.
--   * Stock menus are opened from the hub. Stock popups are added to the parent
--     of the menu that opens them, so the whole chain stays inside the stage, and
--     each stock menu only subscribes to the buttons of its own controller.
require("ui.qol.util")
require("ui.qol.lang")
require("ui.qol.ui")

local QoL = CoD.QoL
local Split = {}
QoL.split = Split

-- Part of a 1280x720 stock menu that should stay visible inside one half
-- (menu x from CONTENT_LEFT to CONTENT_LEFT + CONTENT_WIDTH). The scale is
-- derived from the real half width, so 16:9, 16:10, 21:9 or a resized
-- window all fit; at 16:9 this gives 0.75.
Split.CONTENT_LEFT = 50
Split.CONTENT_WIDTH = 853
Split.MAX_SCALE = 1

-- Texts come from lang.lua when the hub is built.
local ENTRIES = {
    { id = "profile", key = "entry_profile" },
    { id = "cac", key = "entry_cac" },
    { id = "specialists", key = "entry_specialists" },
    { id = "scorestreaks", key = "entry_scorestreaks" },
    { id = "classcopy", key = "entry_classcopy" },
    { id = "done", key = "done" }
}

function Split.available()
    return QoL.isSplitscreenLobby()
        and QoL.controllerForLocalClient(0) ~= nil
        and QoL.controllerForLocalClient(1) ~= nil
end

local function openStockMenu(hub, controller, id)
    if id == "cac" then
        CoD.LobbyBase.OpenCAC(hub, controller)
    elseif id == "specialists" then
        CoD.CCUtility.customizationMode = Enum.eModes.MODE_MULTIPLAYER
        CoD.LobbyBase.OpenChooseCharacterLoadout(hub, controller, LuaEnums.CHOOSE_CHARACTER_OPENED_FROM.LOBBY)
    elseif id == "scorestreaks" then
        CoD.LobbyBase.OpenScorestreaks(hub, controller)
    elseif id == "classcopy" then
        OpenPopup(hub, "QoLClassCopy", controller, { player = hub.qolPlayer })
    end
end

-- Hub ---------------------------------------------------------------------

-- One per half, owned by that player's controller. Two pages: the profile
-- chooser ("Wer spielt?", profiles.lua) and the menu below.
LUI.createMenu.QoLSplitHub = function(controller, userData)
    local UI = QoL.ui
    local self = CoD.Menu.NewForUIEditor("QoLSplitHub")
    self:setOwner(controller)
    self:setLeftRight(true, true, 0, 0)
    self:setTopBottom(true, true, 0, 0)
    self.qolPlayer = userData and userData.player or 0
    self.qolController = controller
    self.qolDone = false
    self.qolProfilesFirst = userData and userData.profilesFirst or false

    local left = Split.CONTENT_LEFT + 60
    local menuRoot = LUI.UIElement.new()
    menuRoot:setLeftRight(true, true, 0, 0)
    menuRoot:setTopBottom(true, true, 0, 0)
    self:addElement(menuRoot)

    UI.text(menuRoot, QoL.L("split_player", self.qolPlayer + 1), left, 110, 700, 40, UI.ORANGE)
    UI.text(menuRoot, QoL.L("split_controller", controller), left, 156, 700, 20, UI.GREY)
    local list = UI.newList(menuRoot, left, 210, 640, 52, #ENTRIES)
    local status = UI.text(menuRoot, "", left, 540, 740, 24, UI.WHITE)
    UI.text(menuRoot, QoL.L("hint_hub"), left, 580, 740, 20, UI.GREY)

    local profilePage
    local function paint()
        local items = {}
        for _, entry in ipairs(ENTRIES) do
            local text = QoL.L(entry.key)
            if entry.id == "profile" then
                local name = QoL.data and QoL.safe("split.displayName", QoL.data.displayName, self.qolPlayer)
                text = QoL.L("split_profile", tostring(name or "-"))
            end
            table.insert(items, { text = text, id = entry.id, color = entry.id == "done" and UI.GREEN or nil })
        end
        list.setItems(items)
        status:setText(self.qolDone and QoL.L("split_waiting") or "")
    end
    self.qolPaint = paint

    local function showMenu()
        menuRoot:setAlpha(1)
        paint()
    end

    local function showProfiles()
        if not profilePage then
            return
        end
        self.qolDone = false
        menuRoot:setAlpha(0)
        profilePage.show()
    end
    self.qolShowProfiles = showProfiles

    if QoL.profiles then
        profilePage = QoL.profiles.newPage(self, controller, self.qolPlayer, {
            x = left, y = 100, rows = 8,
            onDone = function()
                -- Opened for the profile choice after joining: choosing counts
                -- as done, both done closes the split screen.
                if self.qolProfilesFirst then
                    self.qolProfilesFirst = false
                    self.qolDone = true
                end
                showMenu()
                if self.qolDone then
                    Split.checkAllDone()
                end
                -- The other half shows the new name as well.
                if Split.current then
                    for _, hub in pairs(Split.current.qolHubs) do
                        if hub ~= self and hub.qolPaint then
                            QoL.safe("split.repaint", hub.qolPaint)
                        end
                    end
                end
            end
        })
    end

    function self.qolActivate(id)
        if id == "done" then
            self.qolDone = true
            paint()
            Split.checkAllDone()
        elseif id == "profile" then
            showProfiles()
        else
            self.qolDone = false
            paint()
            QoL.safe("split.open " .. id, openStockMenu, self, controller, id)
        end
    end

    local function menuHandler(key)
        if key == "up" then
            list.move(-1)
        elseif key == "down" then
            list.move(1)
        elseif key == "confirm" then
            local item = list.current()
            if item then
                self.qolActivate(item.id)
            end
        elseif key == "back" then
            self.qolActivate("done")
        end
    end

    local function dispatch(key)
        return function()
            if profilePage and profilePage.active then
                profilePage.handlers[key]()
            else
                menuHandler(key)
            end
        end
    end
    UI.bindButtons(self, controller, {
        up = dispatch("up"), down = dispatch("down"), confirm = dispatch("confirm"), back = dispatch("back")
    })
    list.onClick = function(item, button)
        if button == "left" and not (profilePage and profilePage.active) then
            self.qolActivate(item.id)
        end
    end

    showMenu()
    return self
end

-- Overlay -----------------------------------------------------------------

-- Positions clip, stage and labels of one half for the current screen width.
local function layoutHalf(half, halfWidth)
    local left = half.player * halfWidth
    half.clip:setLeftRight(true, false, left, left + halfWidth)
    local scale = math.min(Split.MAX_SCALE, halfWidth / Split.CONTENT_WIDTH)
    -- setScale pivots around the element centre: place the centre so that menu
    -- x = CONTENT_LEFT lands on the left edge of the half, vertically centred.
    local centre = (640 - Split.CONTENT_LEFT) * scale
    half.stage:setLeftRight(true, false, centre - 640, centre + 640)
    half.stage:setScale(scale)
    half.label:setLeftRight(true, false, left + 24, left + halfWidth - 24)
    half.warning:setLeftRight(true, false, left + 24, left + halfWidth - 24)
end

function Split.layout(root)
    local halfWidth = QoL.rootWidth() / 2
    root.qolLayoutWidth = halfWidth
    for _, half in pairs(root.qolHalves) do
        layoutHalf(half, halfWidth)
    end
    root.qolDivider:setLeftRight(true, false, halfWidth - 1, halfWidth + 1)
end

local function addHalf(root, player, controller, autoOpen)
    local clip = LUI.UIElement.new()
    clip:setTopBottom(true, true, 0, 0)
    clip:setUseStencil(true)
    root:addElement(clip)

    local stage = LUI.UIElement.new()
    stage:setTopBottom(true, false, 0, 720)
    clip:addElement(stage)

    local hub = CoD.Menu.safeCreateMenu("QoLSplitHub", controller, { player = player, profilesFirst = autoOpen == "profiles" })
    stage:addElement(hub)
    hub:processEvent({ name = "menu_opened", controller = controller })

    local label = QoL.label(root, QoL.L("split_player", player + 1), 0, 30, 400, 26)
    label:setRGB(1, 0.55, 0.12)
    -- Outside the stage so it stays visible above open stock menus.
    hub.qolWarning = QoL.label(root, "", 0, 690, 600, 22)
    hub.qolWarning:setRGB(1, 0.3, 0.2)

    root.qolHalves[player] = { player = player, clip = clip, stage = stage, label = label, warning = hub.qolWarning }

    if autoOpen == "profiles" then
        hub.qolShowProfiles()
    elseif autoOpen then
        hub:addElement(LUI.UITimer.newElementTimer(50, true, function()
            QoL.safe("split.autoOpen", openStockMenu, hub, controller, autoOpen)
        end))
    end
    return hub
end

LUI.createMenu.QoLSplitScreen = function(controller, userData)
    local self = CoD.Menu.NewForUIEditor("QoLSplitScreen")
    self:setLeftRight(true, true, 0, 0)
    self:setTopBottom(true, true, 0, 0)
    self.qolHostController = controller
    self.qolHubs = {}
    self.qolHalves = {}

    -- Opaque ground: the 3D frontend scene exists only once and both halves
    -- would fight over its camera.
    local ground = LUI.UIImage.new()
    ground:setLeftRight(true, true, 0, 0)
    ground:setTopBottom(true, true, 0, 0)
    ground:setRGB(0.02, 0.025, 0.03)
    ground:setAlpha(1)
    self:addElement(ground)

    local autoOpen = userData and userData.autoOpen or {}
    for player = 0, 1 do
        local playerController = QoL.controllerForLocalClient(player)
        if playerController ~= nil then
            self.qolHubs[player] = addHalf(self, player, playerController, autoOpen[player])
        end
    end

    local divider = LUI.UIImage.new()
    divider:setTopBottom(true, true, 0, 0)
    divider:setRGB(1, 0.55, 0.12)
    divider:setAlpha(0.8)
    self:addElement(divider)
    self.qolDivider = divider
    Split.layout(self)

    -- A pulled cable must not end the session: the stock menus keep their
    -- button subscriptions and work again once the controller is back. Only
    -- close when player 2 has really left splitscreen for a while.
    self.qolGuestMissingTicks = 0
    self:addElement(LUI.UITimer.newElementTimer(500, false, function()
        QoL.safe("split.presence", Split.updatePresence, self)
        -- Window resized or aspect ratio changed: lay the halves out again.
        if math.abs(QoL.rootWidth() / 2 - (self.qolLayoutWidth or 0)) > 1 then
            QoL.safe("split.layout", Split.layout, self)
        end
    end))

    LUI.OverrideFunction_CallOriginalFirst(self, "close", function()
        if Split.current == self then
            Split.current = nil
        end
    end)
    Split.current = self
    return self
end

function Split.checkAllDone()
    local current = Split.current
    if not current then
        return
    end
    for _, hub in pairs(current.qolHubs) do
        if not hub.qolDone then
            return
        end
    end
    Split.close()
end

local GUEST_GONE_TICKS = 20 -- 10 s at 500 ms

function Split.updatePresence(root)
    for player, hub in pairs(root.qolHubs) do
        local connected = Engine.GamepadsConnectedIsActive(player) == true
        if player == 0 then
            hub.qolWarning:setText(connected and "" or QoL.L("split_no_pad"))
        else
            hub.qolWarning:setText(connected and "" or QoL.L("split_lost_pad"))
        end
    end
    local guestHub = root.qolHubs[1]
    if guestHub and not Engine.IsControllerBeingUsed(guestHub.qolController) then
        root.qolGuestMissingTicks = root.qolGuestMissingTicks + 1
        if root.qolGuestMissingTicks == 1 then
            QoL.log("split: player 2 no longer signed in")
        end
        if root.qolGuestMissingTicks >= GUEST_GONE_TICKS then
            Split.close()
        end
    else
        root.qolGuestMissingTicks = 0
    end
end

-- Stock menus stacked above a hub, top-most last.
local function menusAboveHub(hub)
    local stage = hub:getParent()
    local menus = {}
    local child = stage and stage:getFirstChild()
    while child do
        if child ~= hub and child.menuName then
            table.insert(menus, child)
        end
        child = child:getNextSibling()
    end
    return menus
end

-- Closes the stock menus of one half from the top down. The class editor
-- saves on its own back button, so save explicitly before closing it.
local function unwindHalf(hub)
    local menus = menusAboveHub(hub)
    if #menus == 0 then
        return
    end
    QoL.log("split: closing " .. #menus .. " menu(s) of player " .. tostring(hub.qolPlayer + 1))
    if Engine.IsControllerBeingUsed(hub.qolController) then
        QoL.safe("split.saveLoadout", SaveLoadout, hub, hub.qolController)
    end
    for index = #menus, 1, -1 do
        QoL.safe("split.closeMenu " .. tostring(menus[index].menuName), function()
            menus[index]:close()
        end)
    end
end

function Split.close()
    local current = Split.current
    if not current then
        return
    end
    Split.current = nil
    QoL.log("split menu closing")
    if QoL.data and QoL.data.flush then
        QoL.safe("data.flush", QoL.data.flush)
    end
    for _, hub in pairs(current.qolHubs) do
        unwindHalf(hub)
    end
    GoBack(current, current.qolHostController)
end

-- player: 0 host, 1 guest. id: menu to open right away in that player's half
-- ("profiles" = profile chooser).
function Split.open(lobbyMenu, player, id)
    if Split.current then
        local hub = Split.current.qolHubs[player]
        if id == "profiles" and hub and hub.qolShowProfiles then
            hub.qolShowProfiles()
        end
        return true
    end
    if not Split.available() then
        return false
    end
    local host = QoL.controllerForLocalClient(0)
    local autoOpen = {}
    autoOpen[player] = id
    QoL.log("split menu opening: player " .. tostring(player + 1) .. " " .. tostring(id))
    OpenOverlay(lobbyMenu, "QoLSplitScreen", host, { autoOpen = autoOpen })
    return true
end

-- Route the host's lobby buttons through the split menu while player 2 is in.
local function wrapLobbyButton(button, id)
    if not button or not button.action then
        QoL.reportError("split", "lobby button missing: " .. id)
        return
    end
    local stockAction = button.action
    button.action = function(self, element, controller, param, menu)
        local handled = QoL.safe("split.lobbyButton", function()
            if Split.available() then
                return Split.open(menu or self, Engine.GetLocalClientNum(controller), id)
            end
            return false
        end)
        if not handled then
            return stockAction(self, element, controller, param, menu)
        end
    end
end

wrapLobbyButton(CoD.LobbyButtons.MP_CAC, "cac")
wrapLobbyButton(CoD.LobbyButtons.MP_SPECIALISTS, "specialists")
wrapLobbyButton(CoD.LobbyButtons.MP_SCORESTREAKS, "scorestreaks")

-- Both halves start with "Wer spielt?" (after player 2 joined).
function Split.openProfiles(lobbyMenu)
    if Split.current then
        for _, hub in pairs(Split.current.qolHubs) do
            if hub.qolShowProfiles then
                hub.qolShowProfiles()
            end
        end
        return true
    end
    if not Split.available() then
        return false
    end
    QoL.log("split menu opening: profile choice")
    OpenOverlay(lobbyMenu, "QoLSplitScreen", QoL.controllerForLocalClient(0),
        { autoOpen = { [0] = "profiles", [1] = "profiles" } })
    return true
end
