//! Экран 15 спеки: Transaction confirmation — полноэкранное превью
//! отправки до подписи. Экран только отображает то, что передал flow
//! отправки (получатель, сумма, ставка комиссии, сеть) и требует явного
//! подтверждения; он НЕ вызывает ядро. Финальная сумма комиссии
//! рассчитывается ядром по реальным UTXO при подписи — числом её здесь
//! показать нельзя, это честно указано на экране (иначе была бы выдумка).

import 'package:flutter/material.dart';

import 'package:veyro/design/app_colors.dart';
import 'package:veyro/design/components.dart';
import 'package:veyro/util/coin.dart';
import 'package:veyro/util/format.dart';
import 'package:veyro/util/l10n.dart';
import 'package:veyro/util/network_names.dart';

/// Полноэкранное подтверждение отправки. Возвращает `true` через
/// Navigator.pop, если пользователь явно подтвердил отправку.
class TxConfirmScreen extends StatelessWidget {
  /// Адрес получателя (как введён на экране отправки).
  final String recipient;

  /// Сумма в сатоши (уже разобрана целочисленно из поля суммы).
  final int amountSat;

  /// Скорость: ставка, выбранная пользователем, sat/vB.
  final int rateSatVb;

  /// Монета отправки (BTC дефолт — исторический контракт тестов).
  final WalletCoin coin;

  /// Название сети активной сессии ядра (null — «—», честное отсутствие).
  final String? networkDisplay;

  const TxConfirmScreen({
    super.key,
    required this.recipient,
    required this.amountSat,
    required this.rateSatVb,
    this.coin = WalletCoin.btc,
    this.networkDisplay,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('tx_confirm_title'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              VCard(
                title: t('tx_asset_network'),
                icon: Icons.language_outlined,
                children: [
                  _row(
                    context,
                    t('asset_label'),
                    switch (coin) {
                      WalletCoin.ltc => 'Litecoin (LTC)',
                      WalletCoin.bch => 'Bitcoin Cash (BCH)',
                      WalletCoin.xec => 'eCash (XEC)',
                      WalletCoin.rvn => 'Ravencoin (RVN)',
                      _ => 'Bitcoin (BTC)',
                    },
                  ),
                  _row(
                    context,
                    t('network_label'),
                    networkDisplay == null
                        ? t('no_active_session')
                        : (ruNetworkText(networkDisplay) ?? networkDisplay!),
                    mono: networkDisplay != null ? false : true,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    t('confirm_network_desc'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              VCard(
                title: t('recipient_amount_card'),
                icon: Icons.person_outline,
                children: [
                  VMonoCopyRow(label: t('recipient_card'), value: recipient),
                  const SizedBox(height: 12),
                  VAmount(
                    coin == WalletCoin.xec
                        ? satToXecString(amountSat)
                        : satToBtcString(amountSat),
                    suffix: coin.unit,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${groupDigits(amountSat)} '
                    '${coin == WalletCoin.btc || coin == WalletCoin.rvn || coin == WalletCoin.xec ? t('sats') : coin.unit}',
                    style: Theme.of(context).textTheme.bodySmall!
                        .copyWith(color: VColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              VCard(
                title: t('fee_card'),
                icon: Icons.speed_outlined,
                children: [
                  _row(
                    context,
                    t('speed_label'),
                    '$rateSatVb ${coin == WalletCoin.btc ? 'sat/vB' : 'sat/B'}',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t('fee_final_note'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: VColors.error.withValues(alpha: 0.45),
                  ),
                  color: VColors.error.withValues(alpha: 0.10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_outlined,
                      size: 20,
                      color: VColors.error,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        t('send_irreversible'),
                        style: Theme.of(context).textTheme.bodySmall!
                            .copyWith(color: VColors.error),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: VButton.secondary(
                      t('cancel'),
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: VButton.primary(
                      t('sign_send_btn'),
                      icon: Icons.north_east,
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    String key,
    String value, {
    bool mono = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(key, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: mono
                ? VMono(value, fontSize: 13)
                : Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
