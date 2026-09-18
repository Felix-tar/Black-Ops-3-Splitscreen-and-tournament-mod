param(
    [switch]$Install,
    [ValidatePattern('^bo3_qol_ui_dev[0-9]*$')][string]$ModName = 'bo3_qol_ui_dev'
)
$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$toolsRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Call of Duty Black Ops III 455130'
$gameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\Call of Duty Black Ops III'
$staging = Join-Path $toolsRoot "mods\$modName"
if (Test-Path $staging) { throw 'Development staging already exists; inspect it before another build.' }
New-Item -ItemType Directory -Path $staging | Out-Null
Copy-Item (Join-Path $projectRoot 'development\*') $staging -Recurse
$env:TA_GAME_PATH = "$toolsRoot\"
$env:TA_TOOLS_PATH = "$toolsRoot\"
$env:TA_LOCAL_ASSET_CACHE = Join-Path $toolsRoot 'share\assetconvert'
$logRoot = Join-Path $projectRoot 'investigation\build-ui-dev'
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
Push-Location $toolsRoot
try {
    foreach ($language in @('english','german')) {
        foreach ($zoneName in @('core_mod','mp_mod')) {
            & "$toolsRoot\bin\linker_modtools.exe" -language $language -fs_game $modName -modsource $zoneName 2>&1 |
                Tee-Object -FilePath (Join-Path $logRoot "$language-$zoneName.log")
            if ($LASTEXITCODE -ne 0) { throw "Linker failed: $language/$zoneName ($LASTEXITCODE)" }
        }
    }
} finally { Pop-Location }
$dist = Join-Path $projectRoot "dist\ui-development\$modName\zone"
New-Item -ItemType Directory -Force -Path $dist | Out-Null
foreach ($file in @('core_mod.ff','mp_mod.ff','en_core_mod.ff','ge_core_mod.ff','en_mp_mod.ff','ge_mp_mod.ff')) {
    $source = Join-Path $staging "zone\$file"
    if (!(Test-Path $source) -or (Get-Item $source).Length -eq 0) { throw "Missing output: $source" }
    Copy-Item $source $dist
}
if ($Install) {
    $target = Join-Path $gameRoot "mods\$modName"
    if (Test-Path $target) { throw 'Development mod already installed; refusing to merge old files.' }
    Copy-Item (Split-Path $dist) $target -Recurse
}
