-- Persistent storage without DLLs or file I/O.
--
-- BO3 only writes its own profile files, and during multiplayer only the MP
-- files (stats_mp_offline, loadouts_mp_offline) are written to disk. Tested
-- 16.09.: Zombies/Campaign loadouts were changed in memory but never saved.
--
-- The MP loadout DDL contains three loadout sets. Offline play only uses
-- cacLoadouts; the class *names* of customMatchCacLoadouts and
-- leagueCacLoadouts (online private/league matches) are unused here and live in
-- players\mods\<mod>\loadouts_mp_offline_0.cgp, so the real classes stay intact.
--
-- Layout: all slots concatenated = "Q2|<length>|<payload>".
require("ui.qol.util")

local QoL = CoD.QoL
local Storage = {}
QoL.storage = Storage

local MAGIC = "Q2|"
local PROBE = string.rep("0123456789", 8)
local SOURCES = {
    { name = "mp-custom", fileType = "STORAGE_MP_LOADOUTS_OFFLINE", root = "customMatchCacLoadouts" },
    { name = "mp-league", fileType = "STORAGE_MP_LOADOUTS_OFFLINE", root = "leagueCacLoadouts" }
}

Storage.status = "nicht geladen"
Storage.capacity = 0

local function hostController()
    return QoL.controllerForLocalClient(0) or Engine.GetPrimaryController()
end

local function nameArray(controller, source)
    local ok, names = pcall(function()
        local buffer = Engine.StorageGetBuffer(controller, Enum.StorageFileType[source.fileType])
        local set = buffer and buffer[source.root]
        return set and set.customClassName
    end)
    return ok and names or nil
end

-- Finds usable string slots and their maximum length (probed once per slot:
-- the engine truncates strings to the DDL size).
local function discoverSlots(controller)
    local slots = {}
    for _, source in ipairs(SOURCES) do
        local ready = true
        if Engine.StorageIsFileReady then
            ready = Engine.StorageIsFileReady(controller, Enum.StorageFileType[source.fileType]) ~= false
        end
        local names = ready and nameArray(controller, source)
        if names then
            -- Use the real DDL array length; never index past it (the engine
            -- might treat that as a fatal error instead of a Lua error).
            local okLength, length = pcall(function() return #names end)
            local lastIndex = 4
            if okLength and type(length) == "number" and length > 0 then
                lastIndex = math.min(length, 32) - 1
            end
            for index = 0, lastIndex do
                local ok, slot = pcall(function() return names[index] end)
                if not ok or slot == nil then
                    break
                end
                table.insert(slots, { source = source, index = index, slot = slot })
            end
        end
    end
    return slots
end

local function readRaw(slots)
    local parts = {}
    for _, entry in ipairs(slots) do
        local ok, value = pcall(function() return entry.slot:get() end)
        table.insert(parts, ok and value or "")
    end
    return parts
end

function Storage.init()
    local controller = hostController()
    local slots = discoverSlots(controller)
    if #slots == 0 then
        Storage.status = "kein Speicher gefunden"
        return false
    end

    -- Measure slot length once. Only slot 1 is probed; all slots of a class
    -- name array share the same DDL string size.
    local original = readRaw({ slots[1] })[1]
    local maxLength = 0
    local ok = pcall(function()
        slots[1].slot:set(PROBE)
        maxLength = string.len(slots[1].slot:get() or "")
        slots[1].slot:set(original)
    end)
    if not ok or maxLength < 8 then
        Storage.status = "Speicher nicht beschreibbar"
        return false
    end

    Storage.controller = controller
    Storage.slots = slots
    Storage.slotLength = maxLength
    Storage.capacity = #slots * maxLength - string.len(MAGIC) - 6
    local sourceNames = {}
    local seen = {}
    for _, entry in ipairs(slots) do
        if not seen[entry.source.name] then
            seen[entry.source.name] = true
            table.insert(sourceNames, entry.source.name)
        end
    end
    Storage.status = table.concat(sourceNames, "+") .. " " .. #slots .. "x" .. maxLength .. "=" .. Storage.capacity
    QoL.log("Speicher " .. Storage.status)
    return true
end

-- Returns the stored payload string ("" if nothing stored yet).
function Storage.load()
    if not Storage.slots and not Storage.init() then
        return nil
    end
    local raw = table.concat(readRaw(Storage.slots))
    if string.sub(raw, 1, string.len(MAGIC)) ~= MAGIC then
        return ""
    end
    local rest = string.sub(raw, string.len(MAGIC) + 1)
    local separator = string.find(rest, "|", 1, true)
    if not separator then
        return ""
    end
    local length = tonumber(string.sub(rest, 1, separator - 1)) or 0
    return string.sub(rest, separator + 1, separator + length)
end

function Storage.save(payload)
    if not Storage.slots and not Storage.init() then
        return false, "kein Speicher"
    end
    if string.len(payload) > Storage.capacity then
        return false, "zu groß (" .. string.len(payload) .. "/" .. Storage.capacity .. ")"
    end
    local raw = MAGIC .. string.len(payload) .. "|" .. payload
    local length = Storage.slotLength
    local touched = {}
    for position, entry in ipairs(Storage.slots) do
        local first = (position - 1) * length + 1
        local chunk = string.sub(raw, first, first + length - 1)
        entry.slot:set(chunk)
        touched[entry.source.fileType] = true
    end
    for fileType in pairs(touched) do
        Engine.StorageWrite(Storage.controller, Enum.StorageFileType[fileType])
    end
    return true
end
