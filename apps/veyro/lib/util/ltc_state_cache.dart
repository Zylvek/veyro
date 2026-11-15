//! Кэш результата синхронизации LTC (UI-уровень, без изменения FFI) —
//! зеркало `btc_state_cache`: центр управления показывает свежие данные
//! сразу, без второго gap-скана (жалоба владельца на двойную синхро-
//! низацию и «монета не отображается в активах» на Обзоре).

import 'package:flutter/foundation.dart';
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

/// Глобальное «подключается ли LTC прямо сейчас» — видно с любого экрана
/// (Обзор ставит бейдж на карточке монеты), переживает уход с центра.
class LtcConnectState extends ChangeNotifier {
  LtcConnectState._();
  static final LtcConnectState instance = LtcConnectState._();

  bool _busy = false;
  bool get busy => _busy;

  void setBusy(bool value) {
    if (_busy == value) return;
    _busy = value;
    notifyListeners();
  }
}
