//! Экран 16 спеки: History — фильтры (Все/Входящие/Исходящие/Ожидающие/
//! Подтверждённые; «Неудачные» честно отключены — ядро не отдаёт неуспешные
//! в истории), поиск по TXID (адресов в данных истории нет — честная
//! пометка), переход в детали (экран 17). Данные — только btcHistory;
//! история собирается синхронизацией адресов (btcSync) — сетевая операция,
//! запускается только действием пользователя.

import 'package:flutter/material.dart';

import 'package:veyro/design/app_colors.dart';
import 'package:veyro/design/components.dart';
import 'package:veyro/src/rust/api/btc.dart';
import 'package:veyro/src/rust/api/session.dart';
import 'package:veyro/util/format.dart';

import 'tx_details_screen.dart';

/// Фильтры истории. failed есть в enum, но в UI отключён: история ядра
/// не содержит неуспешных транзакций (broadcast неудачных отклоняется до
/// попадания в историю) — выдавать пустой фильтр за рабочий нельзя.
enum HistoryFilter { all, incoming, outgoing, pending, confirmed, failed }

class HistoryScreen extends StatefulWidget {
  /// Точки замены для виджет-тестов (без RustLib).
  final Future<List<BtcHistoryItemDto>> Function()? historyLoader;
  final Future<void> Function()? syncLoader;
  final Future<BtcSessionStateDto?> Function()? sessionLoader;

  const HistoryScreen({
    super.key,
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
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() => _query =
        _searchController.text.trim().toLowerCase()));
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
      final loader = widget.sessionLoader;
      final session = loader != null ? await loader() : await btcSessionState();
      if (mounted) setState(() => _networkCode = session?.networkCode);
    } catch (_) {
      // Сеть неизвестна — детали покажут честное «—».
    }
    try {
      final loader = widget.historyLoader;
      final items = loader != null ? await loader() : await btcHistory();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
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
      } else {
        await btcSync(gapLimit: 20);
      }
      if (!mounted) return;
      setState(() => _syncing = false);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _syncing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Ошибка синхронизации: $e'),
      ));
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
      appBar: AppBar(title: const Text('История BTC'), actions: [
        IconButton(
          tooltip: 'Синхронизировать и обновить (сетевая операция)',
          onPressed: _syncing ? null : _syncThenLoad,
          icon: const Icon(Icons.sync),
        ),
      ]),
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
      return const Center(child: CircularProgressIndicator());
    }
    if (_hasError) {
      final needsSync = _error!.contains('btc_sync first') ||
          _error!.contains('no scanned addresses');
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.sync_problem_outlined,
                size: 40, color: VColors.textSecondary),
            const SizedBox(height: 12),
            Text(
              needsSync
                  ? 'История собирается при синхронизации адресов. Выполните '
                      'синхронизацию на экране BTC (или ниже).'
                  : 'Ошибка: $_error',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            VButton.primary(
              'Синхронизировать и обновить',
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
            const Icon(Icons.receipt_long_outlined,
                size: 44, color: VColors.textSecondary),
            const SizedBox(height: 12),
            Text(
              'История пуста: ни один адрес кошелька ещё не получал средств '
              '(или не выполнена синхронизация).',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            VButton.secondary('Синхронизировать',
                icon: Icons.sync, onPressed: _syncThenLoad),
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
              labelText: 'Поиск по TXID',
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
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Поиск работает по TXID. Поиск по адресу недоступен: адресов в '
              'данных истории ядра нет — только TXID, направление и суммы.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _filterChip(context, 'Все', HistoryFilter.all),
              _filterChip(context, 'Входящие', HistoryFilter.incoming),
              _filterChip(context, 'Исходящие', HistoryFilter.outgoing),
              _filterChip(context, 'Ожидающие', HistoryFilter.pending),
              _filterChip(context, 'Подтверждённые', HistoryFilter.confirmed),
              _failedChip(context),
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
                        title: 'Ничего не найдено',
                        message:
                            'По текущему фильтру и поиску транзакций нет. '
                            'Измените фильтр или очистите поиск.',
                      ),
                      Center(
                        child: TextButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _filter = HistoryFilter.all);
                          },
                          child: const Text('Сбросить фильтр и поиск'),
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
                          title: Text(card.amountText,
                              style: TextStyle(
                                  color: card.color,
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ])),
                          subtitle: Text(
                            '${card.directionText} · ${_heightText(item.height)}'
                            '${card.feeText}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          trailing: const Icon(Icons.chevron_right,
                              size: 16, color: VColors.textSecondary),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => TxDetailsScreen(
                                item: item,
                                networkCode: _networkCode,
                              ),
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

  Widget _filterChip(
      BuildContext context, String label, HistoryFilter filter) {
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
        color:
            selected ? VColors.primary.withValues(alpha: 0.5) : VColors.elevated,
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
      message: 'Ядро не отдаёт неуспешные транзакции: их нет в истории. '
          'Фильтр оставлен отключённым, чтобы не имитировать работу.',
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.45,
          child: FilterChip(
            selected: false,
            label: Text('Неудачные',
                style: TextStyle(
                    fontSize: 12.5, color: VColors.textSecondary)),
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
      height >= 1 ? 'высота $height' : 'в мемпуле';

  ({IconData icon, Color color, String amountText, String directionText, String feeText})
      _buildTileData(BtcHistoryItemDto item) {
    const unknown = (
      icon: Icons.help_outline,
      color: VColors.textSecondary,
      amountText: '—',
      directionText: 'Направление не определено',
    );
    final data = switch (item.direction) {
      'incoming' => (
          icon: Icons.south_west,
          color: VColors.success,
          amountText: '+${satToBtcString(item.receivedSat.toInt())} BTC',
          directionText: 'Получение',
        ),
      'outgoing' => (
          icon: Icons.north_east,
          color: VColors.error,
          amountText: '-${satToBtcString(item.sentNetSat.toInt())} BTC',
          directionText: 'Отправка',
        ),
      'internal' => (
          icon: Icons.swap_horiz,
          color: VColors.secondary,
          amountText: '0 BTC',
          directionText: 'Смена адреса (внутри кошелька)',
        ),
      _ => unknown,
    };
    final feeText = item.feeSat != null && item.direction == 'outgoing'
        ? ' · комиссия ${satToBtcString(item.feeSat!.toInt())}'
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
