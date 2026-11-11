//! Экран 11 спеки: Asset catalog — полный справочник реестра проекта
//! (28 строк утверждённой матрицы совместимости). Каталог — справочник
//! статусов, НЕ адаптеры: балансы и сетевые состояния не изобретаются.
//! Синхронизация (btcSync) — реальная сетевая операция и из каталога
//! НЕ вызывается: нативный баланс возникает только в деталях BTC-актива
//! после явной синхронизации пользователем. Избранное — реальное
//! (DisplayPrefs → SQLite-настройки).

import 'package:flutter/material.dart';

import 'package:veyro/data/asset_registry.dart';
import 'package:veyro/design/app_colors.dart';
import 'package:veyro/design/components.dart';
import 'package:veyro/src/rust/api/session.dart';
import 'package:veyro/util/display_prefs.dart';

import 'asset_detail_screen.dart';

/// Селектор-фильтр каталога (по вердиктам матрицы, без выдуманных).
enum CatalogFilter { all, implemented, researched, special }

class AssetCatalogScreen extends StatefulWidget {
  /// Точка замены для виджет-тестов (без RustLib): чтение сессии BTC.
  final Future<BtcSessionStateDto?> Function()? sessionLoader;

  const AssetCatalogScreen({super.key, this.sessionLoader});

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
  }

  Future<void> _toggleFavorite(String ticker) async {
    await DisplayPrefs.toggleFavorite(ticker);
    if (mounted) setState(() {});
  }

  List<VeyroAsset> get _visibleAssets {
    final query = _searchController.text.trim().toLowerCase();
    return kAssetRegistry.where((asset) {
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
          constraints: const BoxConstraints(maxWidth: 720),
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
                              onFavorite: () => _toggleFavorite(asset.ticker),
                              onOpen: () => Navigator.of(context).push(
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
        leading: AssetMonogram(asset: asset),
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

  const AssetMonogram({super.key, required this.asset, this.radius = 18});

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
