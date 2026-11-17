//! ETC-формат суммы: честный BigInt wei ↔ отображение (18 знаков),
//! без double и без переполнения int64 (1 ETC = 1e18 wei > int64 на
//! суммах больше ~9 монет — поэтому String/BigInt, как в ядре).

import 'package:flutter_test/flutter_test.dart';
import 'package:veyro/util/format.dart';

void main() {
  test('wei → ETC: базовые векторы', () {
    expect(weiToEtcString('0'), '0');
    expect(weiToEtcString('1000000000000000000'), '1');
    expect(weiToEtcString('1230000000000000000'), '1.23');
    expect(weiToEtcString('500000000000000000'), '0.5');
    expect(weiToEtcString('5'), '0.000000000000000005',
        reason: 'честное 18-знаковое значение, без округлений');
    expect(weiToEtcString('1000000000000000000000'), '1000');
  });

  test('wei → ETC: знак для mempool-дельты', () {
    expect(weiToEtcString('-500000000000000000'), '-0.5');
    expect(weiToEtcString('+1000000000000000000'), '1');
  });

  test('wei → ETC: мусор честно как «—»', () {
    expect(weiToEtcString('garbage'), '—');
    expect(weiToEtcString(''), '—');
  });

  test('ETC → wei: точные 18 знаков', () {
    expect(parseEtcToWei('1'), '1000000000000000000');
    expect(parseEtcToWei('1.23'), '1230000000000000000');
    expect(parseEtcToWei('0.1'), '100000000000000000');
    expect(parseEtcToWei(' 1.23'), '1230000000000000000',
        reason: 'пробелы — отображение, не данные');
  });

  test('ETC → wei: честные отказы', () {
    expect(parseEtcToWei(''), null);
    expect(parseEtcToWei('a.b'), null);
    expect(parseEtcToWei('1.2.3'), null);
    expect(parseEtcToWei('1.2345678901234567890'), null,
        reason: '19-й знак не выражается в wei');
    expect(parseEtcToWei('-1'), null, reason: 'сумма отрицательной не бывает');
  });
}
