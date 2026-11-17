//! Экран 10 спеки: Main dashboard. Кошелёк-селектор, статус подключения,
//! избранное, список активов, последние транзакции (только реальные при
//! активной BTC-сессии), Receive/Send и честный раздел фиата: источника
//! курсов нет — фиатные суммы не отображаются (выдавать выдуманные
//! значения запрещено спекой).

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:veyro/data/asset_registry.dart';
import 'package:veyro/design/app_colors.dart';
import 'package:veyro/design/components.dart';
import 'package:veyro/design/motion.dart';
import 'package:veyro/design/veyro_mark.dart';
import 'package:veyro/src/rust/api/btc.dart';
import 'package:veyro/src/rust/api/bch.dart';
import 'package:veyro/src/rust/api/rvn.dart';
import 'package:veyro/src/rust/api/etc.dart';
import 'package:veyro/src/rust/api/xec.dart';
import 'package:veyro/src/rust/api/ltc.dart';
import 'package:veyro/src/rust/api/session.dart';
import 'package:veyro/src/rust/api/storage.dart';
import 'package:veyro/src/rust/api/wallet.dart';
import 'package:veyro/util/app_dirs.dart';
import 'package:veyro/util/btc_state_cache.dart';
import 'package:veyro/util/display_prefs.dart';
import 'package:veyro/util/format.dart';
import 'package:veyro/util/l10n.dart';
import 'package:veyro/util/network.dart';
import 'package:veyro/util/bch_state_cache.dart';
import 'package:veyro/util/rvn_state_cache.dart';
import 'package:veyro/util/etc_state_cache.dart';
import 'package:veyro/util/xec_state_cache.dart';
import 'package:veyro/util/ltc_state_cache.dart';
import 'package:veyro/util/price_source.dart';

import 'asset_catalog_screen.dart' show AssetCatalogScreen, CoinIcon;
import 'settings_screen.dart';
import 'asset_detail_screen.dart';
import 'asset_picker_screen.dart';
import 'btc_screen.dart';
import 'history_screen.dart';
import 'bch_screen.dart';
import 'rvn_screen.dart';
import 'etc_screen.dart';
import 'xec_screen.dart';
import 'ltc_screen.dart';
import 'tx_details_screen.dart';

class DashboardScreen extends StatefulWidget {
  /// Точки замены для виджет-тестов (обычно — реальные вызовы ядра).
  final Future<List<WalletInfoDto>?> Function()? walletLoader;
  final Future<BtcSessionStateDto?> Function()? sessionLoader;
  final Future<List<BtcHistoryItemDto>> Function()? historyLoader;

  const DashboardScreen({
    super.key,
    this.walletLoader,
    this.sessionLoader,
    this.historyLoader,
  });

  /// Стартовая политика (решение владельца): приложение открывается
  /// СПОКОЙНО на Обзоре — без стартовых модалок и авто-переходов в
  /// разблокировку. Подключение BTC — когда пользователь заходит в
  /// BTC-поток (там пароль спрашивается сам).
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<WalletInfoDto>? _wallets;
  String? _selectedId;
  BtcSessionStateDto? _session;
  List<BtcHistoryItemDto>? _recent;
  String? _historyError;
  String? _error;

  // Мультикоин-карточка «Последние транзакции» (решение владельца
  // 17.11.2026: транзакции видны для ВСЕХ реализованных монет; секция
  // каждой монеты появляется при её живой сессии; RVN заморожен —
  // честно вне карточки до живой инфраструктуры).
  List<LtcHistoryItemDto>? _recentLtc;
  List<BchHistoryItemDto>? _recentBch;
  List<XecHistoryItemDto>? _recentXec;
  List<EtcHistoryItemDto>? _recentEtc;
  String? _recentLtcErr;
  String? _recentBchErr;
  String? _recentXecErr;
  String? _recentEtcErr;
  bool _ltcLive = false;
  bool _bchLive = false;
  bool _xecLive = false;
  bool _etcLive = false;
  String? _etcAccount;
  bool _otherRecentsLoading = false;

  /// Курс BTC в валюте отображения; null — курс недоступен (сети нет),
  /// тогда фиатная строка честно скрыта.
  double? _fiatRate;

  /// Курс LTC (строка карточки «Активы»); null — честно скрыта.
  double? _ltcRate;
  double? _bchRate;
  double? _xecRate;
  double? _rvnRate;
  double? _etcRate;

  /// Курс выбранной монеты графика (id из PriceSource.chartCoins) —
  /// для подписи «≈ N {монета}» (решение владельца). Нет курса — нет
  /// подписи, выдуманных значений нет.
  double? _chartCoinRate;

  /// Активное окно реального графика курса (референс: 1D/1W/1M/1Y).
  String _period = '1М';

  /// Окна period-табов в днях (параметр провайдера цен).
  static const Map<String, int> _periodDays = {
    '1Д': 1,
    '1Н': 7,
    '1М': 30,
    '1Г': 365,
  };

  /// Метки периодов идут через словарь (поддержка языков).
  static const Map<String, String> _periodKeyToL10n = {
    '1Д': 'period_1d',
    '1Н': 'period_1w',
    '1М': 'period_1m',
    '1Г': 'period_1y',
  };

  /// Монета линии графика — настройка владельца в чипах графика
  /// («осматривать другие монеты»); выбор хранится в DisplayPrefs.
  String get _chartCoinId =>
      PriceSource.chartCoins[DisplayPrefs.chartCoin] ?? 'ethereum';

  /// Реальная линия курса ЭФИРА (валюта отображения) за окно периода —
  /// график Обзора по требованию владельца, как в референсе Nexus.
  /// От прямого провайдера цен; null — данных нет, график скрыт.
  List<MarketPoint>? _marketPoints;

  @override
  void initState() {
    super.initState();
    // Карточка «Последние транзакции» не исчезает во время синка BTC:
    // по факту его завершения — честный ретрай истории (и всех монет).
    BtcConnectState.instance.addListener(_onCoinSyncPulse);
    LtcConnectState.instance.addListener(_onCoinSyncPulse);
    BchConnectState.instance.addListener(_onCoinSyncPulse);
    XecConnectState.instance.addListener(_onCoinSyncPulse);
    EtcConnectState.instance.addListener(_onCoinSyncPulse);
    _refresh();
  }

  @override
  void dispose() {
    BtcConnectState.instance.removeListener(_onCoinSyncPulse);
    LtcConnectState.instance.removeListener(_onCoinSyncPulse);
    BchConnectState.instance.removeListener(_onCoinSyncPulse);
    XecConnectState.instance.removeListener(_onCoinSyncPulse);
    EtcConnectState.instance.removeListener(_onCoinSyncPulse);
    super.dispose();
  }

  /// Синк любой монеты начался/закончился → перерисовка и честный ретрай
  /// истории (карточка не исчезает; решение владельца 17.11.2026).
  void _onCoinSyncPulse() {
    if (!mounted) return;
    if (!_recentLoading && _session != null && _recent == null) {
      _loadRecent();
    }
    if (_otherRecentsLoading) return;
    final anyBusy = BtcConnectState.instance.busy ||
        LtcConnectState.instance.busy ||
        BchConnectState.instance.busy ||
        XecConnectState.instance.busy ||
        EtcConnectState.instance.busy;
    if (!anyBusy) _loadOtherRecents();
  }

  Future<List<WalletInfoDto>> _loadWallets() async =>
      widget.walletLoader != null
      ? (await widget.walletLoader!()) ?? const []
      : await listWallets(walletsDir: walletsDir());

  Future<BtcSessionStateDto?> _loadSession() async =>
      widget.sessionLoader != null
      ? await widget.sessionLoader!()
      : await btcSessionState();

  Future<void> _refresh() async {
    // Никакой полноэкранной загрузки (решение владельца): Обзор сразу
    // показывает контент, данные бесшумно заполняют его по приходу.
    setState(() {
      _error = null;
      _recent = null;
      _historyError = null;
      _recentLtc = null;
      _recentBch = null;
      _recentXec = null;
      _recentEtc = null;
      _recentLtcErr = null;
      _recentBchErr = null;
      _recentXecErr = null;
      _recentEtcErr = null;
    });
    await DisplayPrefs.ensureLoaded();
    try {
      final wallets = await _loadWallets();
      final session = await _loadSession();
      if (!mounted) return;
      final selected =
          DisplayPrefs.walletId != null &&
              wallets.any((w) => w.id == DisplayPrefs.walletId)
          ? DisplayPrefs.walletId
          : (wallets.isEmpty ? null : wallets.first.id);
      // Курсы BTC/ETH и линию курса эфира забираем ДО снятия загрузки,
      // иначе hero-карта рисуется пустой и «допрыгивает» контентом.
      double? rate;
      double? chartCoinRate;
      double? ltcRate;
      double? bchRate;
      double? xecRate;
      double? rvnRate;
      double? etcRate;
      List<MarketPoint>? series;
      final fiat = DisplayPrefs.fiatCurrency;
      final source = PriceSource.instance;
      // Каждый курс — самостоятельная попытка (решение владельца: фиаты
      // обязаны быть видны на карточках монет): провал ОДНОГО запроса
      // (rate-limit/сеть) не должен гасить остальные строки и график.
      // Ошибка одного курса → null только у него, остальное честно живёт.
      Future<T?> pick<T>(Future<T> Function() fetch) async {
        try {
          return await fetch().timeout(const Duration(seconds: 12));
        } catch (_) {
          return null;
        }
      }

      rate = await pick<double?>(() => source.btcPriceIn(fiat));
      chartCoinRate =
          await pick<double?>(() => source.coinPriceIn(_chartCoinId, fiat));
      ltcRate = await pick<double?>(() => source.coinPriceIn('litecoin', fiat));
      bchRate =
          await pick<double?>(() => source.coinPriceIn('bitcoin-cash', fiat));
      xecRate = await pick<double?>(() => source.coinPriceIn('ecash', fiat));
      rvnRate =
          await pick<double?>(() => source.coinPriceIn('ravencoin', fiat));
      etcRate =
          await pick<double?>(() => source.coinPriceIn('ethereum-classic', fiat));
      series = await pick<List<MarketPoint>?>(() => source
          .marketSeries(_chartCoinId, fiat, _periodDays[_period] ?? 30));
      if (!mounted) return;
      setState(() {
        _wallets = wallets;
        _selectedId = selected;
        _session = session;
        _fiatRate = rate;
        _chartCoinRate = chartCoinRate;
        _ltcRate = ltcRate;
        _bchRate = bchRate;
        _xecRate = xecRate;
        _rvnRate = rvnRate;
        _etcRate = etcRate;
        _marketPoints = series;
      });
      await _loadRecent();
      // Живые сессии остальных монет (секции карточки транзакций) —
      // только реальная сборка; в тестах с инъекциями ядра нет.
      if (widget.sessionLoader == null) {
        try {
          _ltcLive = (await ltcSessionState()) != null;
        } catch (_) {
          _ltcLive = false;
        }
        try {
          _bchLive = (await bchSessionState()) != null;
        } catch (_) {
          _bchLive = false;
        }
        try {
          _xecLive = (await xecSessionState()) != null;
        } catch (_) {
          _xecLive = false;
        }
        try {
          final s = await etcSessionState();
          _etcLive = s != null;
          _etcAccount = s?.accountAddress;
        } catch (_) {
          _etcLive = false;
        }
        if (mounted) _loadOtherRecents();
      }
      // Фоновая догрузка монет прямо с Обзора (решение владельца: «чтобы
      // посмотреть, есть ли монеты, не заходя на монету»): иконка загрузки
      // на карточке, балансы подливаются в кэши тихо. Только в реальной
      // сборке: тесты с инъекциями — без ядра, фоновые FFI-вызовы не для них.
      if (widget.sessionLoader == null && widget.historyLoader == null) {
        await _backgroundCoinSync();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    }
  }

  bool _coinSyncRunning = false;

  /// Тихое обновление балансов BTC/LTC: сессия открыта — синк; сессия
  /// закрыта, но пароль кэширован ядром — тихий unlock на последнем живом
  /// сервере и синк. Ни одного диалога: ошибки — только в debug-лог.
  Future<void> _backgroundCoinSync() async {
    if (_coinSyncRunning || !mounted) return;
    _coinSyncRunning = true;
    final wallet = _selected;
    try {
      // BTC: кэш этого кошелька свежее 5 минут — не тратим соединений.
      final btcSession = await btcSessionState();
      if (btcSession != null && !mounted) return;
      if (btcSession != null) {
        final fresh = wallet == null
            ? null
            : BtcStateCache.instance.take(walletId: wallet.id);
        if (fresh == null) {
          BtcConnectState.instance.setBusy(true);
          try {
            final sync = await btcSync(gapLimit: kDefaultGapLimit);
            if (mounted && wallet != null) {
              BtcStateCache.instance.store(sync, walletId: wallet.id);
            }
          } catch (e) {
            debugPrint('veyro-flow: btc background sync failed: $e');
          } finally {
            BtcConnectState.instance.setBusy(false);
          }
        }
      }
      // LTC: закрытая сессия не помеха, если пароль кэширован ядром.
      final ltcSession = await ltcSessionState();
      if (!mounted) return;
      if (ltcSession == null && wallet != null) {
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
              if (mounted) {
                LtcStateCache.instance.store(sync, walletId: wallet.id);
              }
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
      } else if (ltcSession != null) {
        final fresh = wallet == null
            ? null
            : LtcStateCache.instance.take(walletId: wallet.id);
        if (fresh == null) {
          LtcConnectState.instance.setBusy(true);
          try {
            final sync = await ltcSync(gapLimit: kDefaultGapLimit);
            if (mounted && wallet != null) {
              LtcStateCache.instance.store(sync, walletId: wallet.id);
            }
          } catch (e) {
            debugPrint('veyro-flow: ltc background sync failed: $e');
          } finally {
            LtcConnectState.instance.setBusy(false);
          }
        }
      }
      // BCH: та же дисциплина тихого синка, что у LTC (пароль кэш + серверы).
      final bchSessionLive = await bchSessionState();
      if (!mounted) return;
      if (bchSessionLive == null && wallet != null) {
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
              if (mounted) {
                BchStateCache.instance.store(syncB, walletId: wallet.id);
                try {
                  await dbSetSetting(
                    key: 'bch_last_good_server',
                    value: syncB.serverUrl,
                  );
                } catch (_) {}
              }
            }
          } catch (e) {
            debugPrint('veyro-flow: bch background sync failed: $e');
          } finally {
            BchConnectState.instance.setBusy(false);
          }
        }
      } else if (bchSessionLive != null) {
        final freshB = wallet == null
            ? null
            : BchStateCache.instance.take(walletId: wallet.id);
        if (freshB == null) {
          BchConnectState.instance.setBusy(true);
          try {
            final syncB = await bchSync(gapLimit: kDefaultGapLimit);
            if (mounted && wallet != null) {
              BchStateCache.instance.store(syncB, walletId: wallet.id);
            }
          } catch (e) {
            debugPrint('veyro-flow: bch background sync failed: $e');
          } finally {
            BchConnectState.instance.setBusy(false);
          }
        }
      }
      // XEC: та же дисциплина тихого синка, что у BCH (пароль кэш + серверы).
      final xecSessionLive = await xecSessionState();
      if (!mounted) return;
      if (xecSessionLive == null && wallet != null) {
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
              if (mounted) {
                XecStateCache.instance.store(syncX, walletId: wallet.id);
                try {
                  await dbSetSetting(
                    key: 'xec_last_good_server',
                    value: syncX.serverUrl,
                  );
                } catch (_) {}
              }
            }
          } catch (e) {
            debugPrint('veyro-flow: xec background sync failed: $e');
          } finally {
            XecConnectState.instance.setBusy(false);
          }
        }
      } else if (xecSessionLive != null) {
        final freshX = wallet == null
            ? null
            : XecStateCache.instance.take(walletId: wallet.id);
        if (freshX == null) {
          XecConnectState.instance.setBusy(true);
          try {
            final syncX = await xecSync(gapLimit: kDefaultGapLimit);
            if (mounted && wallet != null) {
              XecStateCache.instance.store(syncX, walletId: wallet.id);
            }
          } catch (e) {
            debugPrint('veyro-flow: xec background sync failed: $e');
          } finally {
            XecConnectState.instance.setBusy(false);
          }
        }
      }
      // RVN: та же дисциплина тихого синка, что у XEC (пароль кэш + серверы).
      final rvnSessionLive = await rvnSessionState();
      if (!mounted) return;
      if (rvnSessionLive == null && wallet != null) {
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
              if (mounted) {
                RvnStateCache.instance.store(syncR, walletId: wallet.id);
                try {
                  await dbSetSetting(
                    key: 'rvn_last_good_server',
                    value: syncR.serverUrl,
                  );
                } catch (_) {}
              }
            }
          } catch (e) {
            debugPrint('veyro-flow: rvn background sync failed: $e');
          } finally {
            RvnConnectState.instance.setBusy(false);
          }
        }
      } else if (rvnSessionLive != null) {
        final freshR = wallet == null
            ? null
            : RvnStateCache.instance.take(walletId: wallet.id);
        if (freshR == null) {
          RvnConnectState.instance.setBusy(true);
          try {
            final syncR = await rvnSync(gapLimit: kDefaultGapLimit);
            if (mounted && wallet != null) {
              RvnStateCache.instance.store(syncR, walletId: wallet.id);
            }
          } catch (e) {
            debugPrint('veyro-flow: rvn background sync failed: $e');
          } finally {
            RvnConnectState.instance.setBusy(false);
          }
        }
      }
      // ETC: та же дисциплина тихого синка, что у XEC/RVN (пароль кэш + серверы).
      final etcSessionLive = await etcSessionState();
      if (!mounted) return;
      if (etcSessionLive == null && wallet != null) {
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
              if (mounted) {
                EtcStateCache.instance.store(syncE, walletId: wallet.id);
                try {
                  await dbSetSetting(
                    key: 'etc_last_good_server',
                    value: syncE.serverUrl,
                  );
                } catch (_) {}
              }
            }
          } catch (e) {
            debugPrint('veyro-flow: etc background sync failed: $e');
          } finally {
            EtcConnectState.instance.setBusy(false);
          }
        }
      } else if (etcSessionLive != null) {
        final freshE = wallet == null
            ? null
            : EtcStateCache.instance.take(walletId: wallet.id);
        if (freshE == null) {
          EtcConnectState.instance.setBusy(true);
          try {
            final syncE = await etcSync();
            if (mounted && wallet != null) {
              EtcStateCache.instance.store(syncE, walletId: wallet.id);
            }
          } catch (e) {
            debugPrint('veyro-flow: etc background sync failed: $e');
          } finally {
            EtcConnectState.instance.setBusy(false);
          }
        }
      }
      if (mounted) setState(() {});
    } catch (e) {
      // Само чтение состояния сессий тоже может упасть (ядро/FFI):
      // Обзор обязан молча деградировать, а не показывать «Ядро недоступно».
      debugPrint('veyro-flow: background coin sync state failed: $e');
    } finally {
      _coinSyncRunning = false;
    }
  }

  /// Реальная линия курса ЭФИРА (прямой провайдер цен; владелец:
  /// график — Ethereum, как в референсе) за окно периода; ошибки →
  /// график скрыт, без выдуманной линии.
  Future<void> _loadMarketSeries() async {
    final fiat = DisplayPrefs.fiatCurrency;
    final days = _periodDays[_period] ?? 30;
    try {
      final series = await PriceSource.instance
          .marketSeries(_chartCoinId, fiat, days)
          .timeout(const Duration(seconds: 12));
      if (!mounted) return;
      setState(() => _marketPoints = series);
    } catch (_) {
      if (!mounted) return;
      setState(() => _marketPoints = null);
    }
  }

  /// Цены серии для линии.
  List<double>? get _seriesPrices =>
      _marketPoints?.map((p) => p.price).toList();

  /// Подписи точек для наведения: «цена · время» (реальные данные
  /// провайдера; окно до суток → только часы:минуты, длинные → дата).
  List<String>? get _seriesHints {
    final points = _marketPoints;
    if (points == null || points.isEmpty) return null;
    final compact =
        points.last.time.difference(points.first.time).inHours <= 34;
    return [for (final p in points) _marketLabel(p, compact)];
  }

  String _marketLabel(MarketPoint point, bool compact) {
    String pad(int v) => v.toString().padLeft(2, '0');
    final t = point.time;
    final currency = DisplayPrefs.fiatCurrency.toUpperCase();
    final price = '${formatFiat(point.price)} $currency';
    final time = compact
        ? '${pad(t.hour)}:${pad(t.minute)}'
        : '${pad(t.day)}.${pad(t.month)}';
    return '$price · $time';
  }

  /// Последние транзакции — только при активной BTC-сессии; ошибки ядро
  /// отдаёт как есть. Пока BTC синхронизируется, история честно грузится
  /// лоадером, а карточка НЕ прячется (решение владельца 17.11.2026:
  /// виджет транзакций не должен пропадать во время синхронизации).
  bool _recentLoading = false;
  Future<void> _loadRecent() async {
    if (_session == null || _recentLoading) return;
    _recentLoading = true;
    try {
      final items = widget.historyLoader != null
          ? await widget.historyLoader!()
          : (await btcHistory()).items;
      if (!mounted) return;
      setState(() {
        _recent = items.take(3).toList();
        _historyError = null;
      });
    } catch (e) {
      if (!mounted) return;
      // Ошибка не прячет карточку: пока идёт синк — лоадер, после синка
      // будет честный ретрай (см. _onCoinSyncPulse).
      setState(() => _historyError = e.toString());
    } finally {
      _recentLoading = false;
    }
  }

  /// Истории остальных реализованных монет — только реальная сборка
  /// (тесты с инъекциями — без ядра). Секция появляется при живой
  /// сессии монеты; лоадер/ошибка честные, без выдуманных нулей.
  Future<void> _loadOtherRecents() async {
    if (widget.sessionLoader != null || widget.historyLoader != null) return;
    if (_otherRecentsLoading) return;
    _otherRecentsLoading = true;
    try {
      if (_ltcLive && _recentLtc == null && !LtcConnectState.instance.busy) {
        try {
          final h = await ltcHistory().timeout(const Duration(seconds: 30));
          if (mounted) {
            setState(() {
              _recentLtc = h.items.take(2).toList();
              _recentLtcErr = null;
            });
          }
        } catch (e) {
          if (mounted) setState(() => _recentLtcErr = e.toString());
        }
      }
      if (_bchLive && _recentBch == null && !BchConnectState.instance.busy) {
        try {
          final h = await bchHistory().timeout(const Duration(seconds: 30));
          if (mounted) {
            setState(() {
              _recentBch = h.items.take(2).toList();
              _recentBchErr = null;
            });
          }
        } catch (e) {
          if (mounted) setState(() => _recentBchErr = e.toString());
        }
      }
      if (_xecLive && _recentXec == null && !XecConnectState.instance.busy) {
        try {
          final h = await xecHistory().timeout(const Duration(seconds: 30));
          if (mounted) {
            setState(() {
              _recentXec = h.items.take(2).toList();
              _recentXecErr = null;
            });
          }
        } catch (e) {
          if (mounted) setState(() => _recentXecErr = e.toString());
        }
      }
      if (_etcLive && _recentEtc == null && !EtcConnectState.instance.busy) {
        try {
          final h = await etcHistory().timeout(const Duration(seconds: 30));
          if (mounted) {
            setState(() {
              _recentEtc = h.items.take(2).toList();
              _recentEtcErr = null;
            });
          }
        } catch (e) {
          if (mounted) setState(() => _recentEtcErr = e.toString());
        }
      }
    } finally {
      _otherRecentsLoading = false;
    }
  }

  Future<void> _selectWallet(String id) async {
    setState(() => _selectedId = id);
    await DisplayPrefs.setWalletId(id);
  }

  Future<void> _toggleHide() async {
    final next = !DisplayPrefs.hideBalances;
    await DisplayPrefs.setHideBalances(next);
    setState(() {});
  }

  WalletInfoDto? get _selected {
    final wallets = _wallets;
    if (wallets == null || wallets.isEmpty) return null;
    return wallets.firstWhere(
      (w) => w.id == _selectedId,
      orElse: () => wallets.first,
    );
  }

  String _maskAmount(String value) =>
      DisplayPrefs.hideBalances ? '••••••' : value;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: _error != null
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: VEmptyState(
                      icon: Icons.cloud_off_outlined,
                      title: t('core_unavailable'),
                      message: '$_error\n${t('check_install')}',
                      action: FilledButton.tonal(
                        onPressed: _refresh,
                        child: Text(t('retry')),
                      ),
                    ),
                  )
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    children: [
                      VEntrance(step: 0, child: _buildTopPanel(context)),
                      const SizedBox(height: 14),
                      VEntrance(step: 1, child: _buildBalanceBlock(context)),
                      const SizedBox(height: 14),
                      VEntrance(step: 2, child: _buildActionsRow(context)),
                      const SizedBox(height: 20),
                      VEntrance(
                        step: 3,
                        child: VTwoColumn(
                          left: Column(
                            children: [
                              _buildAssetsCard(context),
                              const SizedBox(height: 16),
                              _buildFavoritesCard(context),
                            ],
                          ),
                          right: Column(children: [_buildRecentCard(context)]),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  /// Верхняя панель: справа — компактный выбор кошелька и
  /// переключатель скрытия сумм. Селектор НЕ растягивается на пол-экрана
  /// (решение владельца 17.11.2026: «почему верхняя плашка уехала на всю
  /// длину»): карта подстраивается под имя кошелька (потолок 320 —
  /// длинные имена), иконки — прижаты к правому краю через Spacer.
  Widget _buildTopPanel(BuildContext context) {
    final wallets = _wallets ?? const <WalletInfoDto>[];
    return Row(
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              child: DropdownButtonFormField<String>(
                initialValue: _selectedId,
                isDense: true,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 6,
                  ),
                ),
                items: [
                  for (final w in wallets)
                    DropdownMenuItem(value: w.id, child: Text(w.name)),
                ],
                onChanged: (id) {
                  if (id != null) _selectWallet(id);
                },
              ),
            ),
          ),
        ),
        const Spacer(),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
              if (DisplayPrefs.degraded)
                VStatusChip(t('db_unavailable'), kind: VChipKind.warning),
              IconButton(
                tooltip: DisplayPrefs.hideBalances
                    ? t('show_amounts')
                    : t('hide_amounts'),
                icon: Icon(
                  DisplayPrefs.hideBalances
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: VColors.textSecondary,
                ),
                onPressed: _toggleHide,
              ),
              // Настройки — шестерёнка в правом верхнем углу Обзора
              // (решение владельца): навигация без вкладки настроек.
              // Возврат — тихий refresh: настройки (валюта/график)
              // применяются сразу, без перезапуска приложения.
              IconButton(
                tooltip: t('settings_title'),
                icon: const Icon(
                  Icons.settings_outlined,
                  color: VColors.textSecondary,
                ),
                onPressed: () async {
                  await pushVeyro<void>(context, const SettingsScreen());
                  if (mounted) await _refresh();
                },
              ),
            ],
        ),
      ],
    );
  }

  /// Hero-карта баланса (референс владельца «Nexus»: большая тёмная
  /// карта с подсветками): label, крупная сумма (общая цена в валюте
  /// отображения; курс недоступен — сумма в BTC) и подпись «≈ N ETH» —
  /// эквивалент суммы в эфире по реальному курсу провайдера, ровно как
  /// в референсе («Total balance → ≈ 7.4211 ETH»). Под ними РЕАЛЬНЫЙ
  /// график курса ЭФИРА за окно периода (требование владельца). Динамику
  /// в процентах не рисуем — данных о ней ядро не отдаёт.
  Widget _buildBalanceBlock(BuildContext context) {
    final session = _session;
    final balanceSat = _btcBalanceSat();
    final rate = _fiatRate;
    return VHeroPanel(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  t('total_balance'),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: VColors.textSecondary,
                  ),
                ),
                const Spacer(),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    if (session != null && session.hasSpendables)
                      VStatusChip(t('synced_funds'), kind: VChipKind.success),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Общая цена валют (решение владельца: «только общую цену
            // валют и всё»): одно число. Курса нет — сумма в BTC.
            if (rate != null)
              VAmount(
                _maskAmount(formatFiat(balanceSat / 1e8 * rate)),
                suffix: DisplayPrefs.fiatCurrency.toUpperCase(),
                fontSize: 42,
              )
            else
              VAmount(
                _maskAmount(satToBtcString(balanceSat)),
                suffix: 'BTC',
                fontSize: 42,
              ),
            const SizedBox(height: 6),
            // Эквивалент суммы в ВЫБРАННОЙ монете графика — решение
            // владельца («≈ на эту же монету»); цены монеты нет —
            // строки нет. По умолчанию ETH, как в референсе.
            if (rate != null && _chartCoinRate != null && _chartCoinRate! > 0)
              VAnimatedText(
                '≈ ${_maskAmount((balanceSat / 1e8 * rate / _chartCoinRate!).toStringAsFixed(4))} ${DisplayPrefs.chartCoin}',
                style: TextStyle(
                  fontFamily: kMonoFont,
                  fontSize: 13,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: VColors.textSecondary,
                ),
              ),
            const SizedBox(height: 12),
            // Резерв высоты под линию курса: карта не «допрыгивает»
            // контентом, когда серия ещё не дошла или сети нет —
            // зона просто пуста (выдуманную линию не рисуем).
            SizedBox(
              height: 126,
              width: double.infinity,
              child: (_seriesPrices != null && _seriesPrices!.length >= 2)
                  ? VSparkline(values: _seriesPrices!, hints: _seriesHints)
                  : null,
            ),
            const SizedBox(height: 6),
            _buildPeriodTabs(),
          ],
        ),
      ),
    );
  }

  /// Вкладки окна: скользящая «пилюля» под выбранным окном — плавно
  /// катается между вкладками (решение владельца: живые микро-анимации).
  Widget _buildPeriodTabs() {
    final tabs = _periodDays.keys.toList();
    final idx = tabs.indexOf(_period);
    const tabWidth = 52.0;
    return Stack(
      children: [
        AnimatedPositioned(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          left: idx * tabWidth,
          child: Container(
            width: tabWidth,
            height: 34,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: Colors.white.withValues(alpha: 0.09),
            ),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < tabs.length; i++)
              SizedBox(
                width: tabWidth,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    if (_period == tabs[i]) return;
                    setState(() => _period = tabs[i]);
                    _loadMarketSeries();
                  },
                  child: Container(
                    height: 34,
                    alignment: Alignment.center,
                    child: Text(
                      t(_periodKeyToL10n[tabs[i]] ?? tabs[i]),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: _period == tabs[i]
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: _period == tabs[i]
                            ? VColors.textPrimary
                            : VColors.textSecondary.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Реальный подтверждённый баланс BTC из последней синхронизации АКТИВНОГО
  /// кошелька (кэш от экрана входа/центра; ключ — id кошелька, чужие данные
  /// не показываются). Данных нет — 0 (решение владельца).
  int _btcBalanceSat() {
    final id = _selected?.id;
    if (id == null) return 0;
    final sync = BtcStateCache.instance.take(walletId: id);
    if (sync == null) return 0;
    final confirmed = sync.confirmedSat.toInt();
    final delta = sync.unconfirmedDeltaSat.toInt();
    return delta < 0 ? confirmed + delta : confirmed;
  }

  /// Receive / Send — как в референсе: Send — основная (заполненная),
  /// Receive — спокойная. Реальный вход в поток через выбор актива.
  Widget _buildActionsRow(BuildContext context) {
    final selected = _selected;
    return Row(
      children: [
        Expanded(
          child: VButton.primary(
            'Send',
            icon: Icons.north_east,
            onPressed: selected == null
                ? null
                : () => _push(AssetPickerScreen(isReceive: false)),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: VButton.secondary(
            'Receive',
            icon: Icons.south_west,
            onPressed: selected == null
                ? null
                : () => _push(AssetPickerScreen(isReceive: true), reload: true),
          ),
        ),
      ],
    );
  }

  Widget _buildFavoritesCard(BuildContext context) {
    final favorites = kAssetRegistry
        .where((a) => DisplayPrefs.favorites.contains(a.ticker))
        .toList();
    // Пустое избранное — карточки нет вовсе (решение владельца: без
    // подсказок-лекций на Обзоре).
    if (favorites.isEmpty) return const SizedBox.shrink();
    return VCard(
      icon: Icons.star_outline,
      title: t('favorites_card'),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final asset in favorites)
              ActionChip(
                avatar: _AssetAvatar(asset),
                label: Text(asset.ticker),
                onPressed: () =>
                    _push(AssetDetailScreen(asset: asset, wallet: _selected)),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildAssetsCard(BuildContext context) {
    // Бейдж фонового синка BTC/LTC должен перерисовываться по факту смены
    // состояния, не только по setState Обзора — подписка на оба нотифаера.
    return AnimatedBuilder(
      animation: Listenable.merge([
        BtcConnectState.instance,
        LtcConnectState.instance,
        BchConnectState.instance,
        XecConnectState.instance,
        RvnConnectState.instance,
        EtcConnectState.instance,
      ]),
      builder: (context, _) => _buildAssetsCardBody(context),
    );
  }

  Widget _buildAssetsCardBody(BuildContext context) {
    final btc = kAssetRegistry.firstWhere((a) => a.ticker == 'BTC');
    final ltc = kAssetRegistry.firstWhere((a) => a.ticker == 'LTC');
    final bch = kAssetRegistry.firstWhere((a) => a.ticker == 'BCH');
    final xec = kAssetRegistry.firstWhere((a) => a.ticker == 'XEC');
    final rvn = kAssetRegistry.firstWhere((a) => a.ticker == 'RVN');
    final etc = kAssetRegistry.firstWhere((a) => a.ticker == 'ETC');
    final wallet = _selected;
    // Сумма монеты — реальный подтверждённый баланс из последней
    // синхронизации ЭТОГО кошелька (кэш ключён по id; без данных — 0).
    final sync = wallet == null
        ? null
        : BtcStateCache.instance.take(walletId: wallet.id);
    final balanceSat = _btcBalanceSat();
    // LTC — вторая реализованная монета (receive-only ядро + send): та же
    // карточка-шапка, баланс из LTC-кэша этого же кошелька, фиат — тот же
    // источник цен.
    final ltcSync = wallet == null
        ? null
        : LtcStateCache.instance.take(walletId: wallet.id);
    final ltcBalanceLit = ltcSync == null
        ? 0
        : (ltcSync.unconfirmedDeltaSat.toInt() < 0
              ? ltcSync.confirmedSat.toInt() +
                    ltcSync.unconfirmedDeltaSat.toInt()
              : ltcSync.confirmedSat.toInt());
    final rate = _fiatRate;
    final ltcRate = _ltcRate;
    final btcBusy = BtcConnectState.instance.busy;
    return VCard(
      icon: Icons.grid_view_outlined,
      title: t('assets_title'),
      children: [
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            leading: _AssetAvatar(btc),
            title: const Text('Bitcoin'),
            // Количество под именем — как в референсе.
            subtitle: btcBusy
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        height: 12,
                        width: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        t('sync_now_short'),
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  )
                : VAnimatedText(
                    '${_maskAmount(satToBtcString(balanceSat))} BTC',
                    style: const TextStyle(
                      fontFamily: kMonoFont,
                      fontSize: 11.5,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Фиатное выражение позиции — от того же курса, что и
                // hero-карта; курса нет — справа пусто (без выдумок).
                if (rate != null) ...[
                  VAnimatedText(
                    _maskAmount(formatFiat(balanceSat / 1e8 * rate)),
                    style: const TextStyle(
                      fontFamily: kMonoFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                      color: VColors.textPrimary,
                    ),
                  ),
                  Text(
                    DisplayPrefs.fiatCurrency.toUpperCase(),
                    style: const TextStyle(
                      fontFamily: kMonoFont,
                      fontSize: 11,
                      color: VColors.textSecondary,
                    ),
                  ),
                ],
                if (sync != null && sync.unconfirmedDeltaSat.toInt() != 0)
                  Text(
                    '${_maskAmount(signedSatToBtcString(sync.unconfirmedDeltaSat.toInt()))} BTC ${t('mempool_suffix')}',
                    style: TextStyle(
                      fontFamily: kMonoFont,
                      fontSize: 11,
                      color: VColors.warning,
                    ),
                  ),
              ],
            ),
            // Тап по BTC → сразу центр управления (решение владельца:
            // никакой промежуточной страницы деталей).
            onTap: wallet == null ? null : () => _push(BtcScreen(info: wallet)),
          ),
        ),
        AnimatedBuilder(
          animation: LtcConnectState.instance,
          builder: (context, _) {
            final ltcBusy = LtcConnectState.instance.busy;
            return Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                leading: _AssetAvatar(ltc),
                title: const Text('Litecoin'),
                subtitle: ltcBusy
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            t('ltc_connecting_badge'),
                            style: TextStyle(
                              fontFamily: kMonoFont,
                              fontSize: 11.5,
                              color: VColors.warning,
                            ),
                          ),
                        ],
                      )
                    : VAnimatedText(
                        '${_maskAmount(satToBtcString(ltcBalanceLit))} LTC',
                        style: const TextStyle(
                          fontFamily: kMonoFont,
                          fontSize: 11.5,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                trailing: ltcBusy
                    ? const SizedBox(width: 46)
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (ltcRate != null) ...[
                            VAnimatedText(
                              _maskAmount(
                                formatFiat(ltcBalanceLit / 1e8 * ltcRate),
                              ),
                              style: const TextStyle(
                                fontFamily: kMonoFont,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                fontFeatures: [FontFeature.tabularFigures()],
                                color: VColors.textPrimary,
                              ),
                            ),
                            Text(
                              DisplayPrefs.fiatCurrency.toUpperCase(),
                              style: const TextStyle(
                                fontFamily: kMonoFont,
                                fontSize: 11,
                                color: VColors.textSecondary,
                              ),
                            ),
                          ],
                          if (ltcSync != null &&
                              ltcSync.unconfirmedDeltaSat.toInt() != 0)
                            Text(
                              '${_maskAmount(signedSatToBtcString(ltcSync.unconfirmedDeltaSat.toInt()))} LTC ${t('mempool_suffix')}',
                              style: TextStyle(
                                fontFamily: kMonoFont,
                                fontSize: 11,
                                color: VColors.warning,
                              ),
                            ),
                        ],
                      ),
                // Тап по LTC → сразу центр управления (тот же принцип).
                onTap: wallet == null
                    ? null
                    : () => _push(LtcScreen(info: wallet)),
              ),
            );
          },
        ),
        AnimatedBuilder(
          animation: BchConnectState.instance,
          builder: (context, _) {
            final bchBusy = BchConnectState.instance.busy;
            final bchSync = wallet == null
                ? null
                : BchStateCache.instance.take(walletId: wallet.id);
            final bchBalance = bchSync == null
                ? 0
                : (bchSync.unconfirmedDeltaSat.toInt() < 0
                      ? bchSync.confirmedSat.toInt() +
                            bchSync.unconfirmedDeltaSat.toInt()
                      : bchSync.confirmedSat.toInt());
            final bchRate = _bchRate;
            return Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                leading: _AssetAvatar(bch),
                title: const Text('Bitcoin Cash'),
                subtitle: bchBusy
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            t('bch_connecting_badge'),
                            style: TextStyle(
                              fontFamily: kMonoFont,
                              fontSize: 11.5,
                              color: VColors.warning,
                            ),
                          ),
                        ],
                      )
                    : VAnimatedText(
                        '${_maskAmount(satToBtcString(bchBalance))} BCH',
                        style: const TextStyle(
                          fontFamily: kMonoFont,
                          fontSize: 11.5,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                trailing: bchBusy
                    ? const SizedBox(width: 46)
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (bchRate != null) ...[
                            VAnimatedText(
                              _maskAmount(
                                formatFiat(bchBalance / 1e8 * bchRate),
                              ),
                              style: const TextStyle(
                                fontFamily: kMonoFont,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                fontFeatures: [FontFeature.tabularFigures()],
                                color: VColors.textPrimary,
                              ),
                            ),
                            Text(
                              DisplayPrefs.fiatCurrency.toUpperCase(),
                              style: const TextStyle(
                                fontFamily: kMonoFont,
                                fontSize: 11,
                                color: VColors.textSecondary,
                              ),
                            ),
                          ],
                          if (bchSync != null &&
                              bchSync.unconfirmedDeltaSat.toInt() != 0)
                            Text(
                              '${_maskAmount(signedSatToBtcString(bchSync.unconfirmedDeltaSat.toInt()))} BCH ${t('mempool_suffix')}',
                              style: TextStyle(
                                fontFamily: kMonoFont,
                                fontSize: 11,
                                color: VColors.warning,
                              ),
                            ),
                        ],
                      ),
                onTap: wallet == null
                    ? null
                    : () => _push(BchScreen(info: wallet)),
              ),
            );
          },
        ),
        AnimatedBuilder(
          animation: XecConnectState.instance,
          builder: (context, _) {
            final xecBusy = XecConnectState.instance.busy;
            final xecSync = wallet == null
                ? null
                : XecStateCache.instance.take(walletId: wallet.id);
            final xecBalance = xecSync == null
                ? 0
                : (xecSync.unconfirmedDeltaSat.toInt() < 0
                      ? xecSync.confirmedSat.toInt() +
                            xecSync.unconfirmedDeltaSat.toInt()
                      : xecSync.confirmedSat.toInt());
            final xecRate = _xecRate;
            return Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                leading: _AssetAvatar(xec),
                title: const Text('eCash'),
                subtitle: xecBusy
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            t('xec_connecting_badge'),
                            style: TextStyle(
                              fontFamily: kMonoFont,
                              fontSize: 11.5,
                              color: VColors.warning,
                            ),
                          ),
                        ],
                      )
                    : VAnimatedText(
                        '${_maskAmount(satToXecString(xecBalance))} XEC',
                        style: const TextStyle(
                          fontFamily: kMonoFont,
                          fontSize: 11.5,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                trailing: xecBusy
                    ? const SizedBox(width: 46)
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (xecRate != null) ...[
                            VAnimatedText(
                              _maskAmount(
                                formatFiat(xecBalance / 100 * xecRate),
                              ),
                              style: const TextStyle(
                                fontFamily: kMonoFont,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                fontFeatures: [FontFeature.tabularFigures()],
                                color: VColors.textPrimary,
                              ),
                            ),
                            Text(
                              DisplayPrefs.fiatCurrency.toUpperCase(),
                              style: const TextStyle(
                                fontFamily: kMonoFont,
                                fontSize: 11,
                                color: VColors.textSecondary,
                              ),
                            ),
                          ],
                          if (xecSync != null &&
                              xecSync.unconfirmedDeltaSat.toInt() != 0)
                            Text(
                              '${_maskAmount(signedSatToXecString(xecSync.unconfirmedDeltaSat.toInt()))} XEC ${t('mempool_suffix')}',
                              style: TextStyle(
                                fontFamily: kMonoFont,
                                fontSize: 11,
                                color: VColors.warning,
                              ),
                            ),
                        ],
                      ),
                onTap: wallet == null
                    ? null
                    : () => _push(XecScreen(info: wallet)),
              ),
            );
          },
        ),
        // RVN: карточка появляется автоматом при честном переводе
        // статуса реестра (после живого тест-цикла — правило паспорта).
        AnimatedBuilder(
          animation: RvnConnectState.instance,
          builder: (context, _) {
            if (!rvn.implemented) return const SizedBox.shrink();
            final rvnBusy = RvnConnectState.instance.busy;
            final rvnSync = wallet == null
                ? null
                : RvnStateCache.instance.take(walletId: wallet.id);
            final rvnBalance = rvnSync == null
                ? 0
                : (rvnSync.unconfirmedDeltaSat.toInt() < 0
                      ? rvnSync.confirmedSat.toInt() +
                            rvnSync.unconfirmedDeltaSat.toInt()
                      : rvnSync.confirmedSat.toInt());
            final rvnRate = _rvnRate;
            return Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                leading: _AssetAvatar(rvn),
                title: const Text('Ravencoin'),
                subtitle: rvnBusy
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            t('rvn_connecting_badge'),
                            style: TextStyle(
                              fontFamily: kMonoFont,
                              fontSize: 11.5,
                              color: VColors.warning,
                            ),
                          ),
                        ],
                      )
                    : VAnimatedText(
                        '${_maskAmount(satToBtcString(rvnBalance))} RVN',
                        style: const TextStyle(
                          fontFamily: kMonoFont,
                          fontSize: 11.5,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                trailing: rvnBusy
                    ? const SizedBox(width: 46)
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (rvnRate != null) ...[
                            VAnimatedText(
                              _maskAmount(
                                formatFiat(rvnBalance / 1e8 * rvnRate),
                              ),
                              style: const TextStyle(
                                fontFamily: kMonoFont,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                fontFeatures: [FontFeature.tabularFigures()],
                                color: VColors.textPrimary,
                              ),
                            ),
                            Text(
                              DisplayPrefs.fiatCurrency.toUpperCase(),
                              style: const TextStyle(
                                fontFamily: kMonoFont,
                                fontSize: 11,
                                color: VColors.textSecondary,
                              ),
                            ),
                          ],
                          if (rvnSync != null &&
                              rvnSync.unconfirmedDeltaSat.toInt() != 0)
                            Text(
                              '${_maskAmount(signedSatToBtcString(rvnSync.unconfirmedDeltaSat.toInt()))} RVN ${t('mempool_suffix')}',
                              style: TextStyle(
                                fontFamily: kMonoFont,
                                fontSize: 11,
                                color: VColors.warning,
                              ),
                            ),
                        ],
                      ),
                onTap: wallet == null
                    ? null
                    : () => _push(RvnScreen(info: wallet)),
              ),
            );
          },
        ),
        // ETC: карточка появляется автоматом при честном переводе
        // статуса реестра (после живого тест-цикла — правило паспорта).
        AnimatedBuilder(
          animation: EtcConnectState.instance,
          builder: (context, _) {
            if (!etc.implemented) return const SizedBox.shrink();
            final etcBusy = EtcConnectState.instance.busy;
            final etcSync = wallet == null
                ? null
                : EtcStateCache.instance.take(walletId: wallet.id);
            // Честная wei-арифметика только в BigInt (int64 не хватает
            // даже на 10 ETC): показываем confirmed с поправкой на
            // отрицательную мем-дельту — как у сат-карточек.
            BigInt etcShownWei = BigInt.zero;
            if (etcSync != null) {
              final confirmed = BigInt.tryParse(etcSync.confirmedWei);
              if (confirmed != null) {
                final delta =
                    BigInt.tryParse(etcSync.pendingDeltaWei) ?? BigInt.zero;
                final adjusted =
                    delta < BigInt.zero ? confirmed + delta : confirmed;
                if (adjusted > BigInt.zero) etcShownWei = adjusted;
              }
            }
            final etcRate = _etcRate;
            return Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                leading: _AssetAvatar(etc),
                title: const Text('Ethereum Classic'),
                subtitle: etcBusy
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            t('etc_connecting_badge'),
                            style: TextStyle(
                              fontFamily: kMonoFont,
                              fontSize: 11.5,
                              color: VColors.warning,
                            ),
                          ),
                        ],
                      )
                    : VAnimatedText(
                        '${_maskAmount(weiToEtcString(etcShownWei.toString()))} ETC',
                        style: const TextStyle(
                          fontFamily: kMonoFont,
                          fontSize: 11.5,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                trailing: etcBusy
                    ? const SizedBox(width: 46)
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (etcRate != null) ...[
                            VAnimatedText(
                              _maskAmount(
                                formatFiat(
                                  etcShownWei.toDouble() / 1e18 * etcRate,
                                ),
                              ),
                              style: const TextStyle(
                                fontFamily: kMonoFont,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                fontFeatures: [FontFeature.tabularFigures()],
                                color: VColors.textPrimary,
                              ),
                            ),
                            Text(
                              DisplayPrefs.fiatCurrency.toUpperCase(),
                              style: const TextStyle(
                                fontFamily: kMonoFont,
                                fontSize: 11,
                                color: VColors.textSecondary,
                              ),
                            ),
                          ],
                          if (etcSync != null &&
                              BigInt.tryParse(etcSync.pendingDeltaWei) !=
                                  BigInt.zero)
                            Text(
                              '${_maskAmount(weiToEtcString(etcSync.pendingDeltaWei))} ETC ${t('mempool_suffix')}',
                              style: TextStyle(
                                fontFamily: kMonoFont,
                                fontSize: 11,
                                color: VColors.warning,
                              ),
                            ),
                        ],
                      ),
                onTap: wallet == null
                    ? null
                    : () => _push(EtcScreen(info: wallet)),
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: VButton.secondary(
            t('all_assets'),
            icon: Icons.grid_view_outlined,
            onPressed: () {
              pushVeyro<void>(context, AssetCatalogScreen());
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRecentCard(BuildContext context) {
    // Мультикоин-карточка транзакций всех реализованных монет (решение
    // владельца 17.11.2026); RVN вне карточки — честная заморозка P2P.

    void dirInto(
      List<Widget> out, {
      required String direction,
      required String amountText,
      required String subtitle,
      VoidCallback? onTap,
    }) {
      out.add(
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          // Кружок-иконка как в референсе: зелёный приход, красный уход,
          // нейтральный internal.
          leading: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: switch (direction) {
                'incoming' => VColors.success.withValues(alpha: 0.14),
                'outgoing' => VColors.error.withValues(alpha: 0.14),
                _ => VColors.elevated,
              },
            ),
            child: Icon(
              switch (direction) {
                'incoming' => Icons.south_west,
                'outgoing' => Icons.north_east,
                'internal' => Icons.swap_horiz,
                _ => Icons.help_outline,
              },
              size: 16,
              color: switch (direction) {
                'incoming' => VColors.success,
                'outgoing' => VColors.error,
                _ => VColors.textSecondary,
              },
            ),
          ),
          title: Text(
            switch (direction) {
              'incoming' => t('dir_incoming'),
              'outgoing' => t('dir_outgoing'),
              'internal' => t('tx_internal_short'),
              _ => direction,
            },
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall!
                .copyWith(fontFamily: kMonoFont, fontSize: 11),
          ),
          trailing: Text(
            amountText,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: switch (direction) {
                'incoming' => VColors.success,
                'outgoing' => VColors.error,
                _ => VColors.textPrimary,
              },
            ),
          ),
          onTap: onTap,
        ),
      );
    }

    Widget loaderLine() => const Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Center(
            child: LogoLoader(mode: LogoLoaderMode.loading, size: 32),
          ),
        );

    Widget noteLine(String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Center(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        );

    // Единая лента, БЕЗ секционных заголовков (решение владельца
    // 17.11.2026: «просто все транзакции по мере их поступления и всё»):
    // каждая строка несёт тикер в сумме; порядок — самые свежие сверху
    // (ETC по времени провайдера, сат-строки по высоте внутри своей
    // цепи; межмонетный порядок, где времени нет, не утверждается).
    // Пусто у всех → одна честная строка на всю карточку.
    final List<Widget> rows = [];

    bool anyLoading = false;
    bool anyErrorIdle = false;

    if (_session != null) {
      final btcBusy = BtcConnectState.instance.busy;
      final recent = _recent;
      if (_recent == null && (btcBusy || _historyError == null)) {
        anyLoading = true;
      } else if (recent == null) {
        // Ошибка в покое: честная подпись (диагностика в центре BTC).
        anyErrorIdle = true;
      } else {
        for (final item in recent) {
          dirInto(
            rows,
            direction: item.direction,
            amountText: switch (item.direction) {
              'incoming' =>
                '+${satToBtcString(item.receivedSat.toInt())} BTC',
              'outgoing' =>
                '-${satToBtcString(item.sentNetSat.toInt())} BTC',
              'internal' => '0 BTC',
              _ => '—',
            },
            subtitle: item.height >= 1
                ? tf('height_n', {'height': '${item.height}'})
                : t('in_mempool'),
            onTap: () => _push(
              TxDetailsScreen(
                item: item,
                networkCode: _session?.networkCode,
              ),
            ),
          );
        }
      }
    }

    void satCoinRows({
      required String ticker,
      required bool live,
      required bool busy,
      required String? err,
      required List<({String direction, int received, int sentNet, int height})>?
          items,
    }) {
      if (!live) return;
      if (busy) {
        anyLoading = true;
        return;
      }
      if (err != null) {
        anyErrorIdle = true;
        return;
      }
      if (items == null) {
        anyLoading = true;
        return;
      }
      final format = ticker == 'XEC' ? satToXecString : satToBtcString;
      for (final item in items) {
        final sign = switch (item.direction) {
          'incoming' => '+',
          'outgoing' => '-',
          _ => '',
        };
        final value = switch (item.direction) {
          'incoming' => item.received,
          'outgoing' => item.sentNet,
          _ => 0,
        };
        dirInto(
          rows,
          direction: item.direction,
          amountText: '$sign${format(value)} $ticker',
          subtitle: item.height >= 1
              ? tf('height_n', {'height': '${item.height}'})
              : t('in_mempool'),
        );
      }
    }

    satCoinRows(
      ticker: 'LTC',
      live: _ltcLive,
      busy: LtcConnectState.instance.busy,
      err: _recentLtcErr,
      items: _recentLtc
          ?.map((i) => (
                direction: i.direction,
                received: i.receivedSat.toInt(),
                sentNet: i.sentNetSat.toInt(),
                height: i.height.toInt(),
              ))
          .toList(),
    );
    satCoinRows(
      ticker: 'BCH',
      live: _bchLive,
      busy: BchConnectState.instance.busy,
      err: _recentBchErr,
      items: _recentBch
          ?.map((i) => (
                direction: i.direction,
                received: i.receivedSat.toInt(),
                sentNet: i.sentNetSat.toInt(),
                height: i.height.toInt(),
              ))
          .toList(),
    );
    satCoinRows(
      ticker: 'XEC',
      live: _xecLive,
      busy: XecConnectState.instance.busy,
      err: _recentXecErr,
      items: _recentXec
          ?.map((i) => (
                direction: i.direction,
                received: i.receivedSat.toInt(),
                sentNet: i.sentNetSat.toInt(),
                height: i.height.toInt(),
              ))
          .toList(),
    );

    if (_etcLive) {
      final etcBusy = EtcConnectState.instance.busy;
      final etcSync =
          _selected == null ? null : EtcStateCache.instance.take(walletId: _selected!.id);
      final account = _etcAccount ?? etcSync?.accountAddress;
      if (etcBusy) {
        anyLoading = true;
      } else if (_recentEtcErr != null) {
        anyErrorIdle = true;
      } else if (_recentEtc == null) {
        anyLoading = true;
      } else {
        for (final item in _recentEtc!) {
          final incoming =
              account != null && item.from.toLowerCase() == account.toLowerCase();
          final sign = incoming ? '+' : '-';
          final abs = weiToEtcString(item.valueWei);
          final absBody = abs.startsWith('-') ? abs.substring(1) : abs;
          dirInto(
            rows,
            direction: incoming ? 'incoming' : 'outgoing',
            amountText: '$sign$absBody ETC',
            subtitle: item.block == null
                ? t('in_mempool')
                : tf('etc_block_row', {'value': '${item.block}'}),
          );
        }
      }
    }

    if (rows.isEmpty &&
        _session == null &&
        !_ltcLive &&
        !_bchLive &&
        !_xecLive &&
        !_etcLive) {
      return const SizedBox.shrink();
    }
    final List<Widget> children = [...rows];
    if (rows.isEmpty) {
      if (anyLoading) {
        children.add(loaderLine());
      } else if (anyErrorIdle) {
        children.add(noteLine(t('recent_unavailable')));
      } else {
        children.add(noteLine(t('no_transactions')));
      }
    } else if (anyLoading) {
      children.add(loaderLine());
    }
    return VCard(
      icon: Icons.receipt_long_outlined,
      title: t('recent_transactions'),
      children: [
        ...children,
        const SizedBox(height: 4),
        VButton.secondary(
          t('full_history'),
          icon: Icons.history,
          onPressed: () => _push(const HistoryScreen(), reload: true),
        ),
      ],
    );
  }

  Future<void> _push(Widget screen, {bool reload = false}) async {
    debugPrint('veyro-flow: overview pushing ${screen.runtimeType}');
    await pushVeyro<void>(context, screen);
    debugPrint('veyro-flow: overview push returned');
    if (mounted && reload) await _refresh();
  }
}

/// Фолбэк-логотип актива: монограмма на утверждённых цветах (спека:
/// «Logo or approved fallback» — логотипов сетей в проекте нет, честный
/// фолбэк разрешён).
class _AssetAvatar extends StatelessWidget {
  final VeyroAsset asset;

  const _AssetAvatar(this.asset);

  @override
  Widget build(BuildContext context) {
    return CoinIcon(asset: asset, key: ValueKey(asset.ticker));
  }
}
