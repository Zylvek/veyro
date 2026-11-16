//! Пути данных VEYRO. UI владеет расположением файлов и передаёт пути в
//! мост на каждый вызов (договорённость интерфейса bridge).
//!
//! Windows: %APPDATA%\veyro\... ; запасной вариант — каталог в домашней
//! папке (упрощает юнит-тесты на CI с пустым окружением).

import 'dart:io';

String _appDataDir() {
  final appData = Platform.environment['APPDATA'];
  if (appData != null && appData.isNotEmpty) return appData;
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (home != null && home.isNotEmpty) {
    return '$home${Platform.pathSeparator}.veyro';
  }
  return '.';
}

String _join(String base, String child) =>
    '$base${Platform.pathSeparator}$child';

/// Каталог зашифрованных vault-файлов кошельков.
String walletsDir() => _join(_join(_appDataDir(), 'veyro'), 'wallets');

/// Путь к SQLite-базе метаданных (настройки, реестр).
String appDbPath() => _join(_join(_appDataDir(), 'veyro'), 'veyro.db');

/// Кэш значков валют с Iconify API (SVG): один раз скачано — всегда
/// рисуется без сети при следующих запусках.
String iconCacheDir() => _join(_join(_appDataDir(), 'veyro'), 'icon-cache');

/// Дисковый кэш фиатных цен (CoinGecko): свежий курс и линия графика
/// переживают перезапуск — повторные пуски не тратят данных.
String priceCachePath() =>
    _join(_join(_appDataDir(), 'veyro'), 'price_cache.json');
