//! Настройки BTC-сети: выбранная сеть и Electrum-сервер для неё.
//!
//! Хранение — не-секретные SQLite-настройки через мост:
//! - `btc.network` — код сети (0 mainnet / 1 testnet3 / 2 testnet4);
//! - `node_endpoints.<code>` — URL Electrum-сервера этой сети.
//!
//! По умолчанию сеть — mainnet (код 0), решениевладельца: автоматический
//! выбор без ручного testnet-переключения; genesis-проверка в Rust при
//! каждом unlock отвергает сервер чужой сети (fund-safety).
//!
//! Дефолтные серверы всех трёх сетей верифицированы probe-тестом
//! `chains/tests/e2e_probe.rs` (11.11.2026): live-опрос + genesis-проверка;
//! полный список и отсевы TLS — в docs/coins/BTC.md (§84). Genesis-проверка
//! в Rust при каждом unlock всё равно отвергнет сервер чужой сети.

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

/// Дефолтный сервер сети (`null` — ждём ввода пользователя).
///
/// Верифицировано probe-тестом `chains/tests/e2e_probe.rs` (11.11.2026):
/// - mainnet: `ssl://fulcrum.bullbitcoin.com:50002` (Fulcrum 2.1.4, tip 975454);
/// - testnet3: `ssl://electrum.blockstream.info:60002` (electrs 0.4.1, tip 5344711);
/// - testnet4: `ssl://blackie.c3-soft.com:57010` (Fulcrum 2.1.4, tip 160659).
/// Отсеяны по TLS/сертификатам: qtornado (UnsupportedCertVersion),
/// aranguren:51002 и theuplink:60002 (self-signed) — §84 BTC.md.
String? defaultServerUrl(int code) {
  switch (code) {
    case 0:
      return 'ssl://fulcrum.bullbitcoin.com:50002';
    case 1:
      return 'ssl://electrum.blockstream.info:60002';
    case 2:
      return 'ssl://blackie.c3-soft.com:57010';
    default:
      return null;
  }
}

/// Загруженная пара «сеть + сервер» для unlock BTC.
class BtcNetworkSettings {
  final int networkCode;
  final String serverUrl;
  const BtcNetworkSettings({
    required this.networkCode,
    required this.serverUrl,
  });
}

/// Сеть из настроек. Значение по умолчанию — mainnet (код 0),
/// решениевладельца: сеть выбирается автоматически, никакого
/// ручного testnet-переключения. Genesis-проверка ядра при unlock
/// защищает от сервера чужой сети.
Future<int> loadNetworkCode() async {
  final raw = await dbGetSetting(key: keyNetworkCode);
  final code = raw == null ? null : int.tryParse(raw);
  if (code == null || BtcNetworkChoice.byCode(code) == null) return 0;
  return code;
}

/// Сервер из настроек или дефолт сети (пустая строка, если дефолта нет).
///
/// Защита от подменённой базы: persisted значение принимается ТОЛЬКО при
/// честной форме `ssl://…` (см. политику TLS в server_probe); мусор,
/// plaintext `tcp://` и прочие схемы молча заменяются дефолтом.
Future<String> loadServerUrl(int code) async {
  final saved = await dbGetSetting(key: keyNodeEndpoint(code));
  if (saved != null) {
    final v = saved.trim();
    if (v.startsWith('ssl://') && v.length <= 256) return v;
  }
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
