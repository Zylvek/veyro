//! Русские названия BTC-сетей для UI: ядро отдаёт английский
//! networkDisplay («Bitcoin mainnet», «testnet4»); владелец просил
//! показывать такие подписи по-русски. Маппинг по содержимому строки —
//! безопасно и без изменения FFI-контрактов.

/// Русское название сети по строке ядра; неизвестное — as-is.
String? ruNetworkText(String? display) {
  if (display == null) return null;
  final d = display.toLowerCase();
  if (d.contains('mainnet')) {
    return 'Bitcoin · основная сеть (mainnet)';
  }
  if (d.contains('testnet4')) {
    return 'Bitcoin · тестовая сеть (testnet4)';
  }
  if (d.contains('testnet')) {
    return 'Bitcoin · тестовая сеть (testnet)';
  }
  if (d.contains('signet')) {
    return 'Bitcoin · сигнет';
  }
  return display;
}
