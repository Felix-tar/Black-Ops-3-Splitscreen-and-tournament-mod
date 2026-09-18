-- In-match additions, loaded by the HUD through core_patch_require right
-- before the per-player HUDs are built. Shows local profile names and
-- tournament names (from the dvar qol_names) in the scoreboard and in a
-- killfeed fed by the host's match script (LUINotifyEvent "qol_obit").
if Engine.GetCurrentMap() == "core_frontend" then
    return
end

require("ui.qol.util")
require("ui.qol.lang")
require("ui.qol.names")

local QoL = CoD.QoL
local Names = QoL.names

local FLAG_HEADSHOT = 1
local FLAG_MELEE = 2
local FLAG_SUICIDE = 4
local FEED_LINES = 5
local FEED_SECONDS = 6

-- If the lobby's name table did not reach the match, rebuild it for this PC's
-- local players from the stored profiles (loadouts file, readable in game).
local fallbackTried = false
local function ensureNames()
    if fallbackTried or Names.hasAny() then
        return
    end
    fallbackTried = true
    QoL.safe("ingame.loadProfiles", function()
        require("ui.qol.data")
        QoL.data.load()
        QoL.data.publishNames()
    end)
end

local function nameForClient(controller, clientNum)
    if type(clientNum) ~= "number" or clientNum < 0 then
        return nil
    end
    local ok, gamertag = pcall(Engine.GetPlayerNameForClientNum, controller, clientNum)
    if not ok or not gamertag then
        return nil
    end
    return Names.lookup(gamertag) or gamertag
end

-- Scoreboard rows call this global for the name column.
if GetClientNameAndClanTag then
    local stockNameAndClanTag = GetClientNameAndClanTag
    GetClientNameAndClanTag = function(controller, clientNum)
        local ok, name = pcall(function()
            local gamertag = Engine.GetPlayerNameForClientNum(controller, clientNum)
            return gamertag and Names.lookup(gamertag)
        end)
        if ok and name then
            return name
        end
        return stockNameAndClanTag(controller, clientNum)
    end
end

-- The engine killfeed cannot be renamed; hide it while names are active and
-- show the QoL killfeed instead (single screen only; splitscreen has none).
if CoD.GameMessages and CoD.GameMessages.ObituaryWindowUpdateVisibility then
    local stockVisibility = CoD.GameMessages.ObituaryWindowUpdateVisibility
    CoD.GameMessages.ObituaryWindowUpdateVisibility = function(window, event)
        stockVisibility(window, event)
        local ok, active = pcall(Names.hasAny)
        if ok and active then
            window:setAlpha(0)
        end
    end
end

local function describeKill(controller, attackerNum, victimNum, flags)
    local victim = nameForClient(controller, victimNum) or "?"
    local attacker = nameForClient(controller, attackerNum)
    if flags % (FLAG_SUICIDE * 2) >= FLAG_SUICIDE or not attacker or attackerNum == victimNum then
        return victim .. QoL.L("ig_suicide")
    end
    local how = "  >  "
    if flags % (FLAG_HEADSHOT * 2) >= FLAG_HEADSHOT then
        how = QoL.L("ig_headshot")
    elseif flags % (FLAG_MELEE * 2) >= FLAG_MELEE then
        how = QoL.L("ig_melee")
    end
    return attacker .. how .. victim
end

local function attachKillfeed(hud, controller)
    local feed = LUI.UIElement.new()
    feed:setLeftRight(true, false, 24, 560)
    feed:setTopBottom(false, true, -340, -340 + FEED_LINES * 24)
    hud:addElement(feed)

    local rows = {}
    for index = 1, FEED_LINES do
        local row = LUI.UIText.new()
        row:setLeftRight(true, true, 0, 0)
        row:setTopBottom(true, false, (index - 1) * 24, (index - 1) * 24 + 20)
        row:setTTF("fonts/default.ttf")
        row:setAlignment(Enum.LUIAlignment.LUI_ALIGNMENT_LEFT)
        row:setText("")
        feed:addElement(row)
        rows[index] = row
    end

    local entries = {}
    local function paint()
        for index, row in ipairs(rows) do
            local entry = entries[index]
            row:setText(entry and entry.text or "")
            if entry then
                row:setRGB(entry.color[1], entry.color[2], entry.color[3])
            end
        end
    end

    feed:addElement(LUI.UITimer.newElementTimer(500, false, function()
        local now = Engine.milliseconds()
        local changed = false
        while entries[1] and now - entries[1].time > FEED_SECONDS * 1000 do
            table.remove(entries, 1)
            changed = true
        end
        if changed then
            paint()
        end
    end))

    local notifyModel = Engine.CreateModel(Engine.GetModelForController(controller), "scriptNotify")
    hud:subscribeToModel(notifyModel, function(model)
        QoL.safe("ingame.killfeed", function()
            if Engine.GetModelValue(model) ~= "qol_obit" or not Names.hasAny() then
                return
            end
            local data = CoD.GetScriptNotifyData(model) or {}
            local attackerNum, victimNum, flags = data[1], data[2], data[3] or 0
            local color = { 0.92, 0.92, 0.92 }
            local okSelf, selfNum = pcall(Engine.GetClientNum, controller)
            if okSelf and selfNum ~= nil then
                if attackerNum == selfNum then
                    color = { 1, 0.6, 0.15 }
                elseif victimNum == selfNum then
                    color = { 1, 0.35, 0.3 }
                end
            end
            table.insert(entries, { text = describeKill(controller, attackerNum, victimNum, flags),
                color = color, time = Engine.milliseconds() })
            while #entries > FEED_LINES do
                table.remove(entries, 1)
            end
            paint()
        end)
    end)
end

if LUI.createMenu.T7Hud then
    local stockT7Hud = LUI.createMenu.T7Hud
    LUI.createMenu.T7Hud = function(controller, ...)
        local hud = stockT7Hud(controller, ...)
        ensureNames()
        if hud then
            QoL.safe("ingame.attachKillfeed", attachKillfeed, hud, controller)
        end
        return hud
    end
end
