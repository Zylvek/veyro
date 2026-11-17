//! Кэш результата синхронизации ETC (UI-уровень) — зеркало `rvn_state_cache`:
//! центр управления показывает свежие данные сразу, второй RPC-опроса не
//! дублируется. КЭШ КЛЮЧЁН ПО КОШЕЛЬКУ.

import 'package:flutter/foundation.dart';
import 'package:veyro/src/rust/api/etc.dart';

class EtcStateCache {
  String? _walletId;
  EtcSyncDto? _last;
  DateTime? _at;

  EtcStateCache._();
  static final EtcStateCache instance = EtcStateCache._();

  void store(EtcSyncDto sync, {required String walletId}) {
    _last = sync;
    _at = DateTime.now();
    _walletId = walletId;
  }

  EtcSyncDto? take({
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

class EtcConnectState extends ChangeNotifier {
  EtcConnectState._();
  static final EtcConnectState instance = EtcConnectState._();

  bool _busy = false;
  bool get busy => _busy;

  void setBusy(bool value) {
    if (_busy == value) return;
    _busy = value;
    notifyListeners();
  }
}
