-- Local leaderboard of all local profiles plus head-to-head records and
-- profile management (rename, reset statistics, delete).
require("ui.qol.util")
require("ui.qol.lang")
require("ui.qol.ui")
require("ui.qol.data")
require("ui.qol.stats")

local QoL = CoD.QoL
local UI = QoL.ui
local Data = QoL.data
local Stats = QoL.stats
local Leaderboard = {}
QoL.leaderboard = Leaderboard

local SORTS = {
    { key = "lb_sort_wins", value = function(p) return p.wins end },
    { key = "lb_sort_kd", value = function(p) return Stats.kd(p) end },
    { key = "lb_sort_kills", value = function(p) return p.kills end },
    { key = "lb_sort_headshots", value = function(p) return p.headshots end },
    { key = "lb_sort_matches", value = function(p) return p.matches end }
}

local function pad(text, width)
    text = tostring(text)
    if string.len(text) >= width then
        return string.sub(text, 1, width)
    end
    return text .. string.rep(" ", width - string.len(text))
end

LUI.createMenu.QoLLeaderboard = function(controller)
    local self = UI.newMenu("QoLLeaderboard", controller)
    UI.fullscreenGround(self, 0.95)
    local sortIndex = 1
    local mode = "profiles"
    local confirming = nil

    UI.text(self, QoL.L("lb_title"), 110, 56, 900, 46, UI.ORANGE)
    local sortLabel = UI.text(self, "", 110, 106, 560, 22, UI.GREY)
    local usageLabel = UI.text(self, "", 700, 106, 470, 22, UI.GREY, Enum.LUIAlignment.LUI_ALIGNMENT_RIGHT)
    UI.text(self, pad("#", 4) .. pad(QoL.L("lb_col_name"), 16) .. pad(QoL.L("lb_col_matches"), 9)
        .. pad(QoL.L("lb_col_wins"), 7) .. pad(QoL.L("lb_col_kills"), 7) .. pad(QoL.L("lb_col_deaths"), 8)
        .. pad(QoL.L("lb_col_kd"), 7) .. QoL.L("lb_col_headshots"), 110, 146, 1060, 24, UI.GREY)
    local list = UI.newList(self, 110, 176, 1060, 32, 8)
    local sectionTitle = UI.text(self, "", 110, 440, 700, 30, UI.ORANGE)
    local duelRows = {}
    for index = 1, 5 do
        duelRows[index] = UI.text(self, "", 110, 474 + (index - 1) * 26, 1060, 22)
    end
    local actions = UI.newList(self, 110, 474, 700, 30, 4)
    local message = UI.text(self, "", 110, 608, 1060, 24, UI.WHITE)
    local help = UI.text(self, "", 110, 640, 1060, 20, UI.GREY)

    local handlers
    local refresh

    local function say(text, color)
        message:setText(text or "")
        color = color or UI.WHITE
        message:setRGB(color[1], color[2], color[3])
    end

    local function paintUsage()
        local used, capacity = Data.usage()
        local text = Data.available and QoL.L("lb_storage", used, capacity) or QoL.L("lb_storage_none")
        if Data.trimmed > 0 then
            text = text .. QoL.L("lb_storage_trimmed")
        end
        usageLabel:setText(text)
        local color = (not Data.available or (capacity > 0 and used > capacity * 0.85)) and UI.RED or UI.GREY
        usageLabel:setRGB(color[1], color[2], color[3])
    end

    local function paintDuels()
        for _, row in ipairs(duelRows) do row:setText("") end
        if mode ~= "profiles" then
            return
        end
        sectionTitle:setText(QoL.L("lb_duels"))
        local item = list.current()
        if not item or not item.profile then
            duelRows[1]:setText(#Data.get().profiles == 0 and QoL.L("lb_no_profiles") or "")
            return
        end
        local me = item.profile
        local line = 1
        for _, other in ipairs(Data.get().profiles) do
            if other.id ~= me.id and line <= #duelRows then
                local won, lost = Data.vsKills(me.id, other.id), Data.vsKills(other.id, me.id)
                if won + lost > 0 then
                    duelRows[line]:setText(QoL.L("lb_duel_line", me.name, other.name, won, lost))
                    line = line + 1
                end
            end
        end
        if line == 1 then
            duelRows[1]:setText(QoL.L("lb_no_duels", me.name))
        end
    end

    local function paintHelp()
        if mode == "actions" then
            help:setText(QoL.L("hint_actions"))
        else
            help:setText(QoL.L("hint_leaderboard"))
        end
    end

    local function closeActions()
        mode = "profiles"
        confirming = nil
        actions.setItems({})
        paintHelp()
        paintDuels()
    end

    local function openActions(profile)
        mode = "actions"
        confirming = nil
        sectionTitle:setText(QoL.L("lb_profile", profile.name))
        for _, row in ipairs(duelRows) do row:setText("") end
        actions.setItems({
            { text = QoL.L("lb_rename"), run = function()
                UI.askText(self, controller, function(text)
                    local ok, reason = Data.renameProfile(profile.id, text)
                    if ok then
                        say(QoL.L("lb_renamed", profile.name), UI.GREEN)
                    else
                        say(QoL.L("not_possible", tostring(reason)), UI.RED)
                    end
                    closeActions()
                    refresh()
                end)
            end },
            { text = QoL.L("lb_reset"), color = UI.RED, confirm = QoL.L("lb_reset_confirm", profile.name),
                run = function()
                    Data.resetStats(profile.id)
                    say(QoL.L("lb_reset_done", profile.name), UI.GREEN)
                    closeActions()
                    refresh()
                end },
            { text = QoL.L("lb_delete"), color = UI.RED, confirm = QoL.L("lb_delete_confirm", profile.name),
                run = function()
                    Data.deleteProfile(profile.id)
                    say(QoL.L("lb_deleted", profile.name), UI.GREEN)
                    closeActions()
                    refresh()
                end },
            { text = QoL.L("cancel"), run = function() say(""); closeActions() end }
        })
        actions.select(1)
        paintHelp()
    end

    local function createProfile()
        UI.askText(self, controller, function(text)
            local name = Data.sanitizeName(text)
            if name == "" then
                say(QoL.L("profiles_bad_name"), UI.RED)
            elseif Data.findByName(name) then
                say(QoL.L("lb_exists", name), UI.RED)
            else
                local profile, reason = Data.createProfile(name)
                if profile then
                    say(QoL.L("lb_created", name), UI.GREEN)
                else
                    say(QoL.L("not_possible", tostring(reason)), UI.RED)
                end
            end
            refresh()
        end)
    end

    refresh = function()
        local sort = SORTS[sortIndex]
        sortLabel:setText(QoL.L("lb_sort", QoL.L(sort.key)))
        local sorted = {}
        for _, profile in ipairs(Data.get().profiles) do
            table.insert(sorted, profile)
        end
        table.sort(sorted, function(a, b)
            local va, vb = sort.value(a), sort.value(b)
            if va ~= vb then return va > vb end
            return string.lower(a.name) < string.lower(b.name)
        end)
        local items = {}
        for rank, p in ipairs(sorted) do
            table.insert(items, {
                profile = p,
                text = pad(rank, 4) .. pad(p.name, 16) .. pad(p.matches, 8) .. pad(p.wins, 7) .. pad(p.kills, 7)
                    .. pad(p.deaths, 7) .. pad(Stats.kd(p), 7) .. p.headshots
            })
        end
        table.insert(items, { text = QoL.L("profiles_new"), color = UI.GREEN, create = true })
        list.setItems(items)
        paintUsage()
        paintHelp()
        paintDuels()
    end

    local function cycleSort(delta)
        sortIndex = (sortIndex - 1 + delta + #SORTS) % #SORTS + 1
        refresh()
    end

    handlers = {
        up = function()
            if mode == "actions" then
                if not confirming then actions.move(-1) end
            else
                list.move(-1); paintDuels()
            end
        end,
        down = function()
            if mode == "actions" then
                if not confirming then actions.move(1) end
            else
                list.move(1); paintDuels()
            end
        end,
        left = function() if mode == "profiles" then cycleSort(-1) end end,
        right = function() if mode == "profiles" then cycleSort(1) end end,
        confirm = function()
            if mode == "actions" then
                local action = actions.current()
                if not action then return end
                if action.confirm and confirming ~= action then
                    confirming = action
                    say(action.confirm .. QoL.L("yes_no"), UI.RED)
                    return
                end
                confirming = nil
                action.run()
                return
            end
            local item = list.current()
            if item and item.create then
                createProfile()
            elseif item and item.profile then
                say("")
                openActions(item.profile)
            end
        end,
        back = function()
            if mode == "actions" then
                if confirming then
                    confirming = nil
                    say("")
                else
                    closeActions()
                end
            else
                UI.close(self)
            end
        end
    }
    UI.bindButtons(self, controller, handlers)

    list.onClick = function(item, button)
        if mode == "actions" then
            closeActions()
        end
        paintDuels()
        if button == "left" then
            handlers.confirm()
        end
    end
    actions.onClick = function(item, button)
        if button == "left" then
            handlers.confirm()
        else
            handlers.back()
        end
    end
    UI.onClick(sortLabel, function(button) cycleSort(button == "right" and -1 or 1) end)
    UI.button(self, QoL.L("back"), 1000, 672, 170, handlers.back)

    refresh()
    return self
end

function Leaderboard.open(menu)
    local controller = QoL.controllerForLocalClient(0)
    if controller == nil or not menu or menu.occludedBy then
        return false
    end
    OpenOverlay(menu, "QoLLeaderboard", controller)
    return true
end
