//! Живой баланс реализованной монеты для плиток каталога «Активы»
//! (решение владельца 17.11.2026: «в каждой активированной монете —
//! баланс, как у биткойна»). Источник — per-coin кэши синхронизации,
//! ключённые по walletId. Никакого FFI и сетевых вызовов отсюда: кэш
//! пуст (кошелёк не выбран / не синхронизирован ещё) → null, плитка
//! честно не рисует баланс-строку вместо выдуманного нуля.

import 'package:veyro/util/bch_state_cache.dart';
import 'package:veyro/util/btc_state_cache.dart';
import 'package:veyro/util/ltc_state_cache.dart';
import 'package:veyro/util/rvn_state_cache.dart';
import 'package:veyro/util/xec_state_cache.dart';

/// Снимок баланс-строки одной монеты.
class CoinBalanceView {
  /// confirmed + mempool-минус (то, что реально держит кошелёк сейчас).
  final int availableSat;

  /// Точная mempool-дельта последнего синка (0 — нет в мемпуле);
  /// показывается отдельной подписью, как на Обзоре.
  final int mempoolDeltaSat;

  const CoinBalanceView({
    required this.availableSat,
    required this.mempoolDeltaSat,
  });
}

/// Баланс реализованной монеты из её кэша; null — данных нет.
/// Поддержка ровно по реализованным адаптерам (BTC/LTC/BCH/XEC/RVN);
/// прочие тикеры — не реализованные активы, баланса у них не бывает.
CoinBalanceView? coinBalanceView(String ticker, String? walletId) {
  if (walletId == null || walletId.isEmpty) return null;
  final (int confirmed, int delta)? snap = switch (ticker) {
    'BTC' => () {
        final s = BtcStateCache.instance.take(walletId: walletId);
        if (s == null) return null;
        return (
          s.confirmedSat.toInt(),
          s.unconfirmedDeltaSat.toInt(),
        );
      }(),
    'LTC' => () {
        final s = LtcStateCache.instance.take(walletId: walletId);
        if (s == null) return null;
        return (
          s.confirmedSat.toInt(),
          s.unconfirmedDeltaSat.toInt(),
        );
      }(),
    'BCH' => () {
        final s = BchStateCache.instance.take(walletId: walletId);
        if (s == null) return null;
        return (
          s.confirmedSat.toInt(),
          s.unconfirmedDeltaSat.toInt(),
        );
      }(),
    'XEC' => () {
        final s = XecStateCache.instance.take(walletId: walletId);
        if (s == null) return null;
        return (
          s.confirmedSat.toInt(),
          s.unconfirmedDeltaSat.toInt(),
        );
      }(),
    'RVN' => () {
        final s = RvnStateCache.instance.take(walletId: walletId);
        if (s == null) return null;
        return (
          s.confirmedSat.toInt(),
          s.unconfirmedDeltaSat.toInt(),
        );
      }(),
    _ => null,
  };
  if (snap == null) return null;
  final (confirmed, delta) = snap;
  final available = delta < 0 ? confirmed + delta : confirmed;
  return CoinBalanceView(availableSat: available, mempoolDeltaSat: delta);
}
