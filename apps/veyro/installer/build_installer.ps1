# Сборка релизного установщика VEYRO (Flutter release -> Inno Setup -> SHA-256).
# Требования: flutter SDK в D:\Flutter\flutter\bin; Inno Setup (ISCC.exe)
# в %LOCALAPPDATA%\opencode-tools\innosetup (портабельная установка без админа).
# Перед сборкой veyro.exe должен быть закрыт.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot   # ...\apps\veyro
$iscc = Join-Path $env:LOCALAPPDATA 'opencode-tools\innosetup\ISCC.exe'
if (-not (Test-Path $iscc)) { Write-Error "ISCC.exe не найден: $iscc" }

# 1. Release-сборка.
& 'D:\Flutter\flutter\bin\flutter.bat' build windows --release
if ($LASTEXITCODE -ne 0) { Write-Error 'flutter build windows --release failed' }

# 2. Версия из pubspec.yaml.
$pubspec = Get-Content (Join-Path $root 'pubspec.yaml') -Raw
$version = ([regex]::Match($pubspec, '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)')).Groups[1].Value
if (-not $version) { Write-Error 'version не найдена в pubspec.yaml' }
Write-Host "Release version: $version"

# 3. Установщик.
& $iscc (Join-Path $PSScriptRoot 'veyro_setup.iss') "/DRELEASE=$version"
if ($LASTEXITCODE -ne 0) { Write-Error 'ISCC failed' }

$out = Join-Path $root 'build\windows\installer'
$setup = Get-ChildItem $out -Filter "VEYRO-setup-$version.exe" | Select-Object -First 1
if (-not $setup) { Write-Error 'установщик не найден' }

# 4. Контрольные суммы SHA-256 для артефакта.
$hash = (Get-FileHash $setup.FullName -Algorithm SHA256).Hash
$sumsPath = Join-Path $out "VEYRO-setup-$version.exe.sha256"
"$hash  $(Split-Path -Leaf $setup.FullName)" | Set-Content -Encoding ascii $sumsPath

Write-Host "`n=== РАЗРЕЗ РЕЛИЗА ==="
Write-Host "installer: $($setup.FullName)"
Write-Host "sha256:    $sumsPath"
Write-Host "hash:      $hash"
