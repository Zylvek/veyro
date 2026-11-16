//! Монеты VEYRO. Enum живёт в util (не в data), потому что им пользуются
//! и экраны, и провайдеры форм; BTC — исторически «дефолтная» монета,
//! LTC — вторая реализованная, BCH — третья (профиль LTC: UTXO+Electrum,
//! cashaddr, forkid-подпись).

enum WalletCoin { btc, ltc, bch, xec, rvn }

extension WalletCoinX on WalletCoin {
  /// Отображаемая тикер-единица (в суммах и подтверждениях).
  String get unit => switch (this) {
        WalletCoin.btc => 'BTC',
        WalletCoin.ltc => 'LTC',
        WalletCoin.bch => 'BCH',
        WalletCoin.xec => 'XEC',
        WalletCoin.rvn => 'RVN',
      };

  /// Полное название монеты (заголовокAppBar и карточки).
  String get display => switch (this) {
        WalletCoin.btc => 'Bitcoin',
        WalletCoin.ltc => 'Litecoin',
        WalletCoin.bch => 'Bitcoin Cash',
        WalletCoin.xec => 'eCash',
        WalletCoin.rvn => 'Ravencoin',
      };
}
