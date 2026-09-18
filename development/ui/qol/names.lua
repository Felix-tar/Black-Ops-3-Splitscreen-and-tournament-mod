-- Name table gamertag -> display name, shared by lobby and match.
-- The lobby publishes it in the session dvar qol_names ("tag=name|tag=name");
-- the match HUD of the same PC reads it for scoreboard and killfeed.
require("ui.qol.util")

local QoL = CoD.QoL
local Names = {}
QoL.names = Names

local DVAR = "qol_names"

local function clean(text)
    return (string.gsub(tostring(text or ""), "[|=%c]", ""))
end
Names.clean = clean

function Names.encode(map)
    local parts = {}
    for tag, name in pairs(map) do
        if tag ~= "" and name ~= "" and name ~= tag then
            table.insert(parts, clean(tag) .. "=" .. clean(name))
        end
    end
    table.sort(parts)
    return table.concat(parts, "|")
end

function Names.decode(text)
    local map = {}
    for entry in string.gmatch(text or "", "[^|]+") do
        local tag, name = string.match(entry, "^(.-)=(.*)$")
        if tag and name and tag ~= "" and name ~= "" then
            map[tag] = name
        end
    end
    return map
end

function Names.publish(map)
    local text = Names.encode(map)
    Names.cache = nil
    QoL.setSessionValue(DVAR, text)
end

function Names.current()
    local text = QoL.getSessionValue(DVAR)
    if not Names.cache or Names.cacheText ~= text then
        Names.cache = Names.decode(text)
        Names.cacheText = text
    end
    return Names.cache
end

function Names.hasAny()
    return next(Names.current()) ~= nil
end

-- Display name for a gamertag; clan tags like "[ikea]" are ignored.
function Names.lookup(gamertag)
    if type(gamertag) ~= "string" then
        return nil
    end
    local map = Names.current()
    local plain = string.gsub(gamertag, "^%[.-%]", "")
    return map[clean(gamertag)] or map[clean(plain)]
end
