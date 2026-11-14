//! Тесты группы 4 спеки UI (docs/UI_SPEC.md): Address book 18,
//! Wallet manager 19, настройки/безопасность/уведомления 22/23/24,
//! честные строки кошельков, каркас из 7 разделов.
//! Без RustLib: все экраны с injectable-загрузчиками; фейковых контактов,
//! балансов и подключений тесты не создают — injectables возвращают
//! только модельные данные для верстки, изолированно от реального ядра
//! (это тестовые данные, а не демонстрация в UI).


import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veyro/screens/dashboard_screen.dart';
import 'package:veyro/screens/lock_screen.dart';
import 'package:veyro/screens/settings_screen.dart';
import 'package:veyro/src/rust/api/session.dart';
import 'package:veyro/src/rust/api/wallet.dart';
import 'package:veyro/util/format.dart';

const _session = BtcSessionStateDto(
  networkCode: 2,
  networkDisplay: 'testnet4',
  serverUrl: 'http://test-srv:50001',
  account: 0,
  accountXpub: 'tpubDExample',
  hasSpendables: false,
);

WalletInfoDto _wallet(String id, String name, int createdUnix) =>
    WalletInfoDto(
      id: id,
      name: name,
      createdAtUnix: BigInt.from(createdUnix),
    );

void main() {
  group('SettingsScreen (22/23/24): только реализованное переключаемо', () {
    Future<void> pumpSettings(
      WidgetTester tester, {
      Future<BtcSessionStateDto?> Function()? sessionLoader,
      Future<void> Function()? lockAction,
    }) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: SettingsScreen(
          sessionLoader: sessionLoader,
          lockAction: lockAction,
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('сессия закрыта: честный статус, пометки вместо '
        'переключателей нереализованного', (tester) async {
      await pumpSettings(
        tester,
        sessionLoader: () async => null,
      );

      expect(find.text('BTC заблокирован: ключи сессии не загружены'),
          findsOneWidget);
      // Выбор сети/сервера убран из Настроек: подбор автоматический.
      expect(find.text('Настройки сети'), findsNothing);
      // Карточка «Целостность данных» удалена (решение владельца).
      expect(find.textContaining('Схема БД настроек'), findsNothing);
      // Честные пометки вместо переключателей нереализованного.
      expect(find.textContaining('не реализовано в ядре (нет таймера'),
          findsOneWidget);
      expect(find.textContaining('Биометрия'), findsOneWidget);
      expect(find.textContaining('Уведомления не реализованы'),
          findsOneWidget);
      // Тумблер «Скрывать суммы» убран: это делает глазик в Обзоре.
      expect(find.byType(Switch), findsNothing);
    });

    testWidgets('ручная блокировка: доступна при активной сессии и '
        'вызывает реальное действие', (tester) async {
      var lockCalls = 0;
      var sessionClosed = false;
      await pumpSettings(
        tester,
        sessionLoader: () async => sessionClosed ? null : _session,
        lockAction: () async {
          lockCalls++;
          sessionClosed = true; // реальный btc_lock закрывает сессию
        },
      );

      expect(find.textContaining('Ключи сессии в памяти ядра'),
          findsOneWidget);
      await tester.tap(find.text('Заблокировать BTC'));
      await tester.pumpAndSettle();
      expect(lockCalls, 1);
      // Состояние перечитано: блокировка отразилась честным чипом.
      expect(find.text('BTC заблокирован: ключи сессии не загружены'),
          findsOneWidget);
    });
  });

  group('LockScreen (полноэкранный вход — решение владельца)', () {
    Future<void> pumpLock(
      WidgetTester tester, {
      required Future<List<WalletInfoDto>> Function()? walletsLoader,
      required Future<BtcSessionStateDto?> Function()? sessionLoader,
      Future<void> Function(String walletId, String password)? unlockAction,
    }) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: LockScreen(
          walletsLoader: walletsLoader,
          sessionLoader: sessionLoader,
          unlockAction: unlockAction,
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('сессия уже активна: сразу каркас без формы входа',
        (tester) async {
      const session = BtcSessionStateDto(
        networkCode: 2,
        networkDisplay: 'testnet4',
        serverUrl: 'http://s',
        account: 0,
        accountXpub: 'tpubDX',
        hasSpendables: false,
      );
      await pumpLock(
        tester,
        walletsLoader: () async => [_wallet('w1', 'Основной', 1699000000)],
        sessionLoader: () async => session,
      );
      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('ввод пароля: реальный unlockAction → каркас на Обзоре',
        (tester) async {
      var unlockedFor = '';
      await pumpLock(
        tester,
        walletsLoader: () async => [_wallet('w1', 'Основной', 1699000000)],
        sessionLoader: () async => null,
        unlockAction: (id, _) async => unlockedFor = id,
      );
      // Форма входа на весь экран + имя кошелька.
      expect(find.text('ВХОД'), findsOneWidget);
      expect(find.textContaining('Кошелёк «Основной»'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text('Войти'));
      await tester.pumpAndSettle();
      expect(unlockedFor, 'w1');
      // Сразу на каркас (Обзор).
      expect(find.byType(DashboardScreen), findsOneWidget);
    });

    testWidgets('неверный пароль: честная ошибка, вход не выполнен',
        (tester) async {
      await pumpLock(
        tester,
        walletsLoader: () async => [_wallet('w1', 'Основной', 1699000000)],
        sessionLoader: () async => null,
        unlockAction: (_, _) async =>
            throw Exception('vault error: decryption failed'),
      );
      await tester.enterText(find.byType(TextField), '9999');
      await tester.tap(find.text('Войти'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Неверный пароль'), findsOneWidget);
      expect(find.byType(DashboardScreen), findsNothing);
      // Снова можно ввести.
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('кошельков нет: Welcome (создать/импорт)', (tester) async {
      await pumpLock(
        tester,
        walletsLoader: () async => [],
        sessionLoader: () async => null,
      );
      expect(find.text('Создать кошелёк'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });
  });

  test('дата кошелька: unix-секунды ядра → dd.mm.yyyy без «1970»', () {
    // Регрессия «21.01.1970»: createdAtUnix передаётся в СЕКУНДАХ.
    expect(formatWalletDate(1699000000), '03.11.2023');
    expect(formatWalletDate(0), '01.01.1970');
  });
}
