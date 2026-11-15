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
import 'package:veyro/util/l10n.dart';
import 'package:veyro/util/ui_helpers.dart';

import 'tx_confirm_screen.dart';

class SendScreen extends StatefulWidget {
  /// Реальный доступный баланс на момент последней синхронизации
  /// (confirmed + mempool-delta при отрицательной дельте). null —
  /// данных нет: кнопка Max честно скрыта.
  final int? availableSat;

  /// Точка замены для виджет-тестов (без RustLib): пресеты комиссии.
  final Future<BtcFeeRatesDto> Function()? feesLoader;

  const SendScreen({super.key, this.availableSat, this.feesLoader});

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
      error = t('err_recipient');
    } else if (amountSat == null) {
      error = t('err_amount');
    } else if (amountSat <= 0) {
      error = t('err_amount_positive');
    } else if (rate == null || rate <= 0) {
      error = t('err_fee_rate');
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
        _formError = tf(
          'err_send_rejected',
          {'error': '$e'},
        );
      });
    }
  }

  Future<void> _showResult(BtcSendResultDto result) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('tx_sent_title')),
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
                  child: Text(
                    t('tx_already_known'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              VMonoCopyRow(label: 'TXID', value: result.txid),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                switch (result.status) {
                  'broadcast' =>
                    VStatusChip(t('tx_broadcast_chip'), kind: VChipKind.success),
                  _ => VStatusChip(
                      tf(
                        'tx_status_chip',
                        {'status': result.status},
                      ),
                      kind: VChipKind.info),
                },
              ]),
              const SizedBox(height: 10),
              Text(
                tf(
                  'tx_to_recipient',
                  {'value': '${satToBtcString(result.amountSat.toInt())} BTC'},
                ),
                style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()]),
              ),
              Text(
                tf(
                  'tx_fee_row',
                  {
                    'btc': satToBtcString(result.feeSat.toInt()),
                    'sats': groupDigits(result.feeSat.toInt()),
                    'vsize': '${result.vsize.toInt()}',
                    'rate': '${result.feeSatPerVb.toInt()}',
                  },
                ),
                style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()]),
              ),
              if (result.changeAddress != null &&
                  (result.changeSat ?? BigInt.zero) > BigInt.zero)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: VMonoCopyRow(
                    label: t('change_label'),
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
            label: Text(t('copy_txid')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(t('done_btn')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final available = widget.availableSat;
    return Scaffold(
      appBar: AppBar(title: Text(t('send_title'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              VCard(
                title: t('recipient_card'),
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
                title: t('amount_card'),
                icon: Icons.payments_outlined,
                children: [
                  TextField(
                    controller: _amountController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    autocorrect: false,
                    enableIMEPersonalizedLearning: false,
                    decoration: InputDecoration(
                      labelText: t('amount_field'),
                      hintText: '0.00010000',
                      suffixIcon: available != null && available > 0
                          ? TextButton(onPressed: _applyMax, child: const Text('Max'))
                          : null,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (available != null)
                    Text(
                      tf(
                        'available_row',
                        {'value': satToBtcString(available)},
                      ),
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
                _sending ? t('sending_now') : t('send_submit_btn'),
                icon: Icons.north_east,
                busy: _sending,
                onPressed: _sending ? null : _submit,
              ),
              const SizedBox(height: 8),
              Text(
                t('sign_local_note'),
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
      title: t('fee_card'),
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
            child: Text(tf(
              'fees_error_note',
              {'error': '$_feesError'},
            )),
          )
        else if (fees != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (fees.fallback)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    t('fees_fallback_note'),
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
                      title: Text(tf(
                        'fee_fast',
                        {'rate': '${fees.fastSatVb.toInt()}'},
                      )),
                    ),
                    RadioListTile<_FeeChoice>(
                      value: _FeeChoice.normal,
                      title: Text(tf(
                        'fee_normal',
                        {'rate': '${fees.normalSatVb.toInt()}'},
                      )),
                    ),
                    RadioListTile<_FeeChoice>(
                      value: _FeeChoice.slow,
                      title: Text(tf(
                        'fee_slow',
                        {'rate': '${fees.slowSatVb.toInt()}'},
                      )),
                    ),
                    RadioListTile<_FeeChoice>(
                      value: _FeeChoice.manual,
                      title: SizedBox(
                        width: 220,
                        child: TextField(
                          controller: _manualRateController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: t('fee_manual_field'),
                            hintStyle: const TextStyle(fontSize: 12),
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
            decoration: InputDecoration(
              labelText: t('fee_manual_field'),
            ),
          ),
        if (_feesError != null) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _manualRateController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: t('fee_manual_field'),
            ),
          ),
        ],
      ],
    );
  }
}
