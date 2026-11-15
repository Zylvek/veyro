//! Экран 3: BTC — центр управления. Разблокировка (пароль; сеть/сервер берутся
//! из настроек сети), синхронизация (btc_sync), баланс, переходы к receive/
//! send/history/addresses/settings. Все данные — реальные FFI-вызовы ядра.

import 'package:flutter/material.dart';

import 'package:veyro/src/rust/api/btc.dart';
import 'package:veyro/src/rust/api/session.dart';
import 'package:veyro/src/rust/api/wallet.dart';
import 'package:veyro/util/app_dirs.dart';
import 'package:veyro/util/l10n.dart';
import 'package:veyro/design/app_colors.dart';
import 'package:veyro/util/btc_state_cache.dart';
import 'package:veyro/util/format.dart';
import 'package:veyro/util/network_config.dart';
import 'package:veyro/util/ui_helpers.dart';

import 'history_screen.dart';
import 'receive_screen.dart';
import 'send_screen.dart';

class BtcScreen extends StatefulWidget {
  final WalletInfoDto info;

  const BtcScreen({super.key, required this.info});

  @override
  State<BtcScreen> createState() => _BtcScreenState();
}

class _BtcScreenState extends State<BtcScreen> {
  BtcSessionStateDto? _state;
  BtcSyncDto? _sync;
  bool _busy = false;
  String? _error;

  /// Что сейчас происходит (аудит: «Подключение…» без деталей выглядит
  /// как зависание). busyLabel: Разблокировка → Синхронизация.
  String _busyLabel = t('btc_connecting');

  /// Диалог пароля показывается автоматически один раз на вход (решение
  /// владельца: «подключаться сразу», без лишних нажатий). После отмены
  /// остаются ручные кнопки — повторно сам не выскакивает.
  var _autoPrompted = false;

  @override
  void initState() {
    super.initState();
    _entry();
  }

  Future<void> _entry() async {
    debugPrint('veyro-flow: btc screen entry (wallet ${widget.info.name})');
    await _refresh(autosyncIfUnlocked: true);
    debugPrint('veyro-flow: btc refresh done, state=${_state != null}, '
        'busy=$_busy');
    await _maybeAutoPrompt();
  }

  Future<void> _maybeAutoPrompt() async {
    if (_state != null || _autoPrompted || _busy || !mounted) return;
    _autoPrompted = true;
    debugPrint('veyro-flow: btc auto-prompt password dialog');
    await _unlock();
  }

  /// Перечитать состояние сессии; если разблокирована и данных ещё нет —
  /// синхронизировать без кнопки (решение владельца: автосинхронизация
  /// сразу после подключения). Свежий результат синхронизации с экрана
  /// входа берётся из кэша — двойной gap-скан не запускается.
  Future<void> _refresh({
    bool autosyncIfUnlocked = false,
    bool useCache = true,
  }) async {
    setState(() {
      _busy = true;
      _busyLabel = t('btc_syncing_addresses');
      _error = null;
    });
    try {
      final state = await btcSessionState();
      if (!mounted) return;
      setState(() => _state = state);
      if (state != null && (autosyncIfUnlocked || _sync == null)) {
        final cached = useCache ? BtcStateCache.instance.take() : null;
        if (cached != null) {
          setState(() {
            _sync = cached;
            _busy = false;
          });
          return;
        }
        await _doSync();
        return; // _doSync уже снял busy
      }
      setState(() => _busy = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _busy = false;
      });
    }
  }

  Future<void> _unlock() async {
    final settings = await loadSettings();
    if (!mounted) return;

    final password = await promptPassword(
      context,
      title: tf(
        'btc_unlock_title',
        {'name': widget.info.name},
      ),
      confirmLabel: t('connect_btn'),
    );
    if (password == null || !mounted) {
      debugPrint('veyro-flow: password dialog cancelled');
      return;
    }
    debugPrint('veyro-flow: password entered, unlocking…');
    setState(() {
      _busy = true;
      _busyLabel = t('unlocking_now');      _error = null;
    });
    try {
      await btcUnlock(
        walletsDir: walletsDir(),
        walletId: widget.info.id,
        password: password,
        networkCode: settings.networkCode,
        serverUrl: settings.serverUrl,
      );
      if (!mounted) return;
      await _doSync();
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString();
      // vault даёт generic-ошибку расшифровки: добавляем честную подсказку
      // (частый случай — пароль другого из нескольких кошельков).
      final hint = raw.contains('decryption failed')
          ? '$e\n\n${tf(
              'password_mismatch_hint',
              {'name': widget.info.name},
            )}'
          : e.toString();
      setState(() {
        _error = hint;
        _busy = false;
      });
    }
  }

  Future<void> _doSync() async {
    setState(() {
      _busyLabel = t('btc_syncing_addresses_long');
      _error = null;
    });
    try {
      final sync = await btcSync(gapLimit: 20);
      if (!mounted) return;
      BtcStateCache.instance.store(sync);
      setState(() {
        _sync = sync;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _busy = false;
      });
    }
  }

  /// Реальный доступный баланс на момент последней синхронизации:
  /// confirmed + отрицательный mempool-delta (в mempool-расходе сумма
  /// уже ушла из подтверждённых). Нет синхронизации — нет данных (null).
  int? _availableSat() {
    final sync = _sync;
    if (sync == null) return null;
    final confirmed = sync.confirmedSat.toInt();
    final delta = sync.unconfirmedDeltaSat.toInt();
    return delta < 0 ? confirmed + delta : confirmed;
  }

  Future<void> _openSend() async {
    final sent = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
      builder: (_) => SendScreen(availableSat: _availableSat()),
    ));
    if (sent == true && mounted) {
      // После успешной отправки Rust очистил набор UTXO — синхронизируем.
      await _refresh(autosyncIfUnlocked: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    return Scaffold(
      appBar: AppBar(title: const Text('Bitcoin')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: RefreshIndicator(
            onRefresh: () => _refresh(autosyncIfUnlocked: true, useCache: false),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  SectionCard(
                    title: t('error_title'),
                    icon: Icons.error_outline,
                    children: [
                      Text('$_error'),
                      const SizedBox(height: 8),
                      FilledButton.tonal(
                        onPressed: _busy
                            ? null
                            : () => _refresh(
                                autosyncIfUnlocked: true,
                                useCache: false,
                              ),
                        child: Text(t('retry')),
                      ),
                    ],
                  ),
                if (state == null)
                  SectionCard(
                    title: t('session_not_open'),
                    icon: Icons.lock_outline,
                    children: [
                      Text(
                        t('session_desc'),
                        style: const TextStyle(color: Colors.white60),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tf(
                          'wallet_label',
                          {'name': widget.info.name},
                        ),
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _busy ? null : _unlock,
                        child: Text(_busy ? _busyLabel : t('unlock_btc_btn')),
                      ),
                    ],
                  )
                else ...[
                  _buildBalanceCard(context),
                  const SizedBox(height: 16),
                  _buildActionsGrid(context),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBalanceCard(BuildContext context) {
    final sync = _sync;
    return SectionCard(
      title: t('balance_section'),
      icon: Icons.savings_outlined,
      children: [
        if (_sync == null && _busy)
          const Center(child: CircularProgressIndicator())
        else if (_sync == null)
          Text(
            t('not_synced_note'),
            style: const TextStyle(color: Colors.white70),
          )
        else ...[
          Text(
            '${satToBtcString(sync!.confirmedSat.toInt())} BTC',
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
          ),
          Text(
            '${groupDigits(sync.confirmedSat.toInt())} ${t('sats')}',
            style: const TextStyle(color: Colors.white60),
          ),
          if (sync.unconfirmedDeltaSat != 0) ...[
            const SizedBox(height: 6),
            Text(
              tf(
                'mempool_row',
                {'value': '${signedSatToBtcString(sync.unconfirmedDeltaSat)} BTC'},
              ),
              style: const TextStyle(color: Colors.orangeAccent),
            ),
          ],
          const SizedBox(height: 10),
          kvRow(t('utxo_available'), '${sync.utxoCount}'),
          kvRow(t('chain_height'), '${sync.tipHeight}'),
          kvRow(t('addresses_with_history'), '${sync.usedAddresses.length}'),
        ],
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: _busy ? null : _doSync,
          icon: const Icon(Icons.sync),
          label: Text(_sync == null ? t('sync_btn') : t('refresh_btn')),
        ),
      ],
    );
  }

  Widget _buildActionsGrid(BuildContext context) {
    final unlocked = _state != null;
    return Row(
      children: [
        for (final entry in [
          (
            icon: Icons.qr_code_2_outlined,
            label: t('get_btn'),
            onTap: unlocked ? _openReceive : null
          ),
          (
            icon: Icons.north_east,
            label: t('send_btn'),
            onTap: unlocked ? _openSend : null
          ),
          (
            icon: Icons.history,
            label: t('history_btn'),
            onTap: unlocked ? _openHistory : null
          ),
        ])
          Expanded(
            child: _ActionTile(
              icon: entry.icon,
              label: entry.label,
              enabled: entry.onTap != null,
              onTap: entry.onTap,
            ),
          ),
      ],
    );
  }

  Future<void> _openReceive() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const ReceiveScreen(),
    ));
    if (mounted) await _refresh();
  }

  Future<void> _openHistory() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const HistoryScreen(),
    ));
    if (mounted) await _refresh(autosyncIfUnlocked: true);
  }
}

/// Плитка действия центра монет: hover-подъём + мягкое свечение,
/// курсор «клик» на desktop; без действий — честно потушена.
class _ActionTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  State<_ActionTile> createState() => _ActionTileState();
}

class _ActionTileState extends State<_ActionTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.enabled ? Theme.of(context).colorScheme.primary : null;
    return MouseRegion(
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      onEnter: widget.enabled ? (_) => setState(() => _hover = true) : null,
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hover ? -2 : 0, 0),
        decoration: BoxDecoration(
          color: VColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _hover
                ? (accent ?? VColors.textSecondary).withValues(alpha: 0.35)
                : Colors.transparent,
          ),
          boxShadow: [
            if (_hover && widget.enabled)
              BoxShadow(
                color: (accent ?? VColors.textSecondary)
                    .withValues(alpha: 0.18),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: widget.enabled ? widget.onTap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Column(
                children: [
                  Icon(
                    widget.icon,
                    size: 26,
                    color: widget.enabled
                        ? (accent ?? VColors.textPrimary)
                        : VColors.textSecondary.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 8),
                  Opacity(
                    opacity: widget.enabled ? 1.0 : 0.45,
                    child: Text(
                      widget.label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
