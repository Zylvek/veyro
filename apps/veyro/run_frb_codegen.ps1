# Runs flutter_rust_bridge_codegen with the VEYRO toolchain PATH
# (flutter from PATH, or common local fallbacks - see run_flutter_cmd.ps1).
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
flutter_rust_bridge_codegen generate
Write-Host "FRB_CODEGEN_EXIT=$LASTEXITCODE"
