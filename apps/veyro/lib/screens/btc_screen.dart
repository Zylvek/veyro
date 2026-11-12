//! Экран 3: BTC — центр управления. Разблокировка (пароль; сеть/сервер берутся
//! из настроек сети), синхронизация (btc_sync), баланс, переходы к receive/
//! send/history/addresses/settings. Все данные — реальные FFI-вызовы ядра.

import 'package:flutter/material.dart';

import 'package:veyro/src/rust/api/btc.dart';
import 'package:veyro/src/rust/api/session.dart';
import 'package:veyro/src/rust/api/wallet.dart';
import 'package:veyro/util/app_dirs.dart';
import 'package:veyro/util/format.dart';
import 'package:veyro/util/network_config.dart';
import 'package:veyro/util/ui_helpers.dart';

import 'addresses_screen.dart';
import 'history_screen.dart';
import 'network_settings_screen.dart';
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
  String _busyLabel = 'Подключение…';

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
    await _refresh(autosyncIfUnlocked: true);
    await _maybeAutoPrompt();
  }

  Future<void> _maybeAutoPrompt() async {
    if (_state != null || _autoPrompted || _busy || !mounted) return;
    _autoPrompted = true;
    await _unlock();
  }

  /// Перечитать состояние сессии; если разблокирована и данных ещё нет —
  /// синхронизировать без кнопки (решение владельца: автосинхронизация
  /// сразу после подключения).
  Future<void> _refresh({bool autosyncIfUnlocked = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final state = await btcSessionState();
      if (!mounted) return;
      setState(() => _state = state);
      if (state != null && (autosyncIfUnlocked || _sync == null)) {
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
      title: 'Разблокировать BTC',
      confirmLabel: 'Подключиться',
    );
    if (password == null || !mounted) return;

    setState(() {
      _busy = true;
      _busyLabel = 'Разблокировка…';
      _error = null;
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
      setState(() {
        _error = e.toString();
        _busy = false;
      });
    }
  }

  Future<void> _doSync() async {
    setState(() {
      _busyLabel = 'Синхронизация адресов… (gap-limit 20, это может занять '
          'до минуты)';
      _error = null;
    });
    try {
      final sync = await btcSync(gapLimit: 20);
      if (!mounted) return;
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

  Future<void> _lock() async {
    try {
      await btcLock();
      if (!mounted) return;
      setState(() {
        _state = null;
        _sync = null;
      });
    } catch (e) {
      if (!mounted) return;
      showError(context, e);
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

  Future<void> _openNetworkSettings() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const NetworkSettingsScreen(),
    ));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Настройки сети применяются к следующему unlock. Чтобы сменить '
            'сеть сейчас — заблокируйте BTC и откройте заново.'),
      ));
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
            onRefresh: () => _refresh(autosyncIfUnlocked: true),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                if (state != null && state.networkCode == 0)
                  _buildMainnetBanner(context, state),
                if (_error != null)
                  SectionCard(
                    title: 'Ошибка',
                    icon: Icons.error_outline,
                    children: [
                      Text('$_error'),
                      const SizedBox(height: 8),
                      FilledButton.tonal(
                        onPressed:
                            _busy ? null : () => _refresh(autosyncIfUnlocked: true),
                        child: const Text('Повторить'),
                      ),
                    ],
                  ),
                if (state == null)
                  SectionCard(
                    title: 'Сессия не открыта',
                    icon: Icons.lock_outline,
                    children: [
                      const Text(
                        'Подключение к Electrum-серверу выбранной сети.',
                        style: TextStyle(color: Colors.white60),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _busy ? null : _unlock,
                        child: Text(_busy ? _busyLabel : 'Разблокировать BTC'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: _openNetworkSettings,
                        child: const Text('Сервер и сеть'),
                      ),
                    ],
                  )
                else ...[
                  _buildSessionCard(context, state),
                  const SizedBox(height: 16),
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

  Widget _buildMainnetBanner(BuildContext context, BtcSessionStateDto state) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade700),
        color: Colors.red.shade900.withValues(alpha: 0.25),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_outlined, color: Colors.redAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Mainnet: здесь реальные средства. Проверьте адрес и сумму '
              'дважды. Сеть сессии: ${state.networkDisplay}.',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionCard(BuildContext context, BtcSessionStateDto state) {
    return SectionCard(
      title: 'Подключение',
      icon: Icons.dns_outlined,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      children: [
        kvRow('Сеть', state.networkDisplay),
        kvRow('Сервер', state.serverUrl),
        SelectableText(
          'xpub (только публичный): ${state.accountXpub}',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.white54),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : _lock,
              icon: const Icon(Icons.lock_outline),
              label: const Text('Заблокировать'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _openNetworkSettings,
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Сеть'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBalanceCard(BuildContext context) {
    final sync = _sync;
    return SectionCard(
      title: 'Баланс',
      icon: Icons.savings_outlined,
      children: [
        if (_sync == null && _busy)
          const Center(child: CircularProgressIndicator())
        else if (_sync == null)
          const Text(
            'Ещё не синхронизировано. Синхронизация опрашивает сервер по всем '
            'адресам аккаунта (gap-limit 20).',
            style: TextStyle(color: Colors.white70),
          )
        else ...[
          Text(
            '${satToBtcString(sync!.confirmedSat.toInt())} BTC',
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
          ),
          Text(
            '${groupDigits(sync.confirmedSat.toInt())} сат',
            style: const TextStyle(color: Colors.white60),
          ),
          if (sync.unconfirmedDeltaSat != 0) ...[
            const SizedBox(height: 6),
            Text(
              'В мемпуле: ${signedSatToBtcString(sync.unconfirmedDeltaSat)} BTC',
              style: const TextStyle(color: Colors.orangeAccent),
            ),
          ],
          const SizedBox(height: 10),
          kvRow('UTXO доступно', '${sync.utxoCount}'),
          kvRow('Высота чейна', '${sync.tipHeight}'),
          kvRow('Адресов с историей', '${sync.usedAddresses.length}'),
        ],
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: _busy ? null : _doSync,
          icon: const Icon(Icons.sync),
          label: Text(_sync == null ? 'Синхронизировать' : 'Обновить'),
        ),
      ],
    );
  }

  Widget _buildActionsGrid(BuildContext context) {
    Widget action(IconData icon, String label, VoidCallback? onPressed) {
      return Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Column(
              children: [
                Icon(icon, size: 26, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 8),
                Text(label),
              ],
            ),
          ),
        ),
      );
    }

    final unlocked = _state != null;
    return Column(
      children: [
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.1,
          children: [
            action(Icons.qr_code_2_outlined, 'Получить',
                unlocked ? _openReceive : null),
            action(Icons.north_east, 'Отправить', unlocked ? _openSend : null),
            action(Icons.history, 'История', unlocked ? _openHistory : null),
            action(Icons.location_on_outlined, 'Адреса', unlocked ? _openAddresses : null),
            action(Icons.dns_outlined, 'Сервер', unlocked ? _openNetworkSettings : null),
          ],
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

  Future<void> _openAddresses() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const AddressesScreen(),
    ));
    if (mounted) await _refresh();
  }
}
