// Smoke-тест каркаса VEYRO: приложение собирается, тема применяется,
// экран честно отражает статус интеграции. Никаких фейковых данных.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veyro/main.dart';

void main() {
  testWidgets('Welcome screen renders with honest integration status',
      (WidgetTester tester) async {
    await tester.pumpWidget(const VeyroApp());

    // Брендинг на месте.
    expect(find.text('VEYRO'), findsOneWidget);
    expect(find.text('Некастодиальный мультивалютный кошелёк'), findsOneWidget);

    // Честный статус интеграции вместо фейковых кнопок и балансов.
    expect(find.byIcon(Icons.construction_outlined), findsOneWidget);
    expect(find.textContaining('flutter_rust_bridge'), findsOneWidget);

    // Никаких имитаций данных кошелька в каркасе.
    expect(find.text('Баланс'), findsNothing);
    expect(find.text('Создать кошелёк'), findsNothing);
  });
}
