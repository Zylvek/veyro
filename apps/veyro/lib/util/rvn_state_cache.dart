//! Кэш результата синхронизации RVN (UI-уровень) — зеркало `xec_state_cache`:
//! центр управления показывает свежие данные сразу, без второго gap-скана.
//! КЭШ КЛЮЧЁН ПО КОШЕЛЬКУ.

import 'package:flutter/foundation.dart';
import 'package:veyro/src/rust/api/rvn.dart';

class RvnStateCache {
  String? _walletId;
  RvnSyncDto? _last;
  DateTime? _at;

  RvnStateCache._();
  static final RvnStateCache instance = RvnStateCache._();

  void store(RvnSyncDto sync, {required String walletId}) {
    _last = sync;
    _at = DateTime.now();
    _walletId = walletId;
  }

  RvnSyncDto? take({
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

class RvnConnectState extends ChangeNotifier {
  RvnConnectState._();
  static final RvnConnectState instance = RvnConnectState._();

  bool _busy = false;
  bool get busy => _busy;

  void setBusy(bool value) {
    if (_busy == value) return;
    _busy = value;
    notifyListeners();
  }
}
