//! Форматирование и разбор сумм BTC — только целочисленная математика.
//!
//! Сатоши — u64 (на 64-битных десктоп-платформах Dart int): деление и остаток,
//! никаких double. Ошибка округления float недопустима для денег (план,
//! Этап 5: «сатоши u64 не float»).

/// Масштаб BTC: 1 BTC = 10^8 сатоши (консенсусная константа).
const int satPerBtc = 100000000;

final RegExp _digits = RegExp(r'^\d+$');
final RegExp _trailingZeros = RegExp(r'0+$');

/// Сатоши → строка BTC (целочисленно: `~/` и `%`, без double).
///
/// Примеры: 150000000 → "1.5", 150000 → "0.0015", 0 → "0".
String satToBtcString(int sat) {
  if (sat < 0) {
    throw ArgumentError('sat must be non-negative, got $sat');
  }
  final whole = sat ~/ satPerBtc;
  var frac = (sat % satPerBtc).toString().padLeft(8, '0');
  frac = frac.replaceAll(_trailingZeros, '');
  return frac.isEmpty ? '$whole' : '$whole.$frac';
}

/// Со знаком для истории: `+0.0015` / `-0.0015` / `0`.
String signedSatToBtcString(int signedSat) {
  if (signedSat > 0) return '+${satToBtcString(signedSat)}';
  if (signedSat < 0) return '-${satToBtcString(-signedSat)}';
  return '0';
}

/// Сатоши с разделением тысяч для сайд-подписи: `150000` → `150 000`.
String groupDigits(int value) {
  final digits = value.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buf.write('\u00A0'); // неразрывный пробел
    }
    buf.write(digits[i]);
  }
  return value < 0 ? '-${buf.toString()}' : buf.toString();
}

/// Разбор строки BTC в сатоши. Возвращает `null` для любого некорректного
/// ввода (не-цифры, больше 8 десятичных знаков, переполнение int64).
/// Результат ≥ 0; проверки «больше нуля» и «достаточно средств» — на
/// вызывающей стороне и/или в Rust-ядре.
int? parseBtcToSat(String input) {
  final s = input.trim().replaceAll('\u00A0', '').replaceAll(' ', '');
  if (s.isEmpty) return null;
  final parts = s.split('.');
  if (parts.length > 2) return null;
  final whole = parts[0];
  final frac = parts.length == 2 ? parts[1] : '';
  if (whole.isEmpty && frac.isEmpty) return null;
  if (whole.isNotEmpty && !_digits.hasMatch(whole)) return null;
  if (frac.isNotEmpty && !_digits.hasMatch(frac)) return null;
  if (frac.length > 8) return null; // точность сатоши

  final int wholePart;
  if (whole.isEmpty) {
    wholePart = 0;
  } else {
    wholePart = int.tryParse(whole) ?? -1;
    if (wholePart < 0) return null; // переполнение/огромное число
    // Целая часть * 10^8 не должна переполнить int64:
    if (wholePart > (0x7FFFFFFFFFFFFFFF ~/ satPerBtc)) return null;
  }
  final fracPart = frac.isEmpty ? 0 : int.parse(frac.padRight(8, '0'));
  return wholePart * satPerBtc + fracPart;
}
