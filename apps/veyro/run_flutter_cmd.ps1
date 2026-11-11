# Runs the given dart/flutter command with the VEYRO toolchain PATH.
$env:Path = "D:\flutter\flutter\bin;D:\flutter\flutter\bin\cache\dart-sdk\bin;" + $env:Path
Set-Location "$PSScriptRoot"
& $args[0] $args[1..($args.Count - 1)]
Write-Host "FLUTTER_CMD_EXIT=$LASTEXITCODE"
