# Окружение разработки VEYRO. Всё — только на диске D.
# Использование: . D:\Admin\Documents\Проект по умолчанию\veyro\scripts\env.ps1

# 1. Cargo: кэш реестра и загруженных crate'ов на диске D
$env:CARGO_HOME = "D:\rust\cargo"

# 2. Временные файлы сборки на диске D
$env:TEMP = "D:\tmp"
$env:TMP  = "D:\tmp"

# 3. Flutter SDK (установлен в D:\flutter\flutter, не в PATH)
$env:Path = "D:\flutter\flutter\bin;$env:Path"

# 4. Каталог для временных данных интеграционных тестов
$env:VEYRO_TEST_TMP = "D:\tmp\veyro-tests"

# 4.1 Кэш Dart-пакетов (pub) — на диске D (по умолчанию был бы на C)
$env:PUB_CACHE = "D:\flutter\pub-cache"

# 5. Android (всё установлено на диске D)
$env:ANDROID_HOME      = "D:\Users\Admin\AppData\Local\Android\Sdk"
$env:ANDROID_SDK_ROOT  = $env:ANDROID_HOME
$env:ANDROID_NDK_HOME   = "$env:ANDROID_HOME\ndk\28.2.13676358"
$env:Path = "$env:ANDROID_HOME\platform-tools;$env:Path"

# 6. JDK из состава Android Studio (JBR)
$env:JAVA_HOME = "D:\Program Files\Android\Android Studio\jbr"

# Инструменты, обнаруженные при аудите окружения (PHASE 1, обновлено):
#   rustc/cargo 1.99.1, git 2.52, CMake 4.4.5
#   Flutter 3.47.2 (D:\flutter\flutter), Dart 3.13.2
#   Android Studio 2026.1.4, SDK (35/36/37), NDK 28.2, JBR 25
