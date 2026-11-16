//! Тесты исправлений аудита 16.11: кэш синков ключён по кошельку, политика
//! пароля едина для создания/импорта, честные ключи словаря на месте,
//! пикир активов показывает LTC как реализованный актив, а не отключённый.

import 'package:flutter_test/flutter_test.dart';

import 'package:veyro/src/rust/api/btc.dart';
import 'package:veyro/util/btc_state_cache.dart';
import 'package:veyro/util/l10n.dart';
import 'package:veyro/util/ltc_state_cache.dart';
import 'package:veyro/src/rust/api/ltc.dart';
import 'package:veyro/util/network.dart';
import 'package:veyro/util/password_policy.dart';

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
}
