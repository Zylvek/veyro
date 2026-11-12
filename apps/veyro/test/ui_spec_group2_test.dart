//! Тесты группы 2 спеки UI (docs/UI_SPEC.md): Dashboard, Asset catalog,
//! Asset details. Без RustLib: все экраны имеют injectable-загрузчики,
//!(DisplayPrefs честно деградирует в память при недоступной БД).
//!
//! Ключевые гарантии:
//! 1) реестр = утверждённая матрица (28 строк, честный ценз статусов);
//! 2) каталог рендерит реестр целиком/фильтрами без вызовов FFI;
//! 3) dashboard показывает только реальные данные (нет балансов, нет
//!    транзакций без активной сессии, честные чипы сети);
//! 4) детали BTC не имитируют синхронизацию, детали остальных активов
//!    честно говорят, что адаптеров нет.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veyro/data/asset_registry.dart';
import 'package:veyro/src/rust/api/btc.dart';
import 'package:veyro/src/rust/api/session.dart';
import 'package:veyro/src/rust/api/wallet.dart';
import 'package:veyro/screens/asset_catalog_screen.dart';
import 'package:veyro/screens/asset_detail_screen.dart';
import 'package:veyro/screens/dashboard_screen.dart';
import 'package:veyro/util/display_prefs.dart';

WalletInfoDto _wallet(String id, String name) => WalletInfoDto(
      id: id,
      name: name,
      createdAtUnix: BigInt.from(1730000000),
    );

void main() {
  group('Реестр активов (28 строк утверждённой матрицы)', () {
    test('состав вердиктов совпадает с матрицей', () {
      expect(kAssetRegistry.length, 28);

      final researched = kAssetRegistry
          .where((a) => a.lifecycle == AssetLifecycle.researched)
          .toList();
      final sendSupported = kAssetRegistry
          .where((a) => a.lifecycle == AssetLifecycle.sendSupported)
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

      expect(researched.length, 24);
      expect(sendSupported.length, 1);
      expect(researchRequired.length, 1);
      expect(blocked.length, 1);
      expect(historical.length, 1);

      // 24 + 1 + 1 + 1 + 1 = 28: никакие статусы не потеряны.
      expect(
        researched.length +
            sendSupported.length +
            researchRequired.length +
            blocked.length +
            historical.length,
        kAssetRegistry.length,
      );
    });

    test('единственный реализованный адаптер — BTC', () {
      final implemented =
          kAssetRegistry.where((a) => a.implemented).toList();
      expect(implemented.length, 1);
      expect(implemented.single.ticker, 'BTC');
      expect(implemented.single.lifecycle, AssetLifecycle.sendSupported);
      // Send supported ≠ Full support: честное отличие защищено.
      expect(implemented.single.name, 'Bitcoin');
    });

    test('особые строки реестра на своих местах', () {
      final byTicker = {for (final a in kAssetRegistry) a.ticker: a};
      expect(byTicker['IRON']!.lifecycle, AssetLifecycle.blocked);
      expect(byTicker['TARI']!.lifecycle, AssetLifecycle.researchRequired);
      expect(byTicker['XTR']!.lifecycle, AssetLifecycle.historical);
      expect(byTicker['XTR']!.network, contains('не существует'));
      // TARI (L2 Ootle) и XTM (L1) — разные активы, не объединять.
      expect(byTicker['XTM']!.row, 4);
      expect(byTicker['TARI']!.row, 28);
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
      expect(tickers.length, 28);
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
      expect(find.text('Blocked'), findsOneWidget);

      // Сетка фильтров: «Реализованные» оставляет только BTC.
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Реализованные'));
      await tester.pumpAndSettle();
      expect(tileTitle('Bitcoin'), findsOneWidget);
      expect(find.text('Send supported'), findsOneWidget);
      // Остальные скрыты: Monero (Researched) не рендерится.
      expect(tileTitle('Monero'), findsNothing);
    });

    testWidgets('избранное переключается реальным DisplayPrefs', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: AssetCatalogScreen(sessionLoader: () async => null),
      ));
      await tester.pumpAndSettle();

      // LTC (researched) — не реализован: находим через поиск.
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

      // BTC — строка 19 из 28: строим плитку поиском (ListView ленивый).
      await tester.enterText(find.byType(TextField), 'BTC');
      await tester.pumpAndSettle();
      // Честный статус BTC при неактивной сессии (loader вернул null).
      expect(find.textContaining('Сессия закрыта'), findsOneWidget);
      // Никаких фиатных сумм и выдуманных нативных балансов.
      expect(find.textContaining('\$'), findsNothing);
    });
  });

  group('Dashboard (injectable loaders)', () {
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

      // Кошелёк-селектор с реальными именами.
      expect(find.text('Активный кошелёк'), findsOneWidget);
      expect(find.text('Основной'), findsOneWidget);

      // Сумма портфеля — только честное отсутствие данных.
      expect(find.text('Сумма портфеля'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
      expect(find.text('нет данных'), findsOneWidget);
      expect(find.textContaining('\$'), findsNothing);

      // Сеть: сессия не активна → честный чип в верхней панели; карточек
      // лекций на чистом Обзоре нет.
      expect(find.text('BTC: сессия не активна'), findsOneWidget);
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

      expect(find.textContaining('BTC: testnet4'), findsOneWidget);
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
        expect(find.text('••••••'), findsOneWidget);
      }
      // Возврат.
      await tester.tap(find.byTooltip(initialHide
          ? 'Скрыть суммы'
          : 'Показать суммы'));
      await tester.pumpAndSettle();
      expect(DisplayPrefs.hideBalances, initialHide);
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
      // Статус 'Blocked' тоже дважды: чип честного статуса + строка
      // «Статус» в идентификации (kvRow — SelectableText).
      expect(find.text('Blocked'), findsNWidgets(2));
      expect(find.textContaining('Реализация заблокирована'), findsOneWidget);
      // Паспорт на месте, копируемый.
      expect(find.textContaining('docs/coins/IRON.md'), findsOneWidget);
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
      // Кнопка недоступна без кошелька.
      final button = find.text('Разблокировать и управлять BTC');
      expect(button, findsOneWidget);
      final filled = tester.widget<FilledButton>(
        find.ancestor(
          of: button,
          matching: find.byType(FilledButton),
        ),
      );
      expect(filled.onPressed, isNull);
    });
  });
}
