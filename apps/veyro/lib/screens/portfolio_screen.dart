//! Экран 2: обзор портфеля. Показывает только то, что реально реализовано:
//! карточку BTC (состояние сессии из ядра). Остальные монеты не имитируются —
//! их карточек нет вовсе (честность интерфейса, план §5).

import 'package:flutter/material.dart';

import 'package:veyro/src/rust/api/session.dart';
import 'package:veyro/src/rust/api/wallet.dart';
import 'package:veyro/util/app_dirs.dart';
import 'package:veyro/util/network_names.dart';
import 'package:veyro/util/ui_helpers.dart';

import 'btc_screen.dart';

class PortfolioScreen extends StatefulWidget {
  final WalletInfoDto info;

  const PortfolioScreen({super.key, required this.info});

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  BtcSessionStateDto? _btcState;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = await btcSessionState();
      if (!mounted) return;
      setState(() {
        _btcState = state;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
      return;
    }
    if (!mounted) return;
  }

  /// Явный вход в BTC-центр: там пароль спрашивается сам, если сессия
  /// была закрыта.
  Future<void> _openBtc() async {
    debugPrint('veyro-flow: portfolio manual BTC entry for '
        '"${widget.info.name}"');
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BtcScreen(info: widget.info),
    ));
    if (mounted) await _refresh();
  }

  /// Показ seed-фразы: реальный ввод пароля (расшифровка в Rust).
  Future<void> _showSeedPhrase() async {
    final password = await promptPassword(
      context,
      title: 'Показать seed-фразу «${widget.info.name}»',
    );
    if (password == null || !mounted) return;
    try {
      final phrase = await revealMnemonic(
        walletsDir: walletsDir(),
        id: widget.info.id,
        password: password,
      );
      if (!mounted) return;
      await showMnemonicDialog(context, phrase);
    } catch (e) {
      if (!mounted) return;
      showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.info.name)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                if (_loading) ...[
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ] else if (_error != null) ...[
                  SectionCard(
                    title: 'Состояние недоступно',
                    icon: Icons.error_outline,
                    children: [
                      Text('Ошибка: $_error'),
                    ],
                  ),
                ] else ...[
                  _buildBtcCard(context, scheme),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _openBtc,
                    icon: const Icon(Icons.currency_bitcoin),
                    label: Text(
                        _btcState == null ? 'Разблокировать BTC' : 'Открыть BTC'),
                  ),
                ],
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _showSeedPhrase,
                  icon: const Icon(Icons.key_outlined),
                  label: const Text('Показать seed-фразу'),
                ),
                const SizedBox(height: 8),
                Text(
                  'Секреты живут только внутри Rust-ядра: интерфейс ни разу не '
                  'получает seed — лишь адреса и балансы.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBtcCard(BuildContext context, ColorScheme scheme) {
    final state = _btcState;
    final unlocked = state != null;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _openBtc,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFFF7931A).withValues(alpha: 0.2),
                    foregroundColor: const Color(0xFFF7931A),
                    child: const Icon(Icons.currency_bitcoin),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Bitcoin',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        Text(
                          unlocked
                              ? '${ruNetworkText(state.networkDisplay)} · ${state.serverUrl}'
                              : 'Сессия не открыта',
                          style: const TextStyle(color: Colors.white60, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.white38),
                ],
              ),
              const SizedBox(height: 12),
              if (unlocked)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: state.hasSpendables
                        ? Colors.teal.withValues(alpha: 0.15)
                        : Colors.orange.withValues(alpha: 0.12),
                  ),
                  child: Text(
                    state.hasSpendables
                        ? 'Сессия открыта, синхронизирована'
                        : 'Сессия открыта — нужна синхронизация',
                    style: TextStyle(
                      fontSize: 12,
                      color: state.hasSpendables ? Colors.tealAccent : Colors.orangeAccent,
                    ),
                  ),
                )
              else
                Text(
                  'Нажмите, чтобы подключиться к Electrum-серверу и синхронизировать '
                  'баланс. Сеть и сервер настраиваются на экране BTC.',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
