//! Фиатная оценка на Обзоре (мастер-план §13): прямой клиент провайдера
//! цен без собственного сервера. Курс недоступен — фиатная строка скрыта
//! (честное отсутствие данных); доступен — «≈ X <ВАЛЮТА>» под суммой
//! портфеля. Источник курса — [PriceSource] с injectable-загрузчиком:
//! реальные HTTP-вызовы в тестах не выполняются.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
}

void main() {
  setUp(() {
    PriceSource.instance.resetRates();
    BtcStateCache.instance.clear();
  });
  tearDown(() {
    PriceSource.loader = null;
    PriceSource.instance.resetRates();
    BtcStateCache.instance.clear();
  });

  group('PriceSource (injectable loader, без сети)', () {
    test('курс в выбранной валюте приходит от загрузчика', () async {
      var calls = 0;
      PriceSource.loader = () async {
        calls++;
        return {
          'usd': 65000.0,
          'eur': 60000.0,
          'rub': 6200000.0,
        };
      };
      final rub = await PriceSource.instance.btcPriceIn('rub');
      expect(rub, 6200000.0);
      expect(calls, 1);
    });

    test('кэш 5 минут: повторный запрос не бьёт по сети', () async {
      var calls = 0;
      PriceSource.loader = () async {
        calls++;
        return {'rub': 6200000.0};
      };
      await PriceSource.instance.btcPriceIn('rub');
      final second = await PriceSource.instance.btcPriceIn('RUB');
      expect(second, 6200000.0);
      expect(calls, 1);
    });

    test('не поддерживаемая валюта: null без сетевого вызова', () async {
      var calls = 0;
      PriceSource.loader = () async {
        calls++;
        return {'rub': 6200000.0};
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

  group('formatFiat', () {
    test('группы через пробел, два знака, ноль без извращений', () {
      expect(formatFiat(0), '0.00');
      expect(formatFiat(6234567.891), '6 234 567.89');
      expect(formatFiat(12345.67), '12 345.67');
    });
  });

  group('Обзор: фиатная строка под суммой портфеля', () {
    testWidgets('курс доступен → «≈ 0.00 USD» показана', (tester) async {
      tester.view.physicalSize = const Size(800, 2300);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      PriceSource.loader = () async => {'usd': 65000.0};

      await tester.pumpWidget(_dashboard());
      await tester.pumpAndSettle();

      // Валюта отображения по умолчанию USD (без настроек); баланс
      // 0 BTC → фиатная оценка 0.00.
      expect(find.text('≈ 0.00 USD'), findsOneWidget);
    });

    testWidgets('курса нет (нет сети) → строка скрыта', (tester) async {
      _stubPrice(PriceSource.instance);

      tester.view.physicalSize = const Size(800, 2300);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_dashboard());
      await tester.pumpAndSettle();

      // Никаких выдуманных оценок: нет курса — нет фиатной строки.
      expect(find.textContaining('≈'), findsNothing);
      expect(find.textContaining('USD'), findsNothing);
    });
  });
}
