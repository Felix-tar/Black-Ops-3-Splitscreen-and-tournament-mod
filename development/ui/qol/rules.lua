-- Game rules for tournament rounds: every option of "Spiel einrichten"
-- (from the stock table CoD.GameOptions), bots and item restrictions
-- ("Nur Scharfschützengewehre" etc.).
--
-- Rules are a compact text so they fit into tournament state, presets and
-- export files: "key:value" separated by ",".
--   <gametype setting>:<value>   e.g. timeLimit:10, onlyHeadshots:1
--   bot_maxAllies:3, bot_maxAxis:3, bot_maxFree:5, bot_difficulty:2
--   res:snp+pst                  forbidden item categories
-- A setting that is not listed keeps the game default ("Standard").
require("ui.qol.util")

local QoL = CoD.QoL
local Rules = {}
QoL.rules = Rules

-- Item categories for restrictions --------------------------------------------

Rules.CATEGORIES = {
    { id = "smg", label = "Maschinenpistolen" },
    { id = "ar", label = "Sturmgewehre" },
    { id = "cqb", label = "Schrotflinten" },
    { id = "lmg", label = "LMGs" },
    { id = "snp", label = "Scharfschützengewehre" },
    { id = "pst", label = "Pistolen" },
    { id = "lnc", label = "Werfer" },
    { id = "mel", label = "Nahkampfwaffen" },
    { id = "spw", label = "Spezialwaffen" },
    { id = "gad", label = "Ausrüstung (tödlich/taktisch)" },
    { id = "prk", label = "Extras" },
    { id = "wc", label = "Wildcards" },
    { id = "hro", label = "Spezialisten-Fähigkeiten" },
    { id = "ks", label = "Punkteserien" }
}

local PRIMARIES = { "smg", "ar", "cqb", "lmg", "snp" }
local SECONDARIES = { "pst", "lnc", "spw" }

local function without(list, keep)
    local result = {}
    for _, id in ipairs(list) do
        if id ~= keep then
            table.insert(result, id)
        end
    end
    return result
end

local function join(...)
    local result = {}
    for _, list in ipairs({ ... }) do
        for _, id in ipairs(list) do
            table.insert(result, id)
        end
    end
    return result
end

-- Quick choices in the restriction group ("fixed modes").
Rules.TEMPLATES = {
    { label = "Alles erlaubt", forbid = {} },
    { label = "Nur Scharfschützengewehre", forbid = join(without(PRIMARIES, "snp"), SECONDARIES) },
    { label = "Nur Schrotflinten", forbid = join(without(PRIMARIES, "cqb"), SECONDARIES) },
    { label = "Nur Maschinenpistolen", forbid = join(without(PRIMARIES, "smg"), SECONDARIES) },
    { label = "Nur Pistolen", forbid = join(PRIMARIES, { "lnc", "spw" }) },
    { label = "Nur Nahkampf", forbid = join(PRIMARIES, SECONDARIES, { "gad" }) },
    { label = "Ohne Punkteserien und Spezialisten", forbid = { "ks", "hro" } }
}

-- Classifies an item from Engine.GetUnlockableInfoByIndex.
function Rules.categoryOf(slot, group)
    local groups = Enum.itemGroup_t or {}
    if slot == "primary" then
        if group == groups.ITEMGROUP_SMG then return "smg" end
        if group == groups.ITEMGROUP_ASSAULT then return "ar" end
        if group == groups.ITEMGROUP_CQB then return "cqb" end
        if group == groups.ITEMGROUP_LMG then return "lmg" end
        if group == groups.ITEMGROUP_SNIPER then return "snp" end
        return "spw"
    elseif slot == "secondary" then
        if group == groups.ITEMGROUP_PISTOL then return "pst" end
        if group == groups.ITEMGROUP_LAUNCHER then return "lnc" end
        if group == groups.ITEMGROUP_KNIFE then return "mel" end
        return "spw"
    elseif slot == "primarygadget" or slot == "secondarygadget" then
        return "gad"
    elseif type(slot) == "string" then
        if string.find(slot, "^specialty") then return "prk" end
        if string.find(slot, "^bonuscard") then return "wc" end
        if string.find(slot, "^killstreak") then return "ks" end
        if string.find(slot, "^hero") or slot == "specialgadget" then return "hro" end
    end
    return nil
end

-- Text format --------------------------------------------------------------------

function Rules.parse(text)
    local rules = { values = {}, forbid = {} }
    for entry in string.gmatch(text or "", "[^,]+") do
        local key, value = string.match(entry, "^([%w_]+):(.*)$")
        if key == "res" then
            for id in string.gmatch(value, "[%w]+") do
                rules.forbid[id] = true
            end
        elseif key and tonumber(value) then
            rules.values[key] = tonumber(value)
        end
    end
    return rules
end

local function numberText(value)
    if value == math.floor(value) then
        return string.format("%d", value)
    end
    return tostring(value)
end

function Rules.encode(rules)
    local parts = {}
    for key, value in pairs(rules.values) do
        table.insert(parts, key .. ":" .. numberText(value))
    end
    table.sort(parts)
    local forbidden = {}
    for _, category in ipairs(Rules.CATEGORIES) do
        if rules.forbid[category.id] then
            table.insert(forbidden, category.id)
        end
    end
    if #forbidden > 0 then
        table.insert(parts, "res:" .. table.concat(forbidden, "+"))
    end
    return table.concat(parts, ",")
end

function Rules.isEmpty(text)
    return Rules.encode(Rules.parse(text)) == ""
end

-- Catalog --------------------------------------------------------------------------

local function gameOptions()
    if not CoD.GameOptions or not CoD.GameOptions.GameSettings then
        pcall(require, "ui_mp.t6.gameoptions")
    end
    return CoD.GameOptions
end

local function localize(text, value)
    local ok, result = pcall(Engine.Localize, text, value)
    if ok and type(result) == "string" and result ~= "" then
        return result
    end
    return tostring(text)
end

local function settingOptions(definition)
    local options = {}
    local delimiter = "."
    pcall(function() delimiter = Engine.GetDecimalDelimiter() or "." end)
    for index, value in ipairs(definition.values or {}) do
        local shown = tostring(value)
        if tonumber(value) then
            shown = string.gsub(shown, "%.", delimiter, 1)
        end
        local label = shown
        if definition.labels then
            label = definition.labels[index] or definition.labels[#definition.labels]
        end
        table.insert(options, { value = tonumber(value) or value, text = localize(label, shown) })
    end
    return options
end

-- Entry for one gametype setting of CoD.GameOptions.GameSettings.
local function settingEntry(name)
    local options = gameOptions()
    local definition = options and options.GameSettings and options.GameSettings[name]
    if not definition or not definition.values then
        return nil
    end
    local key = definition.setting or name
    local hint = definition.hintText and definition.hintText[1]
    return {
        kind = "setting", key = key, label = localize(definition.name),
        hint = hint and localize(hint) or "", options = settingOptions(definition)
    }
end

local function botEntries()
    local maxBots = 12
    pcall(function() maxBots = CoD.GameSettingsUtility.GetMaxBotsCount() end)
    local counts = {}
    for count = 0, maxBots do
        table.insert(counts, { value = count, text = count == 0 and localize("MENU_DISABLED") or tostring(count) })
    end
    return {
        { kind = "dvar", key = "bot_maxAllies", label = "Bots " .. localize("MPUI_ALLIES_CAPS"), options = counts,
            hint = "Anzahl Bots im Team der Verbündeten (Team-Modi)." },
        { kind = "dvar", key = "bot_maxAxis", label = "Bots " .. localize("MPUI_AXIS_CAPS"), options = counts,
            hint = "Anzahl Bots im Team der Achsenmächte (Team-Modi)." },
        { kind = "dvar", key = "bot_maxFree", label = "Bots (Jeder gegen jeden)", options = counts,
            hint = "Anzahl Bots in Modi ohne Teams." },
        { kind = "dvar", key = "bot_difficulty", label = localize("MENU_BASICTRAINING_DIFFICULTY_CAPS"), options = {
            { value = 0, text = localize("MENU_BASICTRAINING_EASY_CAPS") },
            { value = 1, text = localize("MENU_BASICTRAINING_NORMAL_CAPS") },
            { value = 2, text = localize("MENU_BASICTRAINING_HARD_CAPS") },
            { value = 3, text = localize("MENU_BASICTRAINING_FU_CAPS") }
        }, hint = "Schwierigkeit der Bots." }
    }
end

local function addGroup(groups, title, names, seen)
    local entries = {}
    for _, name in ipairs(names or {}) do
        local entry = settingEntry(name)
        if entry and not seen[entry.key] then
            seen[entry.key] = true
            table.insert(entries, entry)
        end
    end
    if #entries > 0 then
        table.insert(groups, { title = title, entries = entries })
    end
end

-- Groups for the editor. gametypes: list of gametype ids of the affected rounds.
-- Cached: localizing the whole table on every repaint would be slow.
Rules.groupCache = {}

function Rules.groups(gametypes)
    local cacheKey = table.concat(gametypes, "+")
    if not Rules.groupCache[cacheKey] then
        Rules.groupCache[cacheKey] = Rules.buildGroups(gametypes)
    end
    return Rules.groupCache[cacheKey]
end

function Rules.buildGroups(gametypes)
    local options = gameOptions() or {}
    local groups, seen = {}, {}
    for _, gametype in ipairs(gametypes) do
        local names = {}
        for _, name in ipairs((options.TopLevelGametypeSettings or {})[gametype] or {}) do table.insert(names, name) end
        for _, name in ipairs((options.SubLevelGametypeSettings or {})[gametype] or {}) do table.insert(names, name) end
        addGroup(groups, "MODUS: " .. string.upper(QoL.rules.gametypeName(gametype)), names, seen)
    end
    addGroup(groups, "ALLGEMEIN", join(options.GlobalTopLevelGametypeSettings or {}, options.GeneralSettings or {}), seen)
    addGroup(groups, "GESUNDHEIT UND SCHADEN", options.HealthAndDamageSettings, seen)
    addGroup(groups, "SPAWN", options.SpawnSettings, seen)
    addGroup(groups, "KLASSEN", options.CustomClassSettings, seen)
    local global = {}
    for _, name in ipairs(options.GlobalSettings or {}) do
        -- The tournament sets teamAssignment itself.
        if name ~= "teamAssignment" then
            table.insert(global, name)
        end
    end
    addGroup(groups, "SONSTIGES", global, seen)
    table.insert(groups, { title = "BOTS", entries = botEntries() })
    local restrictions = {}
    for _, category in ipairs(Rules.CATEGORIES) do
        table.insert(restrictions, { kind = "restriction", key = category.id, label = category.label,
            hint = "Verbotene Gegenstände können im Klasseneditor nicht ausgerüstet werden.",
            options = { { value = 1, text = "Verboten" } } })
    end
    table.insert(groups, { title = "BESCHRÄNKUNGEN", entries = restrictions, templates = Rules.TEMPLATES })
    return groups
end

function Rules.gametypeName(gametype)
    local ok, list = pcall(Engine.GetGametypesBase)
    if ok and list then
        for _, entry in pairs(list) do
            if entry.gametype == gametype then
                return localize(entry.name)
            end
        end
    end
    return tostring(gametype)
end

-- Editing ----------------------------------------------------------------------------

local STANDARD = "Standard"

function Rules.valueText(entry, rules)
    if entry.kind == "restriction" then
        return rules.forbid[entry.key] and "Verboten" or "Erlaubt"
    end
    local value = rules.values[entry.key]
    if value == nil then
        return STANDARD
    end
    for _, option in ipairs(entry.options) do
        if option.value == value then
            return option.text
        end
    end
    return numberText(value)
end

-- Cycles Standard -> option 1 -> ... -> option n -> Standard.
function Rules.cycle(entry, rules, delta)
    if entry.kind == "restriction" then
        rules.forbid[entry.key] = not rules.forbid[entry.key] or nil
        return
    end
    local count = #entry.options
    local position = 0
    for index, option in ipairs(entry.options) do
        if option.value == rules.values[entry.key] then
            position = index
        end
    end
    position = (position + delta) % (count + 1)
    rules.values[entry.key] = position > 0 and entry.options[position].value or nil
end

function Rules.applyTemplate(template, rules)
    rules.forbid = {}
    for _, id in ipairs(template.forbid) do
        rules.forbid[id] = true
    end
end

-- Short description for lists, e.g. "Zeitlimit: 10 Minuten, Nur ...".
function Rules.summary(text, gametypes)
    local rules = Rules.parse(text)
    local parts = {}
    for _, group in ipairs(Rules.groups(gametypes or {})) do
        for _, entry in ipairs(group.entries) do
            if entry.kind ~= "restriction" and rules.values[entry.key] ~= nil then
                table.insert(parts, entry.label .. ": " .. Rules.valueText(entry, rules))
            end
        end
    end
    local forbidden = {}
    for _, category in ipairs(Rules.CATEGORIES) do
        if rules.forbid[category.id] then
            table.insert(forbidden, category.label)
        end
    end
    if #forbidden > 0 then
        table.insert(parts, "Verboten: " .. table.concat(forbidden, ", "))
    end
    if #parts == 0 then
        return "Standardregeln"
    end
    return table.concat(parts, "  |  ")
end

-- Applying -----------------------------------------------------------------------------

local function allSettingKeys()
    local options = gameOptions() or {}
    local keys = {}
    for name, definition in pairs(options.GameSettings or {}) do
        keys[definition.setting or name] = true
    end
    keys.teamAssignment = nil
    return keys
end

local function applyRestrictions(forbid)
    local restricted = Enum.ItemRestrictionState and Enum.ItemRestrictionState.ITEM_RESTRICTION_STATE_RESTRICTED
    if not restricted or not Engine.SetItemRestrictionState then
        return 0
    end
    local count = 0
    for index = 0, 255 do
        pcall(function()
            if Engine.ItemIndexValid and not Engine.ItemIndexValid(index) then
                return
            end
            local info = Engine.GetUnlockableInfoByIndex(index)
            if not info or (info.allocation or -1) < 0 then
                return
            end
            local category = Rules.categoryOf(info.loadoutSlot, info.groupIndex)
            if category and forbid[category] then
                Engine.SetItemRestrictionState(index, restricted)
                count = count + 1
            else
                Engine.SetItemRestrictionState(index, Engine.GetItemRestrictionState(index, true))
            end
        end)
    end
    return count
end

-- Resets all game settings of the current gametype to their defaults, then
-- applies the rules. Call after the round's gametype has been selected.
function Rules.apply(text, controller)
    local rules = Rules.parse(text)
    for key in pairs(allSettingKeys()) do
        pcall(function()
            local default = Engine.GetGametypeSetting(key, true)
            if default ~= nil then
                Engine.SetGametypeSetting(key, default)
            end
        end)
    end
    local options = gameOptions()
    if rules.values.hardcoreMode ~= nil and options and options.HardcoreSettingChanged then
        pcall(options.HardcoreSettingChanged, rules.values.hardcoreMode, controller)
    end
    local bots = { bot_maxAllies = 0, bot_maxAxis = 0, bot_maxFree = 0, bot_difficulty = 1 }
    for key, value in pairs(rules.values) do
        if bots[key] ~= nil then
            bots[key] = value
        else
            pcall(Engine.SetGametypeSetting, key, value)
        end
    end
    for key, value in pairs(bots) do
        pcall(Engine.SetDvar, key, value)
    end
    local restricted = applyRestrictions(rules.forbid)
    pcall(function()
        Engine.LobbyHostSessionSetDirty(Enum.LobbyType.LOBBY_TYPE_GAME, Enum.SessionDirty.SESSION_DIRTY_UI)
    end)
    pcall(function()
        Engine.ForceNotifyModelSubscriptions(Engine.CreateModel(Engine.CreateModel(Engine.GetGlobalModel(), "GametypeSettings"), "Update"))
    end)
    QoL.log("Regeln angewendet: " .. (text ~= "" and text or "Standard") .. " (" .. restricted .. " Gegenstände gesperrt)")
    return true
end
