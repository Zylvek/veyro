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
import 'package:veyro/design/motion.dart';
import 'package:veyro/design/veyro_mark.dart';
import 'package:veyro/src/rust/api/ltc.dart';
import 'package:veyro/src/rust/api/session.dart';
import 'package:veyro/src/rust/api/wallet.dart';
import 'package:veyro/util/app_dirs.dart';
import 'package:veyro/util/l10n.dart';
import 'package:veyro/util/network_names.dart';
import 'package:veyro/util/display_prefs.dart';
import 'package:veyro/util/ui_helpers.dart';

import 'btc_screen.dart';
import 'ltc_screen.dart';
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
  LtcSessionStateDto? _ltcSession;
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
    // Кошелёк нужен для активов с центром управления (BTC и LTC).
    if (_asset.ticker == 'BTC' || _asset.ticker == 'LTC') {
      try {
        final list = widget.walletLoader != null
            ? await widget.walletLoader!()
            : await listWallets(walletsDir: walletsDir());
        if (!mounted) return;
        setState(() {
          _wallets = list;
          _walletError = null;
          final preferred = widget.wallet ?? _walletById(DisplayPrefs.walletId);
          _chosenWallet = list.any((w) => w.id == preferred?.id)
              ? preferred
              : null;
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
      if (_asset.ticker == 'LTC') {
        try {
          // Честная граница ожидания: если ядро не отвечает — ошибка и
          // Retry, а не вечный лоудер (жалоба владельца на зависание).
          final state = await ltcSessionState().timeout(
            const Duration(seconds: 12),
            onTimeout: () => throw StateError(t('ltc_session_timeout')),
          );
          if (!mounted) return;
          setState(() {
            _ltcSession = state;
            _session = null;
            _sessionChecked = true;
          });
          return;
        } catch (e) {
          if (!mounted) return;
          setState(() {
            _ltcSession = null;
            _session = null;
            _sessionChecked = true;
            _walletError ??= tf('ltc_session_read_error', {'error': '$e'});
          });
          return;
        }
      }
      final session = widget.sessionLoader != null
          ? await widget.sessionLoader!()
          : await btcSessionState();
      if (!mounted) return;
      setState(() {
        _session = session;
        _ltcSession = null;
        _sessionChecked = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _session = null;
        _ltcSession = null;
        _sessionChecked = true;
        _walletError ??= tf('btc_session_read_error', {'error': '$e'});
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
    await pushVeyro<void>(context, BtcScreen(info: wallet));
    // Возврат из центра управления — перечитать сессию (могли unlock/lock).
    if (mounted) {
      await _loadSession();
    }
  }

  Future<void> _openLtcWorkbench() async {
    final wallet = _chosenWallet;
    if (wallet == null) return;
    await pushVeyro<void>(context, LtcScreen(info: wallet));
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
            tooltip: isFavorite
                ? t('fav_remove_tooltip')
                : t('fav_add_tooltip'),
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
              ] else if (_asset.ticker == 'LTC') ...[
                _buildLtcCard(context),
                const SizedBox(height: 14),
              ],
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
                networkLabel(_asset.network),
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
      title: t('identification_card'),
      children: [
        kvRow(t('ticker_label'), _asset.ticker, mono: true),
        kvRow(t('name_label'), _asset.name),
        kvRow(t('network_label'), networkLabel(_asset.network)),
        kvRow(
          t('implemented_in_core'),
          _asset.implemented ? t('yes') : t('no'),
        ),
      ],
    );
  }

  /// Карточка управления LTC: сессия ядра без hasSpendables-чипа
  /// (receive-only milestone; чип spendables у BTC — про отправку).
  Widget _buildLtcCard(BuildContext context) {
    final session = _ltcSession;
    return VCard(
      icon: Icons.settings_backup_restore,
      title: t('management_card'),
      children: [
        if (!_sessionChecked)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Center(
              child: LogoLoader(mode: LogoLoaderMode.loading, size: 44),
            ),
          )
        else if (session != null) ...[
          kvRow(
            t('network_label'),
            ruNetworkText(session.networkDisplay) ?? '—',
          ),
          VMonoCopyRow(label: t('server_label'), value: session.serverUrl),
          kvRow(t('account_row'), "m/84'/2'/${session.account}'"),
        ] else
          Text(
            t('session_closed_note'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        const Divider(height: 22),
        Text(t('sync_note'), style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        if (_walletError != null) ...[
          Text(
            tf('wallets_read_error', {'error': '$_walletError'}),
            style: Theme.of(context).textTheme.bodySmall!
                .copyWith(color: VColors.error),
          ),
        ] else if (_wallets != null && _wallets!.isEmpty) ...[
          Text(
            t('no_wallets_btc'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ] else if (_wallets != null && _wallets!.length > 1) ...[
          DropdownButtonFormField<String>(
            initialValue: _chosenWallet?.id,
            isExpanded: true,
            decoration: InputDecoration(labelText: t('ltc_wallet_field')),
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
          session != null ? t('open_ltc_center') : t('unlock_manage_ltc'),
          icon: Icons.lock_open_outlined,
          onPressed: _chosenWallet == null ? null : _openLtcWorkbench,
        ),
      ],
    );
  }

  Widget _buildBtcCard(BuildContext context) {
    final session = _session;
    return VCard(
      icon: Icons.settings_backup_restore,
      title: t('management_card'),
      children: [
        if (!_sessionChecked)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Center(
              child: LogoLoader(mode: LogoLoaderMode.loading, size: 44),
            ),
          )
        else if (session != null) ...[
          kvRow(
            t('network_label'),
            ruNetworkText(session.networkDisplay) ?? '—',
          ),
          VMonoCopyRow(label: t('server_label'), value: session.serverUrl),
          kvRow(t('account_row'), "m/84'/0'/${session.account}'"),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (session.hasSpendables)
                VStatusChip(t('synced_funds'), kind: VChipKind.success)
              else
                VStatusChip(t('funds_not_synced'), kind: VChipKind.warning),
            ],
          ),
        ] else
          Text(
            t('session_closed_note'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        const Divider(height: 22),
        Text(t('sync_note'), style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        if (_walletError != null) ...[
          Text(
            tf('wallets_read_error', {'error': '$_walletError'}),
            style: Theme.of(context).textTheme.bodySmall!
                .copyWith(color: VColors.error),
          ),
        ] else if (_wallets != null && _wallets!.isEmpty) ...[
          Text(
            t('no_wallets_btc'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ] else if (_wallets != null && _wallets!.length > 1) ...[
          DropdownButtonFormField<String>(
            initialValue: _chosenWallet?.id,
            isExpanded: true,
            decoration: InputDecoration(labelText: t('btc_wallet_field')),
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
          session != null ? t('open_btc_center') : t('unlock_manage_btc'),
          icon: Icons.lock_open_outlined,
          onPressed: _chosenWallet == null ? null : _openBtcWorkbench,
        ),
      ],
    );
  }
}
