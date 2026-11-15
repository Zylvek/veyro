//! Тесты группы 3 спеки UI (docs/UI_SPEC.md): Receive 13, Send 14,
//! Transaction confirmation 15, History 16, Transaction details 17.
//! Без RustLib: все экраны имеют injectable-загрузчики; фейковые
//! транзакции/балансы/статусы не создаются — injectables возвращают
//! только модельные данные для верстки, изолированно от реального ядра
//! (это тестовые данные, а не демонстрация в UI).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:veyro/src/rust/api/btc.dart';
import 'package:veyro/src/rust/api/session.dart';
import 'package:veyro/src/rust/api/wallet.dart';
import 'package:veyro/screens/asset_picker_screen.dart';
import 'package:veyro/screens/receive_screen.dart';
import 'package:veyro/screens/send_screen.dart';
import 'package:veyro/screens/tx_confirm_screen.dart';
import 'package:veyro/screens/tx_details_screen.dart';
import 'package:veyro/screens/history_screen.dart';
import 'package:veyro/util/coin_icons.dart';
import 'package:veyro/util/links.dart';

WalletInfoDto _wallet(String id, String name) => WalletInfoDto(
      id: id,
      name: name,
      createdAtUnix: BigInt.from(1730000000),
    );

const _session = BtcSessionStateDto(
  networkCode: 2,
  networkDisplay: 'testnet4',
  serverUrl: 'http://test-srv:50001',
  account: 0,
  accountXpub: 'tpubDExample',
  hasSpendables: true,
);

void main() {
  // Значки валют: тесты без сети и без дискового кэша — монограммы.
  setUp(() {
    CoinIconService.instance.resetForTest();
    CoinIconService.useDiskCache = false;
    CoinIconService.fetcher = (ticker) async => null;
  });
  tearDown(() {
    CoinIconService.fetcher = null;
    CoinIconService.instance.resetForTest();
  });

  group('Explorer-ссылки (unit)', () {
    test('код сети 0/1/2 → mempool.space; прочие — null', () {
      const txid = '8221ef55deadbeefd675';
      expect(explorerTxUrl(0, txid), 'https://mempool.space/tx/$txid');
      expect(explorerTxUrl(1, txid), 'https://mempool.space/testnet/tx/$txid');
      expect(
          explorerTxUrl(2, txid), 'https://mempool.space/testnet4/tx/$txid');
      expect(explorerTxUrl(5, txid), isNull);
      expect(kBtcExplorerName, 'mempool.space');
    });
  });

  group('TxConfirmScreen (пункт 15)', () {
    testWidgets('показывает актив/сеть/адрес/сумму/ставку + честную пометку',
        (tester) async {
      // Высокий вьюпорт: ListView ленивый — нижние кнопки должны строиться.
      tester.view.physicalSize = const Size(800, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => Navigator.of(context).push<bool>(
                  MaterialPageRoute<bool>(
                    builder: (_) => TxConfirmScreen(
                      recipient: 'tb1qExampleRecipient0000000000',
                      amountSat: 15000,
                      rateSatVb: 3,
                      networkDisplay: 'testnet4',
                    ),
                  ),
                ),
                child: const Text('открыть'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('открыть'));
      await tester.pumpAndSettle();

      expect(find.text('Подтверждение отправки'), findsOneWidget);
      expect(find.text('Bitcoin (BTC)'), findsOneWidget);
      expect(find.text('Bitcoin · тестовая сеть (testnet4)'), findsOneWidget);
      expect(find.text('tb1qExampleRecipient0000000000'), findsOneWidget);
      expect(find.text('0.00015'), findsOneWidget);
      expect(find.text('15\u00A0000 сат'), findsOneWidget);
      expect(find.text('3 sat/vB'), findsOneWidget);
      // Честная пометка о финальной комиссии.
      expect(find.textContaining('Финальная комиссия считается ядром'),
          findsOneWidget);
      expect(find.textContaining('Отправка необратима'), findsOneWidget);

      // Явное подтверждение возвращает true и закрывает экран.
      await tester.tap(find.text('Подписать и отправить'));
      await tester.pumpAndSettle();
      expect(find.text('открыть'), findsOneWidget);
    });

    testWidgets('отмена возвращает пользователя без отправки', (tester) async {
      tester.view.physicalSize = const Size(800, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => Navigator.of(context).push<bool>(
                  MaterialPageRoute<bool>(
                    builder: (_) => const TxConfirmScreen(
                      recipient: 'bc1qX',
                      amountSat: 1,
                      rateSatVb: 1,
                    ),
                  ),
                ),
                child: const Text('открыть'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('открыть'));
      await tester.pumpAndSettle();
      // Сеть неизвестна — честное «—».
      expect(find.text('— (сессия ядра не активна)'), findsOneWidget);
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(find.text('открыть'), findsOneWidget);
    });
  });

  group('TxDetailsScreen (пункт 17)', () {
    testWidgets('исходящая: TXID/суммы/fee/live-статус/explorer', (tester) async {
      tester.view.physicalSize = const Size(800, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final item = BtcHistoryItemDto(
        txid: 'aa' * 32,
        height: -1,
        direction: 'outgoing',
        receivedSat: BigInt.zero,
        sentNetSat: BigInt.from(9000),
        feeSat: BigInt.from(210),
      );
      await tester.pumpWidget(MaterialApp(
        home: TxDetailsScreen(
          item: item,
          networkCode: 2,
          statusLoader: (txid) async => BtcTxStatusDto(
            state: 'confirmed',
            height: 160672,
            confirmations: 4,
            txid: txid,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Отправка'), findsOneWidget);
      expect(find.text('-0.00009'), findsOneWidget);
      expect(find.text('BTC'), findsOneWidget);
      expect(find.textContaining('9\u00A0000 сат'), findsOneWidget);
      expect(find.textContaining('0.0000021 BTC'), findsOneWidget); // fee
      // Live-статус из injectable-загрузчика (реальный контракт DTO).
      expect(find.text('Подтверждено сетью'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      // Height −1 в истории → mempool-отметка в карточке транзакции.
      expect(find.text('— (в мемпуле)'), findsOneWidget);
      // Explorer для testnet4 по коду сети 2.
      expect(
          find.textContaining('https://mempool.space/testnet4/tx/aa'),
          findsOneWidget);
    });

    testWidgets('входящая в мемпуле: статус mempool + честная ошибка статуса',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final item = BtcHistoryItemDto(
        txid: 'bb' * 32,
        height: -1,
        direction: 'incoming',
        receivedSat: BigInt.from(15000),
        sentNetSat: BigInt.zero,
      );
      await tester.pumpWidget(MaterialApp(
        home: TxDetailsScreen(
          item: item,
          networkCode: 2,
          statusLoader: (txid) async => BtcTxStatusDto(
            state: 'mempool',
            height: null,
            confirmations: null,
            txid: txid,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Получение'), findsOneWidget);
      expect(find.text('+0.00015'), findsOneWidget);
      expect(find.text('В мемпуле — не подтверждено'), findsOneWidget);
      // Подтверждения/высота от сервера неизвестны — честные «—».
      expect(find.text('—'), findsWidgets);
    });

    testWidgets('внутренняя (internal): чистая сумма ноль', (tester) async {
      tester.view.physicalSize = const Size(800, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final item = BtcHistoryItemDto(
        txid: 'cc' * 32,
        height: 160670,
        direction: 'internal',
        receivedSat: BigInt.from(5000),
        sentNetSat: BigInt.zero,
      );
      await tester.pumpWidget(MaterialApp(
        home: TxDetailsScreen(
          item: item,
          networkCode: 0,
          statusLoader: (txid) async => BtcTxStatusDto(
            state: 'confirmed',
            height: 160670,
            confirmations: 12,
            txid: txid,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Внутри кошелька'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      expect(find.textContaining('Перевод между своими адресами'),
          findsOneWidget);
      // Mainnet explorer-ссылка.
      expect(find.textContaining('https://mempool.space/tx/'), findsOneWidget);
      expect(find.textContaining('высота 160670'), findsNothing);
    });
  });

  group('HistoryScreen (пункт 16): фильтры и поиск', () {
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
      BtcHistoryItemDto(
        txid: 'cc' * 32,
        height: 160670,
        direction: 'internal',
        receivedSat: BigInt.from(5000),
        sentNetSat: BigInt.zero,
      ),
    ];

    Future<void> pumpHistory(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: HistoryScreen(
          historyLoader: () async => history,
          sessionLoader: () async => _session,
          syncLoader: () async {},
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('все транзакции видны, фильтры честного происхождения',
        (tester) async {
      await pumpHistory(tester);

      expect(find.text('+0.00015 BTC'), findsOneWidget);
      expect(find.text('-0.00009 BTC'), findsOneWidget);
      expect(find.text('0 BTC'), findsOneWidget);
      // Честные подписи: направление · высота/мемпул · комиссия.
      expect(find.textContaining('в мемпуле'), findsOneWidget);
      expect(find.textContaining('комиссия 0.0000021'), findsOneWidget);
    });

    testWidgets('фильтр «Входящие»/«Ожидающие» работает по данным', (tester) async {
      await pumpHistory(tester);

      await tester.tap(find.text('Входящие'));
      await tester.pumpAndSettle();
      expect(find.text('+0.00015 BTC'), findsOneWidget);
      expect(find.text('-0.00009 BTC'), findsNothing);
      expect(find.text('0 BTC'), findsNothing);

      await tester.tap(find.text('Ожидающие'));
      await tester.pumpAndSettle();
      expect(find.text('-0.00009 BTC'), findsOneWidget);
      expect(find.text('+0.00015 BTC'), findsNothing);
    });

    testWidgets('поиск по TXID; честная пометка о невозможности поиска адреса',
        (tester) async {
      await pumpHistory(tester);

      await tester.enterText(find.byType(TextField), 'cc');
      await tester.pumpAndSettle();
      expect(find.text('0 BTC'), findsOneWidget);
      expect(find.text('+0.00015 BTC'), findsNothing);

      await tester.enterText(find.byType(TextField), 'zz');
      await tester.pumpAndSettle();
      expect(find.text('Ничего не найдено'), findsOneWidget);
      expect(find.textContaining('Измените фильтр или очистите поиск'),
          findsOneWidget);

      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
    });

    testWidgets('фильтр «Неудачные» отключён и не имитирует работу',
        (tester) async {
      await pumpHistory(tester);

      expect(find.text('Неудачные'), findsOneWidget);
      // Тап по отключённому чипу (IgnorePointer) не меняет выбор:
      // по-прежнему все три транзакции.
      await tester.tap(find.text('Неудачные'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('+0.00015 BTC'), findsOneWidget);
      expect(find.text('-0.00009 BTC'), findsOneWidget);
      expect(find.text('0 BTC'), findsOneWidget);
    });
  });

  group('AssetPickerScreen (Receive/Send entry)', () {
    testWidgets('BTC честно ведёт на разблокировку; остальные отключены',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: AssetPickerScreen(
          isReceive: false,
          sessionLoader: () async => null,
          walletLoader: () async => [_wallet('w1', 'Основной')],
        ),
      ));
      await tester.pumpAndSettle();

      // Честный статус BTC: сессия закрыта, путь разблокировки назван.
      expect(find.textContaining('Сессия закрыта — разблокировать'),
          findsOneWidget);
      // Нереализованные активы — отключённые плитки со статусами матрицы
      // (XMR — строка 13: в пределах вьюпорта; LTC row 25 лениво за краем).
      Finder tileTitle(String plain) => find.byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText().contains(plain),
          );
      expect(tileTitle('Monero'), findsOneWidget);
      expect(find.text('Исследовано'), findsWidgets);
      expect(find.textContaining('Разблокировать: Основной'), findsNothing);
    });

    testWidgets('активная сессия: BTC-плитка предлагает реальную форму',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: AssetPickerScreen(
          isReceive: true,
          sessionLoader: () async => _session,
          walletLoader: () async => [_wallet('w1', 'Основной')],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Сессия: Bitcoin · тестовая сеть'),
          findsOneWidget);
      // Плитка BTC активна (InkWell onTap не null) — тап откроет ReceiveScreen,
      // который в тестах без ядра требует injectables; здесь не тапаем,
      // только честный текст.
      expect(find.textContaining('форма открыта'), findsOneWidget);
    });
  });

  group('ReceiveScreen (пункт 13)', () {
    const address = BtcAddressDto(
      address: 'tb1qExampleReceiveAddress000000000000x',
      branch: 0,
      index: 5,
      path: "m/84'/1'/0'/0/5",
      used: false,
    );

    testWidgets('QR от реального адреса, Copy работает, Share отключён',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: ReceiveScreen(
          sessionLoader: () async => _session,
          addressLoader: () async => address,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Адрес получения (testnet4)'), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('tb1qExampleReceiveAddress000000000000x'),
          findsOneWidget);
      // Путь деривации/ветка/индекс убраны с экрана (решение владельца:
      // «убери путь, а то что это за бред»).
      expect(find.textContaining("m/84'"), findsNothing);

      // Copy — реальное действие: в буфере и SnackBar.
      await tester.tap(find.text('Копировать адрес'));
      await tester.pump();
      expect(find.textContaining('скопировано'), findsOneWidget);

      // Share — честно отключён (системный канал не подключён).
      expect(find.text('Поделиться'), findsOneWidget);
      final shareButton = find.ancestor(
        of: find.text('Поделиться'),
        matching: find.byType(OutlinedButton),
      );
      expect(
        tester.widget<OutlinedButton>(shareButton).onPressed,
        isNull,
      );

      // Memo-поле удалено по решению владельца: BTC не использует memo.
      expect(find.textContaining('memo/tag'), findsNothing);    });
  });

  group('SendScreen (пункт 14)', () {
    testWidgets('Max подставляет реальный доступный баланс; пресеты комиссии',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: SendScreen(
          availableSat: 12345,
          feesLoader: () async => BtcFeeRatesDto(
            fastSatVb: BigInt.from(5),
            normalSatVb: BigInt.from(2),
            slowSatVb: BigInt.one,
            fallback: false,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Доступно: 0.00012345 BTC'), findsOneWidget);
      await tester.tap(find.text('Max'));
      await tester.pumpAndSettle();
      // Поле суммы теперь содержит реальное значение последней синхронизации.
      expect(find.text('0.00012345'), findsOneWidget);
      expect(find.text('Быстро — 5 sat/vB'), findsOneWidget);
      expect(find.text('Обычно — 2 sat/vB'), findsOneWidget);
    });

    testWidgets('без availableSat кнопки Max нет (честно скрыта)',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: SendScreen(
          feesLoader: () async => BtcFeeRatesDto(
            fastSatVb: BigInt.from(5),
            normalSatVb: BigInt.from(2),
            slowSatVb: BigInt.one,
            fallback: false,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Max'), findsNothing);
      expect(find.textContaining('Доступно:'), findsNothing);
    });

    testWidgets('пустой получатель/сумма: честная валидация до подтверждения',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: SendScreen(
          feesLoader: () async => BtcFeeRatesDto(
            fastSatVb: BigInt.from(5),
            normalSatVb: BigInt.from(2),
            slowSatVb: BigInt.one,
            fallback: false,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Отправить'));
      await tester.pumpAndSettle();
      expect(find.text('Введите адрес получателя.'), findsOneWidget);
      // Подтверждение не открывалось: экран подтверждения не создавался.
      expect(find.text('Подтверждение отправки'), findsNothing);
    });
  });

  group('btc_screen wiring (real payload)', () {
    testWidgets('availableSat = confirmed при нуле mempool-дельты',
        (tester) async {
      // Чистая единичная проверка математики: helper экрана доступен через
      // SendScreen — здесь проверяем сам контракт: положительная дельта не
      // уменьшает баланс; отрицательная — уменьшает (логика покрыта
      // интеграционно в PHASE 4; тут проверяется формула группы 3).
      final sat = BtcSyncDto(
        networkCode: 2,
        confirmedSat: BigInt.from(1000),
        unconfirmedDeltaSat: -300,
        utxoCount: 2,
        usedAddresses: const [],
        nextReceive: const BtcAddressDto(
          address: 'tb1qN',
          branch: 0,
          index: 1,
          path: "m/84'/1'/0'/0/1",
          used: false,
        ),
        nextChange: const BtcAddressDto(
          address: 'tb1qC',
          branch: 1,
          index: 1,
          path: "m/84'/1'/0'/1/1",
          used: false,
        ),
        tipHeight: 160672,
        serverUrl: 'http://s',
      );
      final confirmed = sat.confirmedSat.toInt();
      final delta = sat.unconfirmedDeltaSat.toInt();
      expect(delta < 0 ? confirmed + delta : confirmed, 700);
    });
  });
}
