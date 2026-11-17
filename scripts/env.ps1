# Окружение разработки VEYRO — персональный локальный пример.
# Копируйте в scripts/env.local.ps1 (файл не публикуется) и правьте под себя.
# Использование: . ./env.ps1   (запускать из каталога репозитория)

$script:root = Split-Path -Parent $PSScriptRoot

# 1. Cargo: кэш реестра и загруженных crate'ов — при желании на другом диске.
if (-not $env:CARGO_HOME -and (Test-Path 'D:\rust\cargo')) { $env:CARGO_HOME = 'D:\rust\cargo' }

# 2. Временные файлы сборки — при желании выносятся на другой диск.
if (-not $env:TMP -and (Test-Path 'D:\tmp')) { $env:TEMP = 'D:\tmp'; $env:TMP = 'D:\tmp' }

# 3. Flutter SDK: по умолчанию ожидается рядом (../flutter/flutter) или в PATH.
$candidate = Join-Path (Split-Path -Parent (Split-Path -Parent $script:root)) 'flutter\flutter\bin'
if (Test-Path (Join-Path $candidate 'flutter.bat')) { $env:Path = "$candidate;$env:Path" }

# 4. Каталог для временных данных интеграционных тестов.
if (Test-Path 'D:\tmp') { $env:VEYRO_TEST_TMP = 'D:\tmp\veyro-tests' }

# 4.1 Кэш Dart-пакетов (pub): по умолчанию около Flutter SDK, можно перенести.
$pubCandidate = Join-Path (Split-Path -Parent (Split-Path -Parent $script:root)) 'flutter\pub-cache'
if (Test-Path $pubCandidate) { $env:PUB_CACHE = $pubCandidate }

# 5. Android SDK: ожидается в стандартном месте ($env:LOCALAPPDATA) либо
#    задаётся вручную до дотсорса файла.
if (-not $env:ANDROID_HOME -and (Test-Path "$env:LOCALAPPDATA\Android\Sdk")) {
    $env:ANDROID_HOME     = "$env:LOCALAPPDATA\Android\Sdk"
    $env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
    $ndk = Get-ChildItem "$env:ANDROID_HOME\ndk" -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    if ($ndk) { $env:ANDROID_NDK_HOME = $ndk.FullName }
    $env:Path = "$env:ANDROID_HOME\platform-tools;$env:Path"
}

# 6. JDK из состава Android Studio (JBR), если найден на стандартном месте.
foreach ($jbr in @(
    "$env:LOCALAPPDATA\Programs\Android Studio\jbr",
    "${env:ProgramFiles}\Android\Android Studio\jbr")) {
    if (Test-Path "$jbr\bin\java.exe") { $env:JAVA_HOME = $jbr; break }
}
