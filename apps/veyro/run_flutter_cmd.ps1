# Runs the given dart/flutter command with the VEYRO toolchain PATH.
# Flutter location: PATH first, then common local fallbacks (edit to taste).
$flutterBin = (Get-Command flutter -ErrorAction SilentlyContinue).Source
if (-not $flutterBin) {
    foreach ($cand in @(
        "$env:LOCALAPPDATA\flutter\flutter\bin",
        'D:\flutter\flutter\bin')) {
        if (Test-Path (Join-Path $cand 'flutter.bat')) { $flutterBin = $cand; break }
    }
}
if ($flutterBin) {
    $sdkRoot = Split-Path -Parent $flutterBin
    $env:Path = "$flutterBin;$sdkRoot\cache\dart-sdk\bin;$env:Path"
}
Set-Location "$PSScriptRoot"
& $args[0] $args[1..($args.Count - 1)]
Write-Host "FLUTTER_CMD_EXIT=$LASTEXITCODE"
