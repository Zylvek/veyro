//! Фиатная оценка и реальный график курса на Обзоре (мастер-план §13):
//! прямой клиент провайдера цен без собственного сервера. Курс
//! недоступен — фиатная строка и график скрыты (честное отсутствие
//! данных). Источник — [PriceSource] с injectable-загрузчиками:
//! реальные HTTP-вызовы в тестах не выполняются.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veyro/design/components.dart';
import 'package:veyro/screens/dashboard_screen.dart';
import 'package:veyro/util/btc_state_cache.dart';
import 'package:veyro/util/price_source.dart';

Widget _dashboard() {
  return MaterialApp(
    home: DashboardScreen(
      walletLoader: () async => [],
      sessionLoader: () async => null,
    ),
  );
}

void _stubPrice(PriceSource source) {
  source.resetRates();
  PriceSource.loader = () async => null;
  PriceSource.marketLoader = (coinId, fiat, days) async => null;
}

void main() {
  setUp(() {
    PriceSource.instance.resetRates();
    BtcStateCache.instance.clear();
  });
  tearDown(() {
    PriceSource.loader = null;
    PriceSource.marketLoader = null;
    PriceSource.instance.resetRates();
    BtcStateCache.instance.clear();
  });

  group('PriceSource (injectable loader, без сети)', () {
    test('курсы BTC и ETH приходят от загрузчика', () async {
      var calls = 0;
      PriceSource.loader = () async {
        calls++;
        return const FiatRates(
          btc: {'usd': 65000.0, 'eur': 60000.0, 'rub': 6200000.0},
          eth: {'usd': 3200.0, 'eur': 2900.0, 'rub': 300000.0},
        );
      };
      final rub = await PriceSource.instance.btcPriceIn('rub');
      final ethRub = await PriceSource.instance.ethPriceIn('rub');
      expect(rub, 6200000.0);
      expect(ethRub, 300000.0);
      expect(calls, 1); // обе монеты — одним запросом
    });

    test('кэш 5 минут: повторный запрос не бьёт по сети', () async {
      var calls = 0;
      PriceSource.loader = () async {
        calls++;
        return const FiatRates(
          btc: {'rub': 6200000.0},
          eth: {'rub': 300000.0},
        );
      };
      await PriceSource.instance.btcPriceIn('rub');
      final second = await PriceSource.instance.ethPriceIn('RUB');
      expect(second, 300000.0);
      expect(calls, 1);
    });

    test('не поддерживаемая валюта: null без сетевого вызова', () async {
      var calls = 0;
      PriceSource.loader = () async {
        calls++;
        return const FiatRates(
          btc: {'rub': 6200000.0},
          eth: {'rub': 300000.0},
        );
      };
      final cny = await PriceSource.instance.btcPriceIn('cny');
      expect(cny, isNull);
      expect(calls, 0);
    });

    test('провайдер недоступен: null — курс честно отсутствует', () async {
      PriceSource.loader = () async => null;
      final rate = await PriceSource.instance.btcPriceIn('rub');
      expect(rate, isNull);
    });
  });

  group('PriceSource: реальная линия курса (график ЭФИРА)', () {
    test('серия по окну приходит от загрузчика и кэшируется', () async {
      var calls = 0;
      var requestedCoin = '';
      PriceSource.marketLoader = (coinId, fiat, days) async {
        calls++;
        requestedCoin = coinId;
        final t = DateTime.now();
        return [
          MarketPoint(t.subtract(const Duration(hours: 2)), 2800.0),
          MarketPoint(t, 2900.0),
        ];
      };
      final a = await PriceSource.instance.marketSeries('ethereum', 'RUB', 30);
      final b = await PriceSource.instance.marketSeries('ethereum', 'rub', 30);
      expect(a?.length, 2);
      expect(a?.last.price, 2900.0);
      expect(b?.length, 2);
      expect(calls, 1);
      expect(requestedCoin, 'ethereum'); // график — эфир, как в референсе
    });

    test('провайдер не отдал серию → null (график скрыт)', () async {
      PriceSource.marketLoader = (coinId, fiat, days) async => null;
      expect(
        await PriceSource.instance.marketSeries('ethereum', 'rub', 7),
        isNull,
      );
    });
  });

  group('formatFiat', () {
    test('группы через пробел, два знака, ноль без извращений', () {
      expect(formatFiat(0), '0.00');
      expect(formatFiat(6234567.891), '6 234 567.89');
      expect(formatFiat(12345.67), '12 345.67');
    });
  });

  group('Обзор: общая цена валют — одно число', () {
    testWidgets('курс доступен → сумма и эквивалент в ETH', (tester) async {
      tester.view.physicalSize = const Size(800, 2300);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      PriceSource.loader = () async => const FiatRates(
            btc: {'usd': 65000.0},
            eth: {'usd': 3200.0},
          );
      // Серию курса в этом сценарии провайдер не отдал — графика нет.
      PriceSource.marketLoader = (coinId, fiat, days) async => null;

      await tester.pumpWidget(_dashboard());
      await tester.pumpAndSettle();

      // Валюта отображения по умолчанию USD (без настроек); баланс
      // 0 BTC → общая цена 0.00 USD. Показана в hero и у плитки.
      expect(find.text('0.00'), findsNWidgets(2));
      expect(find.text('USD'), findsNWidgets(2));
      // Эквивалент суммы в ETH — 0/3200 → «≈ 0.0000 ETH», как в референсе.
      expect(find.text('≈ 0.0000 ETH'), findsOneWidget);
    });

    testWidgets('курса нет (нет сети) → честный BTC, без фиата', (tester) async {
      _stubPrice(PriceSource.instance);

      tester.view.physicalSize = const Size(800, 2300);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_dashboard());
      await tester.pumpAndSettle();

      // Никаких выдуманных оценок: курса нет → сумма в BTC (нуль),
      // трейлинг плитки пуст, эквивалент ETH скрыт.
      expect(find.textContaining('USD'), findsNothing);
      expect(find.textContaining('ETH'), findsNothing);
      expect(find.text('0'), findsOneWidget); // hero
      expect(find.text('BTC'), findsOneWidget); // суффикс hero
      // Графика курса без данных нет.
      expect(find.byType(VSparkline), findsNothing);
    });

    testWidgets('провайдер отдал серию → реальный график курса на месте',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2300);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      PriceSource.loader = () async =>
          const FiatRates(btc: {'usd': 65000.0}, eth: {'usd': 3200.0});
      PriceSource.marketLoader = (coinId, fiat, days) async {
        if (coinId != 'ethereum') return null; // график — только эфир
        final t = DateTime.now();
        return [
          MarketPoint(t.subtract(const Duration(hours: 40)), 100.0),
          MarketPoint(t.subtract(const Duration(hours: 20)), 102.5),
          MarketPoint(t, 105.0),
        ];
      };

      await tester.pumpWidget(_dashboard());
      await tester.pumpAndSettle();

      expect(find.byType(VSparkline), findsOneWidget);
      // Окна периода на месте, активное — 1М.
      expect(find.text('1М'), findsOneWidget);
      expect(find.text('1Д'), findsOneWidget);
    });
  });
}
