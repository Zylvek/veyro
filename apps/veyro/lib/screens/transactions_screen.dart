//! Раздел «Транзакции» (навигация аудита UI §8). При активной BTC-сессии
//! показывает реальную историю ядра (HistoryScreen); при закрытой — честное
//! состояние без выдуманных данных: история собирается синхронизацией,
//! которая требует разблокировки. Никаких фейковых списков.

import 'package:flutter/material.dart';

import 'package:veyro/design/components.dart';
import 'package:veyro/src/rust/api/session.dart';

import 'history_screen.dart';

class TransactionsScreen extends StatefulWidget {
  /// Точка замены для виджет-тестов (без RustLib).
  final Future<BtcSessionStateDto?> Function()? sessionLoader;

  const TransactionsScreen({super.key, this.sessionLoader});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  bool _checked = false;
  BtcSessionStateDto? _session;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _checked = false);
    try {
      final loader = widget.sessionLoader;
      final session =
          loader != null ? await loader() : await btcSessionState();
      if (!mounted) return;
      setState(() {
        _session = session;
        _checked = true;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _session = null;
        _checked = true;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return const Center(child: CircularProgressIndicator());
    }
    final session = _session;
    if (session == null) {
      // Сессия закрыта: реальной истории нет и не будет до разблокировки.
      // Честное состояние — без выдуманных транзакций.
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: VEmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'Транзакций пока нет',
            message: 'История появляется после разблокировки BTC-актива: '
                'ядро собирает её при синхронизации с выбранной сети. '
                'Ядро недоступно: ${_error ?? 'сессия закрыта'}',
            action: FilledButton.tonal(
              onPressed: _load,
              child: const Text('Обновить'),
            ),
          ),
        ),
      );
    }
    // Активная сессия: реальная история ядра.
    return const HistoryScreen();
  }
}
