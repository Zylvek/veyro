//! Тесты группы 4 спеки UI (docs/UI_SPEC.md): Address book 18,
//! Wallet manager 19, настройки/безопасность/уведомления 22/23/24,
//! честные строки кошельков, каркас из 7 разделов.
//! Без RustLib: все экраны с injectable-загрузчиками; фейковых контактов,
//! балансов и подключений тесты не создают — injectables возвращают
//! только модельные данные для верстки, изолированно от реального ядра
//! (это тестовые данные, а не демонстрация в UI).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veyro/navigation/app_shell.dart';
import 'package:veyro/screens/address_book_screen.dart';
import 'package:veyro/screens/network_settings_screen.dart';
import 'package:veyro/screens/settings_screen.dart';
import 'package:veyro/screens/wallets_screen.dart';
import 'package:veyro/src/rust/api/session.dart';
import 'package:veyro/src/rust/api/wallet.dart';
import 'package:veyro/util/address_book.dart';

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
  group('AddressBook: JSON-модель и совместимость (unit)', () {
    test('roundtrip контакта с несколькими адресами и метками', () {
      final src = jsonDecode(jsonEncode([
        {
          'id': 'c1',
          'name': 'Алиса',
          'addresses': [
            {
              'address': 'tb1qExampleAddress000000000000000000q',
              'label': 'Холодный',
              'ticker': 'BTC',
              'networkCode': 2,
            },
            {
              'address': 'mxTestLegacyAddress0000000000000000',
              'label': '',
              'ticker': 'BTC',
            },
          ],
        },
      ])) as List;
      final contacts = [
        for (final c in src)
          BookContact.fromJson((c as Map).cast<String, dynamic>()),
      ];
      expect(contacts, hasLength(1));
      expect(contacts.single.name, 'Алиса');
      expect(contacts.single.addresses, hasLength(2));
      expect(contacts.single.addresses.first.networkCode, 2);
      // Адрес без сети — честный null.
      expect(contacts.single.addresses[1].networkCode, isNull);
      expect(contacts.single.addresses[1].label, '');
      // Обратная сериализация сохраняет форму.
      final encoded = jsonEncode([for (final c in contacts) c.toJson()]);
      final reDecoded = AddressBook.decodeJson(encoded);
      expect(reDecoded.single.addresses, hasLength(2));
      expect(reDecoded.single.addresses.first.label, 'Холодный');
    });

    test('addressNetworkCompatible: эвристика по префиксам', () {
      // 0 mainnet: bc1/1/3 совместимы, чужие префиксы — нет.
      expect(addressNetworkCompatible('bc1qMainnet0000', 0), isTrue);
      expect(addressNetworkCompatible('1LegacyMain', 0), isTrue);
      expect(addressNetworkCompatible('3SHMain0000', 0), isTrue);
      expect(addressNetworkCompatible('tb1qTestnet00', 0), isFalse);
      // 1 testnet3: tb1/m/n/2, чужие — нет.
      expect(addressNetworkCompatible('tb1qTestnet30', 1), isTrue);
      expect(addressNetworkCompatible('mxLegacyTes', 1), isTrue);
      expect(addressNetworkCompatible('2P2SHTestnet1', 1), isTrue);
      expect(addressNetworkCompatible('bc1qMainnet00', 1), isFalse);
      // 2 testnet4: тот же набор tb1/m/n/2 — по префиксу не отличить
      // (честный null; ядро проверит при подписи), чужое — false.
      expect(addressNetworkCompatible('tb1qTestnet40', 2), isNull);
      expect(addressNetworkCompatible('mxLegacyTes', 2), isNull);
      expect(addressNetworkCompatible('bc1qMainnet00', 2), isFalse);
      // Не-BTC сети и пустые адреса — честный null.
      expect(addressNetworkCompatible('bc1qMainnet00', 5), isNull);
      expect(addressNetworkCompatible('bc1qMainnet00', null), isNull);
      expect(addressNetworkCompatible('', 2), isNull);
      expect(addressNetworkCompatible('  ', 2), isNull);
    });
  });

  group('AddressBook: CRUD на injectable-хранилище', () {
    test('upsert пишет через settingSaver; reload возвращает изменения',
        () async {
      final savedJson = <String>[];
      final book = await AddressBook.load(
        settingLoader: (_) async => savedJson.isEmpty ? null : savedJson.last,
      );
      book.settingSaver = (_, value) async => savedJson.add(value);
      expect(book.storageHealthy, isTrue);
      expect(book.contacts, isEmpty);

      final next = await book.upsert(const BookContact(
        id: 'c1',
        name: 'Алиса',
        addresses: [
          BookAddress(
            address: 'tb1qExampleAddress000000000000000000q',
            label: 'Холодный',
            ticker: 'BTC',
            networkCode: 2,
          ),
        ],
      ));
      expect(savedJson, hasLength(1));
      expect(savedJson.single, contains('Алиса'));
      expect(next.contacts.single.name, 'Алиса');

      // Повторная вставка перезаписывает контакт по id.
      await next.upsert(const BookContact(
        id: 'c1',
        name: 'Алиса Б.',
        addresses: [
          BookAddress(address: 'tb1qX', label: '', ticker: 'BTC'),
        ],
      ));
      expect(savedJson, hasLength(2));
      final reloaded = await AddressBook.load(
        settingLoader: (_) async => savedJson.last,
      );
      reloaded.settingSaver =
          (_, value) async => savedJson.add(value);
      expect(reloaded.contacts.single.name, 'Алиса Б.');
      expect(reloaded.contacts.single.addresses.first.address, 'tb1qX');

      final removed = await reloaded.remove('c1');
      expect(removed.contacts, isEmpty);
      expect(savedJson, hasLength(3)); // записан пустой массив
    });

    test('отказ хранилища: load даёт пустую degraded-книгу; upsert '
        'оставляет данные только в памяти', () async {
      final book = await AddressBook.load(
        settingLoader: (_) async => throw Exception('db unavailable'),
      );
      expect(book.storageHealthy, isFalse);
      expect(book.contacts, isEmpty);

      final next = await book.upsert(const BookContact(
        id: 'c1',
        name: 'Боб',
        addresses: [BookAddress(address: 'tb1qY', label: '', ticker: 'BTC')],
      ));
      expect(next.storageHealthy, isFalse);
      expect(next.contacts.single.name, 'Боб');
    });
  });

  group('AddressBookScreen (экран 18)', () {
    Future<void> pumpBook(
      WidgetTester tester, {
      Future<String?> Function(String key)? loader,
      Future<void> Function(String key, String value)? saver,
    }) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: AddressBookScreen(settingLoader: loader, settingSaver: saver),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('пустая книга: честный empty state, хранилище здорово',
        (tester) async {
      await pumpBook(tester, loader: (_) async => null);

      expect(find.text('Адресная книга'), findsOneWidget);
      expect(find.text('Контактов нет'), findsOneWidget);
      expect(find.textContaining('Добавьте первый контакт'), findsOneWidget);
      // Пометки деградации нет при здоровом хранилище.
      expect(find.textContaining('Хранилище настроек недоступно'),
          findsNothing);
    });

    testWidgets('честная деградация: пометка + правки живут в памяти',
        (tester) async {
      await pumpBook(
        tester,
        loader: (_) async => throw Exception('db unavailable'),
        saver: (_, _) async => throw Exception('db unavailable'),
      );

      expect(find.textContaining('Хранилище настроек недоступно'),
          findsOneWidget);
      // Добавление в деградированной книге работает (в памяти).
      await tester.tap(find.byTooltip('Добавить контакт'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'Боб');
      await tester.enterText(find.byType(TextField).at(1), 'tb1qBobAddress00');
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(find.text('Боб'), findsOneWidget);
      expect(find.text('tb1qBobAddress00'), findsWidgets);
    });

    testWidgets('создание контакта: имя + адрес, сохранение через '
        'injectable-хранилище', (tester) async {
      final savedJson = <String>[];
      await pumpBook(
        tester,
        loader: (_) async => savedJson.isEmpty ? null : savedJson.last,
        saver: (_, value) async => savedJson.add(value),
      );

      await tester.tap(find.byTooltip('Добавить контакт'));
      await tester.pumpAndSettle();
      expect(find.text('Новый контакт'), findsOneWidget);

      // Валидация до сохранения: пустое имя честно отклоняется.
      await tester.enterText(find.byType(TextField).at(1), 'tb1qAddr000000');
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(find.text('Введите имя контакта.'), findsOneWidget);
      // Пустая строка адреса тоже честно отклоняется.
      await tester.enterText(find.byType(TextField).at(0), 'Алиса');
      await tester.enterText(find.byType(TextField).at(1), '');
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Строка адреса пуста'), findsOneWidget);

      // Корректный контакт сохраняется и появляется в книге.
      await tester.enterText(find.byType(TextField).at(1), 'tb1qA100000000');
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(find.text('Алиса'), findsOneWidget);
      expect(find.text('tb1qA100000000'), findsWidgets);
      expect(find.text('BTC'), findsOneWidget);
      expect(savedJson, hasLength(1));
      expect(savedJson.single, contains('"Алиса"'));
      // Диалог закрылся: экран снова показывает книгу.
      expect(find.text('Новый контакт'), findsNothing);
    });

    testWidgets('чипы совместимости: чужой префикс — ошибка, tb1 на '
        'testnet4 — честное предупреждение', (tester) async {
      final preseeded = jsonEncode([
        {
          'id': 'c1',
          'name': 'Алиса',
          'addresses': [
            {
              'address': 'bc1qMainnetInTestnet00',
              'label': '',
              'ticker': 'BTC',
              'networkCode': 2,
            },
            {
              'address': 'tb1qTestnet4Address0000000x',
              'label': 'Холодный',
              'ticker': 'BTC',
              'networkCode': 2,
            },
          ],
        },
        {
          'id': 'c2',
          'name': 'Боб',
          'addresses': [
            {
              'address': 'bc1qOnlyBtcHere0000000x',
              'label': '',
              'ticker': 'LTC',
            },
          ],
        },
      ]);
      await pumpBook(tester, loader: (_) async => preseeded);

      expect(find.text('Алиса'), findsOneWidget);
      expect(find.text('Боб'), findsOneWidget);
      expect(find.text('bc1qMainnetInTestnet00'), findsWidgets);
      // Префикс mainnet при назначенной testnet4 — честная ошибка.
      expect(find.text('Префикс не совпадает с сетью'), findsOneWidget);
      // tb1 на testnet4 — честное «не отличить по префиксу».
      expect(find.textContaining('По префиксу не отличить'),
          findsOneWidget);

      // Отправка доступна только для BTC-адресов без конфликта.
      // byTooltip находит Tooltip; кнопка — его предок по типу.
      Finder iconByTooltip(String message) => find.ancestor(
            of: find.byTooltip(message),
            matching: find.byType(IconButton),
          ).first;
      expect(tester.widget<IconButton>(
        iconByTooltip('Отправить на этот адрес'),
      ).onPressed, isNotNull);
      expect(
        tester.widget<IconButton>(iconByTooltip(
          'Адрес сохранён с префиксом чужой сети — отправка '
          'заблокирована до исправления',
        )).onPressed,
        isNull,
      );
      expect(
        tester.widget<IconButton>(iconByTooltip(
          'Отправка доступна только для BTC: остальные адаптеры '
          'нереализованы в ядре',
        )).onPressed,
        isNull,
      );
    });

    testWidgets('удаление контакта только после явного подтверждения',
        (tester) async {
      final savedJson = <String>[
        jsonEncode([
          {
            'id': 'c1',
            'name': 'Смета',
            'addresses': [
              {
                'address': 'tb1qAddr99999999',
                'label': '',
                'ticker': 'BTC',
              },
            ],
          },
        ])
      ];
      await pumpBook(
        tester,
        loader: (_) async => savedJson.last,
        saver: (_, value) async => savedJson.add(value),
      );
      expect(find.text('Смета'), findsOneWidget);

      final dialogDelete = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Удалить'),
      );
      await tester.tap(find.text('Удалить'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Удалить «Смета»?'), findsOneWidget);

      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(find.text('Смета'), findsOneWidget); // отмена сохранила

      await tester.tap(find.text('Удалить'));
      await tester.pumpAndSettle();
      await tester.tap(dialogDelete.first);
      await tester.pumpAndSettle();
      expect(find.text('Смета'), findsNothing);
      expect(find.text('Контактов нет'), findsOneWidget);
      expect(savedJson, hasLength(2)); // пустой массив записан
    });
  });

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
      expect(find.textContaining('Тип: vault · создан'), findsOneWidget);
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
  });

  group('Каркас: шесть реальных разделов (адресная книга — из Настроек)', () {
    test('реестр kShellDestinations: 6 назначений, порядок и id', () {
      expect(kShellDestinations.length, 6);
      expect(
        [for (final d in kShellDestinations) d.id],
        [
          'overview',
          'assets',
          'wallets',
          'backup',
          'settings',
          'about',
        ],
      );
      final labels = [for (final d in kShellDestinations) d.label];
      // Адресная книга убрана из навигации (решение владельца): экран
      // открывается из «Настроек», назначение в каркасе отсутствует.
      expect(labels.contains('Адреса'), isFalse);
      expect(labels.contains('Настройки'), isTrue);
      // Назначение «Сеть» удалено: сетевые настройки — из экрана настроек.
      expect(labels.contains('Сеть'), isFalse);
    });
  });
}
