//! Кэш результата синхронизации BCH (UI-уровень) — зеркало `ltc_state_cache`:
//! центр управления показывает свежие данные сразу, без второго gap-скана.
//! КЭШ КЛЮЧЁН ПО КОШЕЛЬКУ: смена активного кошелька делает кэш непоказываемым
//! до синка именно этого кошелька.

import 'package:flutter/foundation.dart';
import 'package:veyro/src/rust/api/bch.dart';

class BchStateCache {
  String? _walletId;
  BchSyncDto? _last;
  DateTime? _at;

  BchStateCache._();
  static final BchStateCache instance = BchStateCache._();

  void store(BchSyncDto sync, {required String walletId}) {
    _last = sync;
    _at = DateTime.now();
    _walletId = walletId;
  }

  /// Свежий результат ЭТОГО КОШЕЛЬКА (не старше [maxAge]) или null.
  BchSyncDto? take({
    required String walletId,
    Duration maxAge = const Duration(minutes: 5),
  }) {
    final last = _last;
    final at = _at;
    if (walletId != _walletId || last == null || at == null) return null;
    if (DateTime.now().difference(at) > maxAge) return null;
    return last;
  }

  void clear() {
    _last = null;
    _at = null;
    _walletId = null;
  }
}

/// Глобальное «подключается ли BCH прямо сейчас» — видно с любого экрана
/// (Обзор ставит бейдж на карточке монеты), переживает уход с центра.
class BchConnectState extends ChangeNotifier {
  BchConnectState._();
  static final BchConnectState instance = BchConnectState._();

  bool _busy = false;
  bool get busy => _busy;

  void setBusy(bool value) {
    if (_busy == value) return;
    _busy = value;
    notifyListeners();
  }
}
