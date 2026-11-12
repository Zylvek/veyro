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
import 'package:veyro/util/btc_state_cache.dart';
import 'package:veyro/util/display_prefs.dart';
import 'package:veyro/util/format.dart';
import 'package:veyro/util/price_source.dart';

import 'asset_catalog_screen.dart' show CoinIcon;
import 'asset_detail_screen.dart';
import 'asset_picker_screen.dart';
import 'btc_screen.dart';
import 'history_screen.dart';
import 'tx_details_screen.dart';

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

  /// Стартовая политика (решение владельца): приложение открывается
  /// СПОКОЙНО на Обзоре — без стартовых модалок и авто-переходов в
  /// разблокировку. Подключение BTC — когда пользователь заходит в
  /// BTC-поток (там пароль спрашивается сам).
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

  /// Курс BTC в валюте отображения; null — курс недоступен (сети нет),
  /// тогда фиатная строка честно скрыта.
  double? _fiatRate;

  /// Курс ETH в валюте отображения — эквивалент в подписи «≈ X ETH»
  /// (как в референсе владельца). Нет курса — подпись скрыта.
  double? _ethRate;

  /// Активное окно реального графика курса (референс: 1D/1W/1M/1Y).
  String _period = '1М';

  /// Окна period-табов в днях (параметр провайдера цен).
  static const Map<String, int> _periodDays = {
    '1Д': 1,
    '1Н': 7,
    '1М': 30,
    '1Г': 365,
  };

  /// Реальная линия курса ЭФИРА (валюта отображения) за окно периода —
  /// график Обзора по требованию владельца, как в референсе Nexus.
  /// От прямого провайдера цен; null — данных нет, график скрыт.
  List<MarketPoint>? _marketPoints;

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
    // Курс BTC и ETH в валюте отображения — прямой запрос к провайдеру
    // цен (без собственного сервера). Ошибка → строки скрыты.
    try {
      final fiat = DisplayPrefs.fiatCurrency;
      final source = PriceSource.instance;
      final rate = await source
          .btcPriceIn(fiat)
          .timeout(const Duration(seconds: 12));
      if (!mounted) return;
      final ethRate = await source
          .ethPriceIn(fiat)
          .timeout(const Duration(seconds: 12));
      if (!mounted) return;
      setState(() {
        _fiatRate = rate;
        _ethRate = ethRate;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _fiatRate = null;
        _ethRate = null;
      });
    }
    // Реальный график курса за активное окно периода.
    await _loadMarketSeries();
  }

  /// Реальная линия курса ЭФИРА (прямой провайдер цен; владелец:
  /// график — Ethereum, как в референсе) за окно периода; ошибки →
  /// график скрыт, без выдуманной линии.
  Future<void> _loadMarketSeries() async {
    final fiat = DisplayPrefs.fiatCurrency;
    final days = _periodDays[_period] ?? 30;
    try {
      final series = await PriceSource.instance
          .marketSeries('ethereum', fiat, days)
          .timeout(const Duration(seconds: 12));
      if (!mounted) return;
      setState(() => _marketPoints = series);
    } catch (_) {
      if (!mounted) return;
      setState(() => _marketPoints = null);
    }
  }

  /// Цены серии для линии.
  List<double>? get _seriesPrices =>
      _marketPoints?.map((p) => p.price).toList();

  /// Подписи точек для наведения: «цена · время» (реальные данные
  /// провайдера; окно до суток → только часы:минуты, длинные → дата).
  List<String>? get _seriesHints {
    final points = _marketPoints;
    if (points == null || points.isEmpty) return null;
    final compact =
        points.last.time.difference(points.first.time).inHours <= 34;
    return [for (final p in points) _marketLabel(p, compact)];
  }

  String _marketLabel(MarketPoint point, bool compact) {
    String pad(int v) => v.toString().padLeft(2, '0');
    final t = point.time;
    final currency = DisplayPrefs.fiatCurrency.toUpperCase();
    final price = '${formatFiat(point.price)} $currency';
    final time = compact
        ? '${pad(t.hour)}:${pad(t.minute)}'
        : '${pad(t.day)}.${pad(t.month)}';
    return '$price · $time';
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

  /// Верхняя панель как в референсе владельца: заголовок страницы слева,
  /// справа — компактный выбор кошелька и переключатель скрытия сумм.
  Widget _buildTopPanel(BuildContext context) {
    final wallets = _wallets ?? const <WalletInfoDto>[];
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Обзор',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Активы и активность',
                style: TextStyle(
                  fontSize: 12.5,
                  color: VColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Flexible(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              child: DropdownButtonFormField<String>(
                initialValue: _selectedId,
                isExpanded: true,
                isDense: true,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(vertical: 10, horizontal: 6),
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

  /// Hero-карта баланса (референс владельца «Nexus»: большая тёмная
  /// карта с подсветками): label, крупная сумма (общая цена в валюте
  /// отображения; курс недоступен — сумма в BTC) и подпись «≈ N ETH» —
  /// эквивалент суммы в эфире по реальному курсу провайдера, ровно как
  /// в референсе («Total balance → ≈ 7.4211 ETH»). Под ними РЕАЛЬНЫЙ
  /// график курса ЭФИРА за окно периода (требование владельца). Динамику
  /// в процентах не рисуем — данных о ней ядро не отдаёт.
  Widget _buildBalanceBlock(BuildContext context) {
    final session = _session;
    final balanceSat = _btcBalanceSat();
    final rate = _fiatRate;
    return VHeroPanel(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  'Общий баланс',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: VColors.textSecondary,
                  ),
                ),
                const Spacer(),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    if (session != null && session.hasSpendables)
                      const VStatusChip(
                        'Есть синхронизированные средства',
                        kind: VChipKind.success,
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Общая цена валют (решение владельца: «только общую цену
            // валют и всё»): одно число. Курса нет — сумма в BTC.
            if (rate != null)
              VAmount(
                _maskAmount(formatFiat(balanceSat / 1e8 * rate)),
                suffix: DisplayPrefs.fiatCurrency.toUpperCase(),
                fontSize: 42,
              )
            else
              VAmount(
                _maskAmount(satToBtcString(balanceSat)),
                suffix: 'BTC',
                fontSize: 42,
              ),
            const SizedBox(height: 6),
            // Эквивалент суммы в ETH — как в референсе владельца
            // («Total balance → ≈ N ETH»); курса ETH нет — строки нет.
            if (rate != null && _ethRate != null && _ethRate! > 0)
              Text(
                '≈ ${_maskAmount((balanceSat / 1e8 * rate / _ethRate!).toStringAsFixed(4))} ETH',
                style: TextStyle(
                  fontFamily: kMonoFont,
                  fontSize: 13,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: VColors.textSecondary,
                ),
              ),
            const SizedBox(height: 12),
            // Реальный график курса ЭФИРА за окно периода (прямой
            // провайдер цен, как в референсе владельца), при наведении —
            // цена точки и время.
            if (_seriesPrices != null && _seriesPrices!.length >= 2) ...[
              VSparkline(
                values: _seriesPrices!,
                hints: _seriesHints,
              ),
              const SizedBox(height: 6),
            ],
            _buildPeriodTabs(),
          ],
        ),
      ),
    );
  }

  /// Вкладки окна реального графика курса: 1Д/1Н/1М/1Г (как в
  /// референсе); переключение окна перезагружает серию.
  Widget _buildPeriodTabs() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final entry in _periodDays.entries)
          Padding(
            padding: const EdgeInsets.only(right: 4, bottom: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                if (_period == entry.key) return;
                setState(() => _period = entry.key);
                _loadMarketSeries();
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: _period == entry.key
                      ? Colors.white.withValues(alpha: 0.09)
                      : Colors.transparent,
                ),
                child: Text(
                  entry.key,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _period == entry.key
                        ? VColors.textPrimary
                        : VColors.textSecondary.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Реальный подтверждённый баланс BTC из последней синхронизации
  /// (кэш от экрана входа/центра). Данных нет — 0 (решение владельца).
  int _btcBalanceSat() {
    final sync = BtcStateCache.instance.take();
    if (sync == null) return 0;
    final confirmed = sync.confirmedSat.toInt();
    final delta = sync.unconfirmedDeltaSat.toInt();
    return delta < 0 ? confirmed + delta : confirmed;
  }

  /// Receive / Send — как в референсе: Send — основная (заполненная),
  /// Receive — спокойная. Реальный вход в поток через выбор актива.
  Widget _buildActionsRow(BuildContext context) {
    final selected = _selected;
    return Row(
      children: [
        Expanded(
          child: VButton.primary(
            'Send',
            icon: Icons.north_east,
            onPressed: selected == null
                ? null
                : () => _push(AssetPickerScreen(isReceive: false)),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: VButton.secondary(
            'Receive',
            icon: Icons.south_west,
            onPressed: selected == null
                ? null
                : () => _push(AssetPickerScreen(isReceive: true), reload: true),
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
    final wallet = _selected;
    // Сумма монеты — реальный подтверждённый баланс из последней
    // синхронизации (кэш; без данных — 0 по решению владельца).
    final sync = BtcStateCache.instance.take();
    final balanceSat = _btcBalanceSat();
    final rate = _fiatRate;
    return VCard(
      icon: Icons.grid_view_outlined,
      title: 'Активы',
      children: [
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            leading: _AssetAvatar(btc),
            title: const Text('Bitcoin'),
            // Количество под именем — как в референсе.
            subtitle: Text(
              '${_maskAmount(satToBtcString(balanceSat))} BTC',
              style: const TextStyle(
                fontFamily: kMonoFont,
                fontSize: 11.5,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Фиатное выражение позиции — от того же курса, что и
                // hero-карта; курса нет — справа пусто (без выдумок).
                if (rate != null) ...[
                  Text(
                    _maskAmount(formatFiat(balanceSat / 1e8 * rate)),
                    style: const TextStyle(
                      fontFamily: kMonoFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                      color: VColors.textPrimary,
                    ),
                  ),
                  Text(
                    DisplayPrefs.fiatCurrency.toUpperCase(),
                    style: const TextStyle(
                      fontFamily: kMonoFont,
                      fontSize: 11,
                      color: VColors.textSecondary,
                    ),
                  ),
                ],
                if (sync != null && sync.unconfirmedDeltaSat.toInt() != 0)
                  Text(
                    '${signedSatToBtcString(sync.unconfirmedDeltaSat.toInt())} BTC (мемпул)',
                    style: TextStyle(
                      fontFamily: kMonoFont,
                      fontSize: 11,
                      color: VColors.warning,
                    ),
                  ),
              ],
            ),
            // Тап по BTC → сразу центр управления (решение владельца:
            // никакой промежуточной страницы деталей).
            onTap: wallet == null
                ? null
                : () => _push(BtcScreen(info: wallet)),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentCard(BuildContext context) {
    final recent = _recent;
    // Без активной сессии — истории нет и карточки нет (состояние
    // сессии уже видно в центре BTC). Ошибка ядра (нет просканированных
    // адресов до btc_sync) — сырым текстом на Обзоре не сыпем:
    // Обзор остаётся спокойным, диагностика — в центре BTC.
    if (_session == null || _historyError != null) {
      return const SizedBox.shrink();
    }
    return VCard(
      icon: Icons.receipt_long_outlined,
      title: 'Последние транзакции',
      children: [
        if (recent == null)
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
              // Кружок-иконка как в референсе: зелёный приход, красный
              // уход, нейтральный internal.
              leading: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: switch (item.direction) {
                    'incoming' => VColors.success.withValues(alpha: 0.14),
                    'outgoing' => VColors.error.withValues(alpha: 0.14),
                    _ => VColors.elevated,
                  },
                ),
                child: Icon(
                  switch (item.direction) {
                    'incoming' => Icons.south_west,
                    'outgoing' => Icons.north_east,
                    'internal' => Icons.swap_horiz,
                    _ => Icons.help_outline,
                  },
                  size: 16,
                  color: switch (item.direction) {
                    'incoming' => VColors.success,
                    'outgoing' => VColors.error,
                    _ => VColors.textSecondary,
                  },
                ),
              ),
              title: Text(
                switch (item.direction) {
                  'incoming' => 'Получение BTC',
                  'outgoing' => 'Отправка BTC',
                  'internal' => 'Внутри кошелька',
                  _ => item.direction,
                },
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                item.height >= 1 ? 'высота ${item.height}' : 'в мемпуле',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall!
                    .copyWith(fontFamily: kMonoFont, fontSize: 11),
              ),
              // Сумма справа, цветом направления.
              trailing: Text(
                switch (item.direction) {
                  'incoming' =>
                    '+${satToBtcString(item.receivedSat.toInt())} BTC',
                  'outgoing' =>
                    '-${satToBtcString(item.sentNetSat.toInt())} BTC',
                  'internal' => '0 BTC',
                  _ => '—',
                },
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: switch (item.direction) {
                    'incoming' => VColors.success,
                    'outgoing' => VColors.error,
                    _ => VColors.textPrimary,
                  },
                ),
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
    debugPrint('veyro-flow: overview pushing ${screen.runtimeType}');
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    debugPrint('veyro-flow: overview push returned');
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
