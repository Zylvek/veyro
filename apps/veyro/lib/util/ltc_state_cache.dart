//! Кэш результата синхронизации LTC (UI-уровень, без изменения FFI) —
//! зеркало `btc_state_cache`: центр управления показывает свежие данные
//! сразу, без второго gap-скана (жалоба владельца на двойную синхро-
//! низацию и «монета не отображается в активах» на Обзоре).

import 'package:veyro/src/rust/api/ltc.dart';

class LtcStateCache {
  LtcSyncDto? _last;
  DateTime? _at;

  LtcStateCache._();
  static final LtcStateCache instance = LtcStateCache._();

  void store(LtcSyncDto sync) {
    _last = sync;
    _at = DateTime.now();
  }

  /// Свежий результат (не старше [maxAge]) или null.
  LtcSyncDto? take({Duration maxAge = const Duration(minutes: 5)}) {
    final last = _last;
    final at = _at;
    if (last == null || at == null) return null;
    if (DateTime.now().difference(at) > maxAge) return null;
    return last;
  }

  void clear() {
    _last = null;
    _at = null;
  }
}
