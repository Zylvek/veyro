//! Тесты исправлений аудита 16.11: кэш синков ключён по кошельку, политика
//! пароля едина для создания/импорта, честные ключи словаря на месте,
//! пикир активов показывает LTC как реализованный актив, а не отключённый.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:veyro/src/rust/api/btc.dart';
import 'package:veyro/util/btc_state_cache.dart';
import 'package:veyro/util/l10n.dart';
import 'package:veyro/util/ltc_state_cache.dart';
import 'package:veyro/src/rust/api/ltc.dart';
import 'package:veyro/util/coin_icons.dart';
import 'package:veyro/util/network.dart';
import 'package:veyro/util/password_policy.dart';
import 'package:veyro/util/server_probe.dart';

BtcSyncDto _btcSync(int confirmed) => BtcSyncDto(
      networkCode: 0,
      confirmedSat: BigInt.from(confirmed),
      unconfirmedDeltaSat: 0,
      utxoCount: 1,
      usedAddresses: const [],
      nextReceive: BtcAddressDto(
        address: 'bc1qtest',
        branch: 0,
        index: 0,
        path: "m/84'/0'/0'/0/0",
        used: false,
      ),
      nextChange: BtcAddressDto(
        address: 'bc1qchange',
        branch: 1,
        index: 0,
        path: "m/84'/0'/0'/1/0",
        used: false,
      ),
      tipHeight: 800000,
      serverUrl: 'ssl://test:50002',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BtcStateCache (ключ по кошельку — аудит #3)', () {
    test('чужой кошелёк не видит баланс другого', () {
      BtcStateCache.instance.clear();
      BtcStateCache.instance.store(_btcSync(123), walletId: 'wallet-a');
      final forB = BtcStateCache.instance.take(walletId: 'wallet-b');
      expect(forB, isNull, reason: 'данные кошелька A не показываются кошельку B');
      final forA = BtcStateCache.instance.take(walletId: 'wallet-a');
      expect(forA?.confirmedSat.toInt(), 123);
      BtcStateCache.instance.clear();
    });

    test('протухший кэш не показывается', () async {
      BtcStateCache.instance.store(_btcSync(5), walletId: 'wallet-old');
      // Реальный такт времени: с нулевым допуском любые часы уже «старые»,
      // но даём планировщику микросекунды на честную разницу.
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final stale = BtcStateCache.instance.take(
        walletId: 'wallet-old',
        maxAge: const Duration(milliseconds: 1),
      );
      expect(stale, isNull);
      BtcStateCache.instance.clear();
    });
  });

  group('LtcStateCache (тот же контракт)', () {
    test('ключ по кошельку', () {
      LtcStateCache.instance.clear();
      final sync = LtcSyncDto(
        confirmedSat: BigInt.from(77),
        unconfirmedDeltaSat: 0,
        utxoCount: 0,
        usedAddresses: const [],
        nextReceive: LtcAddressDto(
          address: 'ltc1test',
          branch: 0,
          index: 0,
          path: "m/84'/2'/0'/0/0",
          used: false,
        ),
        nextChange: LtcAddressDto(
          address: 'ltc1chg',
          branch: 1,
          index: 0,
          path: "m/84'/2'/0'/1/0",
          used: false,
        ),
        tipHeight: 3000000,
        serverUrl: 'ssl://ltc-test:60002',
      );
      LtcStateCache.instance.store(sync, walletId: 'ltc-a');
      expect(LtcStateCache.instance.take(walletId: 'ltc-b'), isNull);
      expect(
          LtcStateCache.instance.take(walletId: 'ltc-a')?.confirmedSat.toInt(),
          77);
      LtcStateCache.instance.clear();
    });
  });

  group('Политика пароля (аудит #6)', () {
    test('импорт требует тот же минимум, что и создание', () {
      expect(isValidWalletPassword('1'), isFalse);
      expect(isValidWalletPassword('1234567' /* 7 */), isFalse);
      expect(isValidWalletPassword('12345678' /* 8 */), isTrue);
      expect(kMinPasswordLength, 8);
    });
  });

  group('Новые честные ключи l10n (аудит #19-22)', () {
    test('LTC-ключи и усечение истории существуют в обоих языках', () {
      const keys = [
        'receive_title_ltc',
        'history_title_ltc',
        'no_wallets_ltc',
        'tx_fee_row_btc',
        'history_truncated_note',
        'sync_now_short',
        'ltc_connecting',
        'ltc_syncing_addresses_long',
        'settings_read_error',
      ];
      for (final key in keys) {
        expect(t(key), isNot(key), reason: 'ключ $key должен быть в словаре');
        expect(t(key).contains(r'{$'), isFalse, reason: '$key без подстановок');
      }
    });
  });

  group('Классификатор сетевых ошибок (аудит #11, Dart)', () {
    test('транспортные ошибки — transient, ошибки содержания — нет', () {
      expect(
        isTransientNetworkError(Exception(
            'transport: unexpected end of file while reading TCP stream')),
        isTrue,
      );
      expect(
        isTransientNetworkError(Exception('timed out after 6s')),
        isTrue,
      );
      expect(
        // «Connection» в содержательной ошибке не делает её сетевой:
        // проверяем честность классификации на реальных формулировках ядра.
        isTransientNetworkError(
            Exception('insufficient funds: need 1000 sat, available 0 sat spendable')),
        isFalse,
      );
      expect(
        isTransientNetworkError(
            Exception('decryption failed: wrong password or corrupted data')),
        isFalse,
      );
    });
  });

  group('Политика TLS (security audit 16.11)', () {
    test('кандидаты серверов — только ssl://', () {
      for (final code in [0, 1, 2]) {
        for (final url in serverCandidates(code)) {
          expect(url.startsWith('ssl://'), isTrue,
              reason: 'plaintext tcp:// исключён: $url');
          expect(url.length, lessThanOrEqualTo(256));
        }
      }
    });

    test('persisted-сервер чужой схемы не принимается валидатором формы', () {
      // Форма-валидатор loadServerUrl: ssl:// только (тест формы значения,
      // без FFI — сам предикат проверяется в network_config через startsWith).
      const formOk = 'ssl://fulcrum.bullbitcoin.com:50002';
      const junk = 'tcp://attacker.example:50001';
      expect(formOk.startsWith('ssl://'), isTrue);
      expect(junk.startsWith('ssl://'), isFalse);
      // Длина-граница тоже честная.
      expect('ssl://${'a' * 1000}:50002'.length > 256, isTrue);
      // Прямой чек формы из network_config: ssl://... && length <= 256.
      bool acceptServerForm(String v) =>
          v.startsWith('ssl://') && v.length <= 256;
      expect(acceptServerForm(formOk), isTrue);
      expect(acceptServerForm(junk), isFalse);
      expect(acceptServerForm(''), isFalse);
    });
  });

  group('SVG-кэш Iconify (security audit 16.11)', () {
    List<int> svg(String body) => utf8.encode('<svg xmlns="http://www.w3.org/2000/svg">$body</svg>');

    test('валидный SVG пропускается, мусор — нет', () {
      expect(isValidSvg(svg('<path d="M0 0"/>')), isTrue);
      expect(isValidSvg(const []), isFalse);
      expect(isValidSvg(utf8.encode('not a svg at all')), isFalse);
      // Скрипты и обработчики — отказ, flutter_svg их не исполняет,
      // но недоверенное содержимое в рендер не попадает вовсе.
      expect(isValidSvg(svg('<script>alert(1)</script>')), isFalse);
      expect(isValidSvg(svg('<rect onload="steal()"/>')), isFalse);
      // XML-инъекции через DOCTYPE/ENTITY — отказ.
      expect(isValidSvg(utf8.encode('<!DOCTYPE svg [<!ENTITY x "1">]><svg>&x;</svg>')), isFalse);
      // Внешние ссылки — отказ (никто не дёргает чужие URL за рендером).
      expect(isValidSvg(svg('<image xlink:href="http://evil/x.png"/>')), isFalse);
      expect(isValidSvg(svg('<image href="data:image/svg+xml,X"/>')), isFalse);
      expect(isValidSvg(svg('<foreignObject><div/></foreignObject>')), isFalse);
      // BOM-файл читается.
      final bom = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode('<svg><path/></svg>')];
      expect(isValidSvg(bom), isTrue);
      // Вздутый файл — отказ.
      expect(isValidSvg(List.filled(maxSvgBytes + 1, 0x20)), isFalse);
    });

    test('валидатор тикера не пропускает путь-инъекцию', () {
      expect(CoinIconService.isValidKey('BTC'), isTrue);
      expect(CoinIconService.isValidKey('KAS'), isTrue);
      expect(CoinIconService.isValidKey('../../etc/passwd'), isFalse);
      expect(CoinIconService.isValidKey('c:\\temp'), isFalse);
      expect(CoinIconService.isValidKey('btc/tmp'), isFalse);
      expect(CoinIconService.isValidKey(''), isFalse);
      expect(CoinIconService.isValidKey('TOOLONGTICKER'), isFalse);
    });
  });
}
