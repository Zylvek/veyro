//! Экран 16 спеки: History — фильтры (Все/Входящие/Исходящие/Ожидающие/
//! Подтверждённые; «Неудачные» честно отключены — ядро не отдаёт неуспешные
//! в истории), поиск по TXID (адресов в данных истории нет — честная
//! пометка), переход в детали (экран 17). Данные — только btcHistory /
//! ltcHistory (walletCoin); история собирается синхронизацией адресов
//! (btcSync / ltcSync) — сетевая операция, запускается только действием
//! пользователя.

import 'package:flutter/material.dart';

import 'package:veyro/design/app_colors.dart';
import 'package:veyro/design/components.dart';
import 'package:veyro/design/motion.dart';
import 'package:veyro/design/veyro_mark.dart';
import 'package:veyro/src/rust/api/btc.dart';
import 'package:veyro/src/rust/api/bch.dart';
import 'package:veyro/src/rust/api/rvn.dart';
import 'package:veyro/src/rust/api/xec.dart';
import 'package:veyro/src/rust/api/ltc.dart';
import 'package:veyro/src/rust/api/session.dart';
import 'package:veyro/util/format.dart';
import 'package:veyro/util/l10n.dart';
import 'package:veyro/util/network.dart';

import 'tx_details_screen.dart';

import 'package:veyro/util/coin.dart';

/// Фильтры истории. failed есть в enum, но в UI отключён: история ядра
/// не содержит неуспешных транзакций (broadcast неудачных отклоняется до
/// попадания в историю) — выдавать пустой фильтр за рабочий нельзя.
enum HistoryFilter { all, incoming, outgoing, pending, confirmed, failed }

class HistoryScreen extends StatefulWidget {
  /// Монета истории (BTC дефолт — исторический контракт тестов).
  final WalletCoin walletCoin;

  /// Точки замены для виджет-тестов (без RustLib).
  final Future<List<BtcHistoryItemDto>> Function()? historyLoader;
  final Future<void> Function()? syncLoader;
  final Future<BtcSessionStateDto?> Function()? sessionLoader;

  const HistoryScreen({
    super.key,
    this.walletCoin = WalletCoin.btc,
    this.historyLoader,
    this.syncLoader,
    this.sessionLoader,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<BtcHistoryItemDto>? _items;
  bool _loading = true;
  bool _syncing = false;
  String? _error;
  HistoryFilter _filter = HistoryFilter.all;
  String _query = '';
  int? _networkCode;

  /// Честное усечение: ядро показывает только самые свежие записи, когда
  /// вся история длиннее MAX_HISTORY_ITEMS.
  bool _truncated = false;
  int _totalEntries = 0;
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(
      () =>
          setState(() => _query = _searchController.text.trim().toLowerCase()),
    );
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    // Код сети нужен для explorer-ссылки в деталях; падение не критично.
    try {
      int? code;
      if (widget.sessionLoader != null) {
        final session = await widget.sessionLoader!();
        code = session?.networkCode;
      } else if (widget.walletCoin == WalletCoin.ltc ||
          widget.walletCoin == WalletCoin.bch ||
          widget.walletCoin == WalletCoin.xec ||
          widget.walletCoin == WalletCoin.rvn) {
        // LTC/BCH/XEC: сеть одна (mainnet) — код сети в сессии смысла не
        // имеет, детали берут эксплорер монеты напрямую.
        code = null;
      } else {
        code = (await btcSessionState())?.networkCode;
      }
      if (mounted) setState(() => _networkCode = code);
    } catch (_) {
      // Сеть неизвестна — детали покажут честное «—».
    }
    try {
      List<BtcHistoryItemDto> items;
      int totalEntries = 0;
      bool truncated = false;
      if (widget.historyLoader != null) {
        items = await widget.historyLoader!();
      } else if (widget.walletCoin == WalletCoin.xec) {
        // XecHistoryItemDto структурно одинаков с BtcHistoryItemDto —
        // приводим к общему типу экрана (контракт 1:1 с BCH-веткой).
        final history = await xecHistory();
        items = history.items
            .map((h) => BtcHistoryItemDto(
                  txid: h.txid,
                  height: h.height,
                  direction: h.direction,
                  receivedSat: h.receivedSat,
                  sentNetSat: h.sentNetSat,
                  feeSat: h.feeSat,
                ))
            .cast<BtcHistoryItemDto>()
            .toList();
        totalEntries = history.totalEntries.toInt();
        truncated = history.truncated;
      } else if (widget.walletCoin == WalletCoin.rvn) {
        // RvnHistoryItemDto структурно одинаков с BtcHistoryItemDto —
        // приводим к общему типу экрана (контракт 1:1 с BTC-веткой).
        final history = await rvnHistory();
        items = history.items
            .map((h) => BtcHistoryItemDto(
                  txid: h.txid,
                  height: h.height,
                  direction: h.direction,
                  receivedSat: h.receivedSat,
                  sentNetSat: h.sentNetSat,
                  feeSat: h.feeSat,
                ))
            .cast<BtcHistoryItemDto>()
            .toList();
        totalEntries = history.totalEntries.toInt();
        truncated = history.truncated;
      } else if (widget.walletCoin == WalletCoin.bch) {
        // BchHistoryItemDto структурно одинаков с BtcHistoryItemDto —
        // приводим к общему типу экрана (контракт 1:1 с LTC-веткой).
        final history = await bchHistory();
        items = history.items
            .map((h) => BtcHistoryItemDto(
                  txid: h.txid,
                  height: h.height,
                  direction: h.direction,
                  receivedSat: h.receivedSat,
                  sentNetSat: h.sentNetSat,
                  feeSat: h.feeSat,
                ))
            .cast<BtcHistoryItemDto>()
            .toList();
      } else if (widget.walletCoin == WalletCoin.ltc) {
        // LtcHistoryItemDto структурно одинаков с BtcHistoryItemDto —
        // приводим к общему типу экрана (исторический контракт тестов).
        final history = await ltcHistory();
        items = history.items
            .map(
              (e) => BtcHistoryItemDto(
                txid: e.txid,
                height: e.height,
                direction: e.direction,
                receivedSat: e.receivedSat,
                sentNetSat: e.sentNetSat,
                feeSat: e.feeSat,
              ),
            )
            .toList();
        totalEntries = history.totalEntries.toInt();
        truncated = history.truncated;
      } else {
        final history = await btcHistory();
        items = history.items;
        totalEntries = history.totalEntries.toInt();
        truncated = history.truncated;
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _truncated = truncated;
        _totalEntries = totalEntries;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Синхронизация прямо отсюда: история требует сканирования адресов.
  Future<void> _syncThenLoad() async {
    setState(() => _syncing = true);
    try {
      final loader = widget.syncLoader;
      if (loader != null) {
        await loader();
      } else if (widget.walletCoin == WalletCoin.bch) {
        await bchSync(gapLimit: kDefaultGapLimit);
      } else if (widget.walletCoin == WalletCoin.xec) {
        await xecSync(gapLimit: kDefaultGapLimit);
      } else if (widget.walletCoin == WalletCoin.rvn) {
        await rvnSync(gapLimit: kDefaultGapLimit);
      } else if (widget.walletCoin == WalletCoin.ltc) {
        await ltcSync(gapLimit: kDefaultGapLimit);
      } else {
        await btcSync(gapLimit: kDefaultGapLimit);
      }
      if (!mounted) return;
      setState(() => _syncing = false);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _syncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tf('sync_error_snackbar', {'error': '$e'}))),
      );
    }
  }

  /// Фильтр из данных ядра — без догадок: pending = height < 1 (−1 = mempool),
  /// confirmed = height >= 1.
  List<BtcHistoryItemDto> get _visibleItems {
    final items = _items ?? const [];
    final query = _query;
    return items.where((item) {
      switch (_filter) {
        case HistoryFilter.all:
          break;
        case HistoryFilter.incoming:
          if (item.direction != 'incoming') return false;
        case HistoryFilter.outgoing:
          if (item.direction != 'outgoing') return false;
        case HistoryFilter.pending:
          if (item.height >= 1) return false;
        case HistoryFilter.confirmed:
          if (item.height < 1) return false;
        case HistoryFilter.failed:
          // Неуспешных в истории ядра нет (см. enum-док).
          return false;
      }
      if (query.isEmpty) return true;
      return item.txid.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(switch (widget.walletCoin) {
          WalletCoin.ltc => t('history_title_ltc'),
          WalletCoin.bch => t('history_title_bch'),
          WalletCoin.xec => t('history_title_xec'),
          WalletCoin.rvn => t('history_title_rvn'),
          _ => t('history_title'),
        }),
        actions: [
          IconButton(
            tooltip: t('sync_refresh_tooltip'),
            onPressed: _syncing ? null : _syncThenLoad,
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: _buildBody(context),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading || _syncing || _items == null && !_hasError) {
      // Фирменная загрузка знака (система владельца), мини-версия.
      return const Center(
        child: LogoLoader(mode: LogoLoaderMode.loading, size: 44),
      );
    }
    if (_hasError) {
      final needsSync =
          _error!.contains('btc_sync first') ||
          _error!.contains('ltc_sync first') ||
          _error!.contains('no scanned addresses');
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.sync_problem_outlined,
              size: 40,
              color: VColors.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              needsSync
                  ? t('history_need_sync')
                  : tf('error_prefix', {'error': '$_error'}),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            VButton.primary(
              t('history_sync_btn'),
              icon: Icons.sync,
              onPressed: _syncThenLoad,
            ),
          ],
        ),
      );
    }
    final items = _items ?? const [];
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.receipt_long_outlined,
              size: 44,
              color: VColors.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              t('history_empty'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            VButton.secondary(
              t('sync_btn'),
              icon: Icons.sync,
              onPressed: _syncThenLoad,
            ),
          ],
        ),
      );
    }
    final visible = _visibleItems;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocus,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_outlined),
              labelText: t('search_txid'),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear_outlined, size: 18),
                      onPressed: () => _searchController.clear(),
                    ),
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _filterChip(context, t('filter_all'), HistoryFilter.all),
              _filterChip(
                context,
                t('filter_incoming'),
                HistoryFilter.incoming,
              ),
              _filterChip(
                context,
                t('filter_outgoing'),
                HistoryFilter.outgoing,
              ),
              _filterChip(context, t('filter_pending'), HistoryFilter.pending),
              _filterChip(
                context,
                t('filter_confirmed'),
                HistoryFilter.confirmed,
              ),
              _failedChip(context),
            ],
          ),
        ),
        if (_truncated)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Row(
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: 14,
                  color: VColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    tf('history_truncated_note', {
                      'shown': '${_items?.length ?? 0}',
                      'total': '$_totalEntries',
                    }),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: visible.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 48),
                      VEmptyState(
                        icon: Icons.search_off,
                        title: t('nothing_found'),
                        message: t('nothing_found_msg'),
                      ),
                      Center(
                        child: TextButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _filter = HistoryFilter.all);
                          },
                          child: Text(t('reset_filters')),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(12),
                    itemCount: visible.length,
                    itemBuilder: (itemContext, index) {
                      final item = visible[index];
                      final card = _buildTileData(item);
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: card.color.withValues(alpha: 0.18),
                            foregroundColor: card.color,
                            child: Icon(card.icon, size: 20),
                          ),
                          title: Text(
                            card.amountText,
                            style: TextStyle(
                              color: card.color,
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          subtitle: Text(
                            '${card.directionText} · ${_heightText(item.height)}'
                            '${card.feeText}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          trailing: const Icon(
                            Icons.chevron_right,
                            size: 16,
                            color: VColors.textSecondary,
                          ),
                          onTap: () => pushVeyro<void>(
                            context,
                            TxDetailsScreen(
                              item: item,
                              coin: widget.walletCoin,
                              networkCode: _networkCode,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  bool get _hasError => _error != null;

  Widget _filterChip(BuildContext context, String label, HistoryFilter filter) {
    final selected = _filter == filter;
    return FilterChip(
      selected: selected,
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          color: selected ? VColors.primary : VColors.textSecondary,
        ),
      ),
      showCheckmark: false,
      side: BorderSide(
        color: selected
            ? VColors.primary.withValues(alpha: 0.5)
            : VColors.elevated,
      ),
      backgroundColor: VColors.card,
      selectedColor: VColors.elevated,
      onSelected: (_) => setState(() => _filter = filter),
    );
  }

  /// «Неудачные» — честно отключённый фильтр с объяснением: ядро не отдаёт
  /// неуспешные в истории, включать его как «рабочий» нельзя.
  Widget _failedChip(BuildContext context) {
    return Tooltip(
      message: t('failed_chip_tooltip'),
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.45,
          child: FilterChip(
            selected: false,
            label: Text(
              t('filter_failed'),
              style: TextStyle(fontSize: 12.5, color: VColors.textSecondary),
            ),
            showCheckmark: false,
            side: const BorderSide(color: VColors.elevated),
            backgroundColor: VColors.card,
            onSelected: (_) {},
          ),
        ),
      ),
    );
  }

  String _heightText(int height) =>
      height >= 1 ? tf('height_n', {'height': '$height'}) : t('in_mempool');

  ({
    IconData icon,
    Color color,
    String amountText,
    String directionText,
    String feeText,
  })
  _buildTileData(BtcHistoryItemDto item) {
    const unknown = (
      icon: Icons.help_outline,
      color: VColors.textSecondary,
      amountText: '—',
      directionText: '',
    );
    final unit = widget.walletCoin.unit;
    String amt(int sat) => widget.walletCoin == WalletCoin.xec
        ? satToXecString(sat)
        : satToBtcString(sat); // RVN: 1 RVN = 1e8 сат — BTC-формат
    final data = switch (item.direction) {
      'incoming' => (
        icon: Icons.south_west,
        color: VColors.success,
        amountText: '+${amt(item.receivedSat.toInt())} $unit',
        directionText: t('dir_incoming'),
      ),
      'outgoing' => (
        icon: Icons.north_east,
        color: VColors.error,
        amountText: '-${amt(item.sentNetSat.toInt())} $unit',
        directionText: t('dir_outgoing'),
      ),
      'internal' => (
        icon: Icons.swap_horiz,
        color: VColors.secondary,
        amountText: '0 $unit',
        directionText: t('dir_internal'),
      ),
      _ => (
        icon: unknown.icon,
        color: unknown.color,
        amountText: unknown.amountText,
        directionText: t('unknown_direction'),
      ),
    };
    final feeText = item.feeSat != null && item.direction == 'outgoing'
        ? tf('fee_prefix', {'value': '${amt(item.feeSat!.toInt())} $unit'})
        : '';
    return (
      icon: data.icon,
      color: data.color,
      amountText: data.amountText,
      directionText: data.directionText,
      feeText: feeText,
    );
  }
}
