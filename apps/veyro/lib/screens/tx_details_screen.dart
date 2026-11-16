//! Экран 17 спеки: Transaction details. Показывает ровно то, что ядро
//! отдало в истории (TXID/направление/суммы/высота), догоняет live-статус
//! дешёвым btcTxStatus и даёт explorer-ссылку для BTC-сетей. Поля, которых
//! в данных нет (время, адреса), помечаются «—» с честным объяснением —
//! никаких выдумок.

import 'package:flutter/material.dart';

import 'package:veyro/design/app_colors.dart';
import 'package:veyro/design/components.dart';
import 'package:veyro/design/veyro_mark.dart';
import 'package:veyro/src/rust/api/btc.dart';
import 'package:veyro/src/rust/api/bch.dart';
import 'package:veyro/src/rust/api/rvn.dart';
import 'package:veyro/src/rust/api/xec.dart';
import 'package:veyro/src/rust/api/ltc.dart';
import 'package:veyro/src/rust/api/session.dart';

import 'package:veyro/util/coin.dart';
import 'package:veyro/util/format.dart';
import 'package:veyro/util/l10n.dart';
import 'package:veyro/util/links.dart';
import 'package:veyro/util/network_names.dart';

/// Общие подписи направлений истории (используются также экраном истории).
String directionLabel(String direction) {
  switch (direction) {
    case 'incoming':
      return t('dir_incoming');
    case 'outgoing':
      return t('dir_outgoing');
    case 'internal':
      return t('tx_internal_short');
    default:
      return tf('direction_row', {'dir': direction});
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

/// Название сети по коду ядра, локализованное (для прочих — null).
String? networkName(int? networkCode) {
  switch (networkCode) {
    case 0:
      return ruNetworkText('Bitcoin mainnet');
    case 1:
      return ruNetworkText('Bitcoin testnet3');
    case 2:
      return ruNetworkText('Bitcoin testnet4');
    default:
      return null;
  }
}

class TxDetailsScreen extends StatefulWidget {
  final BtcHistoryItemDto item;

  /// Монета записи (BTC или LTC) — меняет статус-запрос, суффикс суммы и
  /// explorer-карту.
  final WalletCoin coin;

  /// Код сети для explorer-ссылки (из активной сессии, если известен).
  final int? networkCode;

  /// Точка замены для виджет-тестов (без RustLib): live-статус транзакции.
  final Future<BtcTxStatusDto> Function(String txid)? statusLoader;

  const TxDetailsScreen({
    super.key,
    required this.item,
    this.coin = WalletCoin.btc,
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
    // LTC-провод не нуждается в коде сети (свой explorer); код BTC-сессии
    // к LTC-записи отношения не имеет — не подмешиваем чужое.
    if (_networkCode != null ||
        widget.coin == WalletCoin.ltc ||
        widget.coin == WalletCoin.bch ||
        widget.coin == WalletCoin.xec ||
        widget.coin == WalletCoin.rvn) {
      return;
    }
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
      late final Future<BtcTxStatusDto> Function(String txid) loader;
      if (widget.statusLoader != null) {
        loader = widget.statusLoader!;
      } else if (widget.coin == WalletCoin.xec) {
        loader = (txid) async {
          // XecTxStatusDto и BtcTxStatusDto структурно одинаковы; общий
          // тип UI-состояния — BTC-класс (контракт 1:1 с BCH-веткой).
          final s = await xecTxStatus(txid: txid);
          return BtcTxStatusDto(
            state: s.state,
            height: s.height,
            confirmations: s.confirmations,
            txid: s.txid,
          );
        };
      } else if (widget.coin == WalletCoin.rvn) {
        loader = (txid) async {
          // RvnTxStatusDto и BtcTxStatusDto структурно одинаковы; общий
          // тип UI-состояния — BTC-класс (контракт 1:1 с LTC-веткой).
          final s = await rvnTxStatus(txid: txid);
          return BtcTxStatusDto(
            state: s.state,
            height: s.height,
            confirmations: s.confirmations,
            txid: s.txid,
          );
        };
      } else if (widget.coin == WalletCoin.bch) {
        loader = (txid) async {
          // BchTxStatusDto и BtcTxStatusDto структурно одинаковы; общий
          // тип UI-состояния — BTC-класс (контракт 1:1 с LTC-веткой).
          final s = await bchTxStatus(txid: txid);
          return BtcTxStatusDto(
            state: s.state,
            height: s.height,
            confirmations: s.confirmations,
            txid: s.txid,
          );
        };
      } else if (widget.coin == WalletCoin.ltc) {
        loader = (txid) async {
          // LtcTxStatusDto и BtcTxStatusDto структурно одинаковы; общий
          // тип UI-состояния — BTC-класс (исторический контракт тестов).
          final s = await ltcTxStatus(txid: txid);
          return BtcTxStatusDto(
            state: s.state,
            height: s.height,
            confirmations: s.confirmations,
            txid: s.txid,
          );
        };
      } else {
        loader = (txid) => btcTxStatus(txid: txid);
      }
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
    final fmt = widget.coin == WalletCoin.xec
        ? satToXecString
        : satToBtcString;
    switch (item.direction) {
      case 'incoming':
        return '+${fmt(item.receivedSat.toInt())}';
      case 'outgoing':
        return '-${fmt(item.sentNetSat.toInt())}';
      case 'internal':
        return '0';
      default:
        return '—';
    }
  }

  String get _directionNote {
    switch (widget.item.direction) {
      case 'incoming':
        return tf('summary_incoming', {
          'value': groupDigits(widget.item.receivedSat.toInt()),
        });
      case 'outgoing':
        return tf('summary_outgoing', {
          'value': groupDigits(widget.item.sentNetSat.toInt()),
        });
      case 'internal':
        return t('summary_internal');
      default:
        return tf('summary_unknown', {'dir': widget.item.direction});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('tx_details_title'))),
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
                _buildStatusCard(context),
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

  Widget _row(
    BuildContext context,
    String key,
    String value, {
    bool mono = false,
    Color? valueColor,
  }) {
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
                : Text(
                    value,
                    style: Theme.of(context).textTheme.bodyMedium!
                        .copyWith(color: valueColor),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeadCard(BuildContext context) {
    final item = widget.item;
    return VCard(
      title: t('tx_card'),
      icon: Icons.receipt_long_outlined,
      children: [
        Row(
          children: [
            Icon(
              directionIcon(item.direction),
              size: 20,
              color: VColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              directionLabel(item.direction),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 10),
        VMonoCopyRow(label: 'TXID', value: item.txid),
        const SizedBox(height: 8),
        VAmount(
          _amountText,
          suffix: item.direction == 'internal'
              ? null
              : widget.coin.unit,
          fontSize: 26,
        ),
        const SizedBox(height: 4),
        Text(_directionNote, style: Theme.of(context).textTheme.bodySmall),
        const Divider(height: 24),
        _row(
          context,
          t('block_height_row'),
          item.height >= 1 ? '${item.height}' : t('in_mempool_short'),
        ),
        _row(
          context,
          t('fee_row_label'),
          switch (widget.coin) {
            WalletCoin.ltc => item.feeSat != null
                ? tf('tx_fee_row_ltc', {
                    'ltc': satToBtcString(item.feeSat!.toInt()),
                    'sats': groupDigits(item.feeSat!.toInt()),
                  })
                : '—',
            WalletCoin.xec => item.feeSat != null
                ? tf('tx_fee_row_xec', {
                    'xec': satToXecString(item.feeSat!.toInt()),
                    'sats': groupDigits(item.feeSat!.toInt()),
                  })
                : '—',
            WalletCoin.rvn => item.feeSat != null
                ? tf('tx_fee_row_rvn', {
                    'rvn': satToBtcString(item.feeSat!.toInt()),
                    'sats': groupDigits(item.feeSat!.toInt()),
                  })
                : '—',
            WalletCoin.bch => item.feeSat != null
                ? tf('tx_fee_row_bch', {
                    'bch': satToBtcString(item.feeSat!.toInt()),
                    'sats': groupDigits(item.feeSat!.toInt()),
                  })
                : '—',
            _ => item.feeSat != null
                ? tf('tx_fee_row_btc', {
                    'btc': satToBtcString(item.feeSat!.toInt()),
                    'sats': groupDigits(item.feeSat!.toInt()),
                  })
                : '—',
          },
        ),
      ],
    );
  }

  Widget _buildStatusCard(BuildContext context) {
    final status = _status;
    return VCard(
      title: t('status_card'),
      icon: Icons.verified_outlined,
      children: [
        if (_statusLoading)
          Padding(
            padding: const EdgeInsets.all(10),
            child: Center(
              child: LogoLoader(mode: LogoLoaderMode.loading, size: 44),
            ),
          )
        else if (_statusError != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tf('status_read_error', {'error': '$_statusError'}),
                style: Theme.of(context).textTheme.bodySmall!
                    .copyWith(color: VColors.error),
              ),
              const SizedBox(height: 8),
              VButton.secondary(t('retry_query_btn'), onPressed: _loadStatus),
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
                'confirmed' => VStatusChip(
                  t('status_confirmed'),
                  kind: VChipKind.success,
                ),
                'mempool' => VStatusChip(
                  t('status_mempool'),
                  kind: VChipKind.warning,
                ),
                'unknown' => VStatusChip(
                  t('status_not_found'),
                  kind: VChipKind.error,
                ),
                _ => VStatusChip(
                  tf('tx_status_chip', {'status': status.state}),
                  kind: VChipKind.neutral,
                ),
              },
            ],
          ),
          const SizedBox(height: 10),
          _row(
            context,
            t('confirmations_row'),
            status.confirmations?.toString() ?? '—',
          ),
          _row(
            context,
            t('server_height_row'),
            status.height?.toString() ?? '—',
          ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }

  Widget _buildExplorerCard(BuildContext context) {
    final coin = widget.coin;
    final code = _networkCode;
    final url = switch (coin) {
      WalletCoin.ltc => ltcTxUrl(widget.item.txid),
      WalletCoin.xec => xecTxUrl(widget.item.txid),
      WalletCoin.rvn => rvnTxUrl(widget.item.txid),
      WalletCoin.bch => bchTxUrl(widget.item.txid),
      _ => code == null ? null : explorerTxUrl(code, widget.item.txid),
    };
    final explorerName = switch (coin) {
      WalletCoin.ltc => kLtcExplorerName,
      WalletCoin.xec => kXecExplorerName,
      WalletCoin.rvn => kRvnExplorerName,
      WalletCoin.bch => kBchExplorerName,
      _ => kBtcExplorerName,
    };
    return VCard(
      title: t('network_explorer_card'),
      icon: Icons.public_outlined,
      children: [
        _row(
          context,
          t('network_label'),
          switch (widget.coin) {
            WalletCoin.ltc =>
              (ruNetworkText('Litecoin mainnet') ?? 'Litecoin mainnet'),
            WalletCoin.xec =>
              (ruNetworkText('eCash mainnet') ?? 'eCash mainnet'),
            WalletCoin.rvn =>
              (ruNetworkText('Ravencoin mainnet') ?? 'Ravencoin mainnet'),
            WalletCoin.bch =>
              (ruNetworkText('Bitcoin Cash mainnet') ?? 'Bitcoin Cash mainnet'),
            _ => networkName(code) ?? t('network_unknown'),
          },
        ),
        const SizedBox(height: 8),
        if (url != null) ...[
          VMonoCopyRow(label: 'Explorer', value: url),
          const SizedBox(height: 6),
        ] else
          Text(
            tf('explorer_note', {'name': explorerName}),
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}
