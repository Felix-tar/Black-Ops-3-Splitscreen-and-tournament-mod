-- Entry point, required at the end of core_frontend_patch_require. Each module
-- is loaded in isolation so one failing module leaves the others and the
-- stock frontend working; failures are shown in the lobby debug line.
require("ui.qol.util")

local QoL = CoD.QoL

local MODULES = {
    "ui.qol.lang",
    "ui.qol.input",
    "ui.qol.lobbybuttons",
    "ui.qol.ui",
    "ui.qol.names",
    "ui.qol.storage",
    "ui.qol.data",
    "ui.qol.stats",
    "ui.qol.classcopy",
    "ui.qol.profiles",
    "ui.qol.leaderboard",
    "ui.qol.bigstore",
    "ui.qol.rules",
    "ui.qol.presets",
    "ui.qol.tournament",
    "ui.qol.tournamentmenu",
    "ui.qol.splitmenu",
    "ui.qol.splitlobby"
}

for _, module in ipairs(MODULES) do
    local ok, err = pcall(require, module)
    if not ok then
        QoL.reportError(module, err)
    end
end

-- Checks the pure logic of the modules above (see selftest.lua).
local ok, err = pcall(require, "ui.qol.selftest")
if ok and QoL.selftest then
    QoL.safe("selftest", QoL.selftest.run)
elseif not ok then
    QoL.reportError("ui.qol.selftest", err)
end
