//! Человекочитаемые названия BTC-сетей для UI: ядро отдаёт английский
//! networkDisplay («Bitcoin mainnet», «testnet4»). Локализовано:
//! русский — база («Bitcoin · основная сеть (mainnet)», вердикты
//! владельца), English — «Bitcoin · mainnet» и т.п. Маппинг по
//! содержимому строки — безопасно и без изменения FFI-контрактов.

import 'package:veyro/util/display_prefs.dart';

/// Локализованное название сети по строке ядра; неизвестное — as-is.
String? ruNetworkText(String? display) {
  if (display == null) return null;
  final d = display.toLowerCase();
  final en = DisplayPrefs.language == 'en';
  if (d.contains('mainnet')) {
    return en ? 'Bitcoin · mainnet' : 'Bitcoin · основная сеть (mainnet)';
  }
  if (d.contains('testnet4')) {
    return en ? 'Bitcoin · testnet4' : 'Bitcoin · тестовая сеть (testnet4)';
  }
  if (d.contains('testnet')) {
    return en ? 'Bitcoin · testnet' : 'Bitcoin · тестовая сеть (testnet)';
  }
  if (d.contains('signet')) {
    return en ? 'Bitcoin · signet' : 'Bitcoin · сигнет';
  }
  return display;
}
