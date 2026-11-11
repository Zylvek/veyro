//! Настройки BTC-сети: выбранная сеть и Electrum-сервер для неё.
//!
//! Хранение — не-секретные SQLite-настройки через мост:
//! - `btc.network` — код сети (0 mainnet / 1 testnet3 / 2 testnet4);
//! - `node_endpoints.<code>` — URL Electrum-сервера этой сети
//!   (пользовательский адрес; ключ из плана PHASE 4 §5).
//!
//! По умолчанию выбирается testnet3 — безопасность средств: mainnet
//! переключается только осознанным действием пользователя (плюс баннер на UI
//! и fund-safety genesis-проверка в Rust при каждом unlock).
//!
//! Дефолтные серверы: mainnet — верифицированный публичный сервер из
//! docs/coins/BTC.md (§84, проверен 11.11.2026). Для testnet3 — публичный
//! сервер blockstream (не из верифицированного списка BTC.md; genesis-проверка
//! в Rust всё равно отвергнет сервер чужой сети). Для testnet4 дефолта нет —
//! верифицированного списка нет, честно просим ввести свой сервер.

import 'package:veyro/src/rust/api/storage.dart';

/// Ключ настройки выбранной сети.
const String keyNetworkCode = 'btc.network';

/// Ключ настройки сервера для конкретной сети.
String keyNodeEndpoint(int code) => 'node_endpoints.$code';

/// Один пункт выбора сети в UI.
class BtcNetworkChoice {
  final int code;
  final String title;
  final String note;

  const BtcNetworkChoice(this.code, this.title, this.note);

  /// mainnet / testnet3 / testnet4 — стабильная маппа 0/1/2 из chains
  /// (BtcNetwork::code, зафиксирована в Rust-тестах).
  static const List<BtcNetworkChoice> all = [
    BtcNetworkChoice(0, 'Bitcoin mainnet', 'Реальные средства'),
    BtcNetworkChoice(1, 'Bitcoin testnet3', 'Безопасно для испытаний'),
    BtcNetworkChoice(2, 'Bitcoin testnet4', 'Альтернативный тестнет'),
  ];

  static BtcNetworkChoice? byCode(int code) {
    for (final c in all) {
      if (c.code == code) return c;
    }
    return null;
  }
}

/// Дефолтный сервер сети (может быть `null` — тогда ждём ввода пользователя).
String? defaultServerUrl(int code) {
  switch (code) {
    case 0:
      // docs/coins/BTC.md §84: electrum.qtornado.com (Fulcrum 2.1.4, ssl).
      return 'ssl://electrum.qtornado.com:50002';
    case 1:
      // Не из верифицированного списка BTC.md; genesis-проверка в Rust
      // защищает от сервера другой сети.
      return 'ssl://electrum.blockstream.info:60002';
    default:
      return null; // testnet4: без верифицированного дефолта
  }
}

/// Загруженная пара «сеть + сервер» для unlock BTC.
class BtcNetworkSettings {
  final int networkCode;
  final String serverUrl;
  const BtcNetworkSettings({required this.networkCode, required this.serverUrl});
}

/// Сеть из настроек. Значение по умолчанию — testnet3 (код 1).
Future<int> loadNetworkCode() async {
  final raw = await dbGetSetting(key: keyNetworkCode);
  final code = raw == null ? null : int.tryParse(raw);
  if (code == null || BtcNetworkChoice.byCode(code) == null) return 1;
  return code;
}

/// Сервер из настроек или дефолт сети (пустая строка, если дефолта нет).
Future<String> loadServerUrl(int code) async {
  final saved = await dbGetSetting(key: keyNodeEndpoint(code));
  if (saved != null && saved.trim().isNotEmpty) return saved.trim();
  return defaultServerUrl(code) ?? '';
}

/// Загрузить обе настройки разом (для экрана/диалога unlock).
Future<BtcNetworkSettings> loadSettings() async {
  final code = await loadNetworkCode();
  final url = await loadServerUrl(code);
  return BtcNetworkSettings(networkCode: code, serverUrl: url);
}

/// Сохранить выбранную сеть.
Future<void> saveNetworkCode(int code) =>
    dbSetSetting(key: keyNetworkCode, value: code.toString());

/// Сохранить сервер для сети (пустая строка = вернуться к дефолту).
Future<void> saveServerUrl(int code, String url) =>
    dbSetSetting(key: keyNodeEndpoint(code), value: url.trim());
