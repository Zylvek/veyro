//! Общая сетевая утилита Dart-слоя. Одна реализация вместо копий:
//! - `isTransientNetworkError` — «сбой похож на транспортный/сетевой»
//!   (соответствует классификатору ядра `veyro_bridge::is_transient_
//!   sync_error`); ошибки содержания (адрес/сумма/пароль) сюда не попадают;
//! - `kDefaultGapLimit` — дисциплина адресов BIP44 (константа ядра
//!   `chains::DEFAULT_GAP_LIMIT`, повторяется в UI-вызовах).

const int kDefaultGapLimit = 20;

bool isTransientNetworkError(Object e) {
  final text = e.toString().toLowerCase();
  return text.contains('electrum') ||
      text.contains('unexpected end of file') ||
      text.contains('eof while parsing') ||
      text.contains('all errored') ||
      text.contains('timed out') ||
      text.contains('connection');
}
