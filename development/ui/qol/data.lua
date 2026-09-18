-- Data model for local profiles and statistics, serialised into the small
-- permanent text store of storage.lua (tournaments live in a session dvar,
-- see tournament.lua). Records are separated by ';', fields by ','. Names are
-- sanitised so they never contain separators.
--
--   B<boots>                                   start counter (persistence self-test)
--   P<id>,<kills>,<deaths>,<headshots>,<matches>,<wins>,<name>
--   V<attackerId>,<victimId>,<kills>           head-to-head kills
--   A<p1ProfileId>,<p2ProfileId>               last assignment (0 = none)
--   I<mode>                                    input device of player 1 (input.lua)
require("ui.qol.util")
require("ui.qol.storage")
require("ui.qol.names")

local QoL = CoD.QoL
local Data = {}
QoL.data = Data

Data.MAX_NAME = 14
Data.state = nil
Data.lastSaveError = nil
Data.trimmed = 0

local function emptyState()
    return {
        boots = 0,
        profiles = {},
        vs = {},
        assigned = { [0] = 0, [1] = 0 }
    }
end
Data.emptyState = emptyState

function Data.sanitizeName(name)
    name = tostring(name or "")
    name = string.gsub(name, "[;,|=~\"%c]", "")
    name = string.gsub(name, "^%s+", "")
    name = string.gsub(name, "%s+$", "")
    if string.len(name) > Data.MAX_NAME then
        -- Byte limit; never leave half of an umlaut at the end.
        name = string.sub(name, 1, Data.MAX_NAME)
        name = string.gsub(name, "[\192-\255][\128-\191]*$", "")
    end
    return name
end

local function split(text, separator)
    local parts = {}
    local start = 1
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
Data.split = split

local function number(value)
    return tonumber(value) or 0
end

function Data.parse(payload)
    local state = emptyState()
    for _, record in ipairs(split(payload or "", ";")) do
        local kind = string.sub(record, 1, 1)
        local fields = split(string.sub(record, 2), ",")
        if kind == "B" then
            state.boots = number(fields[1])
        elseif kind == "P" and #fields >= 7 then
            -- The name is the last field; older names may contain commas.
            local id = number(fields[1])
            if id > 0 and not Data.profileIn(state, id) then
                table.insert(state.profiles, {
                    id = id, kills = number(fields[2]), deaths = number(fields[3]),
                    headshots = number(fields[4]), matches = number(fields[5]), wins = number(fields[6]),
                    name = table.concat(fields, ",", 7)
                })
            end
        elseif kind == "V" and #fields >= 3 then
            local kills = number(fields[3])
            if kills > 0 then
                state.vs[number(fields[1]) .. ":" .. number(fields[2])] = kills
            end
        elseif kind == "A" and #fields >= 2 then
            state.assigned[0] = number(fields[1])
            state.assigned[1] = number(fields[2])
        elseif kind == "I" then
            state.inputMode = tonumber(fields[1])
        end
    end
    -- Assignments must point to existing profiles, and never both to one.
    for localClient = 0, 1 do
        if state.assigned[localClient] ~= 0 and not Data.profileIn(state, state.assigned[localClient]) then
            state.assigned[localClient] = 0
        end
    end
    if state.assigned[0] ~= 0 and state.assigned[0] == state.assigned[1] then
        state.assigned[1] = 0
    end
    return state
end

function Data.serialize(state)
    local records = { "B" .. state.boots }
    for _, p in ipairs(state.profiles) do
        table.insert(records, "P" .. table.concat({ p.id, p.kills, p.deaths, p.headshots, p.matches, p.wins, p.name }, ","))
    end
    -- Sorted so the payload is stable (pairs order is not).
    local duels = {}
    for key, kills in pairs(state.vs) do
        if kills > 0 then
            local pair = split(key, ":")
            table.insert(duels, "V" .. pair[1] .. "," .. pair[2] .. "," .. kills)
        end
    end
    table.sort(duels)
    for _, record in ipairs(duels) do
        table.insert(records, record)
    end
    table.insert(records, "A" .. (state.assigned[0] or 0) .. "," .. (state.assigned[1] or 0))
    if state.inputMode and state.inputMode ~= -2 then
        table.insert(records, "I" .. state.inputMode)
    end
    -- Tournaments are kept in a session dvar (tournament.lua), not here.
    return table.concat(records, ";")
end

-- The store holds only a few hundred characters. When the payload is too
-- large, the head-to-head records with the fewest kills are dropped first so
-- profiles and their totals are kept. Returns payload or nil, reason.
function Data.fit(state, capacity)
    local payload = Data.serialize(state)
    if capacity <= 0 or string.len(payload) <= capacity then
        return payload
    end
    local duels = {}
    for key, kills in pairs(state.vs) do
        table.insert(duels, { key = key, kills = kills })
    end
    table.sort(duels, function(a, b)
        if a.kills ~= b.kills then return a.kills < b.kills end
        return a.key < b.key
    end)
    local dropped = 0
    for _, duel in ipairs(duels) do
        state.vs[duel.key] = nil
        dropped = dropped + 1
        payload = Data.serialize(state)
        if string.len(payload) <= capacity then
            Data.trimmed = Data.trimmed + dropped
            QoL.log("Speicher voll: " .. dropped .. " Duell-Einträge entfernt")
            return payload
        end
    end
    Data.trimmed = Data.trimmed + dropped
    return nil, "Speicher voll - bitte ein Profil löschen"
end

function Data.load()
    local payload = QoL.storage.load()
    if payload == nil then
        Data.state = emptyState()
        Data.available = false
        return Data.state
    end
    Data.state = Data.parse(payload)
    Data.available = true
    return Data.state
end

function Data.get()
    return Data.state or Data.load()
end

function Data.save()
    local state = Data.get()
    Data.dirtySince = nil
    if not Data.available then
        Data.lastSaveError = "kein Speicher"
        return false
    end
    local payload, reason = Data.fit(state, QoL.storage.capacity or 0)
    local ok, err = false, reason
    if payload then
        ok, err = QoL.storage.save(payload)
    end
    -- Shown in the lobby status line until a later save succeeds.
    Data.lastSaveError = (not ok) and tostring(err) or nil
    if not ok then
        QoL.log("Speichern fehlgeschlagen: " .. tostring(err))
    end
    return ok
end

-- Used and available characters of the permanent store.
function Data.usage()
    local used = string.len(Data.serialize(Data.get()))
    return used, QoL.storage.capacity or 0
end

-- Profiles -----------------------------------------------------------------

function Data.profileIn(state, id)
    for _, p in ipairs(state.profiles) do
        if p.id == id then
            return p
        end
    end
    return nil
end

function Data.profile(id)
    return Data.profileIn(Data.get(), id)
end

function Data.findByName(name)
    local lower = string.lower(Data.sanitizeName(name))
    for _, p in ipairs(Data.get().profiles) do
        if string.lower(p.name) == lower then
            return p
        end
    end
    return nil
end

function Data.createProfile(name)
    name = Data.sanitizeName(name)
    if name == "" then
        return nil
    end
    local existing = Data.findByName(name)
    if existing then
        return existing
    end
    local state = Data.get()
    local nextId = 1
    for _, p in ipairs(state.profiles) do
        nextId = math.max(nextId, p.id + 1)
    end
    local profile = { id = nextId, name = name, kills = 0, deaths = 0, headshots = 0, matches = 0, wins = 0 }
    table.insert(state.profiles, profile)
    if not Data.save() and Data.available then
        -- Store full: do not keep a profile that would vanish on restart.
        table.remove(state.profiles)
        local reason = Data.lastSaveError
        Data.save()
        return nil, reason
    end
    return profile
end

-- Returns false, reason when the name is empty or taken by another profile.
function Data.renameProfile(id, name)
    local profile = Data.profile(id)
    name = Data.sanitizeName(name)
    if not profile then
        return false, "Profil nicht gefunden"
    elseif name == "" then
        return false, "kein gültiger Name"
    end
    local existing = Data.findByName(name)
    if existing and existing.id ~= id then
        return false, "Name \"" .. name .. "\" gibt es schon"
    end
    profile.name = name
    Data.save()
    Data.changed()
    return true
end

local function removeDuels(state, id)
    for key in pairs(state.vs) do
        local pair = split(key, ":")
        if number(pair[1]) == id or number(pair[2]) == id then
            state.vs[key] = nil
        end
    end
end

function Data.resetStats(id)
    local profile = Data.profile(id)
    if not profile then
        return false
    end
    profile.kills, profile.deaths, profile.headshots, profile.matches, profile.wins = 0, 0, 0, 0, 0
    removeDuels(Data.get(), id)
    Data.save()
    return true
end

function Data.deleteProfile(id)
    local state = Data.get()
    for index, p in ipairs(state.profiles) do
        if p.id == id then
            table.remove(state.profiles, index)
            removeDuels(state, id)
            for localClient = 0, 1 do
                if state.assigned[localClient] == id then
                    state.assigned[localClient] = 0
                end
            end
            Data.save()
            Data.changed()
            return true
        end
    end
    return false
end

-- Local client that currently uses a profile, or nil.
function Data.profileOwner(profileId)
    local assigned = Data.get().assigned
    for localClient = 0, 1 do
        if profileId ~= 0 and assigned[localClient] == profileId then
            return localClient
        end
    end
    return nil
end

-- Names changed: update the name table and the party list.
function Data.changed()
    QoL.safe("data.publishNames", Data.publishNames)
    if Data.onAssignmentChanged then
        QoL.safe("data.onAssignmentChanged", Data.onAssignmentChanged)
    end
end

-- Returns false, reason when the profile is already used by the other player.
function Data.assign(localClient, profileId)
    local state = Data.get()
    profileId = profileId or 0
    if profileId ~= 0 and not Data.profile(profileId) then
        return false, "Profil nicht gefunden"
    end
    local owner = Data.profileOwner(profileId)
    if owner ~= nil and owner ~= localClient then
        return false, "schon von Spieler " .. (owner + 1) .. " gewählt"
    end
    state.assigned[localClient] = profileId
    -- Profile choices come in bursts (both players at once): write later.
    Data.saveSoon()
    Data.changed()
    return true
end

-- Deferred saving: Data.tick (lobby timer) writes 1.5 s after the last change,
-- Data.flush writes immediately (before a match starts, menus close).
Data.dirtySince = nil
Data.SAVE_DELAY = 1500

function Data.saveSoon()
    Data.dirtySince = Engine.milliseconds()
end

function Data.flush()
    if not Data.dirtySince then
        return true
    end
    Data.dirtySince = nil
    return Data.save()
end

function Data.tick()
    if Data.dirtySince and Engine.milliseconds() - Data.dirtySince >= Data.SAVE_DELAY then
        Data.flush()
    end
end

function Data.assignedProfile(localClient)
    local id = Data.get().assigned[localClient] or 0
    return id ~= 0 and Data.profile(id) or nil
end

-- Name shown for a local player: profile name, otherwise the gamertag.
function Data.displayName(localClient)
    local profile = Data.assignedProfile(localClient)
    if profile then
        return profile.name
    end
    local controller = QoL.controllerForLocalClient(localClient)
    if controller ~= nil then
        local ok, tag = pcall(Engine.GetGamertagForController, controller)
        if ok and tag then
            return tag
        end
    end
    return "Spieler " .. tostring(localClient + 1)
end

-- Publishes gamertag -> name for the match HUD and the party list: local
-- profiles of this PC plus names given in the tournament (also for players on
-- other PCs).
function Data.publishNames()
    local map = {}
    local tournament = QoL.tournament and QoL.tournament.current()
    if tournament then
        for _, player in ipairs(tournament.players) do
            if player.alias and player.alias ~= "" then
                map[player.gamertag] = player.alias
            end
        end
    end
    for localClient = 0, 1 do
        local profile = Data.assignedProfile(localClient)
        local controller = QoL.controllerForLocalClient(localClient)
        if profile and controller ~= nil then
            local ok, tag = pcall(Engine.GetGamertagForController, controller)
            if ok and tag then
                map[tag] = profile.name
            end
        end
    end
    QoL.names.publish(map)
end

function Data.vsKills(attackerId, victimId)
    return Data.get().vs[attackerId .. ":" .. victimId] or 0
end

function Data.addVsKills(attackerId, victimId, kills)
    local state = Data.get()
    local key = attackerId .. ":" .. victimId
    state.vs[key] = (state.vs[key] or 0) + kills
end
