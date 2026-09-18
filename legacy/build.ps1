$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$modName = 'bo3_splitscreen_qol'
$toolsRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Call of Duty Black Ops III 455130'
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Call of Duty Black Ops III'

if (-not (Test-Path -LiteralPath (Join-Path $toolsRoot 'bin\linker_modtools.exe'))) {
    throw "BO3 Mod Tools wurden nicht unter '$toolsRoot' gefunden."
}

$toolsMod = Join-Path $toolsRoot "mods\$modName"
$distMod = Join-Path $projectRoot "dist\$modName"

$env:TA_GAME_PATH = "$toolsRoot\"
$env:TA_LOCAL_ASSET_CACHE = Join-Path $toolsRoot 'share\assetconvert'
$env:TA_TOOLS_PATH = "$toolsRoot\"

New-Item -ItemType Directory -Force -Path $toolsMod | Out-Null
Copy-Item -LiteralPath (Join-Path $projectRoot 'zone') -Destination $toolsMod -Recurse -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'scripts') -Destination $toolsMod -Recurse -Force
# Experimental UI sources are intentionally excluded from the recovery build.

# Der alte Linker liest die Zonenbeschreibung aus dem globalen zone_source-
# Verzeichnis; fs_game bestimmt anschließend, aus welchem Mod-Ordner die
# eigentlichen Assets geladen und wohin die FastFiles geschrieben werden.
$globalZoneSource = Join-Path $toolsRoot 'zone_source'
New-Item -ItemType Directory -Force -Path (Join-Path $globalZoneSource 'loc') | Out-Null
Copy-Item -LiteralPath (Join-Path $projectRoot 'zone\mp_mod.zone') -Destination (Join-Path $globalZoneSource 'mp_mod.zone') -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'zone\loc\mp_mod.zone') -Destination (Join-Path $globalZoneSource 'loc\mp_mod.zone') -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'zone\core_mod.zone') -Destination (Join-Path $globalZoneSource 'core_mod.zone') -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'zone\loc\core_mod.zone') -Destination (Join-Path $globalZoneSource 'loc\core_mod.zone') -Force

$oldLocation = Get-Location
try {
    Set-Location -LiteralPath $toolsRoot

    & (Join-Path $toolsRoot 'gdtdb\gdtdb.exe') /update
    if ($LASTEXITCODE -ne 0) {
        throw "Die Asset-Datenbank wurde mit Exitcode $LASTEXITCODE beendet."
    }

    foreach ($language in @('english', 'german')) {
        foreach ($zoneName in @('core_mod', 'mp_mod')) {
            & (Join-Path $toolsRoot 'bin\linker_modtools.exe') -language $language -fs_game $modName -modsource $zoneName
            if ($LASTEXITCODE -ne 0) {
                throw "Der BO3-Linker ($language/$zoneName) wurde mit Exitcode $LASTEXITCODE beendet."
            }
        }
    }
}
finally {
    Set-Location -LiteralPath $oldLocation
}

if (-not (Test-Path -LiteralPath (Join-Path $toolsMod 'zone'))) {
    throw 'Der Linker hat kein zone-Verzeichnis erzeugt.'
}

$distMod = Join-Path $projectRoot "dist\diagnostic-0.2.2\$modName"
$requiredFiles = @('core_mod.ff', 'en_core_mod.ff', 'ge_core_mod.ff', 'mp_mod.ff', 'en_mp_mod.ff', 'ge_mp_mod.ff')
foreach ($file in $requiredFiles) {
    $output = Join-Path $toolsMod "zone\$file"
    if (-not (Test-Path -LiteralPath $output) -or (Get-Item -LiteralPath $output).Length -eq 0) {
        throw "Fehlendes oder leeres Build-Ergebnis: $output"
    }
}
New-Item -ItemType Directory -Force -Path (Join-Path $distMod 'zone') | Out-Null
foreach ($file in $requiredFiles) {
    Copy-Item -LiteralPath (Join-Path $toolsMod "zone\$file") -Destination (Join-Path $distMod "zone\$file") -Force
}
Copy-Item -LiteralPath (Join-Path $projectRoot 'README.md') -Destination $distMod -Force

$gameMods = Join-Path $gameRoot 'mods'
if (Test-Path -LiteralPath $gameRoot) {
    New-Item -ItemType Directory -Force -Path $gameMods | Out-Null
    $installedMod = Join-Path $gameMods $modName
    New-Item -ItemType Directory -Force -Path (Join-Path $installedMod 'zone') | Out-Null
    foreach ($file in $requiredFiles) {
        Copy-Item -LiteralPath (Join-Path $distMod "zone\$file") -Destination (Join-Path $installedMod "zone\$file") -Force
    }
    Copy-Item -LiteralPath (Join-Path $distMod 'README.md') -Destination $installedMod -Force
}

Write-Host "Build fertig: $distMod"
