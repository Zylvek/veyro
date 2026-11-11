//! Экран 10 спеки: Main dashboard. Кошелёк-селектор, статус подключения,
//! избранное, список активов, последние транзакции (только реальные при
//! активной BTC-сессии), Receive/Send и честный раздел фиата: источника
//! курсов нет — фиатные суммы не отображаются (выдавать выдуманные
//! значения запрещено спекой).

import 'package:flutter/material.dart';

import 'package:veyro/data/asset_registry.dart';
import 'package:veyro/design/app_colors.dart';
import 'package:veyro/design/components.dart';
import 'package:veyro/src/rust/api/btc.dart';
import 'package:veyro/src/rust/api/session.dart';
import 'package:veyro/src/rust/api/wallet.dart';
import 'package:veyro/util/app_dirs.dart';
import 'package:veyro/util/display_prefs.dart';
import 'package:veyro/util/format.dart';

import 'asset_catalog_screen.dart';
import 'asset_detail_screen.dart';
import 'asset_picker_screen.dart';
import 'history_screen.dart';
import 'tx_details_screen.dart';

const List<String> kFiatCurrencies = ['USD', 'EUR', 'RUB', 'CNY'];

class DashboardScreen extends StatefulWidget {
  /// Точки замены для виджет-тестов (обычно — реальные вызовы ядра).
  final Future<List<WalletInfoDto>?> Function()? walletLoader;
  final Future<BtcSessionStateDto?> Function()? sessionLoader;
  final Future<List<BtcHistoryItemDto>> Function()? historyLoader;

  const DashboardScreen({
    super.key,
    this.walletLoader,
    this.sessionLoader,
    this.historyLoader,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<WalletInfoDto>? _wallets;
  String? _selectedId;
  BtcSessionStateDto? _session;
  List<BtcHistoryItemDto>? _recent;
  String? _historyError;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<List<WalletInfoDto>> _loadWallets() async =>
      widget.walletLoader != null
          ? (await widget.walletLoader!()) ?? const []
          : await listWallets(walletsDir: walletsDir());

  Future<BtcSessionStateDto?> _loadSession() async =>
      widget.sessionLoader != null
          ? await widget.sessionLoader!()
          : await btcSessionState();

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
      _recent = null;
      _historyError = null;
    });
    await DisplayPrefs.ensureLoaded();
    final wallets = <WalletInfoDto>[];
    BtcSessionStateDto? session;
    try {
      wallets.addAll(await _loadWallets());
      session = await _loadSession();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
      return;
    }
    if (!mounted) return;
    final selected = DisplayPrefs.walletId != null &&
            wallets.any((w) => w.id == DisplayPrefs.walletId)
        ? DisplayPrefs.walletId
        : (wallets.isEmpty ? null : wallets.first.id);
    setState(() {
      _wallets = wallets;
      _selectedId = selected;
      _session = session;
      _loading = false;
    });
    await _loadRecent();
  }

  /// Последние транзакции — только при активной BTC-сессии; ошибки ядро
  /// отдаёт как есть.
  Future<void> _loadRecent() async {
    if (_session == null) return;
    try {
      final items = widget.historyLoader != null
          ? await widget.historyLoader!()
          : await btcHistory();
      if (!mounted) return;
      setState(() => _recent = items.take(3).toList());
    } catch (e) {
      if (!mounted) return;
      setState(() => _historyError = e.toString());
    }
  }

  Future<void> _selectWallet(String id) async {
    setState(() => _selectedId = id);
    await DisplayPrefs.setWalletId(id);
  }

  Future<void> _toggleHide() async {
    final next = !DisplayPrefs.hideBalances;
    await DisplayPrefs.setHideBalances(next);
    setState(() {});
  }

  WalletInfoDto? get _selected {
    final wallets = _wallets;
    if (wallets == null || wallets.isEmpty) return null;
    return wallets.firstWhere((w) => w.id == _selectedId, orElse: () => wallets.first);
  }

  String _maskAmount(String value) =>
      DisplayPrefs.hideBalances ? '••••••' : value;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Обзор')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? VEmptyState(
                        icon: Icons.cloud_off_outlined,
                        title: 'Ядро недоступно',
                        message: '$_error\nПроверьте установку и повторите.',
                        action: FilledButton.tonal(
                          onPressed: _refresh,
                          child: const Text('Повторить'),
                        ),
                      )
                    : ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        children: [
                          _buildWalletCard(context),
                          const SizedBox(height: 14),
                          _buildPortfolioCard(context),
                          const SizedBox(height: 14),
                          _buildFavoritesCard(context),
                          const SizedBox(height: 14),
                          _buildAssetsCard(context),
                          const SizedBox(height: 14),
                          _buildNetworkCard(context),
                          const SizedBox(height: 14),
                          _buildRecentCard(context),
                        ],
                      ),
          ),
        ),
      ),
    );
  }

  Widget _buildWalletCard(BuildContext context) {
    final wallets = _wallets ?? const <WalletInfoDto>[];
    return VCard(
      icon: Icons.account_balance_wallet_outlined,
      title: 'Кошелёк',
      children: [
        if (wallets.isEmpty)
          Text('Кошельков нет — создайте или импортируйте в разделе '
              '«Кошельки».', style: Theme.of(context).textTheme.bodyMedium)
        else
          DropdownButtonFormField<String>(
            initialValue: _selectedId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Активный кошелёк'),
            items: [
              for (final w in wallets)
                DropdownMenuItem(value: w.id, child: Text(w.name)),
            ],
            onChanged: (id) {
              if (id != null) _selectWallet(id);
            },
          ),
        if (DisplayPrefs.degraded) ...[
          const SizedBox(height: 8),
          const VStatusChip(
            'Настройки не сохраняются: БД недоступна',
            kind: VChipKind.warning,
          ),
        ],
      ],
    );
  }

  Widget _buildPortfolioCard(BuildContext context) {
    final session = _session;
    final selected = _selected;
    return VCard(
      icon: Icons.pie_chart_outline,
      title: 'Итого',
      children: [
        Row(
          children: [
            const Text('Сумма портфеля',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                )),
            const Spacer(),
            IconButton(
              tooltip: DisplayPrefs.hideBalances
                  ? 'Показать суммы'
                  : 'Скрыть суммы',
              icon: Icon(
                DisplayPrefs.hideBalances
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: VColors.textSecondary,
              ),
              onPressed: _toggleHide,
            ),
          ],
        ),
        const SizedBox(height: 4),
        VAmount(_maskAmount('—'), suffix: 'нет данных', fontSize: 26),
        Text(
          'Баланс синхронизируется реальным ядром при открытии BTC-актива. '
          'Пока нет синхронизации — пусто, без выдуманных значений.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (session != null) ...[
              VStatusChip(
                'BTC: ${session.networkDisplay} · сессия активна',
                kind: VChipKind.success,
              ),
              if (session.hasSpendables)
                const VStatusChip(
                  'Есть синхронизированные средства',
                  kind: VChipKind.success,
                ),
            ] else
              const VStatusChip(
                'BTC: сессия не активна',
                kind: VChipKind.neutral,
              ),
          ],
        ),
        const Divider(height: 24),
        Row(
          children: [
            const Text('Валюта отображения:', style: TextStyle(fontSize: 13)),
            const Spacer(),
            DropdownButton<String>(
              value: DisplayPrefs.fiatCurrency,
              underline: const SizedBox.shrink(),
              hint: const Text('—'),
              items: [
                for (final code in kFiatCurrencies)
                  DropdownMenuItem(value: code, child: Text(code)),
              ],
              onChanged: (code) async {
                if (code == null) return;
                await DisplayPrefs.setFiatCurrency(code);
                setState(() {});
              },
            ),
          ],
        ),
        Text(
          'Источник курсов фиата ещё не подключён — фиатные суммы '
          'сознательно не отображаются.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: selected == null
                    ? null
                    : () =>
                        _push(AssetPickerScreen(isReceive: true), reload: true),
                icon: const Icon(Icons.south_west, size: 18),
                label: const Text('Receive'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: selected == null
                    ? null
                    : () => _push(AssetPickerScreen(isReceive: false)),
                icon: const Icon(Icons.north_east, size: 18),
                label: const Text('Send'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFavoritesCard(BuildContext context) {
    final favorites = kAssetRegistry
        .where((a) => DisplayPrefs.favorites.contains(a.ticker))
        .toList();
    return VCard(
      icon: Icons.star_outline,
      title: 'Избранные активы',
      children: [
        if (favorites.isEmpty)
          Text(
            'Пусто. Отметьте активы звёздочкой в каталоге — они появятся '
            'здесь.',
            style: Theme.of(context).textTheme.bodyMedium,
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final asset in favorites)
                ActionChip(
                  avatar: _AssetAvatar(asset),
                  label: Text(asset.ticker),
                  onPressed: () => _push(
                    AssetDetailScreen(asset: asset, wallet: _selected),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildAssetsCard(BuildContext context) {
    final btc = kAssetRegistry.firstWhere((a) => a.ticker == 'BTC');
    return VCard(
      icon: Icons.grid_view_outlined,
      title: 'Активы',
      children: [
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            leading: _AssetAvatar(btc),
            title: Text('Bitcoin'),
            subtitle: Text('Единственный реализованный адаптер'),
            trailing: const VStatusChip(
              'Send supported',
              kind: VChipKind.success,
            ),
            onTap: () =>
                _push(AssetDetailScreen(asset: btc, wallet: _selected)),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Справочник: 28 строк из утверждённой матрицы. Остальные 27 — '
          'статусы Researched/Blocked/исторические: адаптеров нет, '
          'балансов не показываем.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        VButton.secondary(
          'Каталог активов',
          icon: Icons.grid_view_outlined,
          onPressed: () => _push(AssetCatalogScreen()),
        ),
      ],
    );
  }

  Widget _buildNetworkCard(BuildContext context) {
    final session = _session;
    return VCard(
      icon: Icons.lan_outlined,
      title: 'Сеть',
      children: [
        if (session != null) ...[
          VMonoCopyRow(label: 'Сервер', value: session.serverUrl),
          const SizedBox(height: 6),
          Text(
            'Публичный Electrum-сервер выбран в настройках сети; сменить — '
            'раздел «Сеть».',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ] else
          Text(
            'BTC-подключение не активно. Статус появится после разблокировки '
            'актива; конфигурация серверов — в разделе «Сеть».',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
      ],
    );
  }

  Widget _buildRecentCard(BuildContext context) {
    final recent = _recent;
    return VCard(
      icon: Icons.receipt_long_outlined,
      title: 'Последние транзакции',
      children: [
        if (_session == null)
          Text(
            'История доступна после разблокировки BTC-актива (реальные '
            'данные с выбранного сервера).',
            style: Theme.of(context).textTheme.bodyMedium,
          )
        else if (_historyError != null)
          Text(
            'Ядро вернуло ошибку истории: $_historyError',
            style: Theme.of(context)
                .textTheme
                .bodyMedium!
                .copyWith(color: VColors.error),
          )
        else if (recent == null)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (recent.isEmpty)
          Text('Транзакций пока нет — всё чисто.',
              style: Theme.of(context).textTheme.bodyMedium)
        else ...[
          for (final item in recent)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                switch (item.direction) {
                  'incoming' => Icons.south_west,
                  'outgoing' => Icons.north_east,
                  'internal' => Icons.swap_horiz,
                  _ => Icons.help_outline,
                },
                color: VColors.textSecondary,
                size: 18,
              ),
              title: Text(
                switch (item.direction) {
                  'incoming' =>
                    '+${satToBtcString(item.receivedSat.toInt())} BTC',
                  'outgoing' =>
                    '-${satToBtcString(item.sentNetSat.toInt())} BTC',
                  'internal' => '0 BTC',
                  _ => '—',
                },
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              subtitle: Text(
                switch (item.direction) {
                  'incoming' => 'Получение',
                  'outgoing' => 'Отправка',
                  'internal' => 'Внутри кошелька',
                  _ => item.direction,
                },
                style: Theme.of(context).textTheme.bodySmall,
              ),
              trailing: Text(
                item.height >= 1 ? 'высота ${item.height}' : 'в мемпуле',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall!
                    .copyWith(fontFamily: kMonoFont, fontSize: 11),
              ),
              onTap: () =>
                  _push(TxDetailsScreen(
                item: item,
                networkCode: _session?.networkCode,
              )),
            ),
          const SizedBox(height: 4),
          VButton.secondary(
            'Полная история',
            icon: Icons.history,
            onPressed: () => _push(const HistoryScreen(), reload: true),
          ),
        ],
      ],
    );
  }

  Future<void> _push(Widget screen, {bool reload = false}) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted && reload) await _refresh();
  }
}

/// Фолбэк-логотип актива: монограмма на утверждённых цветах (спека:
/// «Logo or approved fallback» — логотипов сетей в проекте нет, честный
/// фолбэк разрешён).
class _AssetAvatar extends StatelessWidget {
  final VeyroAsset asset;

  const _AssetAvatar(this.asset);

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 16,
      backgroundColor: VColors.elevated,
      child: Text(
        asset.ticker.characters.first,
        style: const TextStyle(
          color: VColors.primary,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }
}
