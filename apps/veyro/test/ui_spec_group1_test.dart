//! Тесты группы 1 спеки UI (docs/UI_SPEC.md):
//! 1) токены палитры совпадают с утверждёнными значениями 1-в-1;
//! 2) позиционная проверка фразы (create_wallet_flow);
//! 3) Welcome рендерит бренд и честные действия без фейковых балансов;
//! 4) каркас: сайдбар 240 px на широком окне, нижняя навигация на узком.
//! Без RustLib: экраны, работающие с ядром, в тестах не выполняются.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veyro/design/app_colors.dart';
import 'package:veyro/design/v_theme.dart';
import 'package:veyro/navigation/app_shell.dart';
import 'package:veyro/screens/create_wallet_flow.dart';
import 'package:veyro/screens/welcome_screen.dart';

void main() {
  group('Утверждённая палитра Electric Blue Dark', () {
    test('значения совпадают со спекой', () {
      expect(VColors.background, const Color(0xFF080D19));
      expect(VColors.surface, const Color(0xFF101A2D));
      expect(VColors.card, const Color(0xFF14213A));
      expect(VColors.elevated, const Color(0xFF1D2D4A));
      expect(VColors.primary, const Color(0xFF638CFF));
      expect(VColors.primaryGlow, const Color(0xFF397BFF));
      expect(VColors.secondary, const Color(0xFF48C8F5));
      expect(VColors.success, const Color(0xFF35C98A));
      expect(VColors.warning, const Color(0xFFF2B85B));
      expect(VColors.error, const Color(0xFFF16B79));
      expect(VColors.textPrimary, const Color(0xFFF5F8FF));
      expect(VColors.textSecondary, const Color(0xFF8B9BB5));
    });

    test('тема использует токены', () {
      final theme = buildVeyroTheme();
      expect(theme.scaffoldBackgroundColor, VColors.background);
      expect(theme.cardTheme.color, VColors.card);
      expect(theme.colorScheme.primary, VColors.primary);
      expect(theme.textTheme.bodyLarge?.fontFamily, kInterFont);
    });
  });

  test('позиционная проверка фразы: регистр и пробелы игнорируются', () {
    const words = [
      'file',
      'pudding',
      'where',
      'pigeon',
      'adjust',
      'head',
      'second',
    ];
    // Полное совпадение с разнобоем регистра/пробелов.
    expect(
      verifyPhraseAnswers(words, {0: ' File ', 2: 'where', 5: 'HEAD'}),
      isTrue,
    );
    // Неверное слово — не совпало.
    expect(
      verifyPhraseAnswers(words, {0: 'file', 2: 'wrong', 5: 'head'}),
      isFalse,
    );
    // Вне диапазона — отказ.
    expect(verifyPhraseAnswers(words, {9: 'head'}), isFalse);
    // Пустой ответ — отказ.
    expect(verifyPhraseAnswers(words, const {}), isFalse);
  });

  testWidgets('Welcome: бренд, честные действия, никаких балансов',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildVeyroTheme(),
        home: WelcomeScreen(walletCountLoader: () async => 0),
      ),
    );
    await tester.pump();

    expect(find.text('VEYRO'), findsOneWidget);
    expect(find.text('YOUR CRYPTO. YOUR CONTROL.'), findsOneWidget);
    expect(find.text('Создать кошелёк'), findsOneWidget);
    expect(find.text('Импорт кошелька из фразы'), findsOneWidget);
    expect(find.text('Импорт зашифрованного бэкапа'), findsOneWidget);

    // Без кошельков кнопка входа не показывается; фейковых данных нет.
    expect(find.text('Войти в кошелёк'), findsNothing);
    expect(find.text('Баланс'), findsNothing);

    // Кнопка импорта ведёт на реальный экран импорта бэкапа.
    await tester.tap(find.text('Импорт зашифрованного бэкапа'));
    await tester.pumpAndSettle();
    expect(find.text('Полный путь к файлу .veybackup'), findsOneWidget);
  });

  testWidgets('Каркас: сайдбар 240 px на широком окне', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildVeyroTheme(),
        home: const VeyroShell(initialDestination: 'wallets'),
      ),
    );
    await tester.pump();

    // Сайдбар: логотип и все семь реальных разделов (с группы 4
    // заглушки отсутствуют).
    expect(find.text('VEYRO'), findsOneWidget);
    expect(find.text('Кошельки'), findsWidgets); // нав. элемент + заголовок
    expect(find.text('Обзор'), findsOneWidget);
    expect(find.text('Активы'), findsOneWidget);
    expect(find.text('группа 2'), findsNothing);

    // Контент реального раздела (экран кошельков из ядра — FFI не вызывается
    // в тесте: экран покажет прогресс/состояние, каркас не падает).
    expect(find.byType(VeyroShell), findsOneWidget);

    expect(
      tester
          .getSize(
            find.byKey(const Key('shell-sidebar')),
          )
          .width,
      moreOrLessEquals(240, epsilon: 0.5),
    );
  });

  testWidgets('Каркас: нижняя навигация на узком экране', (tester) async {
    tester.view.physicalSize = const Size(412, 920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildVeyroTheme(),
        home: const VeyroShell(initialDestination: 'wallets'),
      ),
    );
    await tester.pump();

    expect(find.byType(NavigationBar), findsOneWidget);
    // Все семь реальных разделов (с группы 4; экран сети — из Настроек).
    expect(find.byType(NavigationDestination), findsNWidgets(7));
    expect(find.text('Обзор'), findsOneWidget);
    expect(find.text('Активы'), findsOneWidget);
    expect(find.text('Адреса'), findsOneWidget);
    expect(find.text('Настройки'), findsOneWidget);
    expect(find.text('Сеть'), findsNothing); // назначение удалено
  });
}
