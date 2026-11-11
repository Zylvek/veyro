//! Экран 15 спеки: Transaction confirmation — полноэкранное превью
//! отправки до подписи. Экран только отображает то, что передал flow
//! отправки (получатель, сумма, ставка комиссии, сеть) и требует явного
//! подтверждения; он НЕ вызывает ядро. Финальная сумма комиссии
//! рассчитывается ядром по реальным UTXO при подписи — числом её здесь
//! показать нельзя, это честно указано на экране (иначе была бы выдумка).

import 'package:flutter/material.dart';

import 'package:veyro/design/app_colors.dart';
import 'package:veyro/design/components.dart';
import 'package:veyro/util/format.dart';

/// Полноэкранное подтверждение отправки. Возвращает `true` через
/// Navigator.pop, если пользователь явно подтвердил отправку.
class TxConfirmScreen extends StatelessWidget {
  /// Адрес получателя (как введён на экране отправки).
  final String recipient;

  /// Сумма в сатоши (уже разобрана целочисленно из поля суммы).
  final int amountSat;

  /// Скорость: ставка, выбранная пользователем, sat/vB.
  final int rateSatVb;

  /// Название сети активной сессии ядра (null — «—», честное отсутствие).
  final String? networkDisplay;

  const TxConfirmScreen({
    super.key,
    required this.recipient,
    required this.amountSat,
    required this.rateSatVb,
    this.networkDisplay,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Подтверждение отправки')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              VCard(
                title: 'Актив и сеть',
                icon: Icons.language_outlined,
                children: [
                  _row(context, 'Актив', 'Bitcoin (BTC)'),
                  _row(
                    context,
                    'Сеть',
                    networkDisplay ?? '— (сессия ядра не активна)',
                    mono: networkDisplay != null ? false : true,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Подпись выполняется в Rust-ядре для сети активной '
                    'сессии; транзакция уйдёт только на выбранный '
                    'Electrum-сервер.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              VCard(
                title: 'Получатель и сумма',
                icon: Icons.person_outline,
                children: [
                  VMonoCopyRow(label: 'Получатель', value: recipient),
                  const SizedBox(height: 12),
                  VAmount(satToBtcString(amountSat), suffix: 'BTC'),
                  const SizedBox(height: 4),
                  Text(
                    '${groupDigits(amountSat)} сат',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall!
                        .copyWith(color: VColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              VCard(
                title: 'Комиссия и скорость',
                icon: Icons.speed_outlined,
                children: [
                  _row(context, 'Скорость', '$rateSatVb sat/vB'),
                  const SizedBox(height: 8),
                  Text(
                    'Финальная комиссия рассчитывается ядром при подписи '
                    'по реальным UTXO (точное число байт ещё не известно) '
                    'и показывается в результате отправки.',
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
                    Icon(Icons.warning_amber_outlined,
                        size: 20, color: VColors.error),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Отправка необратима. Перепроверьте адрес: '
                        'транзакцию нельзя отменить после broadcast. '
                        'Подпись локальная (BIP143): ключи не покидают ядро.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall!
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
                      'Отмена',
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: VButton.primary(
                      'Подписать и отправить',
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

  Widget _row(BuildContext context, String key, String value,
      {bool mono = false}) {
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
