//! Тесты группы 4 спеки UI (docs/UI_SPEC.md): Address book 18,
//! Wallet manager 19, настройки/безопасность/уведомления 22/23/24,
//! честные строки кошельков, каркас из 7 разделов.
//! Без RustLib: все экраны с injectable-загрузчиками; фейковых контактов,
//! балансов и подключений тесты не создают — injectables возвращают
//! только модельные данные для верстки, изолированно от реального ядра
//! (это тестовые данные, а не демонстрация в UI).


import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veyro/navigation/app_shell.dart';
import 'package:veyro/screens/dashboard_screen.dart';
import 'package:veyro/screens/lock_screen.dart';
import 'package:veyro/screens/network_settings_screen.dart';
import 'package:veyro/screens/portfolio_screen.dart';
import 'package:veyro/screens/settings_screen.dart';
import 'package:veyro/screens/wallets_screen.dart';
import 'package:veyro/src/rust/api/session.dart';
import 'package:veyro/src/rust/api/wallet.dart';
import 'package:veyro/util/format.dart';
import 'package:veyro/util/price_source.dart';

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
      Future<int> Function()? schemaLoader,
      Future<void> Function()? lockAction,
    }) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: SettingsScreen(
          sessionLoader: sessionLoader,
          schemaLoader: schemaLoader,
          lockAction: lockAction,
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('сессия закрыта: честный статус, схема из ядра, пометки '
        'вместо переключателей нереализованного', (tester) async {
      await pumpSettings(
        tester,
        sessionLoader: () async => null,
        schemaLoader: () async => 12,
      );

      expect(find.text('BTC заблокирован: ключи сессии не загружены'),
          findsOneWidget);
      expect(find.text('Настройки сети'), findsOneWidget);
      expect(find.textContaining('Смена сервера применяется'),
          findsOneWidget);
      // Реальная версия схемы — честное число из ядра.
      expect(find.textContaining('Схема БД настроек'), findsOneWidget);
      expect(find.text('12'), findsWidgets);
      // Честные пометки вместо переключателей нереализованного.
      expect(find.textContaining('не реализовано в ядре (нет таймера'),
          findsOneWidget);
      expect(find.textContaining('Биометрия'), findsOneWidget);
      expect(find.textContaining('Уведомления не реализованы'),
          findsOneWidget);
      // Единственный переключатель — «Скрывать суммы» (реальная функция).
      expect(find.byType(Switch), findsOneWidget);
    });

    testWidgets('ручная блокировка: доступна при активной сессии и '
        'вызывает реальное действие', (tester) async {
      var lockCalls = 0;
      var sessionClosed = false;
      await pumpSettings(
        tester,
        sessionLoader: () async => sessionClosed ? null : _session,
        schemaLoader: () async => 3,
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

    testWidgets('схема БД не прочитана: честный текст вместо выдуманного '
        'числа', (tester) async {
      await pumpSettings(
        tester,
        sessionLoader: () async => null,
        schemaLoader: () async => throw Exception('db unavailable'),
      );
      expect(find.textContaining('не прочитано'), findsWidgets);
    });

    testWidgets('переход к экрану сети (21) выполняется', (tester) async {
      await pumpSettings(
        tester,
        sessionLoader: () async => null,
        schemaLoader: () async => 12,
      );
      await tester.tap(find.text('Настройки сети'));
      await tester.pumpAndSettle();
      // NetworkSettingsScreen сам честно ловит недоступность БД в тесте.
      expect(find.byType(NetworkSettingsScreen), findsOneWidget);
    });
  });

  group('WalletsScreen (19): честные строки', () {
    Future<void> pumpWallets(
      WidgetTester tester, {
      required Future<List<WalletInfoDto>> Function() walletLoader,
      Future<BtcSessionStateDto?> Function()? sessionLoader,
    }) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: WalletsScreen(
          walletLoader: walletLoader,
          sessionLoader: sessionLoader,
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('vault-тип, дата, глобальный статус сессии, пометки без '
        'кнопок-имитаций', (tester) async {
      await pumpWallets(
        tester,
        walletLoader: () async => [_wallet('w1', 'Основной', 1699000000)],
        sessionLoader: () async => _session,
      );

      expect(find.text('Состояние BTC-сессии'), findsOneWidget);
      expect(find.textContaining('Ключи в памяти ядра'), findsOneWidget);
      expect(find.textContaining('vault · создан'), findsOneWidget);
      expect(find.textContaining('Переименование и удаление'), findsOneWidget);
      expect(find.textContaining('DTO сессии'), findsOneWidget);
      // Кнопки-имитации rename/delete отсутствуют.
      expect(find.byTooltip('Переименовать'), findsNothing);
      expect(find.byTooltip('Удалить кошелёк'), findsNothing);
      // Реальные действия на месте.
      expect(find.text('Создать'), findsOneWidget);
      expect(find.text('Импорт'), findsOneWidget);
    });

    testWidgets('сессия не активна: честный статус', (tester) async {
      await pumpWallets(
        tester,
        walletLoader: () async => [],
        sessionLoader: () async => null,
      );
      expect(find.textContaining('Не загружены'), findsOneWidget);
    });

    testWidgets('закрытая сессия: Обзор открывается спокойно, без '
        'стартовых модалок (решение владельца)', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      // Без сети в тестах: фиатная строка скрыта (честное отсутствие).
      PriceSource.instance.resetRates();
      PriceSource.loader = () async => null;
      addTearDown(() {
        PriceSource.loader = null;
        PriceSource.instance.resetRates();
      });
      await tester.pumpWidget(MaterialApp(
        home: DashboardScreen(
          walletLoader: () async => [_wallet('w1', 'Основной', 1699000000)],
          sessionLoader: () async => null,
        ),
      ));
      await tester.pumpAndSettle();
      // Никаких автоматических заталкиваний: Обзор на экране, оверлеев нет.
      expect(find.byType(PortfolioScreen), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Общий баланс'), findsOneWidget);
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
      expect(find.byType(VeyroShell), findsOneWidget);
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
      expect(find.byType(VeyroShell), findsOneWidget);
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
      expect(find.byType(VeyroShell), findsNothing);
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

  group('Каркас: пять разделов навигации (решение владельца)', () {
    test('реестр kShellDestinations: 5 назначений, порядок и id', () {
      expect(kShellDestinations.length, 5);
      expect(
        [for (final d in kShellDestinations) d.id],
        [
          'overview',
          'assets',
          'transactions',
          'wallets',
          'settings',
        ],
      );
      final labels = [for (final d in kShellDestinations) d.label];
      expect(labels, containsAll([
        'Обзор',
        'Активы',
        'Транзакции',
        'Кошельки',
        'Настройки',
      ]));
      // Бэкап / «О VEYRO» — из «Настроек» (не в навигации); адресная книга удалена из проекта целиком (решение владельца).
      expect(labels.contains('Бэкап'), isFalse);
      expect(labels.contains('О VEYRO'), isFalse);
      expect(labels.contains('Адреса'), isFalse);
      expect(labels.contains('Сеть'), isFalse);
    });

    test('дата кошелька: unix-секунды ядра → dd.mm.yyyy без «1970»',
        () {
      // Регрессия «21.01.1970»: createdAtUnix передаётся в СЕКУНДАХ.
      expect(formatWalletDate(1699000000), '03.11.2023');
      expect(formatWalletDate(0), '01.01.1970');
    });
  });
}

