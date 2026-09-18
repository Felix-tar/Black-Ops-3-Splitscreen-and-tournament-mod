# Build der Mod mit den BO3 Mod Tools.
#   Entwicklung: powershell -NoProfile -ExecutionPolicy Bypass -File .\build-dev.ps1 -Install
#   Release:     powershell -NoProfile -ExecutionPolicy Bypass -File .\build-dev.ps1 -Release -Version 1.0.0
# Entwicklung: Modname bo3_qol_dev, Statuszeile sichtbar, console_mp.log aktiv.
# Release:     Modname bo3_splitscreen_qol, Statuszeile nur bei Fehlern, ZIP unter dist\.
param(
    [switch]$Install,
    [switch]$Release,
    [string]$Version = '1.0.0',
    # Profilordner, aus dem beim ersten Install Klassen/Stats übernommen werden (nur Entwicklung).
    [string]$MigrateProfileFrom = 'bo3_qol_ui_dev3'
)
$ErrorActionPreference = 'Stop'

$modName = if ($Release) { 'bo3_splitscreen_qol' } else { 'bo3_qol_dev' }
$flavor = if ($Release) { 'release' } else { 'dev' }
$projectRoot = $PSScriptRoot
$sourceRoot = Join-Path $projectRoot 'development'
$toolsRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Call of Duty Black Ops III 455130'
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Call of Duty Black Ops III'
$staging = Join-Path $toolsRoot "mods\$modName"
$zoneFiles = @('core_mod.ff', 'mp_mod.ff', 'en_core_mod.ff', 'ge_core_mod.ff', 'en_mp_mod.ff', 'ge_mp_mod.ff')

if (-not (Test-Path -LiteralPath (Join-Path $toolsRoot 'bin\linker_modtools.exe'))) {
    throw "BO3 Mod Tools nicht gefunden: $toolsRoot"
}

# 1. Jede Lua-Datei muss im Zonenrezept stehen und umgekehrt.
$zoneRecipe = Join-Path $sourceRoot 'zone_source\core_mod.zone'
$listed = @(Get-Content -LiteralPath $zoneRecipe | Where-Object { $_ -match '^rawfile,(.+\.lua)\s*$' } | ForEach-Object { $Matches[1] })
$present = @(Get-ChildItem -LiteralPath (Join-Path $sourceRoot 'ui') -Recurse -Filter *.lua |
    ForEach-Object { $_.FullName.Substring($sourceRoot.Length + 1).Replace('\', '/') })
$missingInZone = @($present | Where-Object { $listed -notcontains $_ })
$missingOnDisk = @($listed | Where-Object { $present -notcontains $_ })
if ($missingInZone.Count -or $missingOnDisk.Count) {
    throw "Zonenrezept passt nicht. Nicht im Rezept: $($missingInZone -join ', ') | Fehlt auf Platte: $($missingOnDisk -join ', ')"
}

$withBom = @(Get-ChildItem -LiteralPath (Join-Path $sourceRoot 'ui') -Recurse -Filter *.lua | Where-Object {
    $bytes = [IO.File]::ReadAllBytes($_.FullName)
    $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
})
if ($withBom.Count) {
    throw "Lua-Dateien mit UTF-8-BOM (vom Lua-Compiler evtl. nicht lesbar): $($withBom.Name -join ', ')"
}

$python = Get-Command python -ErrorAction SilentlyContinue
if ($python) {
    # Vollständiger Lua-5.1-Parser: Syntax, unbekannte und neue globale Namen.
    & $python.Source (Join-Path $projectRoot 'tools\lua_lint.py') (Join-Path $sourceRoot 'ui') | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Lua-Prüfung fehlgeschlagen (siehe oben).' }
} else {
    Write-Warning 'Python nicht gefunden - Lua-Prüfung übersprungen.'
}

if ($Install -and (Get-Process -Name BlackOps3 -ErrorAction SilentlyContinue)) {
    throw 'BO3 läuft noch. Bitte das Spiel schließen, sonst sind die Fastfiles gesperrt.'
}

# 2. Staging neu aufbauen (nur unser eigener Modordner in den Mod Tools).
if ((Split-Path -Leaf $staging) -ne $modName) { throw "Unerwarteter Staging-Pfad: $staging" }
# workshop.json enthält nach dem ersten Upload die Workshop-ID: sichern, sonst
# legt der Launcher beim nächsten Veröffentlichen einen neuen Eintrag an.
$workshopStaging = Join-Path $staging 'zone\workshop.json'
$workshopBackup = Join-Path $projectRoot "workshop\$modName\workshop.json"
if (Test-Path -LiteralPath $workshopStaging) {
    New-Item -ItemType Directory -Force -Path (Split-Path $workshopBackup) | Out-Null
    Copy-Item -LiteralPath $workshopStaging -Destination $workshopBackup -Force
}
if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
New-Item -ItemType Directory -Path $staging | Out-Null
Copy-Item -Path (Join-Path $sourceRoot '*') -Destination $staging -Recurse

if ($Release) {
    # Release: feste Version, Statuszeile nur bei Fehlern, kein Konsolen-Log.
    $utilPath = Join-Path $staging 'ui\qol\util.lua'
    $util = [IO.File]::ReadAllText($utilPath)
    $patched = [regex]::Replace($util, 'QoL\.VERSION = "[^"]*"', "QoL.VERSION = ""$Version""")
    $patched = $patched.Replace('QoL.DEV = true', 'QoL.DEV = false')
    if (-not $patched.Contains('QoL.DEV = false') -or -not $patched.Contains("QoL.VERSION = ""$Version""")) {
        throw 'Release-Anpassung von util.lua fehlgeschlagen (VERSION/DEV nicht gefunden).'
    }
    [IO.File]::WriteAllText($utilPath, $patched, (New-Object Text.UTF8Encoding($false)))
}

# 3. Linken (Deutsch + Englisch, core + mp).
$env:TA_GAME_PATH = "$toolsRoot\"
$env:TA_TOOLS_PATH = "$toolsRoot\"
$env:TA_LOCAL_ASSET_CACHE = Join-Path $toolsRoot 'share\assetconvert'
$logRoot = Join-Path $projectRoot ("investigation\build-logs\" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
Push-Location $toolsRoot
try {
    foreach ($language in @('english', 'german')) {
        foreach ($zoneName in @('core_mod', 'mp_mod')) {
            $log = Join-Path $logRoot "$language-$zoneName.log"
            & "$toolsRoot\bin\linker_modtools.exe" -language $language -fs_game $modName -modsource $zoneName 2>&1 |
                Tee-Object -FilePath $log | Out-Host
            if ($LASTEXITCODE -ne 0) { throw "Linker fehlgeschlagen: $language/$zoneName (Exit $LASTEXITCODE), Log: $log" }
            $problems = Select-String -LiteralPath $log -Pattern 'error|failed|couldn''t|could not' -CaseSensitive:$false
            if ($problems) { throw "Linker meldet Probleme ($language/$zoneName): $($problems[0].Line)" }
        }
    }
} finally { Pop-Location }

# 4. Ergebnis prüfen: alle Fastfiles da, alle Lua-Dateien im Paket.
foreach ($file in $zoneFiles) {
    $path = Join-Path $staging "zone\$file"
    if (-not (Test-Path -LiteralPath $path) -or (Get-Item -LiteralPath $path).Length -eq 0) { throw "Fehlendes Build-Ergebnis: $path" }
}
$assetList = Get-Content -LiteralPath (Join-Path $staging 'zone_source\all\assetlist\core_mod.csv')
foreach ($lua in $listed) {
    if ($assetList -notcontains "rawfile,$lua") { throw "Nicht im Paket: $lua" }
}

if (Test-Path -LiteralPath $workshopBackup) {
    Copy-Item -LiteralPath $workshopBackup -Destination $workshopStaging -Force
}

$dist = Join-Path $projectRoot "dist\$flavor\$modName\zone"
New-Item -ItemType Directory -Force -Path $dist | Out-Null
foreach ($file in $zoneFiles) { Copy-Item -LiteralPath (Join-Path $staging "zone\$file") -Destination $dist -Force }

# 5. Lokal installieren.
if ($Install) {
    $target = Join-Path $gameRoot "mods\$modName\zone"
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    foreach ($file in $zoneFiles) { Copy-Item -LiteralPath (Join-Path $dist $file) -Destination $target -Force }

    $profileTarget = Join-Path $gameRoot "players\mods\$modName"
    $profileSource = Join-Path $gameRoot "players\mods\$MigrateProfileFrom"
    if (-not $Release -and -not (Test-Path -LiteralPath $profileTarget) -and $MigrateProfileFrom -and (Test-Path -LiteralPath $profileSource)) {
        Copy-Item -LiteralPath $profileSource -Destination $profileTarget -Recurse
        Write-Host "Profil übernommen: $MigrateProfileFrom -> $modName"
    }
    Write-Host "Installiert: $target"
}

if ($Release) {
    # ZIP für GitHub-Releases: der Ordner darin gehört nach <BO3>\mods\.
    $zip = Join-Path $projectRoot "dist\$modName-$Version.zip"
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
    Compress-Archive -Path (Join-Path $projectRoot "dist\$flavor\$modName") -DestinationPath $zip
    Write-Host "Release-Paket: $zip"
}

Get-ChildItem -LiteralPath $dist | Get-FileHash | Select-Object @{n = 'File'; e = { Split-Path -Leaf $_.Path } }, Hash |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $logRoot 'hashes.json') -Encoding utf8
Write-Host "Build fertig: $modName  (Logs: $logRoot)"
