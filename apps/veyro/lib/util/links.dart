//! Ссылки на block explorer (спека UI 9.10: «Details… explorer link if
//! available»). Ссылка — данные, а не действие: системного лончера в этой
//! сборке нет (url_launcher не добавлен), поэтому экран копирует URL в
//! буфер обмена и честно это подписывает.

/// Имя explorer'а, доступного для BTC-сетей.
const String kBtcExplorerName = 'mempool.space';

/// URL транзакции в block explorer по коду сети ядра:
/// 0 = mainnet, 1 = testnet3, 2 = testnet4 (см. util/network_config.dart).
/// Для сетей без поддерживаемого explorer — null (экран покажет честное «—»).
String? explorerTxUrl(int networkCode, String txid) {
  switch (networkCode) {
    case 0:
      return 'https://mempool.space/tx/$txid';
    case 1:
      return 'https://mempool.space/testnet/tx/$txid';
    case 2:
      return 'https://mempool.space/testnet4/tx/$txid';
    default:
      return null;
  }
}
