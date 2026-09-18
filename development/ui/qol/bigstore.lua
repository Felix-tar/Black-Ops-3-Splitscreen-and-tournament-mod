-- Second permanent store (larger than storage.lua) for tournament presets.
--
-- Uses the item fields of the class sets for online private and league
-- matches (customMatchCacLoadouts / leagueCacLoadouts) in the offline MP
-- loadout file. Offline play only uses cacLoadouts (CoD.CACUtility.
-- SetDefaultCACRoot), and the only Lua validation of those sets runs on the
-- online file. storage.lua already keeps profiles in their class names.
--
-- The bit width of every field is probed once per menu load (the DDL types
-- are not known). Data is a bit stream over all fields with a header
-- (magic, length, Fletcher-16 checksum); a changed layout or reset fields
-- therefore read as "invalid" instead of garbage.
require("ui.qol.util")
require("ui.qol.lang")

local QoL = CoD.QoL
local BigStore = {}
QoL.bigStore = BigStore

local FILE_TYPE = "STORAGE_MP_LOADOUTS_OFFLINE"
local SETS = { "customMatchCacLoadouts", "leagueCacLoadouts" }
local CLASS_COUNT = 10
local MAX_WIDTH = 16
local MAGIC = 20807 -- "QG"
local HEADER_BYTES = 6

BigStore.status = "not loaded"
BigStore.capacity = 0

-- Field names of one custom class, as used by Engine.Get/SetClassItem.
local function classFieldNames()
    local names = {}
    for _, weapon in ipairs({ "primary", "secondary" }) do
        table.insert(names, weapon)
        for _, suffix in ipairs({ "camo", "reticle", "reticlecolor", "lens", "emblem", "tag", "gunsmithvariant",
            "paintjobslot", "paintjobindex" }) do
            table.insert(names, weapon .. suffix)
        end
        for index = 1, 6 do
            table.insert(names, weapon .. "attachment" .. index)
            table.insert(names, weapon .. "attachment" .. index .. "cosmeticvariant")
        end
    end
    for _, gadget in ipairs({ "primarygadget", "secondarygadget", "specialgadget" }) do
        table.insert(names, gadget)
        table.insert(names, gadget .. "count")
        for index = 1, 3 do
            table.insert(names, gadget .. "attachment" .. index)
        end
    end
    for index = 1, 6 do
        table.insert(names, "specialty" .. index)
    end
    for index = 1, 3 do
        table.insert(names, "bonuscard" .. index)
    end
    return names
end

-- Pure helpers (self-test) ----------------------------------------------------

-- Packs bytes (0..255) MSB first into fields of the given widths.
function BigStore.pack(widths, bytes)
    local values = {}
    local field, value, used = 1, 0, 0
    for _, byte in ipairs(bytes) do
        for bit = 7, 0, -1 do
            if not widths[field] then
                return nil
            end
            local digit = math.floor(byte / 2 ^ bit) % 2
            value = value * 2 + digit
            used = used + 1
            if used == widths[field] then
                values[field] = value
                field, value, used = field + 1, 0, 0
            end
        end
    end
    if used > 0 then
        values[field] = value * 2 ^ (widths[field] - used)
    end
    return values
end

function BigStore.unpack(widths, values, count)
    local bytes = {}
    local byte, bits = 0, 0
    for field, width in ipairs(widths) do
        local value = values[field] or 0
        for bit = width - 1, 0, -1 do
            byte = byte * 2 + math.floor(value / 2 ^ bit) % 2
            bits = bits + 1
            if bits == 8 then
                table.insert(bytes, byte)
                if #bytes >= count then
                    return bytes
                end
                byte, bits = 0, 0
            end
        end
    end
    return bytes
end

function BigStore.checksum(bytes, first, last)
    local sum1, sum2 = 0, 0
    for index = first, last do
        sum1 = (sum1 + bytes[index]) % 255
        sum2 = (sum2 + sum1) % 255
    end
    return sum2 * 256 + sum1
end

-- Engine access ------------------------------------------------------------------

local function hostController()
    return QoL.controllerForLocalClient(0) or Engine.GetPrimaryController()
end

local function node(buffer, set, classNum, name)
    local ok, result = pcall(function()
        local value = buffer[set].customclass[classNum][name]
        if value and value.get and value.set then
            return value
        end
        return nil
    end)
    return ok and result or nil
end

local function probeWidth(field)
    local okGet, original = pcall(function() return field:get() end)
    if not okGet or type(original) ~= "number" then
        return 0
    end
    local width = 0
    for bits = MAX_WIDTH, 1, -1 do
        local wanted = 2 ^ bits - 1
        local okSet = pcall(function() field:set(wanted) end)
        local okRead, read = pcall(function() return field:get() end)
        if okSet and okRead and read == wanted then
            -- Check an alternating pattern too (rules out clamping quirks).
            local pattern = math.floor(wanted / 3)
            pcall(function() field:set(pattern) end)
            local okPattern, readPattern = pcall(function() return field:get() end)
            if okPattern and readPattern == pattern then
                width = bits
            end
            break
        end
    end
    pcall(function() field:set(original) end)
    return width
end

function BigStore.init()
    local controller = hostController()
    local ready = true
    if Engine.StorageIsFileReady then
        ready = Engine.StorageIsFileReady(controller, Enum.StorageFileType[FILE_TYPE]) ~= false
    end
    local buffer = ready and Engine.StorageGetBuffer(controller, Enum.StorageFileType[FILE_TYPE])
    if not buffer then
        BigStore.status = "file not ready"
        return false
    end
    -- All classes share one DDL struct: probe class 0 of the first set.
    local layout = {}
    for _, name in ipairs(classFieldNames()) do
        local field = node(buffer, SETS[1], 0, name)
        local width = field and probeWidth(field) or 0
        if width > 0 then
            table.insert(layout, { name = name, width = width })
        end
    end
    local fields, widths = {}, {}
    for _, set in ipairs(SETS) do
        for classNum = 0, CLASS_COUNT - 1 do
            for _, entry in ipairs(layout) do
                local field = node(buffer, set, classNum, entry.name)
                if field then
                    table.insert(fields, field)
                    table.insert(widths, entry.width)
                end
            end
        end
    end
    local bits = 0
    for _, width in ipairs(widths) do
        bits = bits + width
    end
    BigStore.capacity = math.floor(bits / 8) - HEADER_BYTES
    if BigStore.capacity < 64 then
        BigStore.status = "too small (" .. BigStore.capacity .. ")"
        BigStore.capacity = 0
        return false
    end
    BigStore.controller = controller
    BigStore.fields = fields
    BigStore.widths = widths
    BigStore.status = #layout .. " fields/class, " .. BigStore.capacity .. " bytes"
    return true
end

local function readValues()
    local values = {}
    for index, field in ipairs(BigStore.fields) do
        local ok, value = pcall(function() return field:get() end)
        values[index] = (ok and type(value) == "number") and value or 0
    end
    return values
end

-- Returns the stored text, "" when empty/invalid, nil when unavailable.
function BigStore.load()
    if not BigStore.fields and not BigStore.init() then
        return nil
    end
    local values = readValues()
    local header = BigStore.unpack(BigStore.widths, values, HEADER_BYTES)
    local magic = (header[1] or 0) * 256 + (header[2] or 0)
    if magic ~= MAGIC then
        BigStore.state = "empty"
        return ""
    end
    local length = (header[3] or 0) * 256 + (header[4] or 0)
    local stored = (header[5] or 0) * 256 + (header[6] or 0)
    if length > BigStore.capacity then
        BigStore.state = "invalid (length)"
        return ""
    end
    local bytes = BigStore.unpack(BigStore.widths, values, HEADER_BYTES + length)
    if #bytes < HEADER_BYTES + length or BigStore.checksum(bytes, HEADER_BYTES + 1, HEADER_BYTES + length) ~= stored then
        BigStore.state = "invalid (checksum)"
        return ""
    end
    local chars = {}
    for index = HEADER_BYTES + 1, HEADER_BYTES + length do
        table.insert(chars, string.char(bytes[index]))
    end
    BigStore.state = "ok"
    return table.concat(chars)
end

function BigStore.save(text)
    if not BigStore.fields and not BigStore.init() then
        return false, "no extra storage"
    end
    local length = string.len(text)
    if length > BigStore.capacity then
        return false, QoL.L("st_full_size", length, BigStore.capacity)
    end
    local bytes = { 0, 0, math.floor(length / 256), length % 256, 0, 0 }
    for index = 1, length do
        table.insert(bytes, string.byte(text, index))
    end
    bytes[1], bytes[2] = math.floor(MAGIC / 256), MAGIC % 256
    local sum = BigStore.checksum(bytes, HEADER_BYTES + 1, HEADER_BYTES + length)
    bytes[5], bytes[6] = math.floor(sum / 256), sum % 256
    local values = BigStore.pack(BigStore.widths, bytes)
    if not values then
        return false, "packing failed"
    end
    for index, value in pairs(values) do
        pcall(function() BigStore.fields[index]:set(value) end)
    end
    Engine.StorageWrite(BigStore.controller, Enum.StorageFileType[FILE_TYPE])
    BigStore.state = "ok"
    return true
end
