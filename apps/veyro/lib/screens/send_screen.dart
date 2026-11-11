//! Экран 14 спеки (asset-поток Send, BTC): адрес получателя + сумма (BTC →
//! сатоши целочисленно) + комиссия (пресеты btc_fees или ручная sat/vB) →
//! полноэкранное подтверждение (TxConfirmScreen, пункт 15) → btcSend
//! (локальная подпись BIP143, идемпотентный broadcast в Rust). Кнопка Max
//! подставляет реальный доступный баланс из последней синхронизации
//! (availableSat от центра управления); если данных нет — кнопки Max нет.
//! После успеха — TXID/фактическая комиссия/статус и возврат с
//! пересинхронизацией (Rust очистил набор UTXO от повторной отправки).

import 'package:flutter/material.dart';

import 'package:veyro/design/app_colors.dart';
import 'package:veyro/design/components.dart';
import 'package:veyro/src/rust/api/btc.dart';
import 'package:veyro/util/format.dart';
import 'package:veyro/util/ui_helpers.dart';

import 'tx_confirm_screen.dart';

class SendScreen extends StatefulWidget {
  /// Реальный доступный баланс на момент последней синхронизации
  /// (confirmed + mempool-delta при отрицательной дельте). null —
  /// данных нет: кнопка Max честно скрыта.
  final int? availableSat;

  /// Точка замены для виджет-тестов (без RustLib): пресеты комиссии.
  final Future<BtcFeeRatesDto> Function()? feesLoader;

  /// Предзаполнение получателя (из адресной книги). Чистый UI-параметр,
  /// ничего не подписывает: все проверки ядра стоят на месте.
  final String? initialRecipient;

  const SendScreen({
    super.key,
    this.availableSat,
    this.feesLoader,
    this.initialRecipient,
  });

  @override
  State<SendScreen> createState() => _SendScreenState();
}

enum _FeeChoice { fast, normal, slow, manual }

class _SendScreenState extends State<SendScreen> {
  final _recipientController = TextEditingController();
  final _amountController = TextEditingController();
  final _manualRateController = TextEditingController();

  BtcFeeRatesDto? _fees;
  _FeeChoice _feeChoice = _FeeChoice.normal;
  bool _loadingFees = true;
  String? _feesError;
  bool _sending = false;
  String? _formError;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialRecipient;
    if (initial != null && initial.isNotEmpty) {
      _recipientController.text = initial;
    }
    _loadFees();
  }

  @override
  void dispose() {
    _recipientController.dispose();
    _amountController.dispose();
    _manualRateController.dispose();
    super.dispose();
  }

  Future<void> _loadFees() async {
    setState(() {
      _loadingFees = true;
      _feesError = null;
    });
    try {
      final loader = widget.feesLoader;
      final fees = loader != null ? await loader() : await btcFees();
      if (!mounted) return;
      setState(() {
        _fees = fees;
        _loadingFees = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _feesError = e.toString();
        _loadingFees = false;
        // Пресеты недоступны — остаётся честная возможность ввести ставку руками.
        _feeChoice = _FeeChoice.manual;
      });
    }
  }

  int? _resolveRateSatVb() {
    switch (_feeChoice) {
      case _FeeChoice.fast:
        final v = _fees?.fastSatVb.toInt();
        return v != null && v > 0 ? v : null;
      case _FeeChoice.normal:
        final v = _fees?.normalSatVb.toInt();
        return v != null && v > 0 ? v : null;
      case _FeeChoice.slow:
        final v = _fees?.slowSatVb.toInt();
        return v != null && v > 0 ? v : null;
      case _FeeChoice.manual:
        return int.tryParse(_manualRateController.text.trim());
    }
  }

  /// Кнопка Max: подставить реальный доступный баланс (снапшот
  /// последней синхронизации) в поле суммы.
  void _applyMax() {
    final available = widget.availableSat;
    if (available == null || available <= 0) return;
    _amountController.text = satToBtcString(available);
  }

  Future<void> _submit() async {
    final recipient = _recipientController.text.trim();
    final amountSat = parseBtcToSat(_amountController.text);
    final rate = _resolveRateSatVb();

    String? error;
    if (recipient.isEmpty) {
      error = 'Введите адрес получателя.';
    } else if (amountSat == null) {
      error = 'Сумма задана некорректно: цифры и точка, до 8 знаков.';
    } else if (amountSat <= 0) {
      error = 'Сумма должна быть больше нуля.';
    } else if (rate == null || rate <= 0) {
      error = 'Ставка комиссии: целое sat/vB больше нуля.';
    }
    setState(() => _formError = error);
    if (error != null || amountSat == null || rate == null) return;

    // Полноэкранное подтверждение (спека, пункт 15): актив/сеть/адрес/
    // сумма/комиссия + явное действие. Отправка начинается только после
    // pop(true).
    final confirmed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => TxConfirmScreen(
          recipient: recipient,
          amountSat: amountSat,
          rateSatVb: rate,
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _sending = true;
      _formError = null;
    });
    try {
      final result = await btcSend(
        recipient: recipient,
        amountSat: BigInt.from(amountSat),
        feeSatVb: BigInt.from(rate),
      );
      if (!mounted) return;
      await _showResult(result);
      if (!mounted) return;
      Navigator.of(context).pop(true); // портфель пересинхронизируется
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _formError = 'Ядро отклонило отправку: $e';
      });
    }
  }

  Future<void> _showResult(BtcSendResultDto result) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Транзакция отправлена'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (result.alreadyKnown)
                Container(
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: VColors.warning.withValues(alpha: 0.5)),
                    color: VColors.warning.withValues(alpha: 0.12),
                  ),
                  child: const Text(
                    'Эта транзакция уже была известна сети — повторная '
                    'отправка не выполнялась (идемпотентный broadcast).',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              VMonoCopyRow(label: 'TXID', value: result.txid),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                switch (result.status) {
                  'broadcast' =>
                    const VStatusChip('Отправлено в сеть', kind: VChipKind.success),
                  _ => VStatusChip('Статус: ${result.status}',
                      kind: VChipKind.info),
                },
              ]),
              const SizedBox(height: 10),
              Text(
                '${satToBtcString(result.amountSat.toInt())} BTC получателю',
                style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()]),
              ),
              Text(
                'Комиссия: ${satToBtcString(result.feeSat.toInt())} BTC '
                '(${groupDigits(result.feeSat.toInt())} сат, '
                '${result.vsize.toInt()} vSize, '
                '${result.feeSatPerVb.toInt()} sat/vB)',
                style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()]),
              ),
              if (result.changeAddress != null &&
                  (result.changeSat ?? BigInt.zero) > BigInt.zero)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: VMonoCopyRow(
                    label: 'Сдача',
                    value: '${satToBtcString(result.changeSat!.toInt())} BTC → '
                        '${result.changeAddress}',
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () =>
                copyToClipboard(dialogContext, 'TXID', result.txid),
            icon: const Icon(Icons.copy_outlined, size: 16),
            label: const Text('Копировать TXID'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Готово'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final available = widget.availableSat;
    return Scaffold(
      appBar: AppBar(title: const Text('Отправить BTC')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              VCard(
                title: 'Получатель',
                icon: Icons.person_outline,
                children: [
                  TextField(
                    controller: _recipientController,
                    autocorrect: false,
                    enableIMEPersonalizedLearning: false,
                    decoration: const InputDecoration(
                      labelText: 'Адрес (P2WPKH / P2SH / P2PKH / P2TR)',
                      hintText: 'tb1q…  для testnet, bc1q… для mainnet',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              VCard(
                title: 'Сумма',
                icon: Icons.payments_outlined,
                children: [
                  TextField(
                    controller: _amountController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    autocorrect: false,
                    enableIMEPersonalizedLearning: false,
                    decoration: InputDecoration(
                      labelText: 'Сумма, BTC',
                      hintText: '0.00010000',
                      suffixIcon: available != null && available > 0
                          ? TextButton(onPressed: _applyMax, child: const Text('Max'))
                          : null,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (available != null)
                    Text(
                      'Доступно: ${satToBtcString(available)} BTC '
                      '(${groupDigits(available)} сат) — снапшот последней '
                      'синхронизации; ядро потратит реальные UTXO.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  Text(
                    'Разбор суммы целочисленный (сатоши — u64). Точность — 8 '
                    'десятичных знаков.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildFeeCard(context),
              const SizedBox(height: 16),
              if (_formError != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: VColors.error.withValues(alpha: 0.4)),
                    color: VColors.error.withValues(alpha: 0.12),
                  ),
                  child: Text(_formError!,
                      style: TextStyle(color: VColors.error, fontSize: 13)),
                ),
              const SizedBox(height: 4),
              VButton.primary(
                _sending ? 'Подписание и broadcast…' : 'Отправить',
                icon: Icons.north_east,
                busy: _sending,
                onPressed: _sending ? null : _submit,
              ),
              const SizedBox(height: 8),
              Text(
                'Подпись выполняется локально в Rust (BIP143). Seed и '
                'приватные ключи не покидают ядро и не отправляются на сервер.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeeCard(BuildContext context) {
    final fees = _fees;
    return VCard(
      title: 'Комиссия и скорость',
      icon: Icons.speed_outlined,
      children: [
        if (_loadingFees)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_feesError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Пресеты сервера недоступны: $_feesError\n'
                'Введите ставку вручную (sat/vB).'),
          )
        else if (fees != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (fees.fallback)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Сервер не дал оценку комиссии — показаны консервативные '
                    'дефолты, а не измерение. Ставку можно ввести вручную.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall!
                        .copyWith(color: VColors.warning),
                  ),
                ),
              RadioGroup<_FeeChoice>(
                groupValue: _feeChoice,
                onChanged: (v) => setState(() => _feeChoice = v ?? _feeChoice),
                child: Column(
                  children: [
                    RadioListTile<_FeeChoice>(
                      value: _FeeChoice.fast,
                      title: Text('Быстро — ${fees.fastSatVb.toInt()} sat/vB'),
                    ),
                    RadioListTile<_FeeChoice>(
                      value: _FeeChoice.normal,
                      title: Text('Обычно — ${fees.normalSatVb.toInt()} sat/vB'),
                    ),
                    RadioListTile<_FeeChoice>(
                      value: _FeeChoice.slow,
                      title: Text('Медленно — ${fees.slowSatVb.toInt()} sat/vB'),
                    ),
                    RadioListTile<_FeeChoice>(
                      value: _FeeChoice.manual,
                      title: SizedBox(
                        width: 220,
                        child: TextField(
                          controller: _manualRateController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Своя ставка, sat/vB',
                            hintStyle: TextStyle(fontSize: 12),
                          ),
                          onTap: () {
                            if (_feeChoice != _FeeChoice.manual) {
                              setState(() => _feeChoice = _FeeChoice.manual);
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          )
        else
          TextField(
            controller: _manualRateController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Своя ставка, sat/vB',
            ),
          ),
        if (_feesError != null) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _manualRateController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Своя ставка, sat/vB',
            ),
          ),
        ],
      ],
    );
  }
}
