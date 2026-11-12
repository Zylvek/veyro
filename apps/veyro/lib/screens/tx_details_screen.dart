//! Экран 17 спеки: Transaction details. Показывает ровно то, что ядро
//! отдало в истории (TXID/направление/суммы/высота), догоняет live-статус
//! дешёвым btcTxStatus и даёт explorer-ссылку для BTC-сетей. Поля, которых
//! в данных нет (время, адреса), помечаются «—» с честным объяснением —
//! никаких выдумок.

import 'package:flutter/material.dart';

import 'package:veyro/design/app_colors.dart';
import 'package:veyro/design/components.dart';
import 'package:veyro/src/rust/api/btc.dart';
import 'package:veyro/src/rust/api/session.dart';
import 'package:veyro/util/format.dart';
import 'package:veyro/util/links.dart';

/// Общие подписи направлений истории (используются также экраном истории).
String directionLabel(String direction) {
  switch (direction) {
    case 'incoming':
      return 'Получение';
    case 'outgoing':
      return 'Отправка';
    case 'internal':
      return 'Внутри кошелька';
    default:
      return 'Направление: $direction';
  }
}

IconData directionIcon(String direction) {
  switch (direction) {
    case 'incoming':
      return Icons.south_west;
    case 'outgoing':
      return Icons.north_east;
    case 'internal':
      return Icons.swap_horiz;
    default:
      return Icons.help_outline;
  }
}

/// Название сети по коду ядра (util/network_config.dart); для прочих — null.
String? networkName(int? networkCode) {
  switch (networkCode) {
    case 0:
      return 'Bitcoin mainnet';
    case 1:
      return 'Bitcoin Testnet 3';
    case 2:
      return 'Bitcoin Testnet 4';
    default:
      return null;
  }
}

class TxDetailsScreen extends StatefulWidget {
  final BtcHistoryItemDto item;

  /// Код сети для explorer-ссылки (из активной сессии, если известен).
  final int? networkCode;

  /// Точка замены для виджет-тестов (без RustLib): live-статус транзакции.
  final Future<BtcTxStatusDto> Function(String txid)? statusLoader;

  const TxDetailsScreen({
    super.key,
    required this.item,
    this.networkCode,
    this.statusLoader,
  });

  @override
  State<TxDetailsScreen> createState() => _TxDetailsScreenState();
}

class _TxDetailsScreenState extends State<TxDetailsScreen> {
  BtcTxStatusDto? _status;
  bool _statusLoading = false;
  String? _statusError;
  int? _networkCode;

  @override
  void initState() {
    super.initState();
    _networkCode = widget.networkCode;
    _loadStatus();
    _resolveNetwork();
  }

  Future<void> _resolveNetwork() async {
    if (_networkCode != null) return;
    try {
      final session = await btcSessionState();
      if (!mounted) return;
      setState(() => _networkCode = session?.networkCode);
    } catch (_) {
      // Сеть остаётся неизвестной — explorer-карта покажет честное «—».
    }
  }

  Future<void> _loadStatus() async {
    setState(() {
      _statusLoading = true;
      _statusError = null;
    });
    try {
      final loader = widget.statusLoader ?? (txid) => btcTxStatus(txid: txid);
      final status = await loader(widget.item.txid);
      if (!mounted) return;
      setState(() {
        _status = status;
        _statusLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = null;
        _statusLoading = false;
        _statusError = e.toString();
      });
    }
  }

  String get _amountText {
    final item = widget.item;
    switch (item.direction) {
      case 'incoming':
        return '+${satToBtcString(item.receivedSat.toInt())}';
      case 'outgoing':
        return '-${satToBtcString(item.sentNetSat.toInt())}';
      case 'internal':
        return '0';
      default:
        return '—';
    }
  }

  String get _directionNote {
    switch (widget.item.direction) {
      case 'incoming':
        return 'Сумма получена на адреса кошелька: '
            '${groupDigits(widget.item.receivedSat.toInt())} сат.';
      case 'outgoing':
        return 'Чистый уход с кошелька (с учётом возврата сдачи): '
            '${groupDigits(widget.item.sentNetSat.toInt())} сат.';
      case 'internal':
        return 'Перевод между своими адресами: чистая сумма по кошельку '
            'равна нулю.';
      default:
        return 'Направление «${widget.item.direction}» отдало ядро — '
            'суммы проверьте в explorer по TXID.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final inMempool = item.height < 1; // −1 = mempool (см. FFI-док).
    return Scaffold(
      appBar: AppBar(title: const Text('Детали транзакции')),
      body: RefreshIndicator(
        onRefresh: _loadStatus,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                _buildHeadCard(context),
                const SizedBox(height: 12),
                _buildStatusCard(context, inMempool),
                const SizedBox(height: 12),
                _buildExplorerCard(context),
                const SizedBox(height: 12),

              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String key, String value,
      {bool mono = false, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(key, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: mono
                ? VMono(value, fontSize: 12.5, color: valueColor)
                : Text(value,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium!
                        .copyWith(color: valueColor)),
          ),
        ],
      ),
    );
  }

  Widget _buildHeadCard(BuildContext context) {
    final item = widget.item;
    return VCard(
      title: 'Транзакция',
      icon: Icons.receipt_long_outlined,
      children: [
        Row(
          children: [
            Icon(directionIcon(item.direction),
                size: 20, color: VColors.textSecondary),
            const SizedBox(width: 8),
            Text(directionLabel(item.direction),
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 10),
        VMonoCopyRow(label: 'TXID', value: item.txid),
        const SizedBox(height: 8),
        VAmount(_amountText,
            suffix: item.direction == 'internal'
                ? null
                : 'BTC',
            fontSize: 26),
        const SizedBox(height: 4),
        Text(_directionNote, style: Theme.of(context).textTheme.bodySmall),
        const Divider(height: 24),
        _row(context, 'Высота блока',
            item.height >= 1 ? '${item.height}' : '— (в мемпуле)'),
        _row(
          context,
          'Комиссия',
          item.feeSat != null
              ? '${satToBtcString(item.feeSat!.toInt())} BTC '
                  '(${groupDigits(item.feeSat!.toInt())} сат)'
              : '—',
        ),
      ],
    );
  }

  Widget _buildStatusCard(BuildContext context, bool inMempool) {
    final status = _status;
    return VCard(
      title: 'Статус (запрос в ядро)',
      icon: Icons.verified_outlined,
      children: [
        if (_statusLoading)
          const Padding(
            padding: EdgeInsets.all(10),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_statusError != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Статус не прочитан: $_statusError',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall!
                      .copyWith(color: VColors.error)),
              const SizedBox(height: 8),
              VButton.secondary('Повторить запрос',
                  onPressed: _loadStatus),
            ],
          )
        else if (status == null)
          Text('—', style: Theme.of(context).textTheme.bodyMedium)
        else ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              switch (status.state) {
                'confirmed' => const VStatusChip('Подтверждено сетью',
                    kind: VChipKind.success),
                'mempool' => const VStatusChip('В мемпуле — не подтверждено',
                    kind: VChipKind.warning),
                'unknown' => const VStatusChip(
                    'Не найдено на сервере', kind: VChipKind.error),
                _ => VStatusChip('Статус: ${status.state}',
                    kind: VChipKind.neutral),
              },
            ],
          ),
          const SizedBox(height: 10),
          _row(context, 'Подтверждения', status.confirmations?.toString() ?? '—'),
          _row(context, 'Высота (сервер)', status.height?.toString() ?? '—'),
          const SizedBox(height: 6),

        ],
        if (status == null && !_statusLoading && _statusError == null)
          const SizedBox.shrink(),
        if (inMempool && status?.state == 'confirmed')
          const SizedBox.shrink(),
      ],
    );
  }

  Widget _buildExplorerCard(BuildContext context) {
    final code = _networkCode;
    final url = code == null ? null : explorerTxUrl(code, widget.item.txid);
    return VCard(
      title: 'Сеть и explorer',
      icon: Icons.public_outlined,
      children: [
        _row(context, 'Сеть', networkName(code) ?? '— (сеть не определена)'),
        const SizedBox(height: 8),
        if (url != null) ...[
          VMonoCopyRow(label: 'Explorer', value: url),
          const SizedBox(height: 6),

        ] else
          Text(
            'Explorer для этой сети не настроен ($kBtcExplorerName '
            'поддерживает сети mainnet/testnet3/testnet4).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }

}
