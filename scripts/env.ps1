# Окружение разработки MultiWallet. Всё — только на диске D.
# Использование: . D:\...\multiwallet\scripts\env.ps1

# 1. Cargo: кэш реестра и загруженных crate'ов на диске D
$env:CARGO_HOME = "D:\rust\cargo"

# 2. Временные файлы сборки на диске D
$env:TEMP = "D:\tmp"
$env:TMP  = "D:\tmp"

# 3. Flutter SDK (установлен в D:\flutter\flutter, не в PATH)
$env:Path = "D:\flutter\flutter\bin;$env:Path"

# 4. Каталог для временных данных интеграционных тестов
$env:MULTIWALLET_TEST_TMP = "D:\tmp\multiwallet-tests"

# Инструменты, обнаруженные при аудите окружения (PHASE 1):
#   rustc/cargo 1.99.1, git 2.52, Java 21, CMake 4.4.5
#   Flutter 3.47.2 (D:\flutter\flutter), Dart 3.13.2
#   Android SDK/NDK — НЕ установлены (нужны для Phase 9, ставить на D:\Android)
