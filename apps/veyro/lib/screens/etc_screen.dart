//! ETC (Ethereum Classic) — центр управления. EVM-профиль по паспорту
//! docs/coins/ETC.md: один адрес аккаунта (m/44'/61'/account'/0/0), nonce
//! вместо change-индексов, legacy-газ (EIP-1559 НЕ активирован), публичный
//! RPC через https (TLS-only политика), история — BlockScout v2 (третья
//! сторона, честная подпись).
//!
//! Дисциплина та же, что у RVN-центра: «открыл — сразу баланс» (последний
//! синк честно сохраняется на диск как не-секрет), фоновая авто-разблокировка
//! по кэшу пароля, мелкие индикаторы вместо лоудер-карт, «не синхронизировано»
//! вместо выдуманных нулей. Формы отправки — свои (семантика EVM: wei/газ;
//! натягивать её на общую сат/vB-форму — выдумывание, которого нет).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:veyro/design/app_colors.dart';
import 'package:veyro/design/components.dart';
import 'package:veyro/design/motion.dart';
import 'package:veyro/design/veyro_mark.dart';
import 'package:veyro/src/rust/api/etc.dart';
import 'package:veyro/src/rust/api/session.dart';
import 'package:veyro/src/rust/api/storage.dart';
import 'package:veyro/src/rust/api/wallet.dart';
import 'package:veyro/util/app_dirs.dart';
import 'package:veyro/util/coin.dart';
import 'package:veyro/util/display_prefs.dart';
import 'package:veyro/util/etc_state_cache.dart';
import 'package:veyro/util/format.dart';
import 'package:veyro/util/l10n.dart';
import 'package:veyro/util/links.dart';
import 'package:veyro/util/network.dart';
import 'package:veyro/util/ui_helpers.dart';

import 'receive_screen.dart';

const _persistKeyPrefix = 'etc_last_sync';

class EtcScreen extends StatefulWidget {
  final WalletInfoDto info;

  const EtcScreen({super.key, required this.info});

  @override
  State<EtcScreen> createState() => _EtcScreenState();
}

class _EtcScreenState extends State<EtcScreen> {
  EtcSessionStateDto? _state;
  EtcSyncDto? _sync;
  bool _busy = false;
  String? _error;

  /// Что сейчас происходит.
  String _busyLabel = t('etc_connecting');

  DateTime? _lastSeriesFailedAt;
  int _failureStreak = 0;
  var _autoPrompted = false;

  Map<String, dynamic>? _persisted;

  // Форма отправки (честный EVM: адрес/сумма/газ от оценки сервера).
  final _recipient = TextEditingController();
  final _amount = TextEditingController();
  EtcFeesDto? _fees;
  bool _loadingFees = false;
  bool _sending = false;
  String? _formError;

  @override
  void initState() {
    super.initState();
    _loadPersisted();
    _entry();
  }

  @override
  void dispose() {
    _recipient.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _loadPersisted() async {
    try {
      final raw = await dbGetSetting(
        key: '$_persistKeyPrefix:${widget.info.id}',
      );
      if (!mounted) return;
      setState(() {
        _persisted =
            raw == null ? null : (jsonDecode(raw) as Map<String, dynamic>);
      });
    } catch (_) {
      // Честно: прошлых данных нет — экран покажет «не синхронизировано».
    }
  }

  Future<void> _savePersisted(EtcSyncDto sync) async {
    final payload = jsonEncode({
      'confirmedWei': sync.confirmedWei,
      'pendingDeltaWei': sync.pendingDeltaWei,
      'nonce': sync.nonce,
      'tip': sync.tipHeight,
      'server': sync.serverUrl,
      'address': sync.accountAddress,
      'at': DateTime.now().millisecondsSinceEpoch,
    });
    try {
      await dbSetSetting(
        key: '$_persistKeyPrefix:${widget.info.id}',
        value: payload,
      );
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _persisted = jsonDecode(payload) as Map<String, dynamic>;
    });
  }

  Future<void> _entry() async {
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
      final state = await etcSessionState();
      if (!mounted) return;
      setState(() {
        _state = state;
        _busy = false;
      });
      if (state != null) {
        final cached = EtcStateCache.instance.take(walletId: widget.info.id);
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
        _busyLabel = t('etc_connecting_badge');
      });
      EtcConnectState.instance.setBusy(true);
    }
    String password;
    if (autoWithCache) {
      password = '';
    } else {
      password = await promptPassword(
            context,
            title: tf('etc_unlock_title', {'name': widget.info.name}),
            confirmLabel: t('connecting_title'),
          ) ??
          '';
      if (password.isEmpty || !mounted) return;
      setState(() {
        _busy = true;
        _busyLabel = t('etc_connecting');
        _error = null;
      });
      EtcConnectState.instance.setBusy(true);
    }
    try {
      if (_lastSeriesFailedAt != null) {
        final waitSec = (15 * (1 << (_failureStreak - 1))).clamp(15, 240);
        final deadline = _lastSeriesFailedAt!.add(Duration(seconds: waitSec));
        var remain = deadline.difference(DateTime.now()).inSeconds;
        while (remain > 0 && mounted) {
          setState(() {
            _busyLabel = tf('etc_backoff_wait', {'sec': '$remain'});
          });
          await Future.delayed(const Duration(seconds: 1));
          if (!mounted) return;
          remain = deadline.difference(DateTime.now()).inSeconds;
        }
      }
      try {
        await _unlockViaCandidates(password);
        _failureStreak = 0;
        _lastSeriesFailedAt = null;
      } catch (e) {
        final isTransient = isTransientNetworkError(e);
        if (autoWithCache && !isTransient) {
          if (!mounted) return;
          final manual = await promptPassword(
            context,
            title: tf('etc_unlock_title', {'name': widget.info.name}),
            confirmLabel: t('connecting_title'),
          );
          if (manual == null || manual.isEmpty || !mounted) {
            if (mounted) {
              EtcConnectState.instance.setBusy(false);
              setState(() {
                _error = _cleanError(e);
                _busy = false;
              });
            }
            return;
          }
          await _unlockViaCandidates(manual);
          _failureStreak = 0;
          _lastSeriesFailedAt = null;
        } else {
          rethrow;
        }
      }
      if (!mounted) return;
      await _doSync();
      await _loadFees();
    } catch (e) {
      if (!mounted) return;
      // Backoff — только для сетевых неудач; опечатка в пароле не копит его.
      final wrongPassword = e.toString().contains('decryption failed');
      if (!wrongPassword) {
        _failureStreak += 1;
        _lastSeriesFailedAt = DateTime.now();
      }
      EtcConnectState.instance.setBusy(false);
      setState(() {
        _error = _cleanError(e);
        _busy = false;
      });
    }
  }

  /// Ссылки rustls в ошибках — шум; честен текст без них.
  String _cleanError(Object e) {
    final raw = e.toString();
    final base = raw.contains('decryption failed')
        ? '$raw\n\n${tf('password_mismatch_hint', {'name': widget.info.name})}'
        : raw;
    return base.replaceAll(RegExp(r'https?://\S+'), '');
  }

  String _oneLine(String text) {
    var x = text.replaceAll('\n', ' ').replaceAll('  ', ' ').trim();
    if (x.length > 140) x = '${x.substring(0, 137)}…';
    return x;
  }

  Future<void> _unlockViaCandidates(String password) async {
    final stored = List<String>.from(await etcServers());
    String? lastGood;
    try {
      lastGood = await dbGetSetting(key: 'etc_last_good_server');
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
          _busyLabel = tf('etc_candidate_progress', {
            'n': '${i + 1}',
            'm': '${candidates.length}',
            'host': host,
          });
        });
      }
      try {
        await etcUnlock(
          walletsDir: walletsDir(),
          walletId: widget.info.id,
          password: password,
          rpcUrl: server,
        ).timeout(const Duration(seconds: 45));
        try {
          await dbSetSetting(key: 'etc_last_good_server', value: server);
        } catch (_) {}
        unlocked = true;
        break;
      } on TimeoutException {
        failures.add('$host: таймаут 45 c');
        await Future.delayed(const Duration(milliseconds: 800));
      } catch (e) {
        failures.add('$host: ${_oneLine(_cleanError(e))}');
        if (!isTransientNetworkError(e)) break;
        await Future.delayed(const Duration(milliseconds: 1200));
      }
    }
    if (!unlocked) {
      final summary = failures.join('\n');
      throw (summary.isEmpty
          ? StateError('no public etc rpc candidate')
          : StateError(summary));
    }
  }

  Future<void> _doSync() async {
    if (mounted) {
      setState(() {
        _busy = true;
        _busyLabel = t('etc_syncing');
      });
    }
    try {
      final sync = await etcSync();
      if (!mounted) return;
      EtcStateCache.instance.store(sync, walletId: widget.info.id);
      EtcConnectState.instance.setBusy(false);
      await _savePersisted(sync);
      setState(() {
        _sync = sync;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      EtcConnectState.instance.setBusy(false);
      setState(() {
        _error = _cleanError(e);
        _busy = false;
      });
    }
  }

  Future<void> _loadFees() async {
    if (_state == null) return;
    setState(() => _loadingFees = true);
    try {
      final fees = await etcFees().timeout(const Duration(seconds: 30));
      if (!mounted) return;
      setState(() {
        _fees = fees;
        _loadingFees = false;
      });
    } catch (_) {
      if (!mounted) return;
      // Честный отказ оценки: UI покажет fallback-строку из ядра next time;
      // здесь просто нет пресета.
      setState(() {
        _fees = null;
        _loadingFees = false;
      });
    }
  }

  /// Wei-дельта как строка для карты баланса — считается на ходу.

  /// Данные карты баланса: сессия → кэш запуска → персистент → null.
  ({
    String confirmedWei,
    String deltaWei,
    int nonce,
    int tip,
    String server,
    DateTime? at,
  })?
  _balanceView() {
    final sync = _sync;
    if (sync != null) {
      return (
        confirmedWei: sync.confirmedWei,
        deltaWei: sync.pendingDeltaWei,
        nonce: sync.nonce.toInt(),
        tip: sync.tipHeight.toInt(),
        server: sync.serverUrl,
        at: null,
      );
    }
    final cached = EtcStateCache.instance.take(walletId: widget.info.id);
    if (cached != null) {
      return (
        confirmedWei: cached.confirmedWei,
        deltaWei: cached.pendingDeltaWei,
        nonce: cached.nonce.toInt(),
        tip: cached.tipHeight.toInt(),
        server: cached.serverUrl,
        at: null,
      );
    }
    final p = _persisted;
    if (p != null) {
      return (
        confirmedWei: (p['confirmedWei'] as String?) ?? '0',
        deltaWei: (p['pendingDeltaWei'] as String?) ?? '0',
        nonce: (p['nonce'] as num?)?.toInt() ?? 0,
        tip: (p['tip'] as num?)?.toInt() ?? 0,
        server: (p['server'] as String?) ?? '—',
        at: (p['at'] as num?) == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch((p['at'] as num).toInt()),
      );
    }
    return null;
  }

  /// Wei, реально доступный к отправке (confirmed с поправкой на дельту).
  BigInt? _availableWei() {
    final v = _balanceView();
    if (v == null) return null;
    final confirmed = BigInt.tryParse(v.confirmedWei);
    if (confirmed == null) return null;
    final delta = BigInt.tryParse(v.deltaWei) ?? BigInt.zero;
    final available = delta < BigInt.zero ? confirmed + delta : confirmed;
    return available <= BigInt.zero ? null : available;
  }

  BigInt? _feeWei() {
    final fees = _fees;
    if (fees == null) return null;
    final price = BigInt.tryParse(fees.gasPriceWei);
    if (price == null) return null;
    return price * fees.gasLimit;
  }

  Future<void> _loadHistory() async {
    if (_state == null) return;
    try {
      final history = await etcHistory().timeout(const Duration(seconds: 30));
      if (!mounted) return;
      setState(() {
        _history = history;
        _historyError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _history = null;
        _historyError = _oneLine(_cleanError(e));
      });
    }
  }

  EtcHistoryDto? _history;
  String? _historyError;

  Future<void> _submitSend() async {
    final recipient = _recipient.text.trim();
    final parsedWei = parseEtcToWei(_amount.text);
    final feeWei = _feeWei();
    String? error;
    if (recipient.isEmpty) {
      error = t('err_recipient');
    } else if (!recipient.startsWith('0x') || recipient.length != 42) {
      error = t('etc_err_address');
    } else if (parsedWei == null) {
      error = t('err_amount');
    } else if (parsedWei == '0') {
      error = t('err_amount_positive');
    } else if (feeWei == null) {
      error = t('err_fee_rate');
    } else {
      final available = _availableWei();
      if (available != null) {
        final want = BigInt.parse(parsedWei);
        if (want + feeWei > available) {
          error = t('etc_err_insufficient');
        }
      }
    }
    setState(() {
      _formError = error;
    });
    if (error != null) return;
    final amountWei = parsedWei;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('etc_send_confirm_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            kvRow(
              t('etc_recipient_field'),
              recipient,
              mono: true,
              long: true,
            ),
            kvRow(t('etc_amount_field'), '${_amount.text.trim()} ETC'),
            if (feeWei != null)
              kvRow(
                t('fee_row_label'),
                '${weiToEtcString(feeWei.toString())} ETC',
              ),
            const SizedBox(height: 6),
            Text(
              t('etc_irreversible_note'),
              style: const TextStyle(color: VColors.warning),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t('cancel_btn')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t('etc_send_btn_confirm')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _sending = true;
      _formError = null;
    });
    try {
      final result = await etcSend(
        recipient: recipient,
        amountWei: amountWei!,
      ).timeout(const Duration(seconds: 60));
      if (!mounted) return;
      setState(() {
        _sending = false;
      });
      if (mounted) {
        _recipient.clear();
        _amount.clear();
      }
      await _showResult(result);
      if (!mounted) return;
      await _doSync();
      await _loadFees();
      await _loadHistory();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _formError = _cleanError(e);
      });
    }
  }

  Future<void> _showResult(EtcSendResultDto result) async {
    if (!mounted) return;
    // Честный мгновенный срез: если блок уже есть — показываем его высоту.
    String statusText = t('etc_result_broadcast');
    if (result.status == 'mempool') {
      statusText = result.alreadyKnown
          ? t('etc_result_mempool')
          : t('etc_result_broadcast');
    }
    try {
      final st = await etcTxStatus(txhash: result.txhash)
          .timeout(const Duration(seconds: 20));
      if (st.state == 'confirmed') {
        statusText = tf('etc_result_confirmed', {
          'block': st.block?.toString() ?? '—',
        });
      } else if (st.state == 'failed') {
        statusText = t('etc_result_failed');
      } else if (st.state == 'mempool') {
        statusText = t('etc_result_broadcast');
      }
    } catch (_) {
      // honest: срез статуса недоступен — показывается broadcast-строка.
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('etc_result_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            VMonoCopyRow(label: 'TX', value: result.txhash),
            const SizedBox(height: 8),
            kvRow(t('etc_status_label'), statusText),
            kvRow(
              t('fee_row_label'),
              '${weiToEtcString(result.feeWei)} ETC'
              ' (${result.gasLimit} × ${result.gasPriceWei} wei)',
            ),
            const SizedBox(height: 6),
            Text(
              t('etc_explorer_note'),
              style: const TextStyle(
                color: VColors.textSecondary,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(t('close_btn')),
          ),
        ],
      ),
    );
  }

  String _statusLabel(EtcHistoryItemDto item) {
    final s = item.status;
    if (s == 'success') return t('etc_status_success');
    if (s == 'failed') return t('etc_status_failed');
    return t('etc_status_unknown');
  }

  @override
  Widget build(BuildContext context) {
    final unlocked = _state != null;
    final v = _balanceView();
    final deltaText = v == null ? null : weiToEtcString(v.deltaWei);
    final account = _state?.accountAddress;
    return Scaffold(
      appBar: AppBar(title: const Text('Ethereum Classic')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: RefreshIndicator(
            onRefresh: () async {
              await _refresh(autosyncIfUnlocked: true);
              await _loadFees();
              if (unlocked && _history != null) await _loadHistory();
            },
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
                        color: VColors.error.withValues(alpha: 0.4),
                      ),
                      color: VColors.error.withValues(alpha: 0.10),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                SectionCard(
                  title: t('balance_section'),
                  icon: Icons.savings_outlined,
                  children: [
                    if (v == null && _busy)
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: Center(
                          child: LogoLoader(
                            mode: LogoLoaderMode.loading,
                            size: 44,
                          ),
                        ),
                      )
                    else if (v == null)
                      Text(
                        t('not_synced_note'),
                        style: const TextStyle(color: Colors.white70),
                      )
                    else ...[
                      VAmount(
                        DisplayPrefs.maskAmount(
                          '${weiToEtcString(v.confirmedWei)} ETC',
                        ),
                        fontSize: 30,
                      ),
                      if (deltaText != null && deltaText != '0') ...[
                        const SizedBox(height: 6),
                        Text(
                          tf('mempool_row', {
                            'value':
                                '${DisplayPrefs.maskAmount(deltaText)} ETC',
                          }),
                          style: const TextStyle(color: Colors.orangeAccent),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Text(tf('etc_nonce_row', {'value': '${v.nonce}'}),
                          style: const TextStyle(fontSize: 12)),
                      kvRow(t('chain_height'), v.tip > 0 ? '${v.tip}' : '—'),
                      VMonoCopyRow(
                        label: t('server_label'),
                        value: v.server,
                      ),
                      if (v.at != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          tf('balance_asof_row', {
                            'value':
                                '${v.at!.day}.${v.at!.month}.${v.at!.year} ${v.at!.hour.toString().padLeft(2, '0')}:${v.at!.minute.toString().padLeft(2, '0')}',
                          }),
                          style: const TextStyle(
                            color: VColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                      if (_busy) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _busyLabel,
                                style: const TextStyle(
                                  color: VColors.textSecondary,
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 10),
                      if (unlocked) ...[
                        FilledButton.tonalIcon(
                          onPressed: _busy
                              ? null
                              : () async {
                                  await _doSync();
                                  await _loadFees();
                                },
                          icon: const Icon(Icons.sync),
                          label: Text(t('refresh_btn')),
                        ),
                      ] else
                        FilledButton(
                          onPressed: _busy ? null : () => _unlock(),
                          child: Text(_busy ? _busyLabel : t('unlock_etc_btn')),
                        ),
                    ],
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
                        onTap: unlocked
                            ? () async {
                                await pushVeyro<void>(
                                  context,
                                  const ReceiveScreen(coin: WalletCoin.etc),
                                );
                                if (mounted) {
                                  await _refresh(autosyncIfUnlocked: false);
                                }
                              }
                            : null,
                      ),
                    ),
                    Expanded(
                      child: CoinActionTile(
                        icon: Icons.history,
                        label: t('history_btn'),
                        enabled: unlocked,
                        onTap: unlocked ? _loadHistory : null,
                      ),
                    ),
                  ],
                ),
                // Отправка: честная EVM-форма (адрес/сумма/газ от оценки).
                if (unlocked) ...[
                  const SizedBox(height: 16),
                  SectionCard(
                    title: t('send_title_etc'),
                    icon: Icons.north_east,
                    children: [
                      TextField(
                        controller: _recipient,
                        decoration: InputDecoration(
                          labelText: t('etc_recipient_field'),
                          hintText: '0x…',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _amount,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: t('etc_amount_field'),
                          suffixIcon: IconButton(
                            tooltip: t('etc_max_btn'),
                            icon: const Icon(
                              Icons.keyboard_double_arrow_up,
                            ),
                            onPressed: () {
                              final available = _availableWei();
                              if (available == null) return;
                              var text = weiToEtcString(available.toString());
                              final fee = _feeWei();
                              if (fee != null) {
                                final net = available - fee;
                                if (net > BigInt.zero) {
                                  text = weiToEtcString(net.toString());
                                }
                              }
                              _amount.text = text;
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_loadingFees)
                        const Padding(
                          padding: EdgeInsets.all(6),
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else if (_fees != null)
                        Text(
                          _fees!.fallback
                              ? tf('etc_fee_fallback_row', {
                                  'limit': '${_fees!.gasLimit}',
                                  'price': _fees!.gasPriceWei,
                                })
                              : tf('etc_fee_estimate_row', {
                                  'limit': '${_fees!.gasLimit}',
                                  'price': _fees!.gasPriceWei,
                                }),
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: VColors.textSecondary,
                          ),
                        )
                      else
                        Text(
                          t('etc_fee_unavailable'),
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: VColors.warning,
                          ),
                        ),
                      if (_formError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _formError!,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: VColors.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      if (_sending)
                        Row(
                          children: [
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                t('etc_sending'),
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: VColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        )
                      else
                        FilledButton.icon(
                          onPressed: _submitSend,
                          icon: const Icon(Icons.north_east),
                          label: Text(t('etc_send_btn_confirm')),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        t('etc_native_note'),
                        style: const TextStyle(
                          fontSize: 11,
                          color: VColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SectionCard(
                    title: t('history_title_etc'),
                    icon: Icons.history,
                    children: [
                      Row(
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: _busy ? null : _loadHistory,
                            icon: const Icon(Icons.sync),
                            label: Text(t('refresh_btn')),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              t('etc_history_source_note'),
                              style: const TextStyle(
                                fontSize: 11,
                                color: VColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_history == null && _historyError == null)
                        Text(
                          t('etc_history_empty'),
                          style: const TextStyle(color: Colors.white70),
                        )
                      else if (_history == null)
                        Text(
                          tf('etc_history_error', {'error': _historyError!}),
                          style: const TextStyle(color: VColors.error),
                        )
                      else if (_history!.items.isEmpty)
                        Text(
                          t('etc_history_empty'),
                          style: const TextStyle(color: Colors.white70),
                        )
                      else ...[
                        for (final item in _history!.items) ...[
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              () {
                                final incoming =
                                    account == null ? false : item.from.toLowerCase() == account.toLowerCase();
                                final sign = incoming ? '+' : '-';
                                final abs = weiToEtcString(item.valueWei);
                                final absBody = abs.startsWith('-')
                                    ? abs.substring(1)
                                    : abs;
                                return '$sign${DisplayPrefs.maskAmount(absBody)} ETC';
                              }(),
                              style: const TextStyle(
                                fontFamily: kMonoFont,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              '${_oneLine(item.hash)} · ${_statusLabel(item)}'
                              ' · ${t('etc_explorer_short')} $kEtcExplorerName',
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: Text(
                              item.block == null
                                  ? '—'
                                  : tf('etc_block_row', {
                                      'value': '${item.block}',
                                    }),
                              style: const TextStyle(
                                fontFamily: kMonoFont,
                                fontSize: 11,
                                color: VColors.textSecondary,
                              ),
                            ),
                          ),
                          if (item.hash == _history!.items.last.hash &&
                              _history!.truncated)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                tf('etc_history_showing_of', {
                                  'n': '${_history!.items.length}',
                                  'total': '${_history!.totalEntries}',
                                }),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: VColors.textSecondary,
                                ),
                              ),
                            ),
                        ],
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
