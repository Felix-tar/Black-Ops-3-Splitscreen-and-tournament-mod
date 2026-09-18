-- "Wer spielt?" - each local player picks or creates a local profile with
-- their own controller. The chooser is a page that lives inside the half of
-- the split screen (splitmenu.lua), so one player can already edit classes
-- while the other still types a name. Without player 2 it opens full screen.
require("ui.qol.util")
require("ui.qol.lang")
require("ui.qol.ui")
require("ui.qol.data")

local QoL = CoD.QoL
local UI = QoL.ui
local Data = QoL.data
local Profiles = {}
QoL.profiles = Profiles

local NEW_ENTRY = "new"
local NONE_ENTRY = "none"

local function buildItems(localClient)
    local items = {}
    local assigned = Data.get().assigned
    local profiles = {}
    for _, profile in ipairs(Data.get().profiles) do
        table.insert(profiles, profile)
    end
    table.sort(profiles, function(a, b) return string.lower(a.name) < string.lower(b.name) end)
    local other = localClient == 0 and 1 or 0
    for _, profile in ipairs(profiles) do
        local item = { text = profile.name, id = profile.id }
        if assigned[localClient] == profile.id then
            item.text = QoL.L("profiles_chosen", profile.name)
            item.color = UI.GREEN
        elseif assigned[other] == profile.id then
            item.text = QoL.L("profiles_taken", profile.name, other + 1)
            item.color = UI.GREY
            item.blocked = true
        end
        table.insert(items, item)
    end
    table.insert(items, { text = QoL.L("profiles_new"), id = NEW_ENTRY, color = UI.ORANGE })
    table.insert(items, { text = QoL.L("profiles_none", tostring(QoL.safe("gamertag", function()
        return Engine.GetGamertagForController(QoL.controllerForLocalClient(localClient))
    end) or "Steam")), id = NONE_ENTRY })
    return items
end

-- Adds a hidden chooser to a menu (coordinates in 1280x720 of that menu).
-- opts: x, y, rows, onDone(). Returns page with show(), hide(), active and
-- handlers (up/down/confirm/back) for the owner's button bindings.
function Profiles.newPage(menu, controller, localClient, opts)
    local x, y, rows = opts.x or 110, opts.y or 90, opts.rows or 8
    local page = { active = false }
    local root = LUI.UIElement.new()
    root:setLeftRight(true, true, 0, 0)
    root:setTopBottom(true, true, 0, 0)
    root:setAlpha(0)
    menu:addElement(root)

    UI.text(root, QoL.L("profiles_title", localClient + 1), x, y, 700, 36, UI.ORANGE)
    local status = UI.text(root, "", x, y + 44, 700, 22, UI.GREY)
    local list = UI.newList(root, x, y + 86, 620, 40, rows)
    local help = UI.text(root, QoL.L("hint_profiles"), x, y + 96 + rows * 40, 700, 20, UI.GREY)

    local function showProblem(text)
        status:setText(text)
        status:setRGB(UI.RED[1], UI.RED[2], UI.RED[3])
    end

    function page.refresh()
        list.setItems(buildItems(localClient))
        status:setText(QoL.L("profiles_current", Data.displayName(localClient)))
        status:setRGB(UI.GREY[1], UI.GREY[2], UI.GREY[3])
        if not Data.available then
            help:setText(QoL.L("profiles_no_storage"))
        end
    end

    function page.show()
        page.active = true
        root:setAlpha(1)
        page.refresh()
    end

    function page.hide()
        page.active = false
        root:setAlpha(0)
    end

    local function finish()
        page.hide()
        if opts.onDone then
            opts.onDone()
        end
    end

    local function choose(profileId)
        local ok, reason = Data.assign(localClient, profileId)
        if not ok then
            showProblem(QoL.L("not_possible", tostring(reason)))
            return
        end
        finish()
    end

    page.handlers = {
        up = function() list.move(-1) end,
        down = function() list.move(1) end,
        confirm = function()
            local item = list.current()
            if not item then
                return
            end
            if item.id == NEW_ENTRY then
                UI.askText(menu, controller, function(text)
                    if not page.active then
                        return
                    end
                    local name = Data.sanitizeName(text)
                    if name == "" then
                        showProblem(QoL.L("profiles_bad_name"))
                        return
                    end
                    local existing = Data.findByName(name)
                    local owner = existing and Data.profileOwner(existing.id)
                    if owner ~= nil and owner ~= localClient then
                        showProblem(QoL.L("profiles_name_taken", name, owner + 1))
                        return
                    end
                    local profile, problem = Data.createProfile(name)
                    if profile then
                        choose(profile.id)
                    else
                        showProblem(QoL.L("not_possible", tostring(problem)))
                    end
                end)
            elseif item.id == NONE_ENTRY then
                choose(0)
            elseif item.blocked then
                showProblem(QoL.L("not_possible", item.text))
            else
                choose(item.id)
            end
        end,
        back = finish
    }
    list.onClick = function(item, button)
        if page.active and button == "left" then
            page.handlers.confirm()
        end
    end
    return page
end

-- Full screen chooser for player 1 alone (no player 2 signed in).
LUI.createMenu.QoLProfiles = function(controller)
    local self = UI.newMenu("QoLProfiles", controller)
    UI.fullscreenGround(self, 0.95)
    local page = Profiles.newPage(self, controller, 0, {
        x = 110, y = 80, rows = 9,
        onDone = function()
            QoL.safe("data.flush", Data.flush)
            UI.close(self)
        end
    })
    UI.bindButtons(self, controller, page.handlers)
    UI.button(self, QoL.L("done"), 1000, 672, 170, page.handlers.back)
    page.show()
    return self
end

-- Party list (top right): show profile names for this machine's local players.
-- Other machines in a LAN game keep their Steam names on this screen.
function Profiles.applyLobbyNames()
    local list = Engine.GetModel(Engine.GetGlobalModel(), "lobbyRoot.clientList")
    if not list then
        return
    end
    local count = CoD.SafeGetModelValue(list, "count") or 0
    for index = 1, count do
        local member = Engine.GetModel(list, tostring(index))
        local nameModel = member and Engine.GetModel(member, "clanTagAndGamertag")
        local gamertag = member and CoD.SafeGetModelValue(member, "gamertag")
        if nameModel and gamertag and gamertag ~= "" then
            local name = nil
            local isLocal = CoD.SafeGetModelValue(member, "isLocal")
            local controller = CoD.SafeGetModelValue(member, "controllerNum")
            if (isLocal == 1 or isLocal == true) and type(controller) == "number" then
                local profile = Data.assignedProfile(Engine.GetLocalClientNum(controller))
                name = profile and profile.name
            end
            -- Names given in the tournament, also for players on other PCs.
            if not name and QoL.names then
                name = QoL.names.lookup(gamertag)
            end
            if not name then
                -- No profile (any more): same text the stock list would show.
                local clantag = CoD.SafeGetModelValue(member, "clantag") or ""
                name = (clantag ~= "" and ("[" .. clantag .. "]") or "") .. gamertag
            end
            if Engine.GetModelValue(nameModel) ~= name then
                Engine.SetModelValue(nameModel, name)
            end
        end
    end
end

local stockUpdateLobbyList = CoD.LobbyUtility and CoD.LobbyUtility.UpdateLobbyList
if stockUpdateLobbyList then
    CoD.LobbyUtility.UpdateLobbyList = function(...)
        local result = stockUpdateLobbyList(...)
        QoL.safe("profiles.applyLobbyNames", Profiles.applyLobbyNames)
        return result
    end
else
    QoL.reportError("profiles", "CoD.LobbyUtility.UpdateLobbyList not found")
end

-- Do not call the stock UpdateLobbyList here: it needs the list widget as
-- argument, rebuilds every entry with Steam names and errors without it,
-- which left the names reset (bug 16.09.). Rewrite the entries in place.
Data.onAssignmentChanged = function()
    Profiles.applyLobbyNames()
end

-- Both players signed in: split screen, each half starts with the chooser.
-- Otherwise the full screen chooser for player 1.
function Profiles.open(menu)
    local host = QoL.controllerForLocalClient(0)
    if host == nil or not menu or menu.occludedBy then
        return false
    end
    if QoL.split and QoL.split.available() then
        return QoL.split.openProfiles(menu)
    end
    OpenOverlay(menu, "QoLProfiles", host)
    return true
end
