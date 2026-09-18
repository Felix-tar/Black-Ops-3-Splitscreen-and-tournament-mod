-- Turns the match report written by _clientids.gsc (dvar qol_last_match) into
-- profile statistics, head-to-head kills and tournament results.
require("ui.qol.util")
require("ui.qol.data")

local QoL = CoD.QoL
local Data = QoL.data
local Stats = {}
QoL.stats = Stats

local REPORT_DVAR = "qol_last_match"

function Stats.parseReport(text)
    if type(text) ~= "string" or string.sub(text, 1, 3) ~= "v1;" then
        return nil
    end
    local report = { teams = {}, players = {}, kills = {} }
    for _, record in ipairs(Data.split(text, ";")) do
        local key, value = string.match(record, "^(%w+)=(.*)$")
        if key == "gt" then
            report.gametype = value
        elseif key == "map" then
            report.map = value
        elseif key == "t" then
            report.time = value
        elseif key == "ts" then
            local fields = Data.split(value, ",")
            report.teams[fields[1]] = tonumber(fields[2]) or 0
            report.teamBased = true
        elseif key == "p" then
            local fields = Data.split(value, ",")
            if #fields >= 8 then
                -- The name is the last field and may itself contain commas.
                local name = table.concat(fields, ",", 8)
                table.insert(report.players, {
                    ent = tonumber(fields[1]), team = fields[2], kills = tonumber(fields[3]) or 0,
                    deaths = tonumber(fields[4]) or 0, headshots = tonumber(fields[5]) or 0,
                    score = tonumber(fields[6]) or 0, bot = fields[7] == "1", name = name
                })
            end
        elseif key == "k" then
            local fields = Data.split(value, ",")
            local attacker, victim = string.match(fields[1] or "", "^(%d+)_(%d+)$")
            if attacker then
                table.insert(report.kills, { attacker = tonumber(attacker), victim = tonumber(victim), count = tonumber(fields[2]) or 0 })
            end
        end
    end
    return report
end

-- Maps local clients 0/1 to report players: by gamertag first, then by the
-- order of the human players (the host joins first).
local function matchLocalPlayers(report)
    local humans = {}
    for _, player in ipairs(report.players) do
        if not player.bot then
            table.insert(humans, player)
        end
    end
    table.sort(humans, function(a, b) return (a.ent or 99) < (b.ent or 99) end)

    local result = {}
    local used = {}
    for localClient = 0, 1 do
        local controller = QoL.controllerForLocalClient(localClient)
        local ok, tag = false, nil
        if controller ~= nil then
            ok, tag = pcall(Engine.GetGamertagForController, controller)
        end
        if ok and tag then
            for _, player in ipairs(humans) do
                if not used[player] and player.name == tag then
                    result[localClient] = player
                    used[player] = true
                    break
                end
            end
        end
    end
    for localClient = 0, 1 do
        if not result[localClient] then
            for _, player in ipairs(humans) do
                if not used[player] then
                    result[localClient] = player
                    used[player] = true
                    break
                end
            end
        end
    end
    return result
end

local function wonMatch(report, player)
    if report.teamBased then
        local own = report.teams[player.team]
        if own == nil then
            return false
        end
        for team, score in pairs(report.teams) do
            if team ~= player.team and score >= own then
                return false
            end
        end
        return true
    end
    for _, other in ipairs(report.players) do
        if other ~= player and other.score >= player.score then
            return false
        end
    end
    return true
end

-- Winner between the two local players: 0, 1 or nil for a draw.
function Stats.localWinner(report, locals)
    local a, b = locals[0], locals[1]
    if not a or not b then
        return nil
    end
    local aWon, bWon = wonMatch(report, a), wonMatch(report, b)
    if report.teamBased and a.team ~= b.team then
        if aWon then return 0 end
        if bWon then return 1 end
    end
    if a.score ~= b.score then
        return a.score > b.score and 0 or 1
    end
    if a.kills ~= b.kills then
        return a.kills > b.kills and 0 or 1
    end
    return nil
end

function Stats.apply(report)
    local locals = matchLocalPlayers(report)
    local state = Data.get()
    local profileIds = { [0] = state.assigned[0] or 0, [1] = state.assigned[1] or 0 }

    for localClient = 0, 1 do
        local player = locals[localClient]
        local profile = Data.profile(profileIds[localClient])
        if player and profile then
            profile.kills = profile.kills + player.kills
            profile.deaths = profile.deaths + player.deaths
            profile.headshots = profile.headshots + player.headshots
            profile.matches = profile.matches + 1
            if wonMatch(report, player) then
                profile.wins = profile.wins + 1
            end
        end
    end

    local a, b = locals[0], locals[1]
    if a and b and profileIds[0] ~= 0 and profileIds[1] ~= 0 then
        for _, kill in ipairs(report.kills) do
            if kill.attacker == a.ent and kill.victim == b.ent then
                Data.addVsKills(profileIds[0], profileIds[1], kill.count)
            elseif kill.attacker == b.ent and kill.victim == a.ent then
                Data.addVsKills(profileIds[1], profileIds[0], kill.count)
            end
        end
    end

    local winner = Stats.localWinner(report, locals)
    local summary = {
        gametype = report.gametype, map = report.map, winner = winner,
        kills = { a and a.kills or 0, b and b.kills or 0 }
    }
    if QoL.tournament then
        -- The tournament scores all players of the report (also other PCs).
        QoL.safe("tournament.onMatchReport", QoL.tournament.onMatchReport, report)
    end
    Data.save()
    Stats.lastSummary = summary
    return summary
end

-- Called whenever the lobby is created (also after returning from a match).
function Stats.consumePendingReport()
    local ok, text = pcall(Engine.DvarString, nil, REPORT_DVAR)
    if not ok or type(text) ~= "string" or text == "" then
        return nil
    end
    pcall(Engine.SetDvar, REPORT_DVAR, "")
    local report = Stats.parseReport(text)
    if not report then
        QoL.reportError("stats", "Match-Report unlesbar")
        return nil
    end
    QoL.log("Match ausgewertet: " .. tostring(report.gametype) .. " " .. tostring(report.map))
    return Stats.apply(report)
end

function Stats.kd(profile)
    if profile.deaths == 0 then
        return profile.kills
    end
    return math.floor(profile.kills / profile.deaths * 100 + 0.5) / 100
end
