//! Фоновая синхронизация реализованных монет — вне UI. Вызывается из двух
//! мест (решение владельца 17.11.2026: «синхронизация должна идти во время
//! загрузки, а не после её появления на главной»):
//!  1) lock_screen — сразу после успешного разблокирования ядра, параллельно
//!     с орбитой и входом на Обзор (пре-варм);
//!  2) dashboard_screen — тихая догрузка при появлении Обзора (как раньше).
//! Дисциплина для каждой монеты: сессия открыта — синк; закрыта, но пароль
//! кэширован ядром — тихий unlock на последнем живом сервере и синк.
//! Ни одного диалога: ошибки — только в debug-лог. Кэши ключены по walletId.

import 'package:flutter/foundation.dart';

import 'package:veyro/src/rust/api/btc.dart';
import 'package:veyro/src/rust/api/bch.dart';
import 'package:veyro/src/rust/api/rvn.dart';
import 'package:veyro/src/rust/api/etc.dart';
import 'package:veyro/src/rust/api/ltc.dart';
import 'package:veyro/src/rust/api/session.dart';
import 'package:veyro/src/rust/api/storage.dart';
import 'package:veyro/src/rust/api/wallet.dart';
import 'package:veyro/src/rust/api/xec.dart';
import 'package:veyro/util/app_dirs.dart';
import 'package:veyro/util/bch_state_cache.dart';
import 'package:veyro/util/btc_state_cache.dart';
import 'package:veyro/util/etc_state_cache.dart';
import 'package:veyro/util/ltc_state_cache.dart';
import 'package:veyro/util/network.dart';
import 'package:veyro/util/rvn_state_cache.dart';
import 'package:veyro/util/xec_state_cache.dart';

/// Единый фоновый проход по всем реализованным монетам. Безопасно звать
/// повторно: свежий кэш (5 минут) не пере-синхронизируется.
Future<void> runCoinBackgroundSync(WalletInfoDto? wallet) async {
  if (wallet == null) return;
  try {
    // BTC: сессия открыта (unlock уже случился) → синк при несвежем кэше.
    final btcSession = await btcSessionState();
    if (btcSession != null) {
      final fresh = BtcStateCache.instance.take(walletId: wallet.id);
      if (fresh == null) {
        BtcConnectState.instance.setBusy(true);
        try {
          final sync = await btcSync(gapLimit: kDefaultGapLimit);
          BtcStateCache.instance.store(sync, walletId: wallet.id);
        } catch (e) {
          debugPrint('veyro-flow: btc background sync failed: $e');
        } finally {
          BtcConnectState.instance.setBusy(false);
        }
      }
    }
    // LTC: закрытая сессия не помеха, если пароль кэширован ядром.
    final ltcSession = await ltcSessionState();
    if (ltcSession == null) {
      var cached = false;
      try {
        cached = await sessionPasswordCached(walletId: wallet.id);
      } catch (_) {}
      if (cached) {
        LtcConnectState.instance.setBusy(true);
        try {
          final servers = await ltcServers();
          String? lastGood;
          try {
            lastGood = await dbGetSetting(key: 'ltc_last_good_server');
          } catch (_) {}
          final ordered = [...servers];
          if (lastGood != null &&
              lastGood.isNotEmpty &&
              ordered.remove(lastGood)) {
            ordered.insert(0, lastGood);
          }
          var unlocked = false;
          for (final server in ordered.take(2)) {
            try {
              await ltcUnlock(
                walletsDir: walletsDir(),
                walletId: wallet.id,
                password: '',
                serverUrl: server,
              ).timeout(const Duration(seconds: 45));
              unlocked = true;
              break;
            } catch (e) {
              debugPrint('veyro-flow: ltc bg unlock $server failed: $e');
            }
          }
          if (unlocked) {
            final sync = await ltcSync(gapLimit: kDefaultGapLimit);
            LtcStateCache.instance.store(sync, walletId: wallet.id);
            try {
              await dbSetSetting(
                key: 'ltc_last_good_server',
                value: sync.serverUrl,
              );
            } catch (_) {}
          }
        } catch (e) {
          debugPrint('veyro-flow: ltc background sync failed: $e');
        } finally {
          LtcConnectState.instance.setBusy(false);
        }
      }
    } else {
      final fresh = LtcStateCache.instance.take(walletId: wallet.id);
      if (fresh == null) {
        LtcConnectState.instance.setBusy(true);
        try {
          final sync = await ltcSync(gapLimit: kDefaultGapLimit);
          LtcStateCache.instance.store(sync, walletId: wallet.id);
        } catch (e) {
          debugPrint('veyro-flow: ltc background sync failed: $e');
        } finally {
          LtcConnectState.instance.setBusy(false);
        }
      }
    }
    // BCH.
    final bchSessionLive = await bchSessionState();
    if (bchSessionLive == null) {
      var cachedBch = false;
      try {
        cachedBch = await sessionPasswordCached(walletId: wallet.id);
      } catch (_) {}
      if (cachedBch) {
        BchConnectState.instance.setBusy(true);
        try {
          final servers = await bchServers();
          String? lastGoodBch;
          try {
            lastGoodBch = await dbGetSetting(key: 'bch_last_good_server');
          } catch (_) {}
          final ordered = [...servers];
          if (lastGoodBch != null &&
              lastGoodBch.isNotEmpty &&
              ordered.remove(lastGoodBch)) {
            ordered.insert(0, lastGoodBch);
          }
          var unlockedB = false;
          for (final server in ordered.take(2)) {
            try {
              await bchUnlock(
                walletsDir: walletsDir(),
                walletId: wallet.id,
                password: '',
                serverUrl: server,
              ).timeout(const Duration(seconds: 45));
              unlockedB = true;
              break;
            } catch (e) {
              debugPrint('veyro-flow: bch bg unlock $server failed: $e');
            }
          }
          if (unlockedB) {
            final syncB = await bchSync(gapLimit: kDefaultGapLimit);
            BchStateCache.instance.store(syncB, walletId: wallet.id);
            try {
              await dbSetSetting(
                key: 'bch_last_good_server',
                value: syncB.serverUrl,
              );
            } catch (_) {}
          }
        } catch (e) {
          debugPrint('veyro-flow: bch background sync failed: $e');
        } finally {
          BchConnectState.instance.setBusy(false);
        }
      }
    } else {
      final freshB = BchStateCache.instance.take(walletId: wallet.id);
      if (freshB == null) {
        BchConnectState.instance.setBusy(true);
        try {
          final syncB = await bchSync(gapLimit: kDefaultGapLimit);
          BchStateCache.instance.store(syncB, walletId: wallet.id);
        } catch (e) {
          debugPrint('veyro-flow: bch background sync failed: $e');
        } finally {
          BchConnectState.instance.setBusy(false);
        }
      }
    }
    // XEC.
    final xecSessionLive = await xecSessionState();
    if (xecSessionLive == null) {
      var cachedXec = false;
      try {
        cachedXec = await sessionPasswordCached(walletId: wallet.id);
      } catch (_) {}
      if (cachedXec) {
        XecConnectState.instance.setBusy(true);
        try {
          final servers = await xecServers();
          String? lastGoodXec;
          try {
            lastGoodXec = await dbGetSetting(key: 'xec_last_good_server');
          } catch (_) {}
          final ordered = [...servers];
          if (lastGoodXec != null &&
              lastGoodXec.isNotEmpty &&
              ordered.remove(lastGoodXec)) {
            ordered.insert(0, lastGoodXec);
          }
          var unlockedX = false;
          for (final server in ordered.take(2)) {
            try {
              await xecUnlock(
                walletsDir: walletsDir(),
                walletId: wallet.id,
                password: '',
                serverUrl: server,
              ).timeout(const Duration(seconds: 45));
              unlockedX = true;
              break;
            } catch (e) {
              debugPrint('veyro-flow: xec bg unlock $server failed: $e');
            }
          }
          if (unlockedX) {
            final syncX = await xecSync(gapLimit: kDefaultGapLimit);
            XecStateCache.instance.store(syncX, walletId: wallet.id);
            try {
              await dbSetSetting(
                key: 'xec_last_good_server',
                value: syncX.serverUrl,
              );
            } catch (_) {}
          }
        } catch (e) {
          debugPrint('veyro-flow: xec background sync failed: $e');
        } finally {
          XecConnectState.instance.setBusy(false);
        }
      }
    } else {
      final freshX = XecStateCache.instance.take(walletId: wallet.id);
      if (freshX == null) {
        XecConnectState.instance.setBusy(true);
        try {
          final syncX = await xecSync(gapLimit: kDefaultGapLimit);
          XecStateCache.instance.store(syncX, walletId: wallet.id);
        } catch (e) {
          debugPrint('veyro-flow: xec background sync failed: $e');
        } finally {
          XecConnectState.instance.setBusy(false);
        }
      }
    }
    // RVN: инфраструктура честно заморожена (вердикт P2P 17.11) — блок
    // активируется без правок, когда появится узел вне IBD.
    final rvnSessionLive = await rvnSessionState();
    if (rvnSessionLive == null) {
      var cachedRvn = false;
      try {
        cachedRvn = await sessionPasswordCached(walletId: wallet.id);
      } catch (_) {}
      if (cachedRvn) {
        RvnConnectState.instance.setBusy(true);
        try {
          final servers = await rvnServers();
          String? lastGoodRvn;
          try {
            lastGoodRvn = await dbGetSetting(key: 'rvn_last_good_server');
          } catch (_) {}
          final ordered = [...servers];
          if (lastGoodRvn != null &&
              lastGoodRvn.isNotEmpty &&
              ordered.remove(lastGoodRvn)) {
            ordered.insert(0, lastGoodRvn);
          }
          var unlockedR = false;
          for (final server in ordered.take(2)) {
            try {
              await rvnUnlock(
                walletsDir: walletsDir(),
                walletId: wallet.id,
                password: '',
                serverUrl: server,
              ).timeout(const Duration(seconds: 45));
              unlockedR = true;
              break;
            } catch (e) {
              debugPrint('veyro-flow: rvn bg unlock $server failed: $e');
            }
          }
          if (unlockedR) {
            final syncR = await rvnSync(gapLimit: kDefaultGapLimit);
            RvnStateCache.instance.store(syncR, walletId: wallet.id);
            try {
              await dbSetSetting(
                key: 'rvn_last_good_server',
                value: syncR.serverUrl,
              );
            } catch (_) {}
          }
        } catch (e) {
          debugPrint('veyro-flow: rvn background sync failed: $e');
        } finally {
          RvnConnectState.instance.setBusy(false);
        }
      }
    } else {
      final freshR = RvnStateCache.instance.take(walletId: wallet.id);
      if (freshR == null) {
        RvnConnectState.instance.setBusy(true);
        try {
          final syncR = await rvnSync(gapLimit: kDefaultGapLimit);
          RvnStateCache.instance.store(syncR, walletId: wallet.id);
        } catch (e) {
          debugPrint('veyro-flow: rvn background sync failed: $e');
        } finally {
          RvnConnectState.instance.setBusy(false);
        }
      }
    }
    // ETC (EVM-профиль: rpcUrl вместо serverUrl, sync без gap-параметра).
    final etcSessionLive = await etcSessionState();
    if (etcSessionLive == null) {
      var cachedEtc = false;
      try {
        cachedEtc = await sessionPasswordCached(walletId: wallet.id);
      } catch (_) {}
      if (cachedEtc) {
        EtcConnectState.instance.setBusy(true);
        try {
          final servers = await etcServers();
          String? lastGoodEtc;
          try {
            lastGoodEtc = await dbGetSetting(key: 'etc_last_good_server');
          } catch (_) {}
          final ordered = [...servers];
          if (lastGoodEtc != null &&
              lastGoodEtc.isNotEmpty &&
              ordered.remove(lastGoodEtc)) {
            ordered.insert(0, lastGoodEtc);
          }
          var unlockedE = false;
          for (final server in ordered.take(2)) {
            try {
              await etcUnlock(
                walletsDir: walletsDir(),
                walletId: wallet.id,
                password: '',
                rpcUrl: server,
              ).timeout(const Duration(seconds: 45));
              unlockedE = true;
              break;
            } catch (e) {
              debugPrint('veyro-flow: etc bg unlock $server failed: $e');
            }
          }
          if (unlockedE) {
            final syncE = await etcSync();
            EtcStateCache.instance.store(syncE, walletId: wallet.id);
            try {
              await dbSetSetting(
                key: 'etc_last_good_server',
                value: syncE.serverUrl,
              );
            } catch (_) {}
          }
        } catch (e) {
          debugPrint('veyro-flow: etc background sync failed: $e');
        } finally {
          EtcConnectState.instance.setBusy(false);
        }
      }
    } else {
      final freshE = EtcStateCache.instance.take(walletId: wallet.id);
      if (freshE == null) {
        EtcConnectState.instance.setBusy(true);
        try {
          final syncE = await etcSync();
          EtcStateCache.instance.store(syncE, walletId: wallet.id);
        } catch (e) {
          debugPrint('veyro-flow: etc background sync failed: $e');
        } finally {
          EtcConnectState.instance.setBusy(false);
        }
      }
    }
  } catch (e) {
    // Само чтение состояния сессий тоже может упасть (ядро/FFI): тихо.
    debugPrint('veyro-flow: background coin sync state failed: $e');
  }
}
