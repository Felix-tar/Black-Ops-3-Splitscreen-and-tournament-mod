-- Adds "SPLITSCREEN AKTIVIEREN / DEAKTIVIEREN" to the left lobby list below
-- CODCASTER so it is reachable with the D-pad. The stock PC control for this
-- lives in the member list and is effectively mouse-only.
require("ui.qol.util")
require("ui.qol.lang")

local QoL = CoD.QoL
local LobbyButtons = {}
QoL.lobbyButtons = LobbyButtons

local GUEST = 1
local BUTTON_ID = "btnQoLSplitscreen"

local function isSplitscreenLobby(nav)
    return nav == LobbyData.UITargets.UI_MPLOBBYLANGAME.id
        or nav == LobbyData.UITargets.UI_MPLOBBYONLINECUSTOMGAME.id
end

-- Stock list actions are called as action(self, element, controller, param, menu).
local function toggleAction(self, element, controller, param, menu)
    QoL.safe("lobbyButtons.toggle", function()
        local wasActive = Engine.IsControllerBeingUsed(GUEST) == true
        QoL.log(wasActive and "splitscreen off" or "splitscreen on")
        -- LobbySplitscreenToggle may attach a sign-in timer to its first argument.
        LobbySplitscreenToggle(menu or self, controller)
        ForceLobbyButtonUpdate(controller)
    end)
end

local function buildEntry(controller)
    local guestActive = Engine.IsControllerBeingUsed(GUEST) == true
    local disabled = false
    if not guestActive then
        disabled = not CoD.LobbyBase.SplitscreenControllersAllowed()
    end
    return {
        optionDisplay = guestActive and "PLATFORM_SPLITSCREEN_DEACTIVATE" or "PLATFORM_SPLITSCREEN_ACTIVATE",
        action = toggleAction,
        customId = BUTTON_ID,
        isLargeButton = true,
        isLastButtonInGroup = false,
        disabled = disabled,
        selected = CoD.LobbyMenus.History[LobbyData.GetLobbyNav()] == BUTTON_ID,
        warning = false
    }
end

-- Entries that open a QoL overlay; module is resolved when pressed.
local function overlayEntry(id, text, moduleName)
    return {
        optionDisplay = text,
        action = function(self, element, controller, param, menu)
            QoL.safe("lobbyButtons." .. id, function()
                local module = QoL[moduleName]
                if module then
                    module.open(menu or self)
                end
            end)
        end,
        customId = id,
        isLargeButton = false,
        isLastButtonInGroup = false,
        disabled = false,
        selected = false,
        warning = false
    }
end

local function findPosition(buttons, ids)
    for _, id in ipairs(ids) do
        for index = #buttons, 1, -1 do
            if buttons[index].customId == id then
                return index + 1
            end
        end
    end
    return nil
end

-- Offline main menu: splitscreen can only be switched on while this machine
-- hosts its own party, i.e. before "LAN-SPIEL SUCHEN" on a second PC.
local function insertMainMenuButton(controller, nav, buttons)
    local isMainMenu = nav == LobbyData.UITargets.UI_MAIN.id or nav == LobbyData.UITargets.UI_MODESELECT.id
    if not isMainMenu or Engine.GetLobbyNetworkMode() ~= Enum.LobbyNetworkMode.LOBBY_NETWORKMODE_LAN then
        return
    end
    if not IsLobbyHost(Enum.LobbyType.LOBBY_TYPE_PRIVATE) then
        return
    end
    local position = findPosition(buttons, { "btnFindGame", "btnMP" })
    if position then
        table.insert(buttons, position, buildEntry(controller))
    end
end

local function insertButton(controller, nav, buttons)
    insertMainMenuButton(controller, nav, buttons)
    if not isSplitscreenLobby(nav) then
        return
    end
    local position = findPosition(buttons, { "btnCodcasterSettings", "btnScorestreaks" })
    if position == nil then
        return
    end
    -- Splitscreen toggle and tournament belong to the host; profiles and the
    -- leaderboard are per machine, so a PC that joined via LAN gets them too.
    local isHost = IsLobbyHost(Enum.LobbyType.LOBBY_TYPE_GAME) or IsLobbyHost(Enum.LobbyType.LOBBY_TYPE_PRIVATE)
        and not Engine.IsLobbyActive(Enum.LobbyType.LOBBY_TYPE_GAME)
    local entries = {}
    if isHost then
        table.insert(entries, buildEntry(controller))
    end
    table.insert(entries, overlayEntry("btnQoLProfiles", QoL.L("lobby_profiles"), "profiles"))
    table.insert(entries, overlayEntry("btnQoLClassCopy", QoL.L("lobby_classcopy"), "classCopy"))
    table.insert(entries, overlayEntry("btnQoLLeaderboard", QoL.L("lobby_leaderboard"), "leaderboard"))
    if isHost then
        table.insert(entries, overlayEntry("btnQoLTournament", QoL.L("lobby_tournament"), "tournament"))
    end
    local previous = buttons[position - 1]
    -- Keep the group separator where the stock list had it.
    if previous and previous.isLastButtonInGroup then
        previous.isLastButtonInGroup = false
        entries[#entries].isLastButtonInGroup = true
    end
    for offset, entry in ipairs(entries) do
        table.insert(buttons, position + offset - 1, entry)
    end
end

local stockAddButtonsForTarget = CoD.LobbyMenus.AddButtonsForTarget
CoD.LobbyMenus.AddButtonsForTarget = function(controller, nav)
    local buttons = stockAddButtonsForTarget(controller, nav)
    QoL.safe("lobbyButtons.insert", insertButton, controller, nav, buttons)
    return buttons
end

-- The label depends on whether player 2 is signed in; sign-in completes
-- asynchronously, so the lobby timer calls this to refresh the list.
-- Returns true when player 2 has just signed in.
LobbyButtons.lastGuestState = nil
function LobbyButtons.refreshIfGuestChanged()
    local guestActive = Engine.IsControllerBeingUsed(GUEST) == true
    local joined = false
    if LobbyButtons.lastGuestState ~= nil and LobbyButtons.lastGuestState ~= guestActive then
        LuaUtils.ForceLobbyButtonUpdate()
        joined = guestActive
    end
    LobbyButtons.lastGuestState = guestActive
    return joined
end
