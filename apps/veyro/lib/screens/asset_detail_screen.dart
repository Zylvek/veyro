//! Экран 12 спеки: Individual asset details.
//!
//! Честность по статусам:
//! - BTC (единственный реализованный адаптер): реальное состояние сессии
//!   ядра (btcSessionState) и переход в настоящий центр управления
//!   (BtcScreen: разблокировка → синхронизация → балансы/действия).
//!   Синхронизация из экрана деталей НЕ вызывается — только через центр
//!   управления по явному действию пользователя.
//! - Остальные активы: вердикт матрицы + примечание + паспорт исследования.
//!   Никаких балансов/транзакций/сетевых статусов не изобретается.

import 'package:flutter/material.dart';

import 'package:veyro/data/asset_registry.dart';
import 'package:veyro/design/app_colors.dart';
import 'package:veyro/design/components.dart';
import 'package:veyro/src/rust/api/session.dart';
import 'package:veyro/src/rust/api/wallet.dart';
import 'package:veyro/util/app_dirs.dart';
import 'package:veyro/util/network_names.dart';
import 'package:veyro/util/display_prefs.dart';
import 'package:veyro/util/ui_helpers.dart';

import 'btc_screen.dart';
import 'asset_catalog_screen.dart' show CoinIcon;

class AssetDetailScreen extends StatefulWidget {
  final VeyroAsset asset;

  /// Кошелёк, выбранный на Обзоре (если экран открыт оттуда). Иначе
  /// подставляется из реестра/настройки через [walletLoader].
  final WalletInfoDto? wallet;

  /// Точки замены для виджет-тестов (без RustLib).
  final Future<BtcSessionStateDto?> Function()? sessionLoader;
  final Future<List<WalletInfoDto>> Function()? walletLoader;

  const AssetDetailScreen({
    super.key,
    required this.asset,
    this.wallet,
    this.sessionLoader,
    this.walletLoader,
  });

  @override
  State<AssetDetailScreen> createState() => _AssetDetailScreenState();
}

class _AssetDetailScreenState extends State<AssetDetailScreen> {
  BtcSessionStateDto? _session;
  bool _sessionChecked = false;
  List<WalletInfoDto>? _wallets;
  String? _walletError;
  WalletInfoDto? _chosenWallet;

  VeyroAsset get _asset => widget.asset;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await DisplayPrefs.ensureLoaded();
    // Кошелёк нужен только BTC (центр управления работает от кошелька).
    if (_asset.ticker == 'BTC') {
      try {
        final list = widget.walletLoader != null
            ? await widget.walletLoader!()
            : await listWallets(walletsDir: walletsDir());
        if (!mounted) return;
        setState(() {
          _wallets = list;
          _walletError = null;
          final preferred = widget.wallet ?? _walletById(DisplayPrefs.walletId);
          _chosenWallet =
              list.any((w) => w.id == preferred?.id) ? preferred : null;
          // Один кошелёк — подставляем сразу; несколько — предлагает выбор UI.
          if (_chosenWallet == null && list.length == 1) {
            _chosenWallet = list.first;
          }
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _walletError = e.toString();
          _wallets = null;
        });
      }
      await _loadSession();
    }
  }

  WalletInfoDto? _walletById(String? id) {
    final list = _wallets;
    if (id == null || list == null) return null;
    for (final w in list) {
      if (w.id == id) return w;
    }
    return null;
  }

  Future<void> _loadSession() async {
    try {
      final session = widget.sessionLoader != null
          ? await widget.sessionLoader!()
          : await btcSessionState();
      if (!mounted) return;
      setState(() {
        _session = session;
        _sessionChecked = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _session = null;
        _sessionChecked = true;
        _walletError ??= 'Состояние сессии BTC не прочитано: $e';
      });
    }
  }

  Future<void> _toggleFavorite() async {
    await DisplayPrefs.toggleFavorite(_asset.ticker);
    if (mounted) setState(() {});
  }

  Future<void> _openBtcWorkbench() async {
    final wallet = _chosenWallet;
    if (wallet == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => BtcScreen(info: wallet)),
    );
    // Возврат из центра управления — перечитать сессию (могли unlock/lock).
    if (mounted) {
      await _loadSession();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFavorite = DisplayPrefs.favorites.contains(_asset.ticker);
    return Scaffold(
      appBar: AppBar(
        title: Text(_asset.ticker),
        actions: [
          IconButton(
            tooltip: isFavorite ? 'Убрать из избранного' : 'В избранное',
            icon: Icon(
              isFavorite ? Icons.star : Icons.star_outline,
              color: isFavorite ? VColors.warning : VColors.textSecondary,
            ),
            onPressed: _toggleFavorite,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              _buildHeader(context),
              const SizedBox(height: 14),
              _buildIdentityCard(context),
              const SizedBox(height: 14),
              if (_asset.ticker == 'BTC') ...[
                _buildBtcCard(context),
                const SizedBox(height: 14),
              ],
              _buildStatusCard(context),
              const SizedBox(height: 14),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        CoinIcon(asset: _asset, radius: 26),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _asset.name,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 4),
              Text(
                _asset.network,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildIdentityCard(BuildContext context) {
    return VCard(
      icon: Icons.badge_outlined,
      title: 'Идентификация',
      children: [
        kvRow('Тикер (верифицирован)', _asset.ticker, mono: true),
        kvRow('Имя', _asset.name),
        kvRow('Сеть', _asset.network),
        kvRow('Статус', _asset.lifecycle.label),
        kvRow('Реализован в ядре', _asset.implemented ? 'да' : 'нет'),
      ],
    );
  }

  Widget _buildStatusCard(BuildContext context) {
    final lifecycle = _asset.lifecycle;
    return VCard(
      icon: Icons.verified_outlined,
      title: 'Честный статус',
      children: [
        VStatusChip(lifecycle.label, kind: lifecycle.chipKind),
        const SizedBox(height: 10),
        Text(_asset.note, style: Theme.of(context).textTheme.bodyMedium),

      ],
    );
  }



  Widget _buildBtcCard(BuildContext context) {
    final session = _session;
    return VCard(
      icon: Icons.settings_backup_restore,
      title: 'Управление — реальный поток',
      children: [
        if (!_sessionChecked)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (session != null) ...[
          kvRow('Сеть', ruNetworkText(session.networkDisplay) ?? '—'),
          VMonoCopyRow(label: 'Сервер', value: session.serverUrl),
          kvRow('Аккаунт', "m/84'/0'/${session.account}'"),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (session.hasSpendables)
                const VStatusChip('Есть синхронизированные средства',
                    kind: VChipKind.success)
              else
                const VStatusChip('Средства ещё не синхронизированы',
                    kind: VChipKind.warning),
            ],
          ),
        ] else
          Text(
            'Сессия закрыта: разблокировка происходит в центре управления '
            'по паролю кошелька (реальная, не имитация).',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        const Divider(height: 22),
        Text(
          'Баланс и транзакции появляются после явной синхронизации в центре '
          'управления (btcSync — сетевая операция, из экрана деталей '
          'не запускается). Receive/Send поверх реальных FFI-вызовов.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        if (_walletError != null) ...[
          Text(
            'Не удалось прочитать кошельки: $_walletError',
            style: Theme.of(context)
                .textTheme
                .bodySmall!
                .copyWith(color: VColors.error),
          ),
        ] else if (_wallets != null && _wallets!.isEmpty) ...[
          Text(
            'Кошельков нет — создайте или импортируйте кошелёк, затем '
            'вернитесь к BTC.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ] else if (_wallets != null && _wallets!.length > 1) ...[
          DropdownButtonFormField<String>(
            initialValue: _chosenWallet?.id,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Кошелёк для BTC'),
            items: [
              for (final w in _wallets!)
                DropdownMenuItem(value: w.id, child: Text(w.name)),
            ],
            onChanged: (id) async {
              final chosen = _wallets!.firstWhere((w) => w.id == id);
              setState(() => _chosenWallet = chosen);
              await DisplayPrefs.setWalletId(chosen.id);
            },
          ),
          const SizedBox(height: 12),
        ],
        VButton.primary(
          session != null
              ? 'Открыть центр управления BTC'
              : 'Разблокировать и управлять BTC',
          icon: Icons.lock_open_outlined,
          onPressed: _chosenWallet == null ? null : _openBtcWorkbench,
        ),
      ],
    );
  }
}
