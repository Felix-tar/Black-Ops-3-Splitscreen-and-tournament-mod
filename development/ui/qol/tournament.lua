-- Tournaments for everyone in the lobby, including players on other PCs that
-- joined via LAN. Two teams of any size (1v1 up to the lobby limit) or free for
-- all with placement points.
--
-- Flow: host picks format, mode + map per round and the teams -> TURNIER
-- STARTEN applies round 1 (mode, map, teams) and launches the match -> the
-- host's match script reports every player -> onMatchReport scores the round
-- -> the next round is loaded and shown in the lobby.
--
-- State lives in the session dvar qol_tournament (survives lobby <-> match,
-- not a restart of the game) so the small permanent store stays free for
-- profiles. New formats: add an entry to Tournament.formats.
require("ui.qol.util")
require("ui.qol.lang")
require("ui.qol.data")

local QoL = CoD.QoL
local Data = QoL.data
local Tournament = {}
QoL.tournament = Tournament

local STATE_DVAR = "qol_tournament"
local NOT_PLAYED = -1
local DRAW = 0
local function teamName(team)
    return QoL.L(team == 2 and "t_team_b" or "t_team_a")
end

-- Formats ---------------------------------------------------------------------

local function teamWins(t)
    local wins = { 0, 0 }
    for _, round in ipairs(t.rounds) do
        if round.winner == 1 or round.winner == 2 then
            wins[round.winner] = wins[round.winner] + 1
        end
    end
    return wins
end

local function teamKills(t, team)
    local kills = 0
    for _, player in ipairs(t.players) do
        if player.team == team then
            kills = kills + player.kills
        end
    end
    return kills
end

Tournament.formats = {
    bo3 = { titleKey = "t_format_bo3", teams = true, rounds = 3, winsNeeded = 2 },
    bo5 = { titleKey = "t_format_bo5", teams = true, rounds = 5, winsNeeded = 3 },
    -- Placement points per round: last place 1, each place above +1.
    ffa = { titleKey = "t_format_ffa", teams = false, rounds = 3, placementPoints = true }
}

function Tournament.formatTitle(id)
    local format = Tournament.formats[id] or Tournament.formats.bo3
    return QoL.L(format.titleKey)
end
Tournament.formatOrder = { "bo3", "bo5", "ffa" }

-- Team formats: winner team 1/2, DRAW, or nil while undecided.
function Tournament.overallWinner(t)
    local format = Tournament.formats[t.format]
    if format.teams then
        local wins = teamWins(t)
        if wins[1] >= format.winsNeeded then return 1 end
        if wins[2] >= format.winsNeeded then return 2 end
        for _, round in ipairs(t.rounds) do
            if round.winner == NOT_PLAYED or round.winner == DRAW then
                return nil
            end
        end
        if wins[1] ~= wins[2] then
            return wins[1] > wins[2] and 1 or 2
        end
        local k1, k2 = teamKills(t, 1), teamKills(t, 2)
        if k1 ~= k2 then
            return k1 > k2 and 1 or 2
        end
        return DRAW
    end
    for _, round in ipairs(t.rounds) do
        if round.winner == NOT_PLAYED then
            return nil
        end
    end
    local best, bestPoints, tie = nil, -1, false
    for index, player in ipairs(t.players) do
        if player.points > bestPoints then
            best, bestPoints, tie = index, player.points, false
        elseif player.points == bestPoints then
            tie = true
        end
    end
    return tie and DRAW or best
end

-- Serialisation ----------------------------------------------------------------
--   records separated by '|', fields by '~'
--   H~<active>~<format>~<current>~<preset name>
--   P~<team>~<kills>~<deaths>~<points>~<gamertag>~<alias>
--   R~<gametype>~<map>~<winner>~<scoreA>~<scoreB>~<rules (rules.lua)>

local function clean(text)
    return (string.gsub(tostring(text or ""), "[|~\"%c]", ""))
end

local function serialize(t)
    local records = { table.concat({ "H", t.active and 1 or 0, t.format, t.current, clean(t.name) }, "~") }
    for _, p in ipairs(t.players) do
        table.insert(records, table.concat({ "P", p.team, p.kills, p.deaths, p.points, clean(p.gamertag), clean(p.alias) }, "~"))
    end
    for _, r in ipairs(t.rounds) do
        table.insert(records, table.concat({ "R", r.gametype, r.map, r.winner, r.scores[1], r.scores[2], clean(r.rules) }, "~"))
    end
    return table.concat(records, "|")
end

local function parse(text)
    if type(text) ~= "string" or string.sub(text, 1, 2) ~= "H~" then
        return nil
    end
    local t = { players = {}, rounds = {} }
    for _, record in ipairs(Data.split(text, "|")) do
        local f = Data.split(record, "~")
        if f[1] == "H" then
            t.active = f[2] == "1"
            t.format = Tournament.formats[f[3]] and f[3] or "bo3"
            t.current = tonumber(f[4]) or 1
            t.name = f[5] or ""
        elseif f[1] == "P" and #f >= 7 then
            table.insert(t.players, { team = tonumber(f[2]) or 1, kills = tonumber(f[3]) or 0,
                deaths = tonumber(f[4]) or 0, points = tonumber(f[5]) or 0, gamertag = f[6], alias = f[7] })
        elseif f[1] == "R" and #f >= 6 then
            table.insert(t.rounds, { gametype = f[2], map = f[3], winner = tonumber(f[4]) or NOT_PLAYED,
                scores = { tonumber(f[5]) or 0, tonumber(f[6]) or 0 }, rules = f[7] or "" })
        end
    end
    return t
end
Tournament.serialize = serialize
Tournament.parse = parse

function Tournament.current()
    if Tournament.cache == nil then
        Tournament.cache = parse(QoL.getSessionValue(STATE_DVAR)) or false
    end
    return Tournament.cache or nil
end

function Tournament.save(t)
    Tournament.cache = t or false
    if not QoL.setSessionValue(STATE_DVAR, t and serialize(t) or "") then
        QoL.log("tournament state only in menu memory (dvar not settable)")
    end
    -- Tournament names show up in party list, scoreboard and killfeed.
    QoL.safe("tournament.publishNames", Data.publishNames)
    if Data.onAssignmentChanged then
        QoL.safe("tournament.refreshLobbyNames", Data.onAssignmentChanged)
    end
end

-- Lobby ------------------------------------------------------------------------

-- Everyone in the lobby, on this PC or others: gamertag, xuid, team, name.
function Tournament.lobbyPlayers()
    local players = {}
    local list = Engine.GetModel(Engine.GetGlobalModel(), "lobbyRoot.clientList")
    if not list then
        return players
    end
    local count = CoD.SafeGetModelValue(list, "count") or 0
    for index = 1, count do
        local member = Engine.GetModel(list, tostring(index))
        local gamertag = member and CoD.SafeGetModelValue(member, "gamertag")
        if gamertag and gamertag ~= "" then
            local entry = {
                gamertag = gamertag,
                xuid = CoD.SafeGetModelValue(member, "xuid"),
                team = CoD.SafeGetModelValue(member, "team"),
                name = gamertag
            }
            local isLocal = CoD.SafeGetModelValue(member, "isLocal")
            local controller = CoD.SafeGetModelValue(member, "controllerNum")
            if (isLocal == 1 or isLocal == true) and type(controller) == "number" then
                local profile = Data.assignedProfile(Engine.GetLocalClientNum(controller))
                if profile then
                    entry.name = profile.name
                end
            end
            table.insert(players, entry)
        end
    end
    return players
end

local function findLobbyPlayer(lobby, gamertag)
    for _, entry in ipairs(lobby) do
        if clean(entry.gamertag) == clean(gamertag) then
            return entry
        end
    end
    return nil
end

function Tournament.playerName(p)
    if p.alias and p.alias ~= "" then
        return p.alias
    end
    return p.gamertag
end

function Tournament.teamLabel(t, team)
    local names = {}
    for _, p in ipairs(t.players) do
        if p.team == team then
            table.insert(names, Tournament.playerName(p))
        end
    end
    return teamName(team) .. " (" .. table.concat(names, ", ") .. ")"
end

-- Choices ----------------------------------------------------------------------

function Tournament.gametypes()
    local result = {}
    local ok, list = pcall(Engine.GetGametypesBase)
    if ok and list then
        for _, entry in pairs(list) do
            if entry.category == "standard" and (not CoD.AllowGameType or CoD.AllowGameType(entry.gametype)) then
                table.insert(result, { id = entry.gametype, name = Engine.Localize(entry.name) })
            end
        end
    end
    table.sort(result, function(a, b) return a.name < b.name end)
    if #result == 0 then
        result = { { id = "tdm", name = "Team Deathmatch" }, { id = "dm", name = "Free for All" } }
    end
    return result
end

function Tournament.maps()
    if not CoD.mapsTable then
        CoD.mapsTable = Engine.GetGDTMapsTable()
    end
    local result = {}
    for id, entry in pairs(CoD.mapsTable or {}) do
        local valid = entry.session_mode == Enum.eModes.MODE_MULTIPLAYER and not entry.isFreeRunMap
        if valid then
            local okValid, isValid = pcall(Engine.IsMapValid, id)
            valid = not okValid or isValid
        end
        if valid then
            table.insert(result, { id = id, name = Engine.Localize(entry.mapName or id), order = entry.unique_id or 0 })
        end
    end
    table.sort(result, function(a, b) return a.order < b.order end)
    return result
end

function Tournament.nameOf(list, id)
    for _, entry in ipairs(list) do
        if entry.id == id then
            return entry.name
        end
    end
    return tostring(id)
end

function Tournament.cycle(list, id, delta)
    if #list == 0 then
        return id
    end
    local position = 1
    for index, entry in ipairs(list) do
        if entry.id == id then
            position = index
        end
    end
    return list[(position - 1 + delta) % #list + 1].id
end

-- Rounds -----------------------------------------------------------------------

-- Puts every tournament player into the team of the roster. Uses the host
-- assignment of the engine; teamAssignment AUTO would reshuffle teams.
function Tournament.applyTeams(t)
    local format = Tournament.formats[t.format]
    if not format.teams then
        return
    end
    pcall(Engine.SetGametypeSetting, "teamAssignment", LuaEnums.TEAM_ASSIGNMENT.HOST)
    local lobby = Tournament.lobbyPlayers()
    local assigned = 0
    for _, p in ipairs(t.players) do
        local entry = findLobbyPlayer(lobby, p.gamertag)
        if entry and entry.xuid then
            local team = p.team == 1 and Enum.team_t.TEAM_ALLIES or Enum.team_t.TEAM_AXIS
            if pcall(Engine.LobbyHostAssignTeamToClient, entry.xuid, team) then
                assigned = assigned + 1
            end
        end
    end
    QoL.log("tournament: " .. assigned .. " players assigned to teams")
end

function Tournament.applyRound()
    local t = Tournament.current()
    if not t or not t.active then
        return false
    end
    local round = t.rounds[t.current]
    local host = QoL.controllerForLocalClient(0)
    if not round or host == nil then
        return false
    end
    local root = Engine.CreateModel(Engine.GetGlobalModel(), "CustomGamesRoot")
    Engine.SetModelValue(Engine.CreateModel(root, "gameType"), round.gametype)
    QoL.safe("tournament.gametype", GameModeSelected, nil, host)
    QoL.safe("tournament.map", SetMap, host, round.map, false)
    -- Rules after the gametype (it loads the gametype defaults), teams last.
    if QoL.rules then
        QoL.safe("tournament.rules", QoL.rules.apply, round.rules or "", host)
    end
    QoL.safe("tournament.teams", Tournament.applyTeams, t)
    pcall(Engine.LobbyVM_CallFunc, "OnGametypeSettingsChange", {
        lobbyType = Enum.LobbyType.LOBBY_TYPE_GAME,
        lobbyModule = Enum.LobbyModule.LOBBY_MODULE_HOST
    })

    local format = Tournament.formats[t.format]
    local banner = QoL.L("t_banner", t.current, #t.rounds)
    if format.teams then
        banner = banner .. Tournament.teamLabel(t, 1) .. "  vs  " .. Tournament.teamLabel(t, 2)
    else
        banner = banner .. QoL.L("t_banner_ffa")
    end
    if QoL.rules and round.rules and round.rules ~= "" then
        local summary = QoL.safe("tournament.rulesSummary", QoL.rules.summary, round.rules, { round.gametype }) or ""
        banner = banner .. "  -  " .. string.sub(summary, 1, 90)
    end
    pcall(Engine.SetDvar, "qol_round_info", banner)
    return true
end

-- Loads the current round, closes the tournament screen and starts the match
-- like SPIEL STARTEN (after a short delay so the lobby has taken over the
-- settings).
function Tournament.launchFrom(menu)
    local host = QoL.controllerForLocalClient(0)
    local lobby = menu and menu.occludedMenu
    if host == nil or not lobby or not Tournament.applyRound() then
        return false
    end
    if QoL.data and QoL.data.flush then
        QoL.safe("data.flush", QoL.data.flush)
    end
    GoBack(menu, host)
    lobby:addElement(LUI.UITimer.newElementTimer(2000, true, function()
        QoL.safe("tournament.launch", function()
            if lobby.occludedBy then
                QoL.log("tournament: start cancelled, another menu is open")
                return
            end
            -- Teams again right before the start: joining players get auto teams.
            local t = Tournament.current()
            if t then
                Tournament.applyTeams(t)
            end
            local ok = pcall(LobbyOnlineCustomLaunchGame_SelectionList, lobby, lobby, host)
            if not ok then
                Engine.SetDvar("skipto", "")
                Engine.SetDvar("sv_saveGameSkipto", "")
                CoD.LobbyBase.LaunchGame(lobby, host, Enum.LobbyType.LOBBY_TYPE_GAME)
            end
        end)
    end))
    return true
end

-- Scoring ------------------------------------------------------------------------

local function reportPlayer(report, gamertag)
    for _, player in ipairs(report.players) do
        if not player.bot and clean(player.name) == clean(gamertag) then
            return player
        end
    end
    return nil
end

-- Sum of personal scores and the engine team most members played in.
local function teamResult(t, report, team)
    local engineTeams, sum = {}, 0
    for _, p in ipairs(t.players) do
        if p.team == team then
            local rp = reportPlayer(report, p.gamertag)
            if rp then
                sum = sum + rp.score
                engineTeams[rp.team] = (engineTeams[rp.team] or 0) + 1
            end
        end
    end
    local best, bestCount = nil, 0
    for engineTeam, count in pairs(engineTeams) do
        if count > bestCount then
            best, bestCount = engineTeam, count
        end
    end
    return sum, best
end

-- Both teams are compared the same way: engine team scores when the two
-- tournament teams played on different engine teams, otherwise score sums.
local function teamPoints(t, report)
    local sumA, engineA = teamResult(t, report, 1)
    local sumB, engineB = teamResult(t, report, 2)
    if report.teamBased and engineA and engineB and engineA ~= engineB
        and report.teams[engineA] and report.teams[engineB] then
        return report.teams[engineA], report.teams[engineB]
    end
    return sumA, sumB
end

-- Scores one match report into t (pure: no saving, usable by the self-test).
-- Returns handled, event text, whether the next round has to be loaded.
function Tournament.score(t, report)
    if not t or not t.active or not report then
        return false
    end
    local round = t.rounds[t.current]
    if not round then
        return false
    end
    local format = Tournament.formats[t.format]

    local ranked = {}
    for _, p in ipairs(t.players) do
        local rp = reportPlayer(report, p.gamertag)
        if rp then
            table.insert(ranked, { player = p, report = rp, score = rp.score })
        end
    end
    -- A match without any tournament player (e.g. played before the
    -- tournament was set up) must not decide a round.
    if #ranked == 0 then
        return false, QoL.L("t_not_scored")
    end
    for _, entry in ipairs(ranked) do
        entry.player.kills = entry.player.kills + entry.report.kills
        entry.player.deaths = entry.player.deaths + entry.report.deaths
    end

    local event
    if format.teams then
        local a, b = teamPoints(t, report)
        round.scores = { a, b }
        if a == b then
            round.winner = DRAW
            return true, QoL.L("t_event_draw", t.current, a, b), true
        end
        round.winner = a > b and 1 or 2
        local wins = teamWins(t)
        event = QoL.L("t_event_win", t.current, teamName(round.winner), a, b, wins[1], wins[2])
    else
        table.sort(ranked, function(x, y) return x.score > y.score end)
        for place, entry in ipairs(ranked) do
            entry.player.points = entry.player.points + (#ranked - place + 1)
        end
        for index, p in ipairs(t.players) do
            if p == ranked[1].player then
                round.winner = index
            end
        end
        round.scores = { ranked[1].score, ranked[2] and ranked[2].score or 0 }
        event = QoL.L("t_event_ahead", t.current, Tournament.playerName(ranked[1].player))
    end

    local overall = Tournament.overallWinner(t)
    if overall ~= nil or t.current >= #t.rounds then
        t.active = false
        event = event .. QoL.L("t_event_finished")
    else
        t.current = t.current + 1
    end
    return true, event, t.active
end

-- Called by stats.lua for every finished match of this host.
function Tournament.onMatchReport(report)
    local t = Tournament.current()
    local handled, event, loadNext = Tournament.score(t, report)
    if event then
        Tournament.lastEvent = event
    end
    if not handled then
        return
    end
    Tournament.justScored = true
    Tournament.pendingApply = loadNext
    if not t.active then
        pcall(Engine.SetDvar, "qol_round_info", "")
    end
    Tournament.save(t)
end

-- Setup ------------------------------------------------------------------------

Tournament.MAX_ROUNDS = 5

-- Draft = editable tournament: format, rules mode ("a" same rules for all
-- rounds, "r" per round), common rules, 5 rounds, players. A preset
-- (presets.lua) fills format and rounds; maps it does not name are
-- distributed over the available maps.
function Tournament.newDraft(preset)
    local gametypes = Tournament.gametypes()
    local maps = Tournament.maps()
    local draft = { presetName = "", format = "bo3", rulesMode = "a", rules = "", rounds = {}, players = {} }
    local validGametype, validMap = {}, {}
    for _, entry in ipairs(gametypes) do validGametype[entry.id] = true end
    for _, entry in ipairs(maps) do validMap[entry.id] = true end
    for index = 1, Tournament.MAX_ROUNDS do
        local source = preset and preset.rounds[index]
        local gametype = source and source.gametype
        if not validGametype[gametype] then
            gametype = gametypes[math.min(index, #gametypes)].id
        end
        local map = source and source.map
        if not validMap[map] then
            map = #maps > 0 and maps[(index - 1) % #maps + 1].id or ""
        end
        draft.rounds[index] = { gametype = gametype, map = map, rules = source and source.rules or "" }
    end
    if preset then
        draft.presetName = preset.name
        draft.format = Tournament.formats[preset.format] and preset.format or "bo3"
        draft.rulesMode = preset.rulesMode == "r" and "r" or "a"
        draft.rules = preset.rules or ""
    end
    -- Default teams from the lobby: allies = A, axis = B, others alternate.
    local nextTeam = 1
    for _, entry in ipairs(Tournament.lobbyPlayers()) do
        local team
        if entry.team == Enum.team_t.TEAM_ALLIES then
            team = 1
        elseif entry.team == Enum.team_t.TEAM_AXIS then
            team = 2
        else
            team = nextTeam
            nextTeam = nextTeam == 1 and 2 or 1
        end
        table.insert(draft.players, { gamertag = entry.gamertag, alias = entry.name ~= entry.gamertag and entry.name or "",
            team = team, kills = 0, deaths = 0, points = 0 })
    end
    return draft
end

-- Rules that a round of the draft really uses.
function Tournament.roundRules(draft, index)
    if draft.rulesMode == "r" then
        return draft.rounds[index].rules or ""
    end
    return draft.rules or ""
end

-- Preset (presets.lua) from the draft, with the rounds of its format.
function Tournament.draftToPreset(draft, name)
    local preset = { name = name, format = draft.format, rulesMode = draft.rulesMode, rules = draft.rules, rounds = {} }
    for index = 1, Tournament.formats[draft.format].rounds do
        local round = draft.rounds[index]
        table.insert(preset.rounds, { gametype = round.gametype, map = round.map, rules = round.rules })
    end
    return preset
end

function Tournament.start(draft)
    local format = Tournament.formats[draft.format]
    local t = { active = true, format = draft.format, current = 1, name = draft.presetName or "", players = {}, rounds = {} }
    for _, p in ipairs(draft.players) do
        table.insert(t.players, { gamertag = p.gamertag, alias = p.alias, team = p.team, kills = 0, deaths = 0, points = 0 })
    end
    for index = 1, format.rounds do
        local r = draft.rounds[index]
        table.insert(t.rounds, { gametype = r.gametype, map = r.map, rules = Tournament.roundRules(draft, index),
            winner = NOT_PLAYED, scores = { 0, 0 } })
    end
    Tournament.lastEvent = nil
    Tournament.save(t)
end

function Tournament.cancel()
    Tournament.save(nil)
    Tournament.lastEvent = nil
    pcall(Engine.SetDvar, "qol_round_info", "")
end

-- The menu lives in tournamentmenu.lua.

function Tournament.open(menu)
    local host = QoL.controllerForLocalClient(0)
    if host == nil or not menu or menu.occludedBy then
        return false
    end
    OpenOverlay(menu, "QoLTournament", host)
    return true
end
