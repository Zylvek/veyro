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

import 'asset_catalog_screen.dart' show CoinIcon;
import 'asset_detail_screen.dart';
import 'asset_picker_screen.dart';
import 'portfolio_screen.dart';
import 'history_screen.dart';
import 'tx_details_screen.dart';

class DashboardScreen extends StatefulWidget {
  /// Точки замены для виджет-тестов (обычно — реальные вызовы ядра).
  final Future<List<WalletInfoDto>?> Function()? walletLoader;
  final Future<BtcSessionStateDto?> Function()? sessionLoader;
  final Future<List<BtcHistoryItemDto>> Function()? historyLoader;

  /// Авто-переход к кошелёку/паролю при закрытой сессии включён по
  /// умолчанию (поток владельца); тесты верстки передают false.
  final bool autoOpenWallet;

  const DashboardScreen({
    super.key,
    this.walletLoader,
    this.sessionLoader,
    this.historyLoader,
    this.autoOpenWallet = true,
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

  /// Авто-переход к паролю: при закрытой BTC-сессии один раз за вход
  /// Обзор сам открывает кошелёк (выбранный/первый) → портфель → BTC,
  /// где сразу спрашивается пароль. Отключается в тестах верстки.
  var _btcAutoOpened = false;

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
    // Сразу к паролю (решение владельца): закрытая сессия и есть кошельки
    // → один раз за вход открываем портфель (тот перебрасывает в BTC,
    // а BTC сразу показывает диалог пароля).
    if (widget.autoOpenWallet &&
        !_btcAutoOpened &&
        mounted &&
        _error == null &&
        _session == null &&
        _wallets?.isNotEmpty == true) {
      _btcAutoOpened = true;
      await _push(PortfolioScreen(info: _selected!));
    }
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
          constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: VEmptyState(
                          icon: Icons.cloud_off_outlined,
                          title: 'Ядро недоступно',
                          message: '$_error\nПроверьте установку и повторите.',
                          action: FilledButton.tonal(
                            onPressed: _refresh,
                            child: const Text('Повторить'),
                          ),
                        ),
                      )
                    : ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(20),
                        children: [
                          _buildTopPanel(context),
                          const SizedBox(height: 14),
                          _buildBalanceBlock(context),
                          const SizedBox(height: 14),
                          _buildActionsRow(context),
                          const SizedBox(height: 20),
                          VTwoColumn(
                            left: Column(
                              children: [
                                _buildAssetsCard(context),
                                const SizedBox(height: 16),
                                _buildFavoritesCard(context),
                              ],
                            ),
                            right: Column(
                              children: [
                                _buildNetworkCard(context),
                                const SizedBox(height: 16),
                                _buildRecentCard(context),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
          ),
        ),
      ),
    );
  }

  /// Компактная верхняя панель (аудит §4): выбор кошелька, чип состояния
  /// BTC-сессии и переключатель скрытия сумм — в одну строку.
  Widget _buildTopPanel(BuildContext context) {
    final wallets = _wallets ?? const <WalletInfoDto>[];
    final session = _session;
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: DropdownButtonFormField<String>(
                initialValue: _selectedId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Активный кошелёк',
                  border: InputBorder.none,
                ),
                items: [
                  for (final w in wallets)
                    DropdownMenuItem(value: w.id, child: Text(w.name)),
                ],
                onChanged: (id) {
                  if (id != null) _selectWallet(id);
                },
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              if (DisplayPrefs.degraded)
                const VStatusChip(
                  'БД настроек недоступна',
                  kind: VChipKind.warning,
                ),
              if (session != null)
                VStatusChip(
                  'BTC: ${session.networkDisplay}',
                  kind: VChipKind.success,
                )
              else
                const VStatusChip(
                  'BTC: сессия не активна',
                  kind: VChipKind.neutral,
                ),
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
        ),
      ],
    );
  }

  /// Крупный блок общего баланса (аудит §4): финансовые значения с
  /// правильной иерархией. Честное отсутствие данных: ядро ещё не
  /// синхронизировано — «—», без выдуманных значений. Источника цен
  /// пока нет — фиатная строка не показывается вовсе.
  Widget _buildBalanceBlock(BuildContext context) {
    final session = _session;
    return VCard(
      icon: Icons.pie_chart_outline,
      title: 'Сумма портфеля',
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            VAmount(_maskAmount('—'), suffix: 'нет данных', fontSize: 34),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (session != null && session.hasSpendables)
                  const VStatusChip(
                    'Есть синхронизированные средства',
                    kind: VChipKind.success,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Сумма собирается синхронизацией BTC-актива после '
              'разблокировки; цены в фиате появятся с источником курсов',
              style: TextStyle(color: VColors.textSecondary, fontSize: 12.5),
            ),
          ],
        ),
      ],
    );
  }

  /// Receive / Send — реальный вход в поток через выбор актива.
  Widget _buildActionsRow(BuildContext context) {
    final selected = _selected;
    return Row(
      children: [
        Expanded(
          child: VButton.primary(
            'Receive',
            icon: Icons.south_west,
            onPressed: selected == null
                ? null
                : () => _push(AssetPickerScreen(isReceive: true), reload: true),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: VButton.primary(
            'Send',
            icon: Icons.north_east,
            onPressed: selected == null
                ? null
                : () => _push(AssetPickerScreen(isReceive: false)),
          ),
        ),
      ],
    );
  }

  Widget _buildFavoritesCard(BuildContext context) {
    final favorites = kAssetRegistry
        .where((a) => DisplayPrefs.favorites.contains(a.ticker))
        .toList();
    // Пустое избранное — карточки нет вовсе (решение владельца: без
    // подсказок-лекций на Обзоре).
    if (favorites.isEmpty) return const SizedBox.shrink();
    return VCard(
      icon: Icons.star_outline,
      title: 'Избранные активы',
      children: [
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
      ],
    );
  }

  Widget _buildNetworkCard(BuildContext context) {
    final session = _session;
    // Без активной сессии карточки сети нет вовсе — статус сети и так
    // в чипе «Итого», а настройка живёт в разделе «Сеть» и центре BTC.
    if (session == null) return const SizedBox.shrink();
    return VCard(
      icon: Icons.lan_outlined,
      title: 'Сеть',
      children: [
        VMonoCopyRow(label: 'Сервер', value: session.serverUrl),
      ],
    );
  }

  Widget _buildRecentCard(BuildContext context) {
    final recent = _recent;
    // Без активной сессии истории нет и карточки нет (состояние сессии
    // уже показывает чип «Итого»); без лекций на Обзоре.
    if (_session == null) return const SizedBox.shrink();
    return VCard(
      icon: Icons.receipt_long_outlined,
      title: 'Последние транзакции',
      children: [
        if (_historyError != null)
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
    return CoinIcon(asset: asset);
  }
}
