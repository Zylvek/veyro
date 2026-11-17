//! Экран 11 спеки: Asset catalog — полный справочник реестра проекта
//! (28 строк утверждённой матрицы совместимости). Каталог — справочник
//! статусов, НЕ адаптеры: балансы и сетевые состояния не изобретаются.
//! Синхронизация (btcSync) — реальная сетевая операция и из каталога
//! НЕ вызывается: нативный баланс возникает только в деталях BTC-актива
//! после явной синхронизации пользователем. Избранное — реальное
//! (DisplayPrefs → SQLite-настройки).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:veyro/data/asset_registry.dart';
import 'package:veyro/design/app_colors.dart';
import 'package:veyro/design/components.dart';
import 'package:veyro/design/motion.dart';
import 'package:veyro/src/rust/api/session.dart';
import 'package:veyro/src/rust/api/wallet.dart';
import 'package:veyro/util/app_dirs.dart';
import 'package:veyro/util/bch_state_cache.dart';
import 'package:veyro/util/btc_state_cache.dart';
import 'package:veyro/util/coin_balance_view.dart';
import 'package:veyro/util/coin_icons.dart';
import 'package:veyro/util/display_prefs.dart';
import 'package:veyro/util/format.dart';
import 'package:veyro/util/l10n.dart';
import 'package:veyro/util/ltc_state_cache.dart';
import 'package:veyro/util/etc_state_cache.dart';
import 'package:veyro/util/xec_state_cache.dart';
import 'package:veyro/util/rvn_state_cache.dart';

import 'asset_detail_screen.dart';
import 'bch_screen.dart';
import 'btc_screen.dart';
import 'ltc_screen.dart';
import 'etc_screen.dart';
import 'xec_screen.dart';
import 'rvn_screen.dart';

/// Селектор-фильтр каталога (по вердиктам матрицы, без выдуманных).
enum CatalogFilter { all, implemented, researched, special }

class AssetCatalogScreen extends StatefulWidget {
  /// Точка замены для виджет-тестов (без RustLib): чтение сессии BTC.
  final Future<BtcSessionStateDto?> Function()? sessionLoader;

  /// Точка замены: реестр кошелей (для прямого входа в центр BTC).
  final Future<List<WalletInfoDto>> Function()? walletsLoader;

  const AssetCatalogScreen({super.key, this.sessionLoader, this.walletsLoader});

  @override
  State<AssetCatalogScreen> createState() => _AssetCatalogScreenState();
}

class _AssetCatalogScreenState extends State<AssetCatalogScreen> {
  final _searchController = TextEditingController();
  CatalogFilter _filter = CatalogFilter.all;
  bool _prefsLoaded = false;
  String? _error;
  List<WalletInfoDto>? _wallets;

  /// Сортировка: true — A→Я по тикеру; false — исходный порядок матрицы.
  bool _sortAlphabetical = false;

  /// Группировка по состояниям поддержки (аудит §5): заголовки секций
  /// «Реализованные» и честные вердикты матрицы.
  bool _grouped = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    // Пульсы фоновых синков: баланс-строки реализованных монет берут
    // данные из кэшей, обновляемых на Обзоре; перерисовка по факту
    // смены busy-состояния (кэш к этому моменту уже записан).
    BtcConnectState.instance.addListener(_onSyncPulse);
    LtcConnectState.instance.addListener(_onSyncPulse);
    BchConnectState.instance.addListener(_onSyncPulse);
    XecConnectState.instance.addListener(_onSyncPulse);
    EtcConnectState.instance.addListener(_onSyncPulse);
    _load();
  }

  void _onSyncPulse() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    BtcConnectState.instance.removeListener(_onSyncPulse);
    LtcConnectState.instance.removeListener(_onSyncPulse);
    BchConnectState.instance.removeListener(_onSyncPulse);
    XecConnectState.instance.removeListener(_onSyncPulse);
    EtcConnectState.instance.removeListener(_onSyncPulse);
    _searchController.dispose();
    super.dispose();
  }

  /// Живая busy-пометка монеты (тот же источник, что на Обзоре).
  bool _coinBusy(String ticker) => switch (ticker) {
        'BTC' => BtcConnectState.instance.busy,
        'LTC' => LtcConnectState.instance.busy,
        'BCH' => BchConnectState.instance.busy,
        'XEC' => XecConnectState.instance.busy,
        'RVN' => RvnConnectState.instance.busy,
        'ETC' => EtcConnectState.instance.busy,
        _ => false,
      };

  /// Честная баланс-строка реализованной монеты или null (нет данных —
  /// нет строки; никаких выдуманных нулей).
  Widget? _balanceLineFor(VeyroAsset asset, WalletInfoDto? wallet) {
    if (!asset.implemented) return null;
    final ticker = asset.ticker;
    if (ticker == 'ETC') {
      // EVM-честность: wei только строками, арифметика в BigInt.
      final busy = EtcConnectState.instance.busy;
      final sync = wallet?.id == null
          ? null
          : EtcStateCache.instance.take(walletId: wallet!.id);
      if (sync == null && !busy) return null;
      BigInt shown = BigInt.zero;
      BigInt? delta;
      if (sync != null) {
        final confirmed = BigInt.tryParse(sync.confirmedWei);
        if (confirmed != null) {
          delta = BigInt.tryParse(sync.pendingDeltaWei) ?? BigInt.zero;
          final adjusted =
              delta < BigInt.zero ? confirmed + delta : confirmed;
          if (adjusted > BigInt.zero) shown = adjusted;
        }
      }
      return Padding(
        padding: const EdgeInsets.only(top: 2),
        child: sync == null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 11,
                    height: 11,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    t('sync_now_short'),
                    style: TextStyle(
                      fontFamily: kMonoFont,
                      fontSize: 11,
                      color: VColors.warning,
                    ),
                  ),
                ],
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${weiToEtcString(shown.toString())} ETC',
                    style: TextStyle(
                      fontFamily: kMonoFont,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: VColors.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (delta != BigInt.zero) ...[
                    const SizedBox(width: 6),
                    Text(
                      '${weiToEtcString(delta.toString())} ETC',
                      style: TextStyle(
                        fontFamily: kMonoFont,
                        fontSize: 10.5,
                        color: VColors.warning,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      t('mempool_suffix'),
                      style: TextStyle(fontSize: 10.5, color: VColors.warning),
                    ),
                  ],
                ],
              ),
      );
    }
    if (!const {'BTC', 'LTC', 'BCH', 'XEC', 'RVN'}.contains(ticker)) return null;
    final busy = _coinBusy(ticker);
    final view = coinBalanceView(ticker, wallet?.id);
    if (view == null && !busy) return null;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: view == null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 11,
                  height: 11,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 6),
                Text(
                  t('sync_now_short'),
                  style: TextStyle(
                    fontFamily: kMonoFont,
                    fontSize: 11,
                    color: VColors.warning,
                  ),
                ),
              ],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  switch (ticker) {
                    'XEC' => '${satToXecString(view.availableSat)} XEC',
                    _ => '${satToBtcString(view.availableSat)} $ticker',
                  },
                  style: TextStyle(
                    fontFamily: kMonoFont,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: VColors.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (view.mempoolDeltaSat != 0) ...[
                  const SizedBox(width: 6),
                  Text(
                    switch (ticker) {
                      'XEC' =>
                        '${signedSatToXecString(view.mempoolDeltaSat)} XEC',
                      _ =>
                        '${signedSatToBtcString(view.mempoolDeltaSat)} $ticker',
                    },
                    style: TextStyle(
                      fontFamily: kMonoFont,
                      fontSize: 10.5,
                      color: VColors.warning,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    t('mempool_suffix'),
                    style: TextStyle(fontSize: 10.5, color: VColors.warning),
                  ),
                ],
              ],
            ),
    );
  }

  /// Переход с плитки: реализованные — сразу в центр управления (как у
  /// BTC); остальные — честная страница статуса.
  VoidCallback _openAssetTap(VeyroAsset asset) => asset.implemented
      ? () => _openImplemented(asset.ticker)
      : () => pushVeyro<void>(
            context,
            AssetDetailScreen(asset: asset),
          );

  Future<void> _load() async {
    await DisplayPrefs.ensureLoaded();
    if (!mounted) return;
    setState(() => _prefsLoaded = true);
    // Реестр кошелей нужен для прямого входа в центр BTC по тапу на BTC.
    try {
      final wallets = widget.walletsLoader != null
          ? await widget.walletsLoader!()
          : await listWallets(walletsDir: walletsDir());
      if (!mounted) return;
      setState(() {
        _wallets = wallets;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _wallets = const [];
        _error = e.toString();
      });
    }
  }

  /// Выбранный кошелёк (тот же принцип, что на Обзоре): сохранённый
  /// предпочтительный id → первый существующий.
  WalletInfoDto? get _chosenWallet {
    final wallets = _wallets ?? const <WalletInfoDto>[];
    if (wallets.isEmpty) return null;
    final preferredId = DisplayPrefs.walletId;
    for (final w in wallets) {
      if (w.id == preferredId) return w;
    }
    return wallets.first;
  }

  /// Тап по реализованной монете — прямо в её центр управления (тот же
  /// паттерн, что у BTC); без кошельков — честная страница статуса.
  Future<void> _openImplemented(String ticker) async {
    final wallets = _wallets ?? const <WalletInfoDto>[];
    final asset = kAssetRegistry.firstWhere((a) => a.ticker == ticker);
    if (wallets.isEmpty) {
      await pushVeyro<void>(context, AssetDetailScreen(asset: asset));
      return;
    }
    final wallet = _chosenWallet;
    if (wallet == null) {
      await pushVeyro<void>(context, AssetDetailScreen(asset: asset));
      return;
    }
    await pushVeyro<void>(
      context,
      switch (ticker) {
        'BTC' => BtcScreen(info: wallet),
        'BCH' => BchScreen(info: wallet),
        'XEC' => XecScreen(info: wallet),
        'LTC' => LtcScreen(info: wallet),
        'RVN' => RvnScreen(info: wallet),
        'ETC' => EtcScreen(info: wallet),
        _ => AssetDetailScreen(asset: asset),
      },
    );
  }

  Future<void> _toggleFavorite(String ticker) async {
    await DisplayPrefs.toggleFavorite(ticker);
    if (mounted) setState(() {});
  }

  List<VeyroAsset> get _visibleAssets {
    final query = _searchController.text.trim().toLowerCase();
    final result = kAssetRegistry.where((asset) {
      switch (_filter) {
        case CatalogFilter.all:
          break;
        case CatalogFilter.implemented:
          if (!asset.implemented) return false;
        case CatalogFilter.researched:
          if (asset.lifecycle != AssetLifecycle.researched) return false;
        case CatalogFilter.special:
          if (asset.lifecycle == AssetLifecycle.researched) return false;
          if (asset.implemented) return false;
      }
      if (query.isEmpty) return true;
      return asset.ticker.toLowerCase().contains(query) ||
          asset.name.toLowerCase().contains(query) ||
          asset.network.toLowerCase().contains(query);
    }).toList();
    if (_sortAlphabetical) {
      result.sort((a, b) => a.ticker.compareTo(b.ticker));
    }
    return result;
  }

  /// Секции группировки для включённого режима «по статусу»: реализованные
  /// первыми, дальше честные вердикты матрицы, как они названы в паспортах.
  List<MapEntry<String, List<VeyroAsset>>> get _groupedAssets {
    final groups = <String, List<VeyroAsset>>{};
    for (final asset in _visibleAssets) {
      final title = asset.implemented
          ? t('filter_implemented')
          : asset.lifecycle.labelLocalized;
      groups.putIfAbsent(title, () => []).add(asset);
    }
    final ordered = <MapEntry<String, List<VeyroAsset>>>[];
    // Реализованные — всегда первой секцией.
    final implementedTitle = t('filter_implemented');
    if (groups.containsKey(implementedTitle)) {
      ordered.add(MapEntry(implementedTitle, groups.remove(implementedTitle)!));
    }
    final keys = groups.keys.toList()..sort();
    for (final key in keys) {
      ordered.add(MapEntry(key, groups[key]!));
    }
    return ordered;
  }

  /// Честный сетевой статус BTC-строки: только реальные факты FFI.
  /// (Чип статуса сессии убран с плиток каталога по решению владельца.)

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('assets_title'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_outlined),
                    labelText: t('search_hint'),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear_outlined, size: 18),
                            onPressed: () => _searchController.clear(),
                          ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _filterChip(t('filter_all'), CatalogFilter.all),
                    _filterChip(
                      t('filter_implemented'),
                      CatalogFilter.implemented,
                    ),
                    _filterChip(
                      t('filter_researched'),
                      CatalogFilter.researched,
                    ),
                    _filterChip(t('filter_special'), CatalogFilter.special),
                    _toggleChip(
                      t('group_by_status'),
                      _grouped,
                      onToggle: (v) => setState(() => _grouped = v),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: DropdownButton<bool>(
                            value: _sortAlphabetical,
                            underline: const SizedBox.shrink(),
                            isDense: true,
                            items: [
                              DropdownMenuItem(
                                value: false,
                                child: Text(t('sort_matrix')),
                              ),
                              DropdownMenuItem(
                                value: true,
                                child: Text(t('sort_az')),
                              ),
                            ],
                            onChanged: (v) =>
                                setState(() => _sortAlphabetical = v ?? false),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  tf('catalog_note', {'count': '${kAssetRegistry.length}'}),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (_prefsLoaded && DisplayPrefs.degraded)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: VStatusChip(
                      t('prefs_degraded_catalog'),
                      kind: VChipKind.warning,
                    ),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      tf('core_session_read_error', {'error': '$_error'}),
                      style: Theme.of(context).textTheme.bodySmall!
                          .copyWith(color: VColors.warning),
                    ),
                  ),
                ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _load,
                  child: _visibleAssets.isEmpty
                      ? VEmptyState(
                          icon: Icons.search_off,
                          title: t('nothing_found'),
                          message: t('nothing_found_msg'),
                        )
                      : _grouped
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          children: [
                            for (final group in _groupedAssets) ...[
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    '${group.key} · ${group.value.length}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall,
                                  ),
                                ),
                              ),
                              for (final asset in group.value)
                                _AssetTile(
                                  asset: asset,
                                  favorite: DisplayPrefs.favorites.contains(
                                    asset.ticker,
                                  ),
                                  onFavorite: () =>
                                      _toggleFavorite(asset.ticker),
                                  onOpen: _openAssetTap(asset),
                                  balanceLine:
                                      _balanceLineFor(asset, _chosenWallet),
                                ),
                              const SizedBox(height: 10),
                            ],
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          itemCount: _visibleAssets.length,
                          itemBuilder: (context, index) {
                            final asset = _visibleAssets[index];
                            return _AssetTile(
                              asset: asset,
                              favorite: DisplayPrefs.favorites.contains(
                                asset.ticker,
                              ),
                              onFavorite: () => _toggleFavorite(asset.ticker),
                              onOpen: _openAssetTap(asset),
                              balanceLine:
                                  _balanceLineFor(asset, _chosenWallet),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterChip(String label, CatalogFilter filter) {
    final selected = _filter == filter;
    return FilterChip(
      selected: selected,
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          color: selected ? VColors.primary : VColors.textSecondary,
        ),
      ),
      showCheckmark: false,
      side: BorderSide(
        color: selected
            ? VColors.primary.withValues(alpha: 0.5)
            : VColors.elevated,
      ),
      backgroundColor: VColors.card,
      selectedColor: VColors.elevated,
      onSelected: (_) => setState(() => _filter = filter),
    );
  }

  /// Переключатель без привязки к фильтру (группировка).
  Widget _toggleChip(
    String label,
    bool selected, {
    required ValueChanged<bool> onToggle,
  }) {
    return FilterChip(
      selected: selected,
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          color: selected ? VColors.primary : VColors.textSecondary,
        ),
      ),
      showCheckmark: false,
      side: BorderSide(
        color: selected
            ? VColors.primary.withValues(alpha: 0.5)
            : VColors.elevated,
      ),
      backgroundColor: VColors.card,
      selectedColor: VColors.elevated,
      onSelected: onToggle,
    );
  }
}

class _AssetTile extends StatelessWidget {
  final VeyroAsset asset;
  final bool favorite;
  final VoidCallback onFavorite;
  final VoidCallback onOpen;

  /// Строка живого баланса (реализованные монеты) или null — сеть/статус.
  final Widget? balanceLine;

  const _AssetTile({
    required this.asset,
    required this.favorite,
    required this.onFavorite,
    required this.onOpen,
    this.balanceLine,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: CoinIcon(asset: asset, key: ValueKey(asset.ticker)),
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
                style: const TextStyle(
                  fontSize: 13.5,
                  color: VColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                networkLabel(asset.network),
                style: const TextStyle(fontSize: 12),
              ),
              ?balanceLine,
            ],
          ),
        ),
        isThreeLine: balanceLine != null,
        trailing: IconButton(
          tooltip: favorite ? t('fav_remove_tooltip') : t('fav_add_tooltip'),
          icon: Icon(
            favorite ? Icons.star : Icons.star_outline,
            color: favorite ? VColors.warning : VColors.textSecondary,
          ),
          onPressed: onFavorite,
        ),
        onTap: onOpen,
      ),
    );
  }
}

/// Фолбэк-логотип (спека «Logo or approved fallback»): монограмма тикера
/// на утверждённых цветах. Официальных логотипов в проекте нет —
/// честный фолбэк вместо выдуманных картинок.
class AssetMonogram extends StatelessWidget {
  final VeyroAsset asset;
  final double radius;

  const AssetMonogram({super.key, required this.asset, this.radius = 22});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: VColors.elevated,
      child: Text(
        asset.ticker.length <= 2 ? asset.ticker : asset.ticker.substring(0, 2),
        style: TextStyle(
          color: asset.implemented ? VColors.primary : VColors.textSecondary,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.62,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// Иконки монет, уложенные в билд (``assets/coins/<ticker>.png`` —
/// официальные логотипы из CoinGecko). Для активов без загруженной
/// иконки — монограмма-фолбэк выше (спека «Logo or approved fallback»).
const Set<String> kBundledCoinIcons = {
  'ALPH',
  'BCH',
  'BSV',
  'BTC',
  'CFX',
  'DGB',
  'ERG',
  'ETC',
  'ETHW',
  'FB',
  'IRON',
  'KAS',
  'LTC',
  'NEXA',
  'OCTA',
  'QUAI',
  'RVN',
  'XEC',
  'XEL',
  'XMR',
  'XNA',
  'ZEC',
  'ZEPH',
};

/// Иконки монет, уложенные в билд (``assets/coins/<ticker>.svg`` —
/// официальные векторные значки из Kryptex Pool, источник подсказан
/// владельцем; оффлайн и чёткие в любом размере). PNG-набор остаётся
/// запасным оффлайн-фолбэком.
const Set<String> kBundledCoinVectorIcons = {
  'ALPH',
  'BCH',
  'BSV',
  'BTC',
  'CFX',
  'DGB',
  'ERG',
  'ETC',
  'ETHW',
  'FB',
  'IRON',
  'KAS',
  'LTC',
  'NEXA',
  'OCTA',
  'PRL',
  'QTC',
  'QUAI',
  'RVN',
  'XEC',
  'XEL',
  'XNA',
  'XMR',
  'XTM',
  'ZEC',
  'ZEPH',
};

/// Значок монеты: единый круглый контейнер фиксированного размера с
/// тонкой рамкой (как в прототипе владельца), внутри — настоящий вектор
/// (Kryptex → Iconify → PNG → монограмма). contain — узкие лого
/// (Ravencoin, Alephium) рисуются целиком, без обрезки вширь.
class CoinIcon extends StatefulWidget {
  final VeyroAsset asset;
  final double radius;

  const CoinIcon({super.key, required this.asset, this.radius = 22});

  @override
  State<CoinIcon> createState() => _CoinIconState();
}

class _CoinIconState extends State<CoinIcon> {
  /// Кэш текстов бандл-SVG (одна загрузка за процесс).
  static final Map<String, String> _svgCache = <String, String>{};

  bool get _hasVector => kBundledCoinVectorIcons.contains(widget.asset.ticker);

  String? _svg;

  String? _assetTicker;

  @override
  void initState() {
    super.initState();
    _assetTicker = widget.asset.ticker;
    _prepare();
  }

  @override
  void didUpdateWidget(covariant CoinIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Важное: списки (поиск/фильтр) переиспользуют state-виджеты ПО
    // ПОЗИЦИИ — без этого у новой монеты на месте оставался значок
    // прежней («иконки привязаны к месту в списке», реплика владельца).
    // Смена монеты на месте → значок перезагружается по её тикеру.
    if (_assetTicker != widget.asset.ticker) {
      _assetTicker = widget.asset.ticker;
      _svg = null;
      _prepare();
    }
  }

  Future<void> _prepare() async {
    // 1) Бандл-SVG: текст читается один раз за процесс, рисуется
    // векторно через SvgPicture.string (сырой SVG).
    if (_hasVector) {
      final key = widget.asset.ticker.toUpperCase();
      if (!_svgCache.containsKey(key)) {
        try {
          _svgCache[key] = await rootBundle.loadString(
            'assets/coins/${key.toLowerCase()}.svg',
          );
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() => _svg = _svgCache[key]);
      return;
    }
    // 2) Сеть (Iconify) — только для монет вне билда; кэш сервиса.
    if (!kBundledCoinIcons.contains(widget.asset.ticker)) {
      CoinIconService.instance.load(widget.asset.ticker).then((bytes) {
        if (!mounted || bytes == null) return;
        setState(() => _svg = utf8.decode(bytes));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.radius * 2;
    // Настоящий вектор (Kryptex / Iconify) в единой оправе.
    final svg = _svg;
    if (svg != null) {
      return _framed(
        SvgPicture.string(
          svg,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => _pngOrMonogram(size),
        ),
      );
    }
    // Пока SVG читается / не получился — bundle-PNG, затем монограмма.
    return _framed(_pngOrMonogram(size));
  }

  /// Единая круглая оправа: ровный ряд в списках, текст не прыгает.
  Widget _framed(Widget child) {
    final size = widget.radius * 2;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: VColors.elevated.withValues(alpha: 0.35),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      padding: EdgeInsets.all(size * 0.09),
      child: child,
    );
  }

  Widget _pngOrMonogram(double size) {
    if (!kBundledCoinIcons.contains(widget.asset.ticker)) {
      return AssetMonogram(asset: widget.asset, radius: widget.radius);
    }
    return ClipOval(
      child: Image.asset(
        'assets/coins/${widget.asset.ticker.toLowerCase()}.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            AssetMonogram(asset: widget.asset, radius: widget.radius),
      ),
    );
  }
}
