# Runs flutter_rust_bridge_codegen with the VEYRO toolchain PATH (flutter at D:\flutter\flutter).
$env:Path = "D:\flutter\flutter\bin;D:\flutter\flutter\bin\cache\dart-sdk\bin;" + $env:Path
Set-Location "$PSScriptRoot"
flutter_rust_bridge_codegen generate
Write-Host "FRB_CODEGEN_EXIT=$LASTEXITCODE"
