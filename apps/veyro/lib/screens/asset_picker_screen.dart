//! Группа 3 спеки: выбор актива для Receive/Send (мультивалютная обёртка
//! над реальным BTC-потоком). Ядро реализует только адаптер BTC — остальные
//! активы отображаются отключёнными с честным статусом из матрицы
//! (Researched/Blocked/…), без имитации форм и балансов.

import 'package:flutter/material.dart';

import 'package:veyro/data/asset_registry.dart';
import 'package:veyro/design/app_colors.dart';
import 'package:veyro/src/rust/api/session.dart';
import 'package:veyro/src/rust/api/wallet.dart';
import 'package:veyro/util/app_dirs.dart';
import 'package:veyro/util/l10n.dart';
import 'package:veyro/util/display_prefs.dart';

import 'asset_catalog_screen.dart' show CoinIcon;
import 'btc_screen.dart';
import 'receive_screen.dart';
import 'send_screen.dart';

/// Полноэкранный выбор актива для действия Receive (получение) или
/// Send (отправка). BTC ведёт в реальный поток; остальные активы —
/// честно отключены.
class AssetPickerScreen extends StatefulWidget {
  /// true — форма «Получить», false — «Отправить».
  final bool isReceive;

  /// Точки замены для виджет-тестов (без RustLib).
  final Future<BtcSessionStateDto?> Function()? sessionLoader;
  final Future<List<WalletInfoDto>> Function()? walletLoader;

  const AssetPickerScreen({
    super.key,
    required this.isReceive,
    this.sessionLoader,
    this.walletLoader,
  });

  @override
  State<AssetPickerScreen> createState() => _AssetPickerScreenState();
}

class _AssetPickerScreenState extends State<AssetPickerScreen> {
  BtcSessionStateDto? _session;
  WalletInfoDto? _chosenWallet;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await DisplayPrefs.ensureLoaded();
    try {
      final wallets = widget.walletLoader != null
          ? await widget.walletLoader!()
          : await listWallets(walletsDir: walletsDir());
      if (!mounted) return;
      final preferredId = DisplayPrefs.walletId;
      WalletInfoDto? chosen;
      for (final w in wallets) {
        if (w.id == preferredId) chosen = w;
      }
      if (chosen == null && wallets.length == 1) chosen = wallets.first;
      setState(() => _chosenWallet = chosen);
    } catch (_) {
      // Кошельки не прочитать — переход в центр BTC всё равно честный:
      // там будет настоящая ошибка разблокировки.
      if (!mounted) return;
      setState(() => _chosenWallet = null);
    }
    try {
      final loader = widget.sessionLoader;
      final session =
          loader != null ? await loader() : await btcSessionState();
      if (!mounted) return;
      setState(() => _session = session);
    } catch (_) {
      // Ошибку сессии честно показывает центр BTC.
      if (!mounted) return;
      setState(() => _session = null);
    }
  }

  Future<void> _openBtc() async {
    final session = _session;
    if (session != null) {
      // Сессия активна: реальная форма получения/отправки поверх ядра.
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) =>
            widget.isReceive ? const ReceiveScreen() : const SendScreen(),
      ));
      if (mounted) await _load();
      return;
    }
    // Сессия закрыта: центр управления — единственный способ разблокировать
    // (реальный пароль → unlock). Без кошелька это невозможно.
    final wallet = _chosenWallet;
    if (wallet == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Кошельков нет — создайте кошелёк в разделе «Кошельки», '
            'затем разблокируйте BTC.'),
      ));
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => BtcScreen(info: wallet)),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final btc = kAssetRegistry.firstWhere((a) => a.ticker == 'BTC');
    final others = kAssetRegistry.where((a) => a.ticker != 'BTC').toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isReceive
            ? t('receive_pick_title')
            : t('send_pick_title')),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              _BtcTile(
                asset: btc,
                onTap: _openBtc,
              ),
              const SizedBox(height: 10),
              for (final asset in others)
                _DisabledAssetTile(asset: asset),
            ],
          ),
        ),
      ),
    );
  }
}

/// Реальная плитка BTC: активна, ведёт в настоящий поток или в
/// разблокировку через центр управления.
class _BtcTile extends StatelessWidget {
  final VeyroAsset asset;
  final VoidCallback onTap;

  const _BtcTile({required this.asset, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: CoinIcon(asset: asset, radius: 20, key: ValueKey(asset.ticker)),
        title: RichText(
          text: TextSpan(
            children: [
              const TextSpan(
                text: 'BTC',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5,
                  color: VColors.textPrimary,
                  letterSpacing: 0.3,
                ),
              ),
              const WidgetSpan(child: SizedBox(width: 6)),
              TextSpan(
                text: '${asset.name} ${t('implemented_tag')}',
                style: TextStyle(
                  fontSize: 13,
                  color: VColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        trailing:
            const Icon(Icons.chevron_right, size: 18, color: VColors.textSecondary),
        onTap: onTap,
      ),
    );
  }
}

/// Честная отключённая плитка нереализованного актива: статус из матрицы,
/// без действий.
class _DisabledAssetTile extends StatelessWidget {
  final VeyroAsset asset;

  const _DisabledAssetTile({required this.asset});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tf(
        'disabled_adapter_tooltip',
        {'status': asset.lifecycle.labelLocalized},
      ),
      child: Opacity(
        opacity: 0.55,
        child: Card(
          child: ListTile(
            enabled: false,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            leading: CoinIcon(asset: asset, radius: 20, key: ValueKey(asset.ticker)),
            title: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: asset.ticker,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                      color: VColors.textPrimary,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const WidgetSpan(child: SizedBox(width: 6)),
                  TextSpan(
                    text: asset.name,
                    style: TextStyle(
                      fontSize: 13,
                      color: VColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            trailing: Icon(Icons.block_outlined,
                size: 18, color: VColors.textSecondary.withValues(alpha: 0.6)),
          ),
        ),
      ),
    );
  }
}
