//! Кэш результата синхронизации XEC (UI-уровень) — зеркало `bch_state_cache`:
//! центр управления показывает свежие данные сразу, без второго gap-скана.
//! КЭШ КЛЮЧЁН ПО КОШЕЛЬКУ.

import 'package:flutter/foundation.dart';
import 'package:veyro/src/rust/api/xec.dart';

class XecStateCache {
  String? _walletId;
  XecSyncDto? _last;
  DateTime? _at;

  XecStateCache._();
  static final XecStateCache instance = XecStateCache._();

  void store(XecSyncDto sync, {required String walletId}) {
    _last = sync;
    _at = DateTime.now();
    _walletId = walletId;
  }

  XecSyncDto? take({
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

class XecConnectState extends ChangeNotifier {
  XecConnectState._();
  static final XecConnectState instance = XecConnectState._();

  bool _busy = false;
  bool get busy => _busy;

  void setBusy(bool value) {
    if (_busy == value) return;
    _busy = value;
    notifyListeners();
  }
}
