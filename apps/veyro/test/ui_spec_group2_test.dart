//! Тесты группы 2 спеки UI (docs/UI_SPEC.md): Dashboard, Asset catalog,
//! Asset details. Без RustLib: все экраны имеют injectable-загрузчики,
//!(DisplayPrefs честно деградирует в память при недоступной БД).
//!
//! Ключевые гарантии:
//! 1) реестр = утверждённая матрица (26 строк, честный ценз статусов);
//! 2) каталог рендерит реестр целиком/фильтрами без вызовов FFI;
//! 3) dashboard показывает только реальные данные (нет балансов, нет
//!    транзакций без активной сессии, честные чипы сети);
//! 4) детали BTC не имитируют синхронизацию, детали остальных активов
//!    честно говорят, что адаптеров нет.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veyro/design/components.dart';
import 'package:veyro/data/asset_registry.dart';
import 'package:veyro/src/rust/api/btc.dart';
import 'package:veyro/src/rust/api/session.dart';
import 'package:veyro/src/rust/api/wallet.dart';
import 'package:veyro/screens/asset_catalog_screen.dart';
import 'package:veyro/screens/asset_detail_screen.dart';
import 'package:veyro/screens/dashboard_screen.dart';
import 'package:veyro/screens/settings_screen.dart';
import 'package:veyro/util/coin_icons.dart';
import 'package:veyro/util/display_prefs.dart';
import 'package:veyro/util/price_source.dart';

WalletInfoDto _wallet(String id, String name) => WalletInfoDto(
      id: id,
      name: name,
      createdAtUnix: BigInt.from(1730000000),
    );

void main() {
  // Значки валют: тесты без сети и без дискового кэша — монограммы.
  setUp(() {
    CoinIconService.instance.resetForTest();
    CoinIconService.useDiskCache = false;
    CoinIconService.fetcher = (ticker) async => null;
  });
  tearDown(() {
    CoinIconService.fetcher = null;
    CoinIconService.instance.resetForTest();
  });

  group('Реестр активов (26 строк утверждённой матрицы)', () {
    test('состав вердиктов совпадает с матрицей', () {
      expect(kAssetRegistry.length, 26);

      final researched = kAssetRegistry
          .where((a) => a.lifecycle == AssetLifecycle.researched)
          .toList();
      final sendSupported = kAssetRegistry
          .where((a) => a.lifecycle == AssetLifecycle.sendSupported)
          .toList();
      final receiveSupported = kAssetRegistry
          .where((a) => a.lifecycle == AssetLifecycle.receiveSupported)
          .toList();
      final researchRequired = kAssetRegistry
          .where((a) => a.lifecycle == AssetLifecycle.researchRequired)
          .toList();
      final blocked = kAssetRegistry
          .where((a) => a.lifecycle == AssetLifecycle.blocked)
          .toList();
      final historical = kAssetRegistry
          .where((a) => a.lifecycle == AssetLifecycle.historical)
          .toList();

      // LTC реализован в ядре (receive-only, 15.11.2026) — второй
      // реализованный актив.
      expect(researched.length, 23);
      expect(sendSupported.length, 1);
      expect(receiveSupported.length, 1);
      expect(researchRequired.length, 0);
      expect(blocked.length, 1);
      // Фиктивный XTR (historical) удалён — исторических строк нет.
      expect(historical.length, 0);

      // 23 + 1 + 1 + 0 + 1 + 0 = 26: никакие статусы не потеряны.
      expect(
        researched.length +
            sendSupported.length +
            receiveSupported.length +
            researchRequired.length +
            blocked.length +
            historical.length,
        kAssetRegistry.length,
      );
    });

    test('реализованные адаптеры — BTC (полный) и LTC (receive-only)', () {
      final implemented =
          kAssetRegistry.where((a) => a.implemented).toList();
      expect(implemented.length, 2);
      final btc = implemented.firstWhere((a) => a.ticker == 'BTC');
      expect(btc.lifecycle, AssetLifecycle.sendSupported);
      // Send supported ≠ Full support: честное отличие защищено.
      expect(btc.name, 'Bitcoin');
      final ltc = implemented.firstWhere((a) => a.ticker == 'LTC');
      expect(ltc.lifecycle, AssetLifecycle.receiveSupported);
      // Receive-only: отправки в ядре для LTC НЕТ — честный этап.
      expect(ltc.name, 'Litecoin');
    });

    test('особые строки реестра на своих местах', () {
      final byTicker = {for (final a in kAssetRegistry) a.ticker: a};
      expect(byTicker['IRON']!.lifecycle, AssetLifecycle.blocked);
      // Удалены по решению владельца (12.11.2026): XTR — фиктивный
      // биржевой тикер; TARI — Tari L2/Ootle не запущен, кошелька нет.
      expect(byTicker.containsKey('XTR'), isFalse);
      expect(byTicker.containsKey('TARI'), isFalse);
      expect(byTicker.containsKey('XTM'), isTrue);
    });

    test('каждая строка заполнена и трассируема', () {
      final rows = <int>{};
      final tickers = <String>{};
      for (final asset in kAssetRegistry) {
        expect(asset.row, greaterThanOrEqualTo(1),
            reason: '${asset.ticker}: row');
        expect(rows.add(asset.row), isTrue, reason: 'row уникален');
        expect(tickers.add(asset.ticker), isTrue,
            reason: 'тикер ${asset.ticker} уникален');
        expect(asset.name, isNotEmpty);
        expect(asset.network, isNotEmpty);
        expect(asset.passport, 'docs/coins/${asset.ticker}.md');
        expect(asset.note, isNotEmpty);
      }
      // Ряды 1..28 без пропусков.
      expect(tickers.length, 26);
    });
  });

  group('Каталог активов (без FFI)', () {
    testWidgets('рендерит полный реестр, поиск и фильтр работают', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: AssetCatalogScreen(sessionLoader: () async => null),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Активы'), findsOneWidget);
      // Заголовок плитки — RichText «ТИКЕР Имя»: find.text его не находит
      // (ищет точное совпадение всего текста), поэтому predicate-хелпер.
      Finder tileTitle(String plain) => find.byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText().contains(plain),
          );

      // Поиск BTC: Bitcoin (и Bitcoin Cash — «форк BTC» в идентичности сети).
      await tester.enterText(find.byType(TextField), 'BTC');
      await tester.pumpAndSettle();
      expect(tileTitle('Bitcoin'), findsWidgets);
      expect(tileTitle('Bitcoin Cash'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Iron Fish');
      await tester.pumpAndSettle();
      expect(tileTitle('Iron Fish'), findsOneWidget);
      // Статус-чипы убраны с плиток каталога (решение владельца: монета
      // работает — не надо об этом писать; другие — тоже без чипов).
      expect(find.text('Заблокировано'), findsNothing);

      // Фильтр «Реализованные»: BTC и LTC (receive-only).
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Реализованные'));
      await tester.pumpAndSettle();
      expect(tileTitle('Bitcoin'), findsOneWidget);
      expect(tileTitle('Litecoin'), findsOneWidget);
      expect(find.text('Отправка проверена (testnet)'), findsNothing);
      // Остальные скрыты: Monero (Researched) не рендерится.
      expect(tileTitle('Monero'), findsNothing);
    });

    testWidgets('избранное переключается реальным DisplayPrefs', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: AssetCatalogScreen(sessionLoader: () async => null),
      ));
      await tester.pumpAndSettle();

      // LTC (receive-only) — избранное через реальный DisplayPrefs.
      await tester.enterText(find.byType(TextField), 'Litecoin');
      await tester.pumpAndSettle();

      final initialFavorite = DisplayPrefs.favorites.contains('LTC');
      // Тап по звезде меняет состояние (БД деградировала — память, честно).
      await tester.tap(find.byIcon(
          initialFavorite ? Icons.star : Icons.star_outline).first);
      await tester.pumpAndSettle();
      expect(DisplayPrefs.favorites.contains('LTC'), !initialFavorite);

      // Обратно — тап по уже заполненной (или пустой) звезде.
      await tester.tap(find.byIcon(
          initialFavorite ? Icons.star_outline : Icons.star).first);
      await tester.pumpAndSettle();
      expect(DisplayPrefs.favorites.contains('LTC'), initialFavorite);
    });

    testWidgets('нет выдуманных балансов или сетей', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: AssetCatalogScreen(sessionLoader: () async => null),
      ));
      await tester.pumpAndSettle();

      // BTC — строка 19 из 26: строим плитку поиском (ListView ленивый).
      await tester.enterText(find.byType(TextField), 'BTC');
      await tester.pumpAndSettle();
      // Чип статуса сессии убран с плиток каталога (решение владельца):
      // статуса сессии на строке нет вовсе.
      expect(find.textContaining('Сессия'), findsNothing);
      // Никаких фиатных сумм и выдуманных нативных балансов.
      expect(find.textContaining('\$'), findsNothing);
    });
  });

  group('Dashboard (injectable loaders)', () {
    // Источник цен скрыт (без сети в тестах): фиатная строка и график
    // курса отсутствуют. Значки валют — без Iconify (монограммы).
    setUp(() {
      PriceSource.instance.resetRates();
      PriceSource.loader = () async => null;
      PriceSource.marketLoader = (coinId, fiat, days) async => null;
      CoinIconService.instance.resetForTest();
      CoinIconService.useDiskCache = false;
      CoinIconService.fetcher = (ticker) async => null;
    });
    tearDown(() {
      PriceSource.loader = null;
      PriceSource.marketLoader = null;
      CoinIconService.fetcher = null;
      CoinIconService.instance.resetForTest();
    });

    testWidgets('два кошелька: селектор, честный пустой портфель',
        (tester) async {
      // Высокий вьюпорт: ListView ленивый — иначе нижние карточки не строятся.
      tester.view.physicalSize = const Size(800, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final wallets = [_wallet('w1', 'Основной'), _wallet('w2', 'Запасной')];
      await tester.pumpWidget(MaterialApp(
        home: DashboardScreen(
          walletLoader: () async => wallets,
          sessionLoader: () async => null,
        ),
      ));
      await tester.pumpAndSettle();

      // Кошелёк-селектор: компактный дропдаун с реальными именами.
      expect(find.text('Основной'), findsOneWidget);

      // Общий баланс в hero-карте — честный ноль (решение владельца).
      expect(find.text('Общий баланс'), findsOneWidget);
      expect(find.text('0'), findsOneWidget); // hero; курс в тесте недоступен
      expect(find.text('BTC'), findsWidgets);
      // Линия баланса и окна периода на месте (плоская при пустой истории).
      expect(find.byType(VSparkline), findsNothing); // без сети графика нет
      expect(find.text('1М'), findsOneWidget);
      expect(find.textContaining('\$'), findsNothing);
      // Чип сессии с Обзора убран (решение владельца).
      expect(find.text('BTC: сессия не активна'), findsNothing);
      expect(find.textContaining('Сеть'), findsNothing);
      expect(find.text('Последние транзакции'), findsNothing);

      // Пояснений-лекций больше нет; селектор валюты переехал в Настройки.
      expect(find.textContaining('Валюта отображения'), findsNothing);
      expect(find.textContaining('курсов фиата'), findsNothing);
      expect(find.textContaining('История доступна'), findsNothing);
      expect(find.textContaining('Справочник'), findsNothing);
    });

    testWidgets('активная сессия: честные чипы и реальные транзакции',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const session = BtcSessionStateDto(
        networkCode: 1,
        networkDisplay: 'testnet4',
        serverUrl: 'http://test-srv:50001',
        account: 0,
        accountXpub: 'tpubDExample',
        hasSpendables: true,
      );
      final history = [
        BtcHistoryItemDto(
          txid: 'aa' * 32,
          height: 160671,
          direction: 'incoming',
          receivedSat: BigInt.from(15000),
          sentNetSat: BigInt.zero,
        ),
        BtcHistoryItemDto(
          txid: 'bb' * 32,
          height: -1,
          direction: 'outgoing',
          receivedSat: BigInt.zero,
          sentNetSat: BigInt.from(9000),
          feeSat: BigInt.from(210),
        ),
      ];

      await tester.pumpWidget(MaterialApp(
        home: DashboardScreen(
          walletLoader: () async => [_wallet('w1', 'Основной')],
          sessionLoader: () async => session,
          historyLoader: () async => history,
        ),
      ));
      await tester.pumpAndSettle();

      // Чип сессии с Обзора убран: сеть/сервер — в центре BTC.
      expect(find.textContaining('BTC: testnet4'), findsNothing);
      expect(find.text('Есть синхронизированные средства'), findsOneWidget);
      // Реальные суммы истории (formatters, табличные цифры).
      expect(find.text('+0.00015 BTC'), findsOneWidget);
      expect(find.text('-0.00009 BTC'), findsOneWidget);
      // Mempool-элемент честно помечен, подтверждённый — высотой.
      expect(find.text('высота 160671'), findsOneWidget);
      expect(find.text('в мемпуле'), findsOneWidget);
    });

    testWidgets('hide/show переключается, избранное открыто честно',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: DashboardScreen(
          walletLoader: () async => [_wallet('w1', 'Основной')],
          sessionLoader: () async => null,
        ),
      ));
      await tester.pumpAndSettle();

      final initialHide = DisplayPrefs.hideBalances;
      await tester.tap(find.byTooltip(initialHide
          ? 'Показать суммы'
          : 'Скрыть суммы'));
      await tester.pumpAndSettle();
      expect(DisplayPrefs.hideBalances, !initialHide);
      if (!initialHide) {
        // Маска: hero-сумма (плитка без курса — трейлинг пуст).
        expect(find.text('••••••'), findsOneWidget);
      }
      // Возврат.
      await tester.tap(find.byTooltip(initialHide
          ? 'Скрыть суммы'
          : 'Показать суммы'));
      await tester.pumpAndSettle();
      expect(DisplayPrefs.hideBalances, initialHide);
    });

    testWidgets('шестерёнка настроек: открывает экран Настройки',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      PriceSource.instance.resetRates();
      CoinIconService.instance.resetForTest();
      CoinIconService.useDiskCache = false;
      CoinIconService.fetcher = (ticker) async => null;
      addTearDown(() {
        PriceSource.loader = null;
        PriceSource.marketLoader = null;
        CoinIconService.fetcher = null;
        CoinIconService.instance.resetForTest();
      });
      await tester.pumpWidget(MaterialApp(
        home: DashboardScreen(
          walletLoader: () async => [_wallet('w1', 'Основной')],
          sessionLoader: () async => null,
        ),
      ));
      await tester.pumpAndSettle();

      // Шестерёнка в правом верхнем углу шапки Обзора.
      expect(find.byTooltip('Настройки'), findsOneWidget);
      await tester.tap(find.byTooltip('Настройки'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
    });
  });

  group('Детали актива (без FFI)', () {
    testWidgets('не-реализованный актив: честный статус, адаптера нет',
        (tester) async {
      // Высокий вьюпорт: ListView ленивый, карточка паспорта — нижняя.
      tester.view.physicalSize = const Size(800, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final iron = kAssetRegistry.firstWhere((a) => a.ticker == 'IRON');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: AssetDetailScreen(asset: iron)),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Iron Fish'), findsNWidgets(2)); // заголовок + kvRow
      // Статус-чипы убраны с деталей тоже (решение владельца): осталась
      // только честная заметка о состоянии исследования.
      expect(find.text('Заблокировано'), findsNothing);
      // Ойкеровские лекции убраны: примечание остаётся, «смысловых»
      // абзацев и паспорта больше нет.
      expect(find.textContaining('Реализация заблокирована'), findsNothing);
      expect(find.textContaining('docs/coins/'), findsNothing);
      // Никакого реального потока BTC здесь не предлагается.
      expect(find.textContaining('центр управления'), findsNothing);
      // Никаких имитированных балансов/кнопок send/receive.
      expect(find.textContaining('0.00'), findsNothing);
    });

    testWidgets('BTC: сессия закрыта — честный статус, кнопка с паролем',
        (tester) async {
      final btc = kAssetRegistry.firstWhere((a) => a.ticker == 'BTC');
      await tester.pumpWidget(MaterialApp(
        home: AssetDetailScreen(
          asset: btc,
          sessionLoader: () async => null,
          walletLoader: () async => [_wallet('w1', 'Основной')],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Сессия закрыта'), findsOneWidget);
      expect(find.textContaining('btcSync — сетевая операция'), findsOneWidget);
      // Один кошелёк подставляется автоматически: кнопка реального потока
      // доступна.
      expect(find.text('Разблокировать и управлять BTC'), findsOneWidget);
    });

    testWidgets('BTC: нет кошельков — честное пустое состояние',
        (tester) async {
      final btc = kAssetRegistry.firstWhere((a) => a.ticker == 'BTC');
      await tester.pumpWidget(MaterialApp(
        home: AssetDetailScreen(
          asset: btc,
          sessionLoader: () async => null,
          walletLoader: () async => [],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Кошельков нет'), findsOneWidget);
      // Кнопка недоступна без кошелька (VButton primary — InkWell с null
      // колбэком; градиент держится отдельно).
      final button = find.text('Разблокировать и управлять BTC');
      expect(button, findsOneWidget);
      final ink = tester.widgetList<InkWell>(
        find.ancestor(of: button, matching: find.byType(InkWell)),
      ).first;
      expect(ink.onTap, isNull);
    });
  });
}
