# Erzeugt das Steam-Workshop-Vorschaubild (512x512 PNG) ohne Zusatzsoftware.
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\make_thumbnail.ps1
param(
    [string]$Out = (Join-Path $PSScriptRoot '..\workshop\thumbnail.png')
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$size = 512
$bitmap = New-Object Drawing.Bitmap($size, $size)
$g = [Drawing.Graphics]::FromImage($bitmap)
$g.SmoothingMode = 'AntiAlias'
$g.TextRenderingHint = 'ClearTypeGridFit'

$dark = [Drawing.Color]::FromArgb(10, 13, 17)
$darker = [Drawing.Color]::FromArgb(4, 6, 8)
$panel = [Drawing.Color]::FromArgb(22, 28, 35)
$row = [Drawing.Color]::FromArgb(58, 68, 80)
$orange = [Drawing.Color]::FromArgb(255, 140, 31)
$white = [Drawing.Color]::FromArgb(238, 240, 243)
$grey = [Drawing.Color]::FromArgb(150, 160, 172)

# Hintergrund mit leichtem Verlauf
$rect = New-Object Drawing.Rectangle(0, 0, $size, $size)
$bg = New-Object Drawing.Drawing2D.LinearGradientBrush($rect, $dark, $darker, 90)
$g.FillRectangle($bg, $rect)

# Zwei Menuehaelften als Splitscreen-Motiv
$panelBrush = New-Object Drawing.SolidBrush($panel)
$rowBrush = New-Object Drawing.SolidBrush($row)
$orangeBrush = New-Object Drawing.SolidBrush($orange)
$top = 178
$height = 208
foreach ($half in 0, 1) {
    $x = 44 + $half * 216
    $g.FillRectangle($panelBrush, $x, $top, 208, $height)
    # Kopfzeile der Haelfte
    $g.FillRectangle($orangeBrush, $x + 16, $top + 18, 92, 10)
    for ($i = 0; $i -lt 5; $i++) {
        $y = $top + 52 + $i * 30
        if ($i -eq (1 + $half * 2)) {
            $g.FillRectangle($orangeBrush, $x + 16, $y, 176, 18)
        } else {
            $g.FillRectangle($rowBrush, $x + 16, $y, 150, 14)
        }
    }
}

# Trennlinie in der Mitte
$g.FillRectangle($orangeBrush, 254, $top - 16, 4, $height + 32)

# Texte
$dot = [char]0x00B7
$center = New-Object Drawing.StringFormat
$center.Alignment = 'Center'
$fontLabel = New-Object Drawing.Font('Segoe UI', 17, [Drawing.FontStyle]::Bold)
$fontTitle = New-Object Drawing.Font('Segoe UI', 42, [Drawing.FontStyle]::Bold)
$fontSub = New-Object Drawing.Font('Segoe UI', 16, [Drawing.FontStyle]::Regular)
$fontFoot = New-Object Drawing.Font('Segoe UI', 15, [Drawing.FontStyle]::Bold)
$greyBrush = New-Object Drawing.SolidBrush($grey)
$whiteBrush = New-Object Drawing.SolidBrush($white)

$g.DrawString('BLACK OPS III', $fontLabel, $greyBrush, ($size / 2), 44, $center)
$g.DrawString('SPLITSCREEN', $fontTitle, $whiteBrush, ($size / 2), 68, $center)
$g.DrawString('QoL', $fontTitle, $orangeBrush, ($size / 2), 114, $center)
$g.DrawString("Klassen  $dot  Profile  $dot  Statistiken  $dot  Turniere", $fontSub, $greyBrush, ($size / 2), 412, $center)
$g.DrawString("2 SPIELER  $dot  OFFLINE & LAN", $fontFoot, $orangeBrush, ($size / 2), 450, $center)

$folder = Split-Path -Parent $Out
if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Force -Path $folder | Out-Null }
$bitmap.Save($Out, [Drawing.Imaging.ImageFormat]::Png)
$g.Dispose()
$bitmap.Dispose()
Write-Host "Vorschaubild: $Out ($([math]::Round((Get-Item $Out).Length / 1KB)) KB)"
