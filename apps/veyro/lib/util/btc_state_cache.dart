//! Кэш результата синхронизации BTC (UI-уровень, без изменения FFI).
//!
//! Зачем: экран входа уже выполняет btc_sync сразу после btc_unlock; без
//! кэша центр управления запускал ЕЩЁ ОДИН полный gap-limit-скан —
//! пользователь видел второй круг спиннера (жалоба владельца: «btc ещё не
//! синхронизировался»). Данные в кэше — реальный вывод ядра с меткой
//! времени: если свежее ~2 минут, центр показывает их сразу, а свежую
//! синхронизацию делает pull-to-refresh/кнопка.

import 'package:flutter/foundation.dart';

import 'package:veyro/src/rust/api/btc.dart';

class BtcStateCache {
  BtcSyncDto? _last;
  DateTime? _at;

  BtcStateCache._();
  static final BtcStateCache instance = BtcStateCache._();

  void store(BtcSyncDto sync) {
    _last = sync;
    _at = DateTime.now();
  }

  /// Свежий результат (не старше [maxAge]) или null.
  BtcSyncDto? take({Duration maxAge = const Duration(minutes: 5)}) {
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

/// Глобальное «синхронизируется ли BTC прямо сейчас» — бейдж на карточке
/// Обзора (аналог LtcConnectState).
class BtcConnectState extends ChangeNotifier {
  BtcConnectState._();
  static final BtcConnectState instance = BtcConnectState._();

  bool _busy = false;
  bool get busy => _busy;

  void setBusy(bool value) {
    if (_busy == value) return;
    _busy = value;
    notifyListeners();
  }
}
