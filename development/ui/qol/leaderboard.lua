-- Local leaderboard of all local profiles plus head-to-head records and
-- profile management (rename, reset statistics, delete).
require("ui.qol.util")
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
    { title = "Siege", value = function(p) return p.wins end },
    { title = "K/D", value = function(p) return Stats.kd(p) end },
    { title = "Kills", value = function(p) return p.kills end },
    { title = "Kopfschüsse", value = function(p) return p.headshots end },
    { title = "Spiele", value = function(p) return p.matches end }
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

    UI.text(self, "LOKALE BESTENLISTE", 110, 56, 900, 46, UI.ORANGE)
    local sortLabel = UI.text(self, "", 110, 106, 560, 22, UI.GREY)
    local usageLabel = UI.text(self, "", 700, 106, 470, 22, UI.GREY, Enum.LUIAlignment.LUI_ALIGNMENT_RIGHT)
    UI.text(self, pad("#", 4) .. pad("NAME", 16) .. pad("SPIELE", 8) .. pad("SIEGE", 7) .. pad("KILLS", 7)
        .. pad("TODE", 7) .. pad("K/D", 7) .. "KOPFSCH.", 110, 146, 1060, 24, UI.GREY)
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
        local text = Data.available and ("Speicher: " .. used .. " / " .. capacity .. " Zeichen")
            or "Kein dauerhafter Speicher - nur bis zum Neustart"
        if Data.trimmed > 0 then
            text = text .. "  (alte Duelle gekürzt)"
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
        sectionTitle:setText("DUELLE")
        local item = list.current()
        if not item or not item.profile then
            duelRows[1]:setText(#Data.get().profiles == 0
                and "Noch keine Profile. Beim Aktivieren des Splitscreens oder mit + NEUES PROFIL anlegen." or "")
            return
        end
        local me = item.profile
        local line = 1
        for _, other in ipairs(Data.get().profiles) do
            if other.id ~= me.id and line <= #duelRows then
                local won, lost = Data.vsKills(me.id, other.id), Data.vsKills(other.id, me.id)
                if won + lost > 0 then
                    duelRows[line]:setText(me.name .. " gegen " .. other.name .. ":   " .. won .. " Kills  /  " .. lost .. " Tode")
                    line = line + 1
                end
            end
        end
        if line == 1 then
            duelRows[1]:setText(me.name .. ": noch keine Duelle gegen andere Profile.")
        end
    end

    local function paintHelp()
        if mode == "actions" then
            help:setText("Hoch/Runter: Aktion   A/Enter/Klick: ausführen   B/Esc: zurück")
        else
            help:setText("Hoch/Runter: Profil   Links/Rechts: Sortierung   A/Enter/Klick: Profil bearbeiten   B/Esc: zurück")
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
        sectionTitle:setText("PROFIL " .. profile.name)
        for _, row in ipairs(duelRows) do row:setText("") end
        actions.setItems({
            { text = "UMBENENNEN", run = function()
                UI.askText(self, controller, function(text)
                    local ok, reason = Data.renameProfile(profile.id, text)
                    if ok then
                        say("Umbenannt in " .. profile.name .. ".", UI.GREEN)
                    else
                        say("Nicht möglich: " .. tostring(reason), UI.RED)
                    end
                    closeActions()
                    refresh()
                end)
            end },
            { text = "STATISTIK ZURÜCKSETZEN", color = UI.RED, confirm = "Statistik von " .. profile.name .. " auf 0 setzen?",
                run = function()
                    Data.resetStats(profile.id)
                    say("Statistik von " .. profile.name .. " zurückgesetzt.", UI.GREEN)
                    closeActions()
                    refresh()
                end },
            { text = "PROFIL LÖSCHEN", color = UI.RED, confirm = "Profil " .. profile.name .. " endgültig löschen?",
                run = function()
                    Data.deleteProfile(profile.id)
                    say("Profil " .. profile.name .. " gelöscht.", UI.GREEN)
                    closeActions()
                    refresh()
                end },
            { text = "ABBRECHEN", run = function() say(""); closeActions() end }
        })
        actions.select(1)
        paintHelp()
    end

    local function createProfile()
        UI.askText(self, controller, function(text)
            local name = Data.sanitizeName(text)
            if name == "" then
                say("Kein gültiger Name.", UI.RED)
            elseif Data.findByName(name) then
                say("Profil " .. name .. " gibt es schon.", UI.RED)
            else
                local profile, reason = Data.createProfile(name)
                if profile then
                    say("Profil " .. name .. " angelegt.", UI.GREEN)
                else
                    say("Nicht möglich: " .. tostring(reason), UI.RED)
                end
            end
            refresh()
        end)
    end

    refresh = function()
        local sort = SORTS[sortIndex]
        sortLabel:setText("Sortiert nach: < " .. sort.title .. " >")
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
        table.insert(items, { text = "+ NEUES PROFIL", color = UI.GREEN, create = true })
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
                    say(action.confirm .. "   A/Enter/Klick: Ja   B/Esc: Nein", UI.RED)
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
    UI.button(self, "ZURÜCK", 1000, 672, 170, handlers.back)

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
