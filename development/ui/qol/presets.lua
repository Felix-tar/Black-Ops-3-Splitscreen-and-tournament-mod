-- Tournament presets ("Turniervorlagen"): format, rounds with mode, map and
-- rules. Built-in presets ship with the mod; own presets are kept in the
-- additional store (bigstore.lua) and can be exported to a file and imported
-- on another PC.
--
-- Preset code (one line, also used in files):
--   T1~<name>~<format>~<a = same rules for all | r = per round>~<rules>~<round>^<round>...
--   round = <gametype>/<map>/<rules>          (empty map = first free map)
--
-- File: the game cannot write files, but it writes its console log. EXPORT
-- prints ready-made cfg lines into console_mp.log of the mod folder; copied
-- into qol_turniere.cfg they are loaded again with IMPORT (exec).
require("ui.qol.util")
require("ui.qol.lang")
require("ui.qol.bigstore")
require("ui.qol.rules")

local QoL = CoD.QoL
local Presets = {}
QoL.presets = Presets

local STORE_PREFIX = "P1|"
local SESSION_DVAR = "qol_presets"
local FILE_NAME = "qol_turniere.cfg"
local COUNT_DVAR = "qol_vorlagen_anzahl"
local CODE_DVAR = "qol_vorlage_"
Presets.MAX_IMPORT = 30
Presets.FILE_NAME = FILE_NAME

local SNIPER = "res:smg+ar+cqb+lmg+pst+lnc+spw"
local SHOTGUN = "res:smg+ar+lmg+snp+pst+lnc+spw"

-- Built-in preset names stay English in every language: they are also the
-- identifier used when saving and importing.
Presets.BUILTIN = {
    { name = "Classic", format = "bo3", rulesMode = "a", rules = "",
        rounds = { { gametype = "tdm" }, { gametype = "dom" }, { gametype = "sd" } } },
    { name = "Snipers", format = "bo3", rulesMode = "a", rules = SNIPER,
        rounds = { { gametype = "tdm" }, { gametype = "conf" }, { gametype = "tdm" } } },
    { name = "Headshots", format = "bo3", rulesMode = "a", rules = "onlyHeadshots:1",
        rounds = { { gametype = "tdm" }, { gametype = "dom" }, { gametype = "tdm" } } },
    { name = "Hardcore", format = "bo3", rulesMode = "a", rules = "hardcoreMode:1",
        rounds = { { gametype = "tdm" }, { gametype = "sd" }, { gametype = "dom" } } },
    { name = "Shotguns", format = "bo3", rulesMode = "a", rules = SHOTGUN,
        rounds = { { gametype = "tdm" }, { gametype = "koth" }, { gametype = "tdm" } } },
    { name = "Free for all", format = "ffa", rulesMode = "a", rules = "",
        rounds = { { gametype = "dm" }, { gametype = "gun" }, { gametype = "dm" } } }
}
for _, preset in ipairs(Presets.BUILTIN) do
    preset.builtin = true
end

-- Codes (pure, self-test) -----------------------------------------------------------

function Presets.cleanName(name)
    name = string.gsub(tostring(name or ""), "[;,|=~\"%^/%c]", "")
    name = string.gsub(name, "^%s+", "")
    name = string.gsub(name, "%s+$", "")
    return string.sub(name, 1, 20)
end

local function cleanRules(text)
    return QoL.rules.encode(QoL.rules.parse(text or ""))
end

local function cleanId(text)
    return (string.gsub(tostring(text or ""), "[^%w_]", ""))
end

function Presets.encode(preset)
    local rounds = {}
    for _, round in ipairs(preset.rounds) do
        table.insert(rounds, cleanId(round.gametype) .. "/" .. cleanId(round.map) .. "/" .. cleanRules(round.rules))
    end
    return table.concat({ "T1", Presets.cleanName(preset.name), cleanId(preset.format),
        preset.rulesMode == "r" and "r" or "a", cleanRules(preset.rules), table.concat(rounds, "^") }, "~")
end

local function split(text, separator)
    local parts, start = {}, 1
    while true do
        local position = string.find(text, separator, start, true)
        if not position then
            table.insert(parts, string.sub(text, start))
            return parts
        end
        table.insert(parts, string.sub(text, start, position - 1))
        start = position + 1
    end
end

function Presets.decode(code)
    if type(code) ~= "string" then
        return nil
    end
    code = string.gsub(code, "^%s+", "")
    code = string.gsub(code, "%s+$", "")
    local fields = split(code, "~")
    if fields[1] ~= "T1" or #fields < 6 then
        return nil
    end
    local preset = {
        name = Presets.cleanName(fields[2]), format = cleanId(fields[3]),
        rulesMode = fields[4] == "r" and "r" or "a", rules = cleanRules(fields[5]), rounds = {}
    }
    if preset.name == "" then
        return nil
    end
    for _, roundText in ipairs(split(fields[6], "^")) do
        local parts = split(roundText, "/")
        if parts[1] and parts[1] ~= "" then
            table.insert(preset.rounds, { gametype = cleanId(parts[1]), map = cleanId(parts[2]), rules = cleanRules(parts[3]) })
        end
    end
    if #preset.rounds == 0 then
        return nil
    end
    return preset
end

-- Several codes separated by "|" (store, paste).
function Presets.decodeList(text)
    local list = {}
    for _, code in ipairs(split(text or "", "|")) do
        local preset = Presets.decode(code)
        if preset then
            table.insert(list, preset)
        end
    end
    return list
end

function Presets.encodeList(list)
    local codes = {}
    for _, preset in ipairs(list) do
        table.insert(codes, Presets.encode(preset))
    end
    return table.concat(codes, "|")
end

-- Store ----------------------------------------------------------------------------------

Presets.user = nil
Presets.persistent = false

function Presets.ensureLoaded()
    if Presets.user then
        return Presets.user
    end
    local text = QoL.safe("bigStore.load", QoL.bigStore.load)
    if text ~= nil then
        Presets.persistent = true
        if string.sub(text, 1, string.len(STORE_PREFIX)) == STORE_PREFIX then
            Presets.user = Presets.decodeList(string.sub(text, string.len(STORE_PREFIX) + 1))
        else
            Presets.user = {}
        end
    else
        Presets.persistent = false
        Presets.user = Presets.decodeList(QoL.getSessionValue(SESSION_DVAR))
    end
    return Presets.user
end

function Presets.persist()
    local text = Presets.encodeList(Presets.ensureLoaded())
    QoL.setSessionValue(SESSION_DVAR, text)
    if not Presets.persistent then
        return true
    end
    local ok, err = QoL.bigStore.save(STORE_PREFIX .. text)
    if not ok then
        QoL.log("presets not saved: " .. tostring(err))
    end
    return ok, err
end

function Presets.storageText()
    Presets.ensureLoaded()
    if not Presets.persistent then
        return QoL.L("f_storage_none", tostring(QoL.bigStore.status))
    end
    local used = string.len(STORE_PREFIX .. Presets.encodeList(Presets.user))
    return QoL.L("f_storage", used, QoL.bigStore.capacity)
end

function Presets.all()
    local list = {}
    for _, preset in ipairs(Presets.BUILTIN) do
        table.insert(list, preset)
    end
    for _, preset in ipairs(Presets.ensureLoaded()) do
        table.insert(list, preset)
    end
    return list
end

local function findIndex(list, name)
    local lower = string.lower(name)
    for index, preset in ipairs(list) do
        if string.lower(preset.name) == lower then
            return index
        end
    end
    return nil
end

function Presets.isBuiltinName(name)
    return findIndex(Presets.BUILTIN, name) ~= nil
end

-- Adds or replaces an own preset. Returns ok, message.
function Presets.saveUser(preset)
    preset.name = Presets.cleanName(preset.name)
    if preset.name == "" then
        return false, QoL.L("profiles_bad_name")
    elseif Presets.isBuiltinName(preset.name) then
        return false, QoL.L("t_preset_builtin", preset.name)
    end
    local list = Presets.ensureLoaded()
    local copy = Presets.decode(Presets.encode(preset))
    local index = findIndex(list, preset.name)
    local previous = index and list[index]
    if index then
        list[index] = copy
    else
        table.insert(list, copy)
    end
    local ok, err = Presets.persist()
    if not ok then
        -- Undo, the store is full.
        if previous then
            list[index] = previous
        else
            table.remove(list)
        end
        Presets.persist()
        return false, err
    end
    return true, index and QoL.L("t_preset_overwritten") or QoL.L("t_preset_saved")
end

function Presets.deleteUser(name)
    local list = Presets.ensureLoaded()
    local index = findIndex(list, name)
    if not index then
        return false
    end
    table.remove(list, index)
    Presets.persist()
    return true
end

-- Merges imported presets (same name replaces). Returns count, skipped.
function Presets.merge(imported)
    local list = Presets.ensureLoaded()
    local count, skipped = 0, 0
    for _, preset in ipairs(imported) do
        if Presets.isBuiltinName(preset.name) then
            skipped = skipped + 1
        else
            local index = findIndex(list, preset.name)
            if index then
                list[index] = preset
            else
                table.insert(list, preset)
            end
            count = count + 1
        end
    end
    if count > 0 then
        Presets.persist()
    end
    return count, skipped
end

-- File export / import --------------------------------------------------------------------------

function Presets.logPath()
    local ok, folder = pcall(Engine.DvarString, nil, "fs_game")
    folder = (ok and folder and folder ~= "") and folder or "mods\\<mod>"
    return "<BO3>\\" .. string.gsub(folder, "/", "\\") .. "\\console_mp.log"
end

-- Writes all own presets as cfg lines into the console log. Every line starts
-- with ";" so it stays a valid command even with a log prefix like "Error: ".
function Presets.exportToLog()
    local list = Presets.ensureLoaded()
    pcall(Engine.Exec, nil, "logfile 2")
    local function out(line)
        pcall(Engine.PrintError, Enum.consoleLabel.LABEL_DEFAULT, line .. "\n")
    end
    out(";// ===== BO3 Splitscreen QoL tournament presets - copy from here into " .. FILE_NAME .. " =====")
    out(";set " .. COUNT_DVAR .. " " .. #list)
    for index, preset in ipairs(list) do
        out(";set " .. CODE_DVAR .. index .. " \"" .. Presets.encode(preset) .. "\"")
    end
    out(";// ===== end of tournament presets =====")
    return #list
end

-- Executes qol_turniere.cfg and reads the presets it sets. Asynchronous:
-- onDone(count, skipped, problem) runs after the command buffer ran.
function Presets.importFromFile(timerParent, controller, onDone)
    QoL.setSessionValue(COUNT_DVAR, "")
    pcall(Engine.Exec, controller, "exec " .. FILE_NAME)
    timerParent:addElement(LUI.UITimer.newElementTimer(800, true, function()
        QoL.safe("presets.import", function()
            local count = tonumber(QoL.getSessionValue(COUNT_DVAR))
            if not count then
                onDone(0, 0, QoL.L("f_not_found", FILE_NAME))
                return
            end
            local imported = {}
            for index = 1, math.min(count, Presets.MAX_IMPORT) do
                local preset = Presets.decode(QoL.getSessionValue(CODE_DVAR .. index))
                if preset then
                    table.insert(imported, preset)
                end
            end
            local added, skipped = Presets.merge(imported)
            onDone(added, skipped + (count - #imported), nil)
        end)
    end))
end

-- Development test: qol_exec_test.cfg exists in the game folder, in players\
-- and in the mod folder, each setting its own dvar. Whichever is set tells
-- where "exec" reads files from.
local FILE_TEST_DVARS = {
    { dvar = "qol_exec_root", place = "game" },
    { dvar = "qol_exec_players", place = "players" },
    { dvar = "qol_exec_mod", place = "mod" }
}

function Presets.detectFileLocation(timerParent)
    for _, test in ipairs(FILE_TEST_DVARS) do
        QoL.setSessionValue(test.dvar, "")
    end
    Presets.fileTest = "running"
    pcall(Engine.Exec, QoL.controllerForLocalClient(0), "exec qol_exec_test.cfg")
    timerParent:addElement(LUI.UITimer.newElementTimer(1000, true, function()
        local found = {}
        for _, test in ipairs(FILE_TEST_DVARS) do
            if QoL.getSessionValue(test.dvar) == "1" then
                table.insert(found, test.place)
            end
        end
        Presets.fileTest = #found > 0 and table.concat(found, "+") or "none"
        Presets.fileTestPlace = found[1]
        QoL.log("file test exec: " .. Presets.fileTest)
    end))
end

function QoL.fileLocation()
    if Presets.fileTestPlace == "players" then
        return QoL.L("f_place_players")
    elseif Presets.fileTestPlace == "mod" then
        return QoL.L("f_place_mod")
    end
    return QoL.L("f_place_game")
end

function Presets.importCode(text)
    local imported = Presets.decodeList(text)
    if #imported == 0 then
        return 0, 0, QoL.L("f_bad_code")
    end
    local added, skipped = Presets.merge(imported)
    return added, skipped, nil
end
