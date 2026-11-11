//! Smoke-тест приложения: тема применяется, Welcome показывает бренд и
//! честные действия без фейковых кошельков (спека docs/UI_SPEC.md).
//! Детальная проверка группы 1 — ui_spec_group1_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veyro/design/v_theme.dart';
import 'package:veyro/screens/welcome_screen.dart';

void main() {
  testWidgets('App + Welcome: бренд, честные действия, никаких балансов',
      (WidgetTester tester) async {
    // Welcome без реестра (loader не вызывается): каркас приложения + экран.
    await tester.pumpWidget(
      MaterialApp(
        theme: buildVeyroTheme(),
        home: WelcomeScreen(walletCountLoader: () async => null),
      ),
    );
    await tester.pump();

    expect(find.text('VEYRO'), findsOneWidget);
    expect(
      find.textContaining('Некастодиальный мультивалютный кошелёк'),
      findsOneWidget,
    );
    // Ваш CRYPTO/TAGLINE на месте.
    expect(find.text('YOUR CRYPTO. YOUR CONTROL.'), findsOneWidget);

    // Честные действия спеки (создать/импорт), ни одного фейкового баланса.
    expect(find.text('Создать кошелёк'), findsOneWidget);
    expect(find.text('Импорт кошелька из фразы'), findsOneWidget);
    expect(find.text('Баланс'), findsNothing);
    expect(find.textContaining('0.00'), findsNothing);
  });
}
