//! Экран 5: отправка. Адрес получателя + сумма (BTC → сатоши целочисленно) +
//! комиссия (пресеты сервера из btc_fees или ручная sat/vB) → подтверждение →
//! btc_send (план, локальная подпись BIP143, идемпотентный broadcast в Rust).
//! После успеха показываем txid/комиссию/статус и заставляем портфель
//! пересинхронизироваться (Rust сам очистил набор UTXO от повторной отправки).

import 'package:flutter/material.dart';

import 'package:veyro/src/rust/api/btc.dart';
import 'package:veyro/util/format.dart';
import 'package:veyro/util/ui_helpers.dart';

class SendScreen extends StatefulWidget {
  const SendScreen({super.key});

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
      final fees = await btcFees();
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

    final confirmed = await confirmAction(
      context,
      title: 'Подтвердите отправку',
      body: 'Получатель: $recipient\n\n'
          'Сумма: ${satToBtcString(amountSat)} BTC '
          '(${groupDigits(amountSat)} сат)\n'
          'Ставка комиссии: $rate sat/vB (комиссия будет рассчитана в ядре '
          'по реальным UTXO и показана в результате).\n\n'
          'Отправка необратима.',
      confirmLabel: 'Подписать и отправить',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

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
                    color: Colors.orange.withValues(alpha: 0.15),
                  ),
                  child: const Text(
                    'Эта транзакция уже была известна сети — повторная отправка '
                    'не выполнялась (идемпотентный broadcast).',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              const Text('TXID', style: TextStyle(color: Colors.white60, fontSize: 12)),
              SelectableText(result.txid,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              const SizedBox(height: 8),
              Text(
                '${satToBtcString(result.amountSat.toInt())} BTC получателю',
              ),
              Text(
                'Комиссия: ${satToBtcString(result.feeSat.toInt())} BTC '
                '(${groupDigits(result.feeSat.toInt())} сат, '
                '${result.vsize.toInt()} vSize, '
                '${result.feeSatPerVb.toInt()} sat/vB)',
              ),
              if (result.changeAddress != null &&
                  (result.changeSat ?? BigInt.zero) > BigInt.zero)
                Text(
                  'Сдача: ${satToBtcString(result.changeSat!.toInt())} BTC → '
                  '${result.changeAddress}',
                ),
              const SizedBox(height: 8),
              Text('Статус: ${result.status}'),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () =>
                copyToClipboard(dialogContext, 'TXID', result.txid),
            icon: const Icon(Icons.copy_outlined),
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
    return Scaffold(
      appBar: AppBar(title: const Text('Отправить BTC')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SectionCard(
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
              SectionCard(
                title: 'Сумма',
                icon: Icons.payments_outlined,
                children: [
                  TextField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    autocorrect: false,
                    enableIMEPersonalizedLearning: false,
                    decoration: const InputDecoration(
                      labelText: 'Сумма, BTC',
                      hintText: '0.00010000',
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Разбор суммы целочисленный (сатоши — u64). Точность — 8 '
                    'десятичных знаков.',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
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
                    color: Colors.red.shade900.withValues(alpha: 0.3),
                  ),
                  child: Text(_formError!, style: const TextStyle(color: Colors.white)),
                ),
              const SizedBox(height: 4),
              FilledButton.icon(
                onPressed: _sending ? null : _submit,
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.north_east),
                label: Text(_sending ? 'Подпись и broadcast…' : 'Отправить'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Подпись выполняется локально в Rust (BIP143). Seed и приватные '
                'ключи не покидают ядро и не отправляются на сервер.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeeCard(BuildContext context) {
    final fees = _fees;
    return SectionCard(
      title: 'Комиссия',
      icon: Icons.speed_outlined,
      children: [
        if (_loadingFees)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_feesError != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Пресеты сервера недоступны: $_feesError\n'
                  'Введите ставку вручную (sat/vB).'),
            ],
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (fees!.fallback)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Сервер не дал оценку комиссии — показаны консервативные '
                    'дефолты, а не измерение. Ставку можно ввести вручную.',
                    style: TextStyle(color: Colors.amber.shade200, fontSize: 12),
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
                        width: 200,
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
          ),
        if (_feesError != null || _fees == null)
          TextField(
            controller: _manualRateController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Своя ставка, sat/vB',
            ),
          ),
      ],
    );
  }
}
