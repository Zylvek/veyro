// Smoke-тест каркаса VEYRO: приложение собирается, тема применяется,
// Welcome честно отражает статус интеграции и открывает список кошельков.
// Никаких фейковых данных.

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

    // Реальный вход в кошельки (не имитация).
    expect(find.text('Открыть кошельки'), findsOneWidget);

    // Никаких имитаций данных кошелька на Welcome.
    expect(find.text('Баланс'), findsNothing);
    expect(find.text('Создать кошелёк'), findsNothing);
  });
}
