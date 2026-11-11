//! Группа 3 спеки: выбор актива для Receive/Send (мультивалютная обёртка
//! над реальным BTC-потоком). Ядро реализует только адаптер BTC — остальные
//! активы отображаются отключёнными с честным статусом из матрицы
//! (Researched/Blocked/…), без имитации форм и балансов.

import 'package:flutter/material.dart';

import 'package:veyro/data/asset_registry.dart';
import 'package:veyro/design/app_colors.dart';
import 'package:veyro/design/components.dart';
import 'package:veyro/src/rust/api/session.dart';
import 'package:veyro/src/rust/api/wallet.dart';
import 'package:veyro/util/app_dirs.dart';
import 'package:veyro/util/display_prefs.dart';

import 'asset_catalog_screen.dart' show AssetMonogram;
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
  bool _sessionChecked = false;
  String? _sessionError;
  List<WalletInfoDto>? _wallets;
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
      setState(() => _wallets = wallets);
      setState(() => _chosenWallet = chosen);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // Кошельки не прочитать — BTC-переход всё равно честно честный:
        // без списка кошельков разблокировка невозможна.
        _wallets = null;
        _chosenWallet = null;
        _sessionError ??= 'Кошельки не прочитаны: $e';
      });
    }
    try {
      final session = widget.sessionLoader != null
          ? await widget.sessionLoader!()
          : await btcSessionState();
      if (!mounted) return;
      setState(() {
        _session = session;
        _sessionChecked = true;
        _sessionError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _session = null;
        _sessionChecked = true;
        _sessionError = 'Состояние сессии не прочитано: $e';
      });
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
        title: Text(widget.isReceive ? 'Получение — выбор актива' : 'Отправка — выбор актива'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Ядро реализует адаптер только Bitcoin: полный цикл на '
                'testnet4 проверен, остальное — статусы матрицы. Форма '
                'Receive/Send для нереализованных активов не имитируется.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              _BtcTile(
                asset: btc,
                session: _session,
                sessionChecked: _sessionChecked,
                sessionError: _sessionError,
                walletName: _chosenWallet?.name,
                hasWallets: _wallets == null || _wallets!.isNotEmpty,
                onTap: _openBtc,
              ),
              const SizedBox(height: 10),
              for (final asset in others)
                _DisabledAssetTile(asset: asset),
              const SizedBox(height: 10),
              Text(
                'Нужен другой актив? Его адаптер появится в ядре после '
                'реализации сети (см. матрицу и паспорта в каталоге) — '
                'не раньше.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
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
  final BtcSessionStateDto? session;
  final bool sessionChecked;
  final String? sessionError;
  final String? walletName;
  final bool hasWallets;
  final VoidCallback onTap;

  const _BtcTile({
    required this.asset,
    required this.session,
    required this.sessionChecked,
    required this.sessionError,
    required this.walletName,
    required this.hasWallets,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final unlocked = session != null;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: AssetMonogram(asset: asset, radius: 20),
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
                text: 'Bitcoin · реализован',
                style: TextStyle(
                  fontSize: 13,
                  color: VColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              VStatusChip('Send supported', kind: asset.lifecycle.chipKind),
              if (!sessionChecked)
                const VStatusChip('Статус сессии: …', kind: VChipKind.neutral)
              else if (sessionError != null)
                VStatusChip('Ядро недоступно', kind: VChipKind.warning)
              else if (unlocked)
                VStatusChip(
                    'Сессия: ${session!.networkDisplay} — форма открыта',
                    kind: VChipKind.success)
              else if (!hasWallets)
                const VStatusChip('Нет кошельков — создать в «Кошельки»',
                    kind: VChipKind.warning)
              else
                VStatusChip(
                    'Сессия закрыта — разблокировать: '
                    '${walletName ?? 'кошелёк не выбран'}',
                    kind: VChipKind.info),
            ],
          ),
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right, size: 18, color: VColors.textSecondary),
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
      message: 'Receive/Send недоступны: адаптер этой сети не реализован '
          'в ядре (${asset.lifecycle.label}).',
      child: Opacity(
        opacity: 0.55,
        child: Card(
          child: ListTile(
            enabled: false,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            leading: AssetMonogram(asset: asset, radius: 20),
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
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  VStatusChip(asset.lifecycle.label,
                      kind: asset.lifecycle.chipKind),
                ],
              ),
            ),
            isThreeLine: true,
            trailing: Icon(Icons.block_outlined,
                size: 18, color: VColors.textSecondary.withValues(alpha: 0.6)),
          ),
        ),
      ),
    );
  }
}
