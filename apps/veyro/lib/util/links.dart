//! Ссылки на block explorer (спека UI 9.10: «Details… explorer link if
//! available»). Ссылка — данные, а не действие: системного лончера в этой
//! сборке нет (url_launcher не добавлен), поэтому экран копирует URL в
//! буфер обмена и честно это подписывает.

/// Имя explorer'а, доступного для BTC-сетей.
const String kBtcExplorerName = 'mempool.space';

/// Имя explorer'а для LTC mainnet.
const String kLtcExplorerName = 'litecoinspace.org';

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

/// URL транзакции LTC mainnet (паспорт LTC §1: litecoinspace.org,
/// проверен живым 11.11.2026).
String? ltcTxUrl(String txid) {
  return 'https://litecoinspace.org/tx/$txid';
}

/// Имя explorer'а для BCH mainnet (паспорт BCH §5).
const String kBchExplorerName = 'explorer.bitcoin.com';

/// URL транзакции BCH mainnet (паспорт BCH §5: explorer.bitcoin.com).
String? bchTxUrl(String txid) {
  return 'https://explorer.bitcoin.com/bch/tx/$txid';
}

/// Имя explorer'а для XEC (eCash) mainnet (паспорт XEC §11: официальный
/// explorer.e.cash).
const String kXecExplorerName = 'explorer.e.cash';

/// URL транзакции XEC mainnet.
String? xecTxUrl(String txid) {
  return 'https://explorer.e.cash/tx/$txid';
}

/// Имя community-explorer'а для RVN mainnet (паспорт RVN §5: канонический
/// официальный не зафиксирован; ravencoin.network — устоявшееся
/// community-решение).
const String kRvnExplorerName = 'ravencoin.network';

/// URL транзакции RVN mainnet.
String? rvnTxUrl(String txid) {
  return 'https://ravencoin.network/tx/$txid';
}

/// Имя explorer'а для ETC mainnet (паспорт ETC §5: BlockScout, API v2
/// проверен 11.11.2026).
const String kEtcExplorerName = 'etc.blockscout.com';

/// URL транзакции ETC mainnet.
String? etcTxUrl(String txhash) {
  return 'https://etc.blockscout.com/tx/$txhash';
}
