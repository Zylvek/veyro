//! Экран 6: история транзакций (btc_history с суммами из prevout-кэша в Rust;
//! «своя»/«чужая» определяется по скриптам, которые отдал Electrum — никаких
//! догадок). До первой синхронизации история просто ещё не собрана — экран
//! предлагает синхронизацию, а не показывает пустышку.

import 'package:flutter/material.dart';

import 'package:veyro/src/rust/api/btc.dart';
import 'package:veyro/util/format.dart';
import 'package:veyro/util/ui_helpers.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<BtcHistoryItemDto>? _items;
  bool _loading = true;
  bool _syncing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await btcHistory();
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
      await btcSync(gapLimit: 20);
      if (!mounted) return;
      setState(() => _syncing = false);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _syncing = false);
      showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('История BTC')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: _buildBody(context),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading || _syncing) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      final needsSync = _error!.contains('btc_sync first') ||
          _error!.contains('no scanned addresses');
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.sync_problem_outlined, size: 40, color: Colors.white54),
            const SizedBox(height: 12),
            Text(needsSync
                ? 'История собирается при синхронизации адресов. Выполните '
                    'синхронизацию на экране BTC (или ниже).'
                : 'Ошибка: $_error'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _syncThenLoad,
              icon: const Icon(Icons.sync),
              label: const Text('Синхронизировать и обновить'),
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
            const Icon(Icons.receipt_long_outlined, size: 44, color: Colors.white38),
            const SizedBox(height: 12),
            const Text(
              'История пуста: ни один адрес кошелька ещё не получал средств.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      itemBuilder: (itemContext, index) {
        final item = items[index];
        final card = _buildTileData(item);
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: card.color.withValues(alpha: 0.18),
              foregroundColor: card.color,
              child: Icon(card.icon, size: 20),
            ),
            title: Text(card.amountText,
                style: TextStyle(color: card.color, fontWeight: FontWeight.w600)),
            subtitle: Text(
              '${card.directionText} · ${_heightText(item.height)}'
              '${card.feeText}',
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
            trailing: const Icon(Icons.chevron_right, size: 16, color: Colors.white24),
            onTap: () => copyToClipboard(context, 'TXID', item.txid),
          ),
        );
      },
    );
  }

  ({IconData icon, Color color, String amountText, String directionText, String feeText})
      _buildTileData(BtcHistoryItemDto item) {
    const incomingColor = Color(0xFF4ADE80);
    const outgoingColor = Color(0xFFF87171);
    const internalColor = Color(0xFF94A3B8);
    switch (item.direction) {
      case 'incoming':
        return (
          icon: Icons.south_west,
          color: incomingColor,
          amountText: '+${satToBtcString(item.receivedSat.toInt())} BTC',
          directionText: 'Получение',
          feeText: '',
        );
      case 'outgoing':
        final fee = item.feeSat ?? BigInt.zero;
        return (
          icon: Icons.north_east,
          color: outgoingColor,
          amountText: '-${satToBtcString(item.sentNetSat.toInt())} BTC',
          directionText: 'Отправка',
          feeText: ' · комиссия ${groupDigits(
              fee.toInt())} сат',
        );
      case 'internal':
        return (
          icon: Icons.swap_horiz,
          color: internalColor,
          amountText: '0 BTC',
          directionText: 'Смена адреса (внутри кошелька)',
          feeText: '',
        );
      default:
        return (
          icon: Icons.help_outline,
          color: internalColor,
          amountText: '—',
          directionText: 'Направление не определено',
          feeText: '',
        );
    }
  }

  String _heightText(int height) {
    if (height >= 1) return 'высота $height';
    if (height == -1) return 'в мемпуле';
    return 'конфликт (0)';
  }
}
