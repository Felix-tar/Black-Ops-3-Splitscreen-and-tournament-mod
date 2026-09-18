-- Built-in self-test of the pure logic (no engine state is touched): profile
-- store format, name table, match report and tournament scoring. Runs once
-- per menu load from main.lua. Development builds show the result in the
-- lobby status line; failures are reported as errors in every build.
require("ui.qol.util")

local QoL = CoD.QoL
local Selftest = {}
QoL.selftest = Selftest

local function check(results, name, condition)
    results.total = results.total + 1
    if not condition then
        table.insert(results.failed, name)
    end
end

-- Two local players (the guest has the " 1" suffix) and a bot whose name
-- contains a comma.
local SAMPLE_REPORT = "v1;t=1000;gt=tdm;map=mp_biodome;ts=allies,75;ts=axis,40;"
    .. "p=0,allies,20,5,3,2100,0,TestSpieler;p=1,axis,5,20,1,700,0,TestSpieler 1;"
    .. "p=2,axis,7,9,0,800,1,Bot, mit Komma;k=0_1,12;k=1_0,4"

local function sampleState(Data)
    local state = Data.emptyState()
    state.boots = 7
    table.insert(state.profiles, { id = 1, name = "Anna", kills = 10, deaths = 5, headshots = 2, matches = 3, wins = 2 })
    table.insert(state.profiles, { id = 2, name = "Ben", kills = 4, deaths = 9, headshots = 0, matches = 3, wins = 1 })
    state.vs["1:2"] = 6
    state.vs["2:1"] = 3
    state.assigned[0], state.assigned[1] = 1, 2
    state.inputMode = -1
    return state
end

local function testData(r)
    local Data = QoL.data
    local state = sampleState(Data)
    local payload = Data.serialize(state)
    local copy = Data.parse(payload)
    check(r, "data.boots", copy.boots == 7)
    check(r, "data.profiles", #copy.profiles == 2 and copy.profiles[1].kills == 10 and copy.profiles[2].name == "Ben")
    check(r, "data.duels", copy.vs["1:2"] == 6 and copy.vs["2:1"] == 3)
    check(r, "data.assigned", copy.assigned[0] == 1 and copy.assigned[1] == 2)
    check(r, "data.input", copy.inputMode == -1)
    check(r, "data.stable", Data.serialize(copy) == payload)
    check(r, "data.doubleAssign", Data.parse("B1;P1,0,0,0,0,0,A;A1,1").assigned[1] == 0)
    check(r, "data.unknownProfile", Data.parse("B1;A5,0").assigned[0] == 0)
    check(r, "data.empty", #Data.parse("").profiles == 0 and Data.parse(nil).boots == 0)
    check(r, "data.sanitize", Data.sanitizeName("  a;b,c|d=e~f  ") == "abcdef")
    check(r, "data.nameLength", string.len(Data.sanitizeName("abcdefghijklmnopqrst")) == Data.MAX_NAME)

    -- A full store drops the smallest duels but keeps every profile.
    local trimmedBefore = Data.trimmed
    local big = Data.parse(payload)
    for other = 3, 12 do
        big.vs["1:" .. other] = other * 10
    end
    local capacity = string.len(payload) + 12
    local fitted = Data.fit(big, capacity)
    check(r, "data.fit", fitted ~= nil and string.len(fitted) <= capacity and #big.profiles == 2 and big.vs["1:12"] == 120)
    check(r, "data.fitFull", Data.fit(Data.parse(payload), 10) == nil)
    Data.trimmed = trimmedBefore
end

local function testNames(r)
    local Names = QoL.names
    local map = Names.decode(Names.encode({ ["TestSpieler"] = "Anna", ["TestSpieler 1"] = "Ben", same = "same" }))
    check(r, "names.roundtrip", map["TestSpieler"] == "Anna" and map["TestSpieler 1"] == "Ben")
    check(r, "names.skipSame", map.same == nil)
    check(r, "names.clean", Names.decode(Names.encode({ ["a|b"] = "c=d" }))["ab"] == "cd")
end

local function testStats(r)
    local Stats = QoL.stats
    local report = Stats.parseReport(SAMPLE_REPORT)
    check(r, "stats.parse", report ~= nil and report.gametype == "tdm" and report.map == "mp_biodome")
    if not report then
        return
    end
    check(r, "stats.players", #report.players == 3 and report.players[3].name == "Bot, mit Komma" and report.players[3].bot)
    check(r, "stats.teams", report.teamBased and report.teams.allies == 75 and report.teams.axis == 40)
    check(r, "stats.kills", #report.kills == 2 and report.kills[1].attacker == 0 and report.kills[1].count == 12)
    check(r, "stats.localWinner", Stats.localWinner(report, { [0] = report.players[1], [1] = report.players[2] }) == 0)
    check(r, "stats.kd", Stats.kd({ kills = 10, deaths = 4 }) == 2.5 and Stats.kd({ kills = 3, deaths = 0 }) == 3)
    check(r, "stats.invalid", Stats.parseReport("kaputt") == nil)
end

local function newTournament(format)
    return {
        active = true, format = format, current = 1,
        players = {
            { gamertag = "TestSpieler", alias = "Anna", team = 1, kills = 0, deaths = 0, points = 0 },
            { gamertag = "TestSpieler 1", alias = "", team = 2, kills = 0, deaths = 0, points = 0 }
        },
        rounds = {
            { gametype = "tdm", map = "mp_biodome", winner = -1, scores = { 0, 0 } },
            { gametype = "dm", map = "mp_spire", winner = -1, scores = { 0, 0 } },
            { gametype = "tdm", map = "mp_apartments", winner = -1, scores = { 0, 0 } }
        }
    }
end

local function testTournament(r)
    local T = QoL.tournament
    local Stats = QoL.stats
    local win = Stats.parseReport(SAMPLE_REPORT)

    local t = newTournament("bo3")
    local handled, _, loadNext = T.score(t, win)
    check(r, "tournament.round1", handled and t.rounds[1].winner == 1 and t.current == 2 and loadNext)
    check(r, "tournament.totals", t.players[1].kills == 20 and t.players[2].deaths == 20)
    T.score(t, win)
    check(r, "tournament.finished", not t.active and T.overallWinner(t) == 1)
    check(r, "tournament.afterEnd", not T.score(t, win))

    local draw = Stats.parseReport("v1;gt=tdm;map=x;ts=allies,10;ts=axis,10;"
        .. "p=0,allies,1,1,0,100,0,TestSpieler;p=1,axis,1,1,0,100,0,TestSpieler 1")
    local d = newTournament("bo3")
    local _, _, replay = T.score(d, draw)
    check(r, "tournament.draw", d.rounds[1].winner == 0 and d.current == 1 and replay)

    local foreign = Stats.parseReport("v1;gt=tdm;map=x;p=0,allies,1,1,0,100,0,jemand")
    local f = newTournament("bo3")
    check(r, "tournament.foreign", not T.score(f, foreign) and f.current == 1 and f.rounds[1].winner == -1)

    local ffa = newTournament("ffa")
    T.score(ffa, win)
    check(r, "tournament.ffa", ffa.players[1].points == 2 and ffa.players[2].points == 1 and ffa.rounds[1].winner == 1)

    local copy = T.parse(T.serialize(t))
    check(r, "tournament.roundtrip", copy ~= nil and copy.format == "bo3" and not copy.active and #copy.players == 2
        and copy.players[1].alias == "Anna" and copy.rounds[2].winner == 1)
end

local function testBigStore(r)
    local B = QoL.bigStore
    local widths = { 8, 5, 3, 16, 7, 1, 12, 6, 8, 9, 11, 4, 8, 8, 8, 8, 8, 8, 8, 8 }
    local bytes = { 81, 71, 0, 5, 200, 17, 72, 228, 255, 0, 1 }
    local values = B.pack(widths, bytes)
    local back = B.unpack(widths, values, #bytes)
    local same = #back == #bytes
    for index = 1, #bytes do
        same = same and back[index] == bytes[index]
    end
    check(r, "bigstore.roundtrip", same)
    local fits = true
    for index, value in pairs(values) do
        fits = fits and value >= 0 and value < 2 ^ widths[index]
    end
    check(r, "bigstore.fieldRange", fits)
    check(r, "bigstore.tooSmall", B.pack({ 4 }, { 1, 2 }) == nil)
    local sum = B.checksum(bytes, 1, #bytes)
    bytes[5] = 201
    check(r, "bigstore.checksum", B.checksum(bytes, 1, #bytes) ~= sum)
end

local function testRules(r)
    local Rules = QoL.rules
    check(r, "rules.roundtrip", Rules.encode(Rules.parse("timeLimit:2.5,res:pst+snp,onlyHeadshots:1")) == "onlyHeadshots:1,timeLimit:2.5,res:snp+pst")
    check(r, "rules.empty", Rules.encode(Rules.parse("")) == "" and Rules.isEmpty("kaputt,:x"))
    local rules = Rules.parse("")
    local entry = { kind = "setting", key = "scoreLimit", options = { { value = 10, text = "10" }, { value = 20, text = "20" } } }
    Rules.cycle(entry, rules, 1)
    local first = rules.values.scoreLimit
    Rules.cycle(entry, rules, 1)
    local second = rules.values.scoreLimit
    Rules.cycle(entry, rules, 1)
    check(r, "rules.cycle", first == 10 and second == 20 and rules.values.scoreLimit == nil)
    Rules.cycle(entry, rules, -1)
    check(r, "rules.cycleBack", rules.values.scoreLimit == 20)
    local restriction = { kind = "restriction", key = "snp" }
    Rules.cycle(restriction, rules, 1)
    local on = rules.forbid.snp
    Rules.cycle(restriction, rules, 1)
    check(r, "rules.restriction", on == true and rules.forbid.snp == nil)
    Rules.applyTemplate(Rules.TEMPLATES[2], rules)
    check(r, "rules.template", rules.forbid.ar and rules.forbid.pst and not rules.forbid.snp)
    if Enum.itemGroup_t and Enum.itemGroup_t.ITEMGROUP_SNIPER then
        check(r, "rules.category", Rules.categoryOf("primary", Enum.itemGroup_t.ITEMGROUP_SNIPER) == "snp"
            and Rules.categoryOf("specialty3", 0) == "prk" and Rules.categoryOf("killstreak1", 0) == "ks")
    end
end

local function testPresets(r)
    local Presets = QoL.presets
    local preset = { name = "Test~Abend|1", format = "bo5", rulesMode = "r", rules = "onlyHeadshots:1",
        rounds = { { gametype = "tdm", map = "mp_biodome", rules = "res:snp" }, { gametype = "dom", map = "", rules = "" } } }
    local code = Presets.encode(preset)
    local copy = Presets.decode(code)
    check(r, "presets.roundtrip", copy ~= nil and Presets.encode(copy) == code and copy.name == "TestAbend1"
        and copy.rulesMode == "r" and #copy.rounds == 2 and copy.rounds[1].rules == "res:snp" and copy.rounds[2].map == "")
    check(r, "presets.invalid", Presets.decode("kaputt") == nil and Presets.decode("T1~~bo3~a~~tdm//") == nil)
    check(r, "presets.list", #Presets.decodeList(code .. "|" .. Presets.encode(Presets.BUILTIN[1])) == 2)
    local builtinOk = true
    for _, entry in ipairs(Presets.BUILTIN) do
        builtinOk = builtinOk and Presets.decode(Presets.encode(entry)) ~= nil
    end
    check(r, "presets.builtin", builtinOk)
end

local function testTournamentRules(r)
    local T = QoL.tournament
    local t = newTournament("bo3")
    t.name = "Abend"
    t.rounds[2].rules = "timeLimit:5,res:snp"
    local copy = T.parse(T.serialize(t))
    check(r, "tournament.rulesRoundtrip", copy ~= nil and copy.name == "Abend" and copy.rounds[2].rules == "timeLimit:5,res:snp"
        and copy.rounds[1].rules == "")
end

function Selftest.run()
    local results = { total = 0, failed = {} }
    local suites = {
        { name = "data", run = testData, needs = QoL.data },
        { name = "names", run = testNames, needs = QoL.names },
        { name = "stats", run = testStats, needs = QoL.stats },
        { name = "tournament", run = testTournament, needs = QoL.tournament and QoL.stats },
        { name = "bigstore", run = testBigStore, needs = QoL.bigStore },
        { name = "rules", run = testRules, needs = QoL.rules },
        { name = "presets", run = testPresets, needs = QoL.presets and QoL.rules },
        { name = "tournamentRules", run = testTournamentRules, needs = QoL.tournament }
    }
    for _, suite in ipairs(suites) do
        if suite.needs then
            local ok, err = pcall(suite.run, results)
            if not ok then
                table.insert(results.failed, suite.name .. " (" .. (string.match(tostring(err), "^[^\n]*") or "?") .. ")")
            end
        else
            table.insert(results.failed, suite.name .. " (Modul fehlt)")
        end
    end
    Selftest.results = results
    if #results.failed == 0 then
        Selftest.summary = "Selbsttest OK (" .. results.total .. ")"
        QoL.log(Selftest.summary)
    else
        Selftest.summary = "Selbsttest: " .. #results.failed .. " Fehler"
        QoL.reportError("selftest", table.concat(results.failed, ", "))
    end
    return results
end
