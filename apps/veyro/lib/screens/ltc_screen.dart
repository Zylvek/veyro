//! LTC — центр управления в стиле «открыл — сразу баланс» (решение
//! владельца, пример Trust Wallet): последняя известная сумма сохраняется
//! на диск (не секрет), экран показывает её мгновенно; подключение и
//! синхронизация идут фоном с честными мелкими индикаторами. Крупных
//! лоудер-карт нет вовсе.
//!
//! Сессия ядра (seed) открывается в фоне авто-разблокировкой (пароль
//! кэширован per-wallet) или по кнопке. MWEB-предупреждение (паспорт
//! LTC) — обязательное, внизу мелкой строкой; MWEB-адреса ядро отказывает.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:veyro/src/rust/api/ltc.dart';
import 'package:veyro/src/rust/api/session.dart';
import 'package:veyro/src/rust/api/storage.dart';
import 'package:veyro/src/rust/api/wallet.dart';
import 'package:veyro/design/app_colors.dart';
import 'package:veyro/design/components.dart';
import 'package:veyro/util/coin.dart';
import 'package:veyro/util/app_dirs.dart';
import 'package:veyro/util/l10n.dart';
import 'package:veyro/util/format.dart';
import 'package:veyro/util/ltc_state_cache.dart';
import 'package:veyro/util/ui_helpers.dart';

import 'history_screen.dart';
import 'receive_screen.dart';
import 'send_screen.dart';

const _persistKeyPrefix = 'ltc_last_sync';
class LtcScreen extends StatefulWidget {
  final WalletInfoDto info;

  const LtcScreen({super.key, required this.info});

  @override
  State<LtcScreen> createState() => _LtcScreenState();
}

class _LtcScreenState extends State<LtcScreen> {
  LtcSessionStateDto? _state;
  LtcSyncDto? _sync;
  bool _busy = false;
  String? _error;

  /// Что сейчас происходит.
  String _busyLabel = t('btc_connecting');

  /// Дисциплина повторов: после неудачной серии пауза удваивается
  /// (15 c → … → 4 мин max), успех сброс.
  DateTime? _lastSeriesFailedAt;
  int _failureStreak = 0;

  var _autoPrompted = false;

  /// Последняя известная статистика с диска (не секрет): мгновенный первый
  /// показ, без лоудеров.
  Map<String, dynamic>? _persisted;

  @override
  void initState() {
    super.initState();
    _loadPersisted();
    _entry();
  }

  Future<void> _loadPersisted() async {
    try {
      final raw = await dbGetSetting(
          key: '$_persistKeyPrefix:${widget.info.id}');
      if (!mounted) return;
      setState(() {
        _persisted =
            raw == null ? null : (jsonDecode(raw) as Map<String, dynamic>);
      });
    } catch (_) {
      if (!mounted) return;
    }
  }

  Future<void> _savePersisted(LtcSyncDto sync) async {
    final payload = jsonEncode({
      'confirmed': sync.confirmedSat.toInt(),
      'delta': sync.unconfirmedDeltaSat.toInt(),
      'utxo': sync.utxoCount,
      'tip': sync.tipHeight,
      'server': sync.serverUrl,
      'at': DateTime.now().millisecondsSinceEpoch,
      'receive': {
        'address': sync.nextReceive.address,
        'path': sync.nextReceive.path,
        'branch': sync.nextReceive.branch,
        'index': sync.nextReceive.index,
      },
    });
    try {
      await dbSetSetting(
          key: '$_persistKeyPrefix:${widget.info.id}', value: payload);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _persisted = jsonDecode(payload) as Map<String, dynamic>;
    });
  }

  Future<void> _entry() async {
    debugPrint('veyro-flow: ltc screen entry (wallet ${widget.info.name})');
    await _refresh(autosyncIfUnlocked: true);
    await _maybeAutoPrompt();
  }

  Future<void> _maybeAutoPrompt() async {
    if (_state != null || _autoPrompted || _busy || !mounted) return;
    _autoPrompted = true;
    await _unlock(auto: true);
  }

  Future<void> _refresh({required bool autosyncIfUnlocked}) async {
    try {
      final state = await ltcSessionState();
      if (!mounted) return;
      setState(() {
        _state = state;
        _busy = false;
      });
      // Свежий кэш (этого запуска) — показать сразу; персистентные данные
      // уже на экране. Авто-синк — только если данных ещё нет.
      if (state != null) {
        final cached = LtcStateCache.instance.take();
        if (cached != null && _sync == null) {
          setState(() => _sync = cached);
          if (!autosyncIfUnlocked) return;
        }
        if (autosyncIfUnlocked && _sync == null) await _doSync();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _busy = false;
      });
    }
  }

  Future<void> _unlock({bool auto = false}) async {
    if (!mounted) return;
    // Тихая авто-разблокировка: бейдж на карточке/Обзоре, БЕЗ лоадер-карт.
    var cacheKnown = true;
    var cached = false;
    try {
      cached = await sessionPasswordCached(walletId: widget.info.id);
    } catch (_) {
      cacheKnown = false;
    }
    if (!mounted) return;
    final autoWithCache = auto && (cached || !cacheKnown);
    if (autoWithCache) {
      setState(() {
        _busy = true;
        _busyLabel = t('ltc_connecting_badge');
      });
      LtcConnectState.instance.setBusy(true);
    }
    String password;
    if (autoWithCache) {
      password = '';
    } else {
      password = await promptPassword(
            context,
            title: tf('ltc_unlock_title', {'name': widget.info.name}),
            confirmLabel: t('connect_btn'),
          ) ??
          '';
      if (password.isEmpty || !mounted) return;
      setState(() {
        _busy = true;
        _busyLabel = t('unlocking_now');
        _error = null;
      });
      LtcConnectState.instance.setBusy(true);
    }
    try {
      if (_lastSeriesFailedAt != null) {
        final waitSec = (15 * (1 << (_failureStreak - 1))).clamp(15, 240);
        final deadline = _lastSeriesFailedAt!.add(Duration(seconds: waitSec));
        var remain = deadline.difference(DateTime.now()).inSeconds;
        if (remain > 0) {
          while (remain > 0 && mounted) {
            setState(() {
              _busyLabel = tf('ltc_backoff_wait', {'sec': '$remain'});
            });
            await Future.delayed(const Duration(seconds: 1));
            if (!mounted) return;
            remain = deadline.difference(DateTime.now()).inSeconds;
          }
        }
      }
      try {
        await _unlockViaCandidates(password);
        _failureStreak = 0;
        _lastSeriesFailedAt = null;
      } catch (e) {
        final raw = e.toString();
        final isTransient = raw.contains('electrum') ||
            raw.contains('unexpected end of file') ||
            raw.contains('all errored') ||
            raw.contains('timed out') ||
            raw.contains('connection') ||
            raw.contains('EOF');
        final silentUsed = autoWithCache;
        if (silentUsed && !isTransient) {
          if (!mounted) return;
          final manual = await promptPassword(
            context,
            title: tf('ltc_unlock_title', {'name': widget.info.name}),
            confirmLabel: t('connect_btn'),
          );
          if (manual == null || manual.isEmpty || !mounted) {
            if (mounted) {
              LtcConnectState.instance.setBusy(false);
              setState(() {
                _error = _cleanError(e);
                _busy = false;
              });
            }
            return;
          }
          try {
            await _unlockViaCandidates(manual);
            _failureStreak = 0;
            _lastSeriesFailedAt = null;
          } catch (e2) {
            _failureStreak += 1;
            _lastSeriesFailedAt = DateTime.now();
            rethrow;
          }
        } else {
          rethrow;
        }
      }
      if (!mounted) return;
      await _doSync();
    } catch (e) {
      if (!mounted) return;
      _failureStreak += 1;
      _lastSeriesFailedAt = DateTime.now();
      LtcConnectState.instance.setBusy(false);
      setState(() {
        _error = _cleanError(e);
        _busy = false;
      });
    }
  }

  /// Ссылки rustls в транспортных ошибках — шум; честен текст без них.
  String _cleanError(Object e) {
    final raw = e.toString();
    final base = raw.contains('decryption failed')
        ? '$raw\n\n${tf('password_mismatch_hint', {'name': widget.info.name})}'
        : raw;
    return base.replaceAll(RegExp(r'https?://\S+'), '');
  }

  /// Одна строка на кандидата в сводной ошибке: без ссылок/переносов.
  String _oneLine(String text) {
    var t = text.replaceAll('\n', ' ').replaceAll('  ', ' ').trim();
    if (t.length > 140) t = '${t.substring(0, 137)}…';
    return t;
  }

  /// Full unlock attempt: last-good server first (persisted), transient →
  /// next, per-candidate timeout so the loop never stalls forever.
  Future<void> _unlockViaCandidates(String password) async {
    final stored = List<String>.from(await ltcServers());
    String? lastGood;
    try {
      lastGood = await dbGetSetting(key: 'ltc_last_good_server');
    } catch (_) {}
    if (lastGood != null && lastGood.isNotEmpty && stored.remove(lastGood)) {
      stored.insert(0, lastGood);
    }
    final candidates = stored;
    final failures = <String>[];
    var unlocked = false;
    for (var i = 0; i < candidates.length; i++) {
      final server = candidates[i];
      final host = Uri.tryParse(server)?.host ?? server;
      if (mounted) {
        setState(() {
          _busyLabel = tf('ltc_candidate_progress', {
            'n': '${i + 1}',
            'm': '${candidates.length}',
            'host': host,
          });
        });
      }
      try {
        debugPrint('veyro-flow: ltc unlock via $server');
        await ltcUnlock(
          walletsDir: walletsDir(),
          walletId: widget.info.id,
          password: password,
          serverUrl: server,
        ).timeout(const Duration(seconds: 60));
        try {
          await dbSetSetting(key: 'ltc_last_good_server', value: server);
        } catch (_) {}
        unlocked = true;
        break;
      } on TimeoutException {
        failures.add('$host: таймаут 60 c');
        await Future.delayed(const Duration(milliseconds: 800));
      } catch (e) {
        failures.add('$host: ${_oneLine(_cleanError(e))}');
        final raw = e.toString();
        final transient = raw.contains('electrum') ||
            raw.contains('unexpected end of file') ||
            raw.contains('all errored') ||
            raw.contains('timed out') ||
            raw.contains('connection') ||
            raw.contains('EOF');
        if (!transient) break;
        await Future.delayed(const Duration(milliseconds: 1200));
      }
    }
    if (!unlocked) {
      final summary = failures.join('\n');
      throw (summary.isEmpty
          ? StateError('no electrum-ltc candidate')
          : StateError(summary));
    }
  }

  Future<void> _doSync() async {
    if (mounted) {
      setState(() {
        _busyLabel = t('btc_syncing_addresses_long');
      });
    }
    try {
      final sync = await ltcSync(gapLimit: 20);
      if (!mounted) return;
      LtcStateCache.instance.store(sync);
      LtcConnectState.instance.setBusy(false);
      await _savePersisted(sync);
      setState(() {
        _sync = sync;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString();
      final transient = raw.contains('electrum') ||
          raw.contains('unexpected end of file') ||
          raw.contains('all errored') ||
          raw.contains('timed out') ||
          raw.contains('connection');
      if (transient && mounted) {
        try {
          await _unlockViaCandidates('');
          final sync2 = await ltcSync(gapLimit: 20);
          if (!mounted) return;
          LtcStateCache.instance.store(sync2);
          LtcConnectState.instance.setBusy(false);
          await _savePersisted(sync2);
          setState(() {
            _sync = sync2;
            _busy = false;
          });
          return;
        } catch (e2) {
          LtcConnectState.instance.setBusy(false);
          setState(() {
            _error = _cleanError(e2);
            _busy = false;
          });
          return;
        }
      }
      if (!mounted) return;
      LtcConnectState.instance.setBusy(false);
      setState(() {
        _error = _cleanError(e);
        _busy = false;
      });
    }
  }

  /// Реальный доступный баланс (send-плитке нужен набор UTXO сессии).
  int? _availableLit() {
    final sync = _sync;
    if (sync == null) return null;
    final confirmed = sync.confirmedSat.toInt();
    final delta = sync.unconfirmedDeltaSat.toInt();
    return delta < 0 ? confirmed + delta : confirmed;
  }

  /// Значения для карты баланса: сессия → кэш → персистент → нули.
  ({int confirmed, int delta, int utxo, int tip, String server, DateTime? at})
      _balanceView() {
    final sync = _sync;
    if (sync != null) {
      return (
        confirmed: sync.confirmedSat.toInt(),
        delta: sync.unconfirmedDeltaSat.toInt(),
        utxo: sync.utxoCount,
        tip: sync.tipHeight,
        server: sync.serverUrl,
        at: null,
      );
    }
    final p = _persisted;
    if (p != null) {
      return (
        confirmed: (p['confirmed'] as num?)?.toInt() ?? 0,
        delta: (p['delta'] as num?)?.toInt() ?? 0,
        utxo: (p['utxo'] as num?)?.toInt() ?? 0,
        tip: (p['tip'] as num?)?.toInt() ?? 0,
        server: (p['server'] as String?) ?? '—',
        at: (p['at'] as num?) == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch((p['at'] as num).toInt()),
      );
    }
    return (confirmed: 0, delta: 0, utxo: 0, tip: 0, server: '—', at: null);
  }

  Future<void> _openSend() async {
    final sent = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
      builder: (_) => SendScreen(
        coin: WalletCoin.ltc,
        availableSat: _availableLit(),
      ),
    ));
    if (sent == true && mounted) {
      await _refresh(autosyncIfUnlocked: false);
      await _doSync();
    }
  }

  @override
  Widget build(BuildContext context) {
    final unlocked = _state != null;
    final v = _balanceView();
    return Scaffold(
      appBar: AppBar(title: const Text('Litecoin')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: RefreshIndicator(
            onRefresh: () => _refresh(autosyncIfUnlocked: true),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: VColors.error.withValues(alpha: 0.4)),
                      color: VColors.error.withValues(alpha: 0.10),
                    ),
                    child: Text(_error!,
                        style: const TextStyle(fontSize: 12.5)),
                  ),
                  const SizedBox(height: 10),
                ],
                SectionCard(
                  title: t('balance_section'),
                  icon: Icons.savings_outlined,
                  children: [
                    Text(
                      '${satToString(v.confirmed)} LTC',
                      style: const TextStyle(
                          fontSize: 30, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '${groupDigits(v.confirmed)} ${t('ltc_unit')}',
                      style: const TextStyle(color: Colors.white60),
                    ),
                    if (v.delta != 0) ...[
                      const SizedBox(height: 6),
                      Text(
                        tf('mempool_row',
                            {'value': '${signedLitString(v.delta)} LTC'}),
                        style: const TextStyle(color: Colors.orangeAccent),
                      ),
                    ],
                    const SizedBox(height: 10),
                    kvRow(t('utxo_available'), '${v.utxo}'),
                    kvRow(t('chain_height'), v.tip > 0 ? '${v.tip}' : '—'),
                    if (v.at != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        tf('balance_asof_row', {
                          'value':
                              '${v.at!.day}.${v.at!.month}.${v.at!.year} ${v.at!.hour.toString().padLeft(2, '0')}:${v.at!.minute.toString().padLeft(2, '0')}'
                        }),
                        style: const TextStyle(
                            color: VColors.textSecondary, fontSize: 11),
                      ),
                    ],
                    if (_busy) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _busyLabel,
                              style: const TextStyle(
                                  color: VColors.textSecondary,
                                  fontSize: 11.5),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    if (unlocked) ...[
                      FilledButton.tonalIcon(
                        onPressed: _busy ? null : _doSync,
                        icon: const Icon(Icons.sync),
                        label: Text(t('refresh_btn')),
                      ),
                    ] else
                      FilledButton(
                        onPressed: _busy ? null : () => _unlock(),
                        child: Text(
                            _busy ? _busyLabel : t('unlock_ltc_btn')),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: CoinActionTile(
                        icon: Icons.qr_code_2_outlined,
                        label: t('get_btn'),
                        enabled: unlocked,
                        onTap: unlocked ? _openReceive : null,
                      ),
                    ),
                    Expanded(
                      child: CoinActionTile(
                        icon: Icons.north_east,
                        label: t('send_btn'),
                        enabled: unlocked && _availableLit() != null,
                        onTap: unlocked ? _openSend : null,
                      ),
                    ),
                    Expanded(
                      child: CoinActionTile(
                        icon: Icons.history,
                        label: t('history_btn'),
                        enabled: unlocked,
                        onTap: unlocked ? _openHistory : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  t('ltc_mweb_short'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: VColors.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openReceive() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const ReceiveScreen(coin: WalletCoin.ltc),
    ));
    if (mounted) await _refresh(autosyncIfUnlocked: false);
  }

  Future<void> _openHistory() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => HistoryScreen(walletCoin: WalletCoin.ltc),
    ));
    if (mounted) await _refresh(autosyncIfUnlocked: true);
  }
}

/// Сатоши/лит → строка (для отрицательных значений тоже: mempool строка).
String satToString(int sat) {
  if (sat < 0) {
    return '-${satToString(-sat)}';
  }
  return satToBtcString(sat);
}

String signedLitString(int signedLit) {
  if (signedLit > 0) return '+${satToString(signedLit)}';
  if (signedLit < 0) return '-${satToString(-signedLit)}';
  return '0';
}
