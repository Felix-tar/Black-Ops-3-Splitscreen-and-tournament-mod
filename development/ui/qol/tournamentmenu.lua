-- Tournament screen: set up (presets, format, rounds with mode, map and
-- rules), rules editor, teams, preset file import/export and standings.
-- Left a list, right a preview (map picture, mode icon, rules).
require("ui.qol.util")
require("ui.qol.lang")
require("ui.qol.ui")
require("ui.qol.data")
require("ui.qol.rules")
require("ui.qol.presets")
require("ui.qol.tournament")

local QoL = CoD.QoL
local UI = QoL.ui
local Data = QoL.data
local Rules = QoL.rules
local Presets = QoL.presets
local Tournament = QoL.tournament

local NOT_PLAYED = -1
local DRAW = 0
local PREVIEW_ROWS = 20
local PREVIEW_CHARS = 42
local IMAGE_ROWS = 14

local function teamName(team)
    return QoL.L(team == 2 and "t_team_b" or "t_team_a")
end

local FORMAT_INFO = { bo3 = "t_info_bo3", bo5 = "t_info_bo5", ffa = "t_info_ffa" }

-- Word wrap for the preview; long words (codes) are cut into pieces.
local function wrap(text, width)
    local lines, line = {}, ""
    for word in string.gmatch(tostring(text or ""), "%S+") do
        while string.len(word) > width do
            if line ~= "" then
                table.insert(lines, line)
                line = ""
            end
            table.insert(lines, string.sub(word, 1, width))
            word = string.sub(word, width + 1)
        end
        if line == "" then
            line = word
        elseif string.len(line) + 1 + string.len(word) <= width then
            line = line .. " " .. word
        else
            table.insert(lines, line)
            line = word
        end
    end
    if line ~= "" then
        table.insert(lines, line)
    end
    return lines
end

local function shorten(text, length)
    if string.len(text) <= length then
        return text
    end
    return string.sub(text, 1, length - 3) .. "..."
end

local function modeIcon(gametype)
    local ok, image = pcall(function()
        return Engine.StructTableLookupString(CoDShared.gametypesStructTable, "name", gametype, "image")
    end)
    return ok and image or nil
end

local function mapImage(map)
    local entry = CoD.mapsTable and CoD.mapsTable[map]
    return entry and entry.previewImage or nil
end

LUI.createMenu.QoLTournament = function(controller)
    local self = UI.newMenu("QoLTournament", controller)
    UI.fullscreenGround(self, 0.96)
    local gametypes = Tournament.gametypes()
    local maps = Tournament.maps()
    local presets = Presets.all()
    local presetIndex = 1
    local draft = Tournament.newDraft()
    local page = Tournament.current() and "standings" or "setup"
    local rulesTarget = "all"
    local editing = nil
    local confirmItem = nil

    UI.text(self, QoL.L("t_title"), 110, 40, 640, 40, UI.ORANGE)
    local subtitle = UI.text(self, "", 110, 84, 1060, 22, UI.GREY)
    local list = UI.newList(self, 110, 118, 650, 32, 14)
    local message = UI.text(self, "", 110, 580, 1060, 24, UI.WHITE)
    local help = UI.text(self, "", 110, 612, 1060, 20, UI.GREY)

    UI.panel(self, 776, 110, 418, 466, 0.6)
    local previewTitle = UI.text(self, "", 790, 118, 390, 26, UI.ORANGE)
    local previewImage = UI.image(self, 790, 150, 390, 219)
    local previewIcon = UI.image(self, 790, 376, 48, 48)
    local previewMode = UI.text(self, "", 846, 388, 334, 24, UI.WHITE)
    local previewRows = {}
    for index = 1, PREVIEW_ROWS do
        previewRows[index] = UI.text(self, "", 790, 150 + (index - 1) * 21, 390, 18, UI.WHITE)
    end

    local paint
    local handlers

    local function say(text, color)
        message:setText(text or "")
        color = color or UI.WHITE
        message:setRGB(color[1], color[2], color[3])
    end

    -- preview = { title, image, icon, mode, lines }
    local function showPreview(preview)
        preview = preview or {}
        previewTitle:setText(preview.title or "")
        local hasImage = UI.setImage(previewImage, preview.image)
        local hasIcon = UI.setImage(previewIcon, preview.icon)
        previewMode:setText((hasImage or hasIcon) and (preview.mode or "") or "")
        local first = (hasImage or hasIcon) and IMAGE_ROWS + 1 or 1
        local lines = preview.lines or {}
        for index, row in ipairs(previewRows) do
            local line = index >= first and lines[index - first + 1] or nil
            row:setText(line or "")
        end
    end

    local function updatePreview()
        local item = list.current()
        local preview = nil
        if item and item.preview then
            preview = QoL.safe("tournament.preview", item.preview)
        end
        showPreview(preview)
    end

    local function addLines(lines, text)
        for _, line in ipairs(wrap(text, PREVIEW_CHARS)) do
            table.insert(lines, line)
        end
    end

    local function roundCount()
        return Tournament.formats[draft.format].rounds
    end

    local function roundPreview(index, round, rulesText, extra)
        local lines = {}
        addLines(lines, QoL.L("t_map", Tournament.nameOf(maps, round.map)))
        addLines(lines, QoL.L("t_rules", Rules.summary(rulesText or "", { round.gametype })))
        if extra then
            addLines(lines, extra)
        end
        return {
            title = QoL.L("t_round", index), image = mapImage(round.map), icon = modeIcon(round.gametype),
            mode = Tournament.nameOf(gametypes, round.gametype), lines = lines
        }
    end

    local function presetPreview(preset)
        if not preset then
            return nil
        end
        local lines = {}
        local format = Tournament.formats[preset.format] or Tournament.formats.bo3
        addLines(lines, Tournament.formatTitle(preset.format)
            .. QoL.L(preset.builtin and "t_preset_builtin_tag" or "t_preset_own_tag"))
        addLines(lines, preset.rulesMode == "r" and QoL.L("t_preset_rules_each")
            or QoL.L("t_rules", Rules.summary(preset.rules or "", {})))
        for index, round in ipairs(preset.rounds) do
            if index <= format.rounds then
                local mapName = (round.map and round.map ~= "") and Tournament.nameOf(maps, round.map) or QoL.L("t_preset_map_auto")
                addLines(lines, index .. ". " .. Tournament.nameOf(gametypes, round.gametype) .. " - " .. mapName)
                if preset.rulesMode == "r" then
                    addLines(lines, "   " .. Rules.summary(round.rules or "", { round.gametype }))
                end
            end
        end
        addLines(lines, QoL.L("t_preset_load_hint"))
        return { title = QoL.L("t_preset", preset.name), lines = lines }
    end

    local function refreshPresets(selectName)
        presets = Presets.all()
        presetIndex = math.max(1, math.min(presetIndex, #presets))
        if selectName then
            for index, preset in ipairs(presets) do
                if string.lower(preset.name) == string.lower(selectName) then
                    presetIndex = index
                end
            end
        end
    end

    local function validateTeams()
        local counts = { 0, 0 }
        for _, p in ipairs(draft.players) do
            counts[p.team] = counts[p.team] + 1
        end
        if #draft.players < 2 then
            return false, QoL.L("t_need_players")
        end
        if Tournament.formats[draft.format].teams and (counts[1] == 0 or counts[2] == 0) then
            return false, QoL.L("t_need_teams")
        end
        return true
    end

    -- Keeps team choices and names when players are read again.
    local function keepPlayers(fresh)
        local previous = {}
        for _, p in ipairs(draft.players) do
            previous[p.gamertag] = p
        end
        for _, p in ipairs(fresh.players) do
            if previous[p.gamertag] then
                p.team = previous[p.gamertag].team
                p.alias = previous[p.gamertag].alias
            end
        end
        return fresh.players
    end

    -- Rules page ------------------------------------------------------------------------

    local function rulesGametypes()
        if rulesTarget ~= "all" then
            return { draft.rounds[rulesTarget].gametype }
        end
        local result, seen = {}, {}
        for index = 1, roundCount() do
            local gametype = draft.rounds[index].gametype
            if not seen[gametype] then
                seen[gametype] = true
                table.insert(result, gametype)
            end
        end
        return result
    end

    local function storeRules()
        local text = Rules.encode(editing)
        if rulesTarget == "all" then
            draft.rules = text
        else
            draft.rounds[rulesTarget].rules = text
        end
        return text
    end

    local function openRules(target)
        rulesTarget = target
        local text = target == "all" and draft.rules or draft.rounds[target].rules
        editing = Rules.parse(text)
        page = "rules"
        say("")
        list.selected = 2
        list.offset = 0
        paint()
    end

    local function rulesItems()
        local items = {}
        for _, group in ipairs(Rules.groups(rulesGametypes())) do
            table.insert(items, { text = "---  " .. group.title .. "  ---", header = true, color = UI.ORANGE })
            for _, template in ipairs(group.templates or {}) do
                table.insert(items, { text = QoL.L("t_quick", QoL.L(template.key)), color = UI.GREY,
                    action = function()
                        Rules.applyTemplate(template, editing)
                        storeRules()
                        say(QoL.L("t_quick", QoL.L(template.key)), UI.GREEN)
                    end,
                    preview = function()
                        local lines = {}
                        local forbidden = {}
                        for _, id in ipairs(template.forbid) do
                            for _, category in ipairs(Rules.CATEGORIES) do
                                if category.id == id then
                                    table.insert(forbidden, Rules.categoryLabel(category.id))
                                end
                            end
                        end
                        addLines(lines, #forbidden > 0 and QoL.L("r_forbidden_list", table.concat(forbidden, ", "))
                            or QoL.L("r_no_restriction"))
                        addLines(lines, QoL.L("r_restriction_info"))
                        return { title = QoL.L(template.key), lines = lines }
                    end })
            end
            for _, entry in ipairs(group.entries) do
                local changed = (entry.kind == "restriction" and editing.forbid[entry.key])
                    or (entry.kind ~= "restriction" and editing.values[entry.key] ~= nil)
                table.insert(items, {
                    text = entry.label .. ":   < " .. Rules.valueText(entry, editing) .. " >",
                    color = changed and UI.GREEN or nil,
                    change = function(delta)
                        Rules.cycle(entry, editing, delta)
                        storeRules()
                    end,
                    preview = function()
                        local lines = {}
                        addLines(lines, entry.hint ~= "" and entry.hint or " ")
                        table.insert(lines, " ")
                        addLines(lines, QoL.L("r_current", Rules.valueText(entry, editing)))
                        if entry.kind ~= "restriction" then
                            addLines(lines, QoL.L("r_default_hint"))
                        end
                        return { title = entry.label, lines = lines }
                    end
                })
            end
        end
        table.insert(items, { text = "---  " .. QoL.L("t_actions") .. "  ---", header = true, color = UI.ORANGE })
        if rulesTarget ~= "all" and roundCount() > 1 then
            table.insert(items, { text = QoL.L("t_copy_all"), color = UI.GREEN,
                confirm = QoL.L("t_copy_all_confirm"),
                action = function()
                    local text = storeRules()
                    for index = 1, Tournament.MAX_ROUNDS do
                        draft.rounds[index].rules = text
                    end
                    draft.rules = text
                    say(QoL.L("t_copied_all"), UI.GREEN)
                end })
            if rulesTarget > 1 then
                table.insert(items, { text = QoL.L("t_take_from", rulesTarget - 1),
                    action = function()
                        editing = Rules.parse(draft.rounds[rulesTarget - 1].rules)
                        storeRules()
                        say(QoL.L("t_taken_from", rulesTarget - 1), UI.GREEN)
                    end })
            end
        end
        table.insert(items, { text = QoL.L("t_reset_rules"), color = UI.RED, confirm = QoL.L("t_reset_rules_confirm"),
            action = function()
                editing = Rules.parse("")
                storeRules()
                say(QoL.L("t_reset_rules_done"), UI.GREEN)
            end })
        table.insert(items, { text = QoL.L("done"), color = UI.GREEN, action = function()
            page = "setup"
            paint()
            return "painted"
        end })
        return items
    end

    -- Setup page --------------------------------------------------------------------------

    local function setupItems()
        local format = Tournament.formats[draft.format]
        local items = {}
        local preset = presets[presetIndex]
        table.insert(items, {
            text = QoL.L("t_preset", preset and preset.name or "-"),
            color = UI.ORANGE,
            change = function(delta)
                presetIndex = (presetIndex - 1 + delta) % #presets + 1
            end,
            action = function()
                local fresh = Tournament.newDraft(preset)
                fresh.players = keepPlayers(fresh)
                draft = fresh
                say(QoL.L("t_preset_loaded", preset.name), UI.GREEN)
            end,
            preview = function() return presetPreview(presets[presetIndex]) end
        })
        table.insert(items, { text = QoL.L("t_format", Tournament.formatTitle(draft.format)),
            change = function(delta)
                local position = 1
                for index, id in ipairs(Tournament.formatOrder) do
                    if id == draft.format then position = index end
                end
                draft.format = Tournament.formatOrder[(position - 1 + delta) % #Tournament.formatOrder + 1]
            end,
            preview = function()
                local lines = {}
                addLines(lines, QoL.L(FORMAT_INFO[draft.format] or "t_info_bo3"))
                return { title = Tournament.formatTitle(draft.format), lines = lines }
            end })
        table.insert(items, { text = QoL.L("t_rules_mode", QoL.L(draft.rulesMode == "r" and "t_rules_each" or "t_rules_same")),
            change = function()
                if draft.rulesMode == "a" then
                    draft.rulesMode = "r"
                    for index = 1, Tournament.MAX_ROUNDS do
                        draft.rounds[index].rules = draft.rules
                    end
                    say(QoL.L("t_rules_each"))
                else
                    draft.rulesMode = "a"
                    draft.rules = draft.rounds[1].rules or ""
                    say(QoL.L("t_rules_same") .. " - " .. QoL.L("t_taken_from", 1))
                end
            end,
            preview = function()
                local lines = {}
                addLines(lines, QoL.L("t_rules_mode_info"))
                return { title = QoL.L("t_rules_all_title"), lines = lines }
            end })
        if draft.rulesMode == "a" then
            table.insert(items, { text = QoL.L("t_rules_all_entry", shorten(Rules.summary(draft.rules, {}), 34)), color = UI.GREEN,
                action = function() openRules("all"); return "painted" end,
                preview = function()
                    local lines = {}
                    addLines(lines, Rules.summary(draft.rules, rulesGametypes()))
                    table.insert(lines, " ")
                    addLines(lines, QoL.L("t_rules_open_hint"))
                    return { title = QoL.L("t_rules_all_title"), lines = lines }
                end })
        end
        for index = 1, format.rounds do
            local round = draft.rounds[index]
            local function preview()
                return roundPreview(index, round, Tournament.roundRules(draft, index))
            end
            table.insert(items, { text = QoL.L("t_round_mode", index, Tournament.nameOf(gametypes, round.gametype)),
                change = function(delta) round.gametype = Tournament.cycle(gametypes, round.gametype, delta) end,
                preview = preview })
            table.insert(items, { text = QoL.L("t_round_map", index, Tournament.nameOf(maps, round.map)),
                change = function(delta) round.map = Tournament.cycle(maps, round.map, delta) end,
                preview = preview })
            if draft.rulesMode == "r" then
                table.insert(items, { text = QoL.L("t_round_rules", index, shorten(Rules.summary(round.rules, { round.gametype }), 30)),
                    color = UI.GREEN,
                    action = function() openRules(index); return "painted" end,
                    preview = preview })
            end
        end
        local teamText = format.teams and QoL.L("t_teams_entry", #draft.players) or QoL.L("t_players_entry", #draft.players)
        table.insert(items, { text = teamText, action = function() page = "teams"; paint(); return "painted" end,
            preview = function()
                local lines = {}
                if format.teams then
                    addLines(lines, Tournament.teamLabel(draft, 1))
                    addLines(lines, Tournament.teamLabel(draft, 2))
                else
                    for _, p in ipairs(draft.players) do addLines(lines, Tournament.playerName(p)) end
                end
                return { title = QoL.L("t_players_title"), lines = lines }
            end })
        table.insert(items, { text = QoL.L("t_save_preset"),
            action = function()
                UI.askText(self, controller, function(text)
                    local name = Presets.cleanName(text)
                    local ok, result = Presets.saveUser(Tournament.draftToPreset(draft, name))
                    if ok then
                        draft.presetName = name
                        refreshPresets(name)
                        say(result .. ": " .. name, UI.GREEN)
                    else
                        say(QoL.L("not_possible", tostring(result)), UI.RED)
                    end
                    paint()
                end)
            end,
            preview = function()
                local lines = {}
                addLines(lines, QoL.L("t_save_info"))
                addLines(lines, Presets.storageText())
                return { title = QoL.L("t_save_preset"), lines = lines }
            end })
        if preset and not preset.builtin then
            table.insert(items, { text = QoL.L("t_delete_preset", preset.name), color = UI.RED,
                confirm = QoL.L("t_delete_confirm", preset.name),
                action = function()
                    Presets.deleteUser(preset.name)
                    refreshPresets()
                    say(QoL.L("t_preset_deleted"), UI.GREEN)
                end })
        end
        table.insert(items, { text = QoL.L("t_file_entry"),
            action = function() page = "file"; list.selected = 1; paint(); return "painted" end,
            preview = function()
                local lines = {}
                addLines(lines, QoL.L("t_file_info"))
                return { title = QoL.L("t_file_entry"), lines = lines }
            end })
        table.insert(items, { text = QoL.L("t_start"), color = UI.GREEN,
            action = function()
                local ok, problem = validateTeams()
                if not ok then
                    say(problem, UI.RED)
                    return
                end
                Tournament.start(draft)
                if Tournament.launchFrom(self) then
                    return "closed"
                end
                say(QoL.L("t_start_failed"), UI.RED)
            end,
            preview = function()
                local lines = {}
                for index = 1, format.rounds do
                    local round = draft.rounds[index]
                    addLines(lines, index .. ". " .. Tournament.nameOf(gametypes, round.gametype) .. " - " .. Tournament.nameOf(maps, round.map))
                end
                addLines(lines, QoL.L("t_start_info"))
                return { title = QoL.L("t_start"), lines = lines }
            end })
        return items
    end

    -- Teams page --------------------------------------------------------------------------------

    local function teamItems()
        local format = Tournament.formats[draft.format]
        local items = {}
        for _, p in ipairs(draft.players) do
            local label = Tournament.playerName(p)
            if label ~= p.gamertag then
                label = label .. "  [" .. p.gamertag .. "]"
            end
            if format.teams then
                label = teamName(p.team) .. ":  " .. label
            end
            table.insert(items, { text = label, player = p, color = p.team == 1 and UI.WHITE or UI.GREY,
                change = format.teams and function() p.team = p.team == 1 and 2 or 1 end or nil })
        end
        table.insert(items, { text = QoL.L("t_reload_lobby"), action = function()
            local fresh = Tournament.newDraft()
            draft.players = keepPlayers(fresh)
        end })
        table.insert(items, { text = QoL.L("back"), color = UI.GREEN, action = function() page = "setup"; paint(); return "painted" end })
        return items
    end

    -- File page ---------------------------------------------------------------------------------

    local function fileInstructions()
        local lines = {}
        addLines(lines, QoL.L("f_info1"))
        addLines(lines, Presets.logPath())
        addLines(lines, QoL.L("f_info2", Presets.FILE_NAME))
        addLines(lines, QoL.L("f_info3", Presets.FILE_NAME, QoL.fileLocation and QoL.fileLocation() or ""))
        addLines(lines, QoL.L("f_info4"))
        return lines
    end

    local function fileItems()
        local preset = presets[presetIndex]
        local items = {}
        table.insert(items, { text = QoL.L("f_export"),
            action = function()
                local count = Presets.exportToLog()
                say(QoL.L("f_exported", count), UI.GREEN)
            end,
            preview = function() return { title = QoL.L("f_title_export"), lines = fileInstructions() } end })
        table.insert(items, { text = QoL.L("f_import", string.upper(Presets.FILE_NAME)),
            action = function()
                say(QoL.L("f_loading", Presets.FILE_NAME))
                Presets.importFromFile(self, controller, function(count, skipped, problem)
                    if problem then
                        say(problem, UI.RED)
                    else
                        refreshPresets()
                        say(QoL.L("f_imported", count, skipped > 0 and QoL.L("f_skipped", skipped) or ""), UI.GREEN)
                        paint()
                    end
                end)
            end,
            preview = function() return { title = QoL.L("f_title_import"), lines = fileInstructions() } end })
        table.insert(items, { text = QoL.L("f_paste"),
            action = function()
                UI.askText(self, controller, function(text)
                    local count, skipped, problem = Presets.importCode(text)
                    if problem then
                        say(problem, UI.RED)
                    else
                        refreshPresets()
                        say(QoL.L("f_imported", count, skipped > 0 and QoL.L("f_skipped", skipped) or ""), UI.GREEN)
                    end
                    paint()
                end, "KEYBOARD_TYPE_FILESHARE_PUBLISH_DESCRIPTION")
            end,
            preview = function()
                local lines = {}
                addLines(lines, QoL.L("f_paste_info"))
                return { title = QoL.L("f_title_paste"), lines = lines }
            end })
        if preset then
            table.insert(items, { text = QoL.L("f_show_code", preset.name),
                preview = function()
                    local lines = {}
                    addLines(lines, Presets.encode(preset))
                    return { title = QoL.L("f_code_title", preset.name), lines = lines }
                end })
        end
        table.insert(items, { text = QoL.L("back"), color = UI.GREEN, action = function() page = "setup"; paint(); return "painted" end })
        return items
    end

    -- Standings page ------------------------------------------------------------------------------

    local function standingsItems(t)
        local format = Tournament.formats[t.format]
        local items = {}
        for index, round in ipairs(t.rounds) do
            local state
            if round.winner == NOT_PLAYED then
                state = QoL.L((index == t.current and t.active) and "t_state_next" or "t_state_open")
            elseif round.winner == DRAW then
                state = QoL.L((index == t.current and t.active) and "t_state_draw_replay" or "t_state_draw")
            elseif format.teams then
                state = QoL.L("t_state_team", teamName(round.winner), round.scores[1], round.scores[2])
            else
                state = QoL.L("t_state_ahead", Tournament.playerName(t.players[round.winner] or { gamertag = "?" }))
            end
            table.insert(items, { text = QoL.L("t_round", index) .. ":  " .. Tournament.nameOf(gametypes, round.gametype) .. "  -  " .. state,
                color = UI.GREY,
                preview = function() return roundPreview(index, round, round.rules, QoL.L("t_result", state)) end })
        end
        local players = {}
        for _, p in ipairs(t.players) do table.insert(players, p) end
        table.sort(players, function(a, b)
            if format.teams and a.team ~= b.team then return a.team < b.team end
            if a.points ~= b.points then return a.points > b.points end
            return a.kills > b.kills
        end)
        for _, p in ipairs(players) do
            local prefix = format.teams and (teamName(p.team) .. "  ") or (p.points .. "  ")
            table.insert(items, { text = prefix .. Tournament.playerName(p) .. "   " .. p.kills .. " / " .. p.deaths })
        end
        if t.active then
            local round = t.rounds[t.current]
            table.insert(items, { text = QoL.L("t_start_round", t.current), color = UI.GREEN,
                action = function()
                    if Tournament.launchFrom(self) then
                        return "closed"
                    end
                    say(QoL.L("t_round_failed"), UI.RED)
                end,
                preview = function() return round and roundPreview(t.current, round, round.rules) or nil end })
            table.insert(items, { text = QoL.L("t_cancel"), color = UI.RED, confirm = QoL.L("t_cancel_confirm"),
                action = function()
                    Tournament.cancel()
                    draft = Tournament.newDraft()
                    page = "setup"
                    say(QoL.L("t_cancelled"))
                end })
        else
            table.insert(items, { text = QoL.L("t_new"), color = UI.GREEN, action = function()
                Tournament.cancel()
                draft = Tournament.newDraft()
                page = "setup"
            end })
        end
        return items
    end

    -- Painting and input ---------------------------------------------------------------------------

    paint = function()
        local t = Tournament.current()
        if page == "standings" and not t then
            page = "setup"
        end
        local items
        subtitle:setRGB(UI.GREY[1], UI.GREY[2], UI.GREY[3])
        if page == "standings" then
            local format = Tournament.formats[t.format]
            local name = (t.name and t.name ~= "") and (t.name .. "  -  ") or ""
            if t.active then
                if format.teams then
                    local wins = { 0, 0 }
                    for _, round in ipairs(t.rounds) do
                        if round.winner == 1 or round.winner == 2 then wins[round.winner] = wins[round.winner] + 1 end
                    end
                    subtitle:setText(name .. QoL.L("t_subtitle_score", Tournament.formatTitle(t.format),
                        teamName(1), wins[1], wins[2], teamName(2)))
                else
                    subtitle:setText(name .. QoL.L("t_subtitle_round", Tournament.formatTitle(t.format), t.current, #t.rounds))
                end
            else
                local winner = Tournament.overallWinner(t)
                if winner == DRAW or winner == nil then
                    subtitle:setText(name .. QoL.L("t_winner_draw"))
                elseif format.teams then
                    subtitle:setText(name .. QoL.L("t_winner", Tournament.teamLabel(t, winner)))
                else
                    subtitle:setText(name .. QoL.L("t_winner", Tournament.playerName(t.players[winner])))
                end
                subtitle:setRGB(UI.GREEN[1], UI.GREEN[2], UI.GREEN[3])
            end
            items = standingsItems(t)
            help:setText(QoL.L("hint_list"))
            if Tournament.lastEvent then
                say(Tournament.lastEvent)
            end
        elseif page == "rules" then
            local target = rulesTarget == "all" and QoL.L("t_rules_target_all")
                or QoL.L("t_rules_target_round", rulesTarget, Tournament.nameOf(gametypes, draft.rounds[rulesTarget].gametype))
            subtitle:setText(QoL.L("t_rules_page", target))
            items = rulesItems()
            help:setText(QoL.L("hint_rules"))
        elseif page == "teams" then
            subtitle:setText(QoL.L("t_teams_hint"))
            items = teamItems()
            help:setText(QoL.L("hint_teams"))
        elseif page == "file" then
            subtitle:setText(Presets.storageText())
            items = fileItems()
            help:setText(QoL.L("hint_list"))
        else
            subtitle:setText(QoL.L("t_subtitle_new", #draft.players, Presets.storageText()))
            items = setupItems()
            help:setText(QoL.L("hint_setup"))
        end
        list.setItems(items)
        local current = list.current()
        if current and current.header then
            list.move(1)
        end
        updatePreview()
    end

    local function move(delta)
        for _ = 1, #list.items do
            list.move(delta)
            local item = list.current()
            if not item or not item.header then
                break
            end
        end
        confirmItem = nil
        updatePreview()
    end

    local function change(delta)
        local item = list.current()
        if item and item.change then
            confirmItem = nil
            item.change(delta)
            paint()
        end
    end

    handlers = {
        up = function() move(-1) end,
        down = function() move(1) end,
        left = function() change(-1) end,
        right = function() change(1) end,
        confirm = function()
            local item = list.current()
            if not item or item.header then
                return
            end
            if item.action then
                if item.confirm and confirmItem ~= item.text then
                    confirmItem = item.text
                    say(item.confirm .. QoL.L("yes_no"), UI.RED)
                    return
                end
                confirmItem = nil
                local result = item.action()
                -- A started round closes this menu; a page change already painted.
                if result ~= "closed" and result ~= "painted" then
                    paint()
                end
            elseif item.change then
                change(1)
            end
        end,
        extra = function()
            local item = list.current()
            if page == "teams" and item and item.player then
                UI.askText(self, controller, function(text)
                    item.player.alias = Data.sanitizeName(text)
                    paint()
                end)
            end
        end,
        back = function()
            if confirmItem then
                confirmItem = nil
                say("")
            elseif page == "rules" or page == "teams" or page == "file" then
                page = "setup"
                paint()
            else
                UI.close(self)
            end
        end
    }
    UI.bindButtons(self, controller, handlers)
    list.onClick = function(item, button)
        if button == "right" then
            handlers.left()
        else
            handlers.confirm()
        end
        updatePreview()
    end
    UI.button(self, QoL.L("back"), 1000, 672, 170, handlers.back)

    paint()
    return self
end
