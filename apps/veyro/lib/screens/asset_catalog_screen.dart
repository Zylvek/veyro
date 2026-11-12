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
import 'package:veyro/src/rust/api/session.dart';
import 'package:veyro/src/rust/api/wallet.dart';
import 'package:veyro/util/app_dirs.dart';
import 'package:veyro/util/coin_icons.dart';
import 'package:veyro/util/display_prefs.dart';

import 'asset_detail_screen.dart';
import 'btc_screen.dart';

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
  BtcSessionStateDto? _btcSession;
  bool _sessionChecked = false;
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
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await DisplayPrefs.ensureLoaded();
    if (!mounted) return;
    setState(() => _prefsLoaded = true);
    // Состояние сессии — дешёвое FFI-чтение (без сети), как на портфеле.
    // null = сессия закрыта: это честное отсутствие данных, не ошибка.
    try {
      final session = widget.sessionLoader != null
          ? await widget.sessionLoader!()
          : await btcSessionState();
      if (!mounted) return;
      setState(() {
        _btcSession = session;
        _sessionChecked = true;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sessionChecked = true;
        _error = e.toString();
      });
    }
    // Реестр кошелей нужен для прямого входа в центр BTC по тапу на BTC.
    try {
      final wallets = widget.walletsLoader != null
          ? await widget.walletsLoader!()
          : await listWallets(walletsDir: walletsDir());
      if (!mounted) return;
      setState(() => _wallets = wallets);
    } catch (_) {
      if (!mounted) return;
      setState(() => _wallets = const []);
    }
  }

  /// Тап по BTC (решение владельца: сразу центр управления, без страницы
  /// деталей). Нужен кошелёк: сохранённый → первый; без кошельков —
  /// откат на честную страницу статуса BTC.
  Future<void> _openBtc() async {
    final wallets = _wallets ?? const <WalletInfoDto>[];
    if (wallets.isEmpty) {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => AssetDetailScreen(
          asset: kAssetRegistry.firstWhere((a) => a.ticker == 'BTC'),
        ),
      ));
      return;
    }
    final preferredId = DisplayPrefs.walletId;
    WalletInfoDto? chosen;
    for (final w in wallets) {
      if (w.id == preferredId) chosen = w;
    }
    chosen ??= wallets.first;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BtcScreen(info: chosen!),
    ));
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
      final title = asset.implemented ? 'Реализованные' : asset.lifecycle.label;
      groups.putIfAbsent(title, () => []).add(asset);
    }
    final ordered = <MapEntry<String, List<VeyroAsset>>>[];
    // Реализованные — всегда первой секцией.
    if (groups.containsKey('Реализованные')) {
      ordered.add(MapEntry('Реализованные', groups.remove('Реализованные')!));
    }
    final keys = groups.keys.toList()..sort();
    for (final key in keys) {
      ordered.add(MapEntry(key, groups[key]!));
    }
    return ordered;
  }

  /// Честный сетевой статус BTC-строки: только реальные факты FFI.
  String _btcStatusChip() {
    if (!_sessionChecked) return 'Статус: …';
    if (_error != null) return 'Ядро недоступно';
    final session = _btcSession;
    if (session == null) return 'Сессия закрыта (нужен пароль)';
    return 'Сессия: ${session.networkDisplay}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Активы')),
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
                    labelText: 'Поиск: тикер, имя или сеть',
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _filterChip('Все', CatalogFilter.all),
                    _filterChip('Реализованные', CatalogFilter.implemented),
                    _filterChip('Researched', CatalogFilter.researched),
                    _filterChip('Особые статусы', CatalogFilter.special),
                    _toggleChip(
                      'Группировать по статусу',
                      _grouped,
                      onToggle: (v) => setState(() => _grouped = v),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Card(
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 10),
                          child: DropdownButton<bool>(
                            value: _sortAlphabetical,
                            underline: const SizedBox.shrink(),
                            isDense: true,
                            items: const [
                              DropdownMenuItem(
                                value: false,
                                child: Text('Порядок матрицы'),
                              ),
                              DropdownMenuItem(
                                value: true,
                                child: Text('A→Я по тикеру'),
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
                  'Справочник статусов ${kAssetRegistry.length} активов. '
                  'Балансы и транзакции — только реализованные активы; '
                  'остальное — честные вердикты матрицы, без имитаций.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (_prefsLoaded && DisplayPrefs.degraded)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: VStatusChip(
                      'Настройки не сохраняются: БД недоступна',
                      kind: VChipKind.warning,
                    ),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Ядро недоступно (состояние сессии BTC не прочитано): '
                      '$_error',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall!
                          .copyWith(color: VColors.warning),
                    ),
                  ),
                ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _load,
                  child: _visibleAssets.isEmpty
                      ? const VEmptyState(
                          icon: Icons.search_off,
                          title: 'Ничего не найдено',
                          message: 'По запросу нет активов в реестре. '
                              'Измените фильтр или строку поиска.',
                        )
                      : _grouped
                          ? ListView(
                              physics:
                                  const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(16),
                              children: [
                                for (final group in _groupedAssets) ...[
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 6),
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
                                      favorite: DisplayPrefs.favorites
                                          .contains(asset.ticker),
                                      btcStatusText: asset.ticker == 'BTC'
                                          ? _btcStatusChip()
                                          : null,
                                      onFavorite: () =>
                                          _toggleFavorite(asset.ticker),
                                      onOpen: asset.ticker == 'BTC' ? _openBtc : () => Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) => AssetDetailScreen(
                                              asset: asset),
                                        ),
                                      ),
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
                                  favorite: DisplayPrefs.favorites
                                      .contains(asset.ticker),
                                  btcStatusText: asset.ticker == 'BTC'
                                      ? _btcStatusChip()
                                      : null,
                                  onFavorite: () =>
                                      _toggleFavorite(asset.ticker),
                                  onOpen: asset.ticker == 'BTC' ? _openBtc : () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          AssetDetailScreen(asset: asset),
                                    ),
                                  ),
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
  final String? btcStatusText;
  final VoidCallback onFavorite;
  final VoidCallback onOpen;

  const _AssetTile({
    required this.asset,
    required this.favorite,
    required this.onFavorite,
    required this.onOpen,
    this.btcStatusText,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: CoinIcon(asset: asset),
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
            children: [
              Text(asset.network, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  VStatusChip(asset.lifecycle.label,
                      kind: asset.lifecycle.chipKind),
                  if (btcStatusText != null)
                    VStatusChip(btcStatusText!, kind: VChipKind.info),
                ],
              ),
            ],
          ),
        ),
        isThreeLine: true,
        trailing: IconButton(
          tooltip: favorite ? 'Убрать из избранного' : 'В избранное',
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
  'ALPH', 'BCH', 'BSV', 'BTC', 'CFX', 'DGB', 'ERG', 'ETC', 'ETHW', 'FB',
  'IRON', 'KAS', 'LTC', 'NEXA', 'OCTA', 'QUAI', 'RVN', 'XEC', 'XEL',
  'XMR', 'XNA', 'ZEC', 'ZEPH',
};

/// Иконки монет, уложенные в билд (``assets/coins/<ticker>.svg`` —
/// официальные векторные значки из Kryptex Pool, источник подсказан
/// владельцем; оффлайн и чёткие в любом размере). PNG-набор остаётся
/// запасным оффлайн-фолбэком.
const Set<String> kBundledCoinVectorIcons = {
  'ALPH', 'BCH', 'BSV', 'BTC', 'CFX', 'DGB', 'ERG', 'ETC', 'ETHW', 'FB',
  'IRON', 'KAS', 'LTC', 'NEXA', 'OCTA', 'PRL', 'QTC', 'QUAI', 'RVN', 'XEC',
  'XEL', 'XNA', 'XMR', 'XTM', 'ZEC', 'ZEPH',
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

  bool get _hasVector =>
      kBundledCoinVectorIcons.contains(widget.asset.ticker);

  String? _svg;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    // 1) Бандл-SVG: текст читается один раз за процесс, рисуется
    // векторно через SvgPicture.string (сырой SVG).
    if (_hasVector) {
      final key = widget.asset.ticker.toUpperCase();
      if (!_svgCache.containsKey(key)) {
        try {
          _svgCache[key] = await rootBundle
              .loadString('assets/coins/${key.toLowerCase()}.svg');
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
      return _framed(SvgPicture.string(
        svg,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => _pngOrMonogram(size),
      ));
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
