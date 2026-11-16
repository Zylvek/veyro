//! LTC — центр управления: вид точно как у BTC-центра (решение владельца
//! «как у битка»): разблокировка (пароль; сервер — автоподбор из живого
//! списка ядра с genesis-чеком), баланс крупно, плитки действий общим
//! CoinActionTile. Получить/Отправить/История — реальные FFI-вызовы.
//! MWEB-предупреждение (паспорт LTC) — обязательное, внизу мелкой строкой;
//! MWEB-адреса ядро отказывает (transparent-only).

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:veyro/src/rust/api/ltc.dart';
import 'package:veyro/src/rust/api/session.dart';
import 'package:veyro/src/rust/api/storage.dart';
import 'package:veyro/src/rust/api/wallet.dart';
import 'package:veyro/design/app_colors.dart';
import 'package:veyro/design/components.dart';
import 'package:veyro/design/veyro_mark.dart';
import 'package:veyro/util/app_dirs.dart';
import 'package:veyro/util/coin.dart';
import 'package:veyro/util/l10n.dart';
import 'package:veyro/util/format.dart';
import 'package:veyro/util/ltc_state_cache.dart';
import 'package:veyro/util/ui_helpers.dart';

import 'history_screen.dart';
import 'receive_screen.dart';
import 'send_screen.dart';

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

  /// Что сейчас происходит («Подключение…» без деталей выглядит как
  /// зависание — жалоба владельца).
  String _busyLabel = t('btc_connecting');
  /// Дисциплина повторов (решение владельца «не долбить серверы»):
  /// после неудачной серии пауза удваивается (15 c → … → 4 мин max),
  /// успех сброс.
  DateTime? _lastSeriesFailedAt;
  int _failureStreak = 0;

  /// Диалог пароля показывается автоматически один раз на вход; после
  /// отмены остаются ручные кнопки.
  var _autoPrompted = false;

  /// Auto-unlock is in flight (cache password lives): показываем индикатор
  /// подключения вместо «Сессия не открыта» — никакого мигания на входе.
  var _autoConnecting = false;

  @override
  void initState() {
    super.initState();
    _entry();
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
      if (state != null) {
        // Решение владельца по двойному скану: свежий кэш — показать сразу,
        // пересинк по явному действию (кнопка/pull-to-refresh).
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
    // Авто-вход (кэш пароля жив) → сразу индикатор подключения вместо
    // «Сессия не открыта» — никакого мигания на входе в монету.
    if (auto) {
      try {
        _autoConnecting =
            await sessionPasswordCached(walletId: widget.info.id);
      } catch (_) {
        _autoConnecting = false;
      }
      if (_autoConnecting && mounted) {
        setState(() {
          _busy = true;
          _busyLabel = t('ltc_connecting_badge');
        });
      }
    }
    // Единый вход (решение владельца): если пароль уже кэширован ядром
    // после первой разблокировки — монета подключается без диалога.
    String password;
    try {
      final cached = await sessionPasswordCached(walletId: widget.info.id);
      if (!mounted) return;
      if (cached) {
        password = '';
      } else {
        // Никакой тишины: кэша нет или проверка не удалась — честный
        // диалог (владелец мог запустить старую DLL рядом с новым exe,
        // тогда именно эта ветка спасает от «кнопка жмётся, а ничего»).
        password = await promptPassword(
              context,
              title: tf('ltc_unlock_title', {'name': widget.info.name}),
              confirmLabel: t('connect_btn'),
            ) ??
            '';
        if (!mounted) return;
      }
    } catch (_) {
      if (!mounted) return;
      password = await promptPassword(
            context,
            title: tf('ltc_unlock_title', {'name': widget.info.name}),
            confirmLabel: t('connect_btn'),
          ) ??
          '';
      if (!mounted) return;
    }
    if (password.isEmpty) {
      // Пустая строка допустима только при живом кэше; иначе — отмена
      // диалога: ничего не делаем.
      var cacheKnown = true;
      try {
        final cached = await sessionPasswordCached(walletId: widget.info.id);
        cacheKnown = cached;
      } catch (_) {
        // Проверка недоступна: идём разблокироваться в ядро — там честная
        // ошибка «no cached password» вместо тишины.
        cacheKnown = true;
      }
      if (!cacheKnown) {
        if (mounted) {
          setState(() {
            _autoConnecting = false;
            _busy = false;
          });
        }
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = true;
      _busyLabel = t('unlocking_now');
      _error = null;
    });
    LtcConnectState.instance.setBusy(true);
    try {
      // Экспоненциальная пауза после неудачной серии: не долбим серверы
      // (rate-limits копятся именно от частых попыток). Честная пауза с
      // лейблом — юзер видит, сколько осталось.
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
        // Успех — экспонента обнуляется.
        _failureStreak = 0;
        _lastSeriesFailedAt = null;
      } catch (e) {
        // Тихая попытка не прошла из-за НЕ ПОДХОДЯЩЕГО пароля? Один честный
        // диалог — никакого бесконечного цикла ошибок. Транспорт-неудачи
        // уже переборены кандидатами внутрь _unlockViaCandidates.
        final raw = e.toString();
        final isTransient = raw.contains('electrum') ||
            raw.contains('unexpected end of file') ||
            raw.contains('all errored') ||
            raw.contains('timed out') ||
            raw.contains('connection') ||
            raw.contains('EOF');
        final cachedUsed = password.isEmpty;
        if (cachedUsed && !isTransient) {
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
      _autoConnecting = false;
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
        // Success → remember the live server (persisted, non-secret).
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
    setState(() {
      _busyLabel = t('btc_syncing_addresses_long');
      _error = null;
    });
    try {
      final sync = await ltcSync(gapLimit: 20);
      if (!mounted) return;
      LtcStateCache.instance.store(sync);
      LtcConnectState.instance.setBusy(false);
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
      // Тихий авто-повтор один раз; при повторном сбое — пере-подключение
      // на следующий живой сервер (переключение, а не кивание в мёртвого).
      if (transient && mounted) {
        try {
          await _unlockViaCandidates('');
          final sync2 = await ltcSync(gapLimit: 20);
          if (!mounted) return;
          LtcStateCache.instance.store(sync2);
          LtcConnectState.instance.setBusy(false);
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

  /// Реальный доступный баланс на момент последней синхронизации:
  /// confirmed + отрицательный mempool-delta. Нет синхронизации — нет
  /// данных (null, кнопка Max на SendScreen честно скрыта).
  int? _availableLit() {
    final sync = _sync;
    if (sync == null) return null;
    final confirmed = sync.confirmedSat.toInt();
    final delta = sync.unconfirmedDeltaSat.toInt();
    return delta < 0 ? confirmed + delta : confirmed;
  }

  Future<void> _openSend() async {
    final sent = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
      builder: (_) => SendScreen(
        coin: WalletCoin.ltc,
        availableSat: _availableLit(),
      ),
    ));
    if (sent == true && mounted) {
      // После успешной отправки Rust очистил набор UTXO — синхронизируем.
      await _refresh(autosyncIfUnlocked: false);
      await _doSync();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    return Scaffold(
      appBar: AppBar(title: const Text('Litecoin')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: RefreshIndicator(
            onRefresh: () => _refresh(autosyncIfUnlocked: false),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  SectionCard(
                    title: t('error_title'),
                    icon: Icons.error_outline,
                    children: [
                      Text(_error!, style: const TextStyle(fontSize: 13.5)),
                      const SizedBox(height: 8),
                      FilledButton.tonal(
                        onPressed: _busy
                            ? null
                            : () => _refresh(autosyncIfUnlocked: true),
                        child: Text(t('retry')),
                      ),
                    ],
                  ),
                if (state == null && _autoConnecting)
                  SectionCard(
                    title: t('session_not_open'),
                    icon: Icons.lock_outline,
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Center(
                          child: LogoLoader(
                            mode: LogoLoaderMode.loading,
                            size: 44,
                          ),
                        ),
                      ),
                      Text(
                        _busyLabel,
                        style: const TextStyle(color: Colors.white60),
                      ),
                      Text(
                        tf('wallet_label', {'name': widget.info.name}),
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 12),
                      ),
                    ],
                  )
                else if (state == null)
                  SectionCard(
                    title: t('session_not_open'),
                    icon: Icons.lock_outline,
                    children: [
                      Text(
                        t('session_desc'),
                        style: const TextStyle(color: Colors.white60),
                      ),
                      Text(
                        t('ltc_server_autopick_note'),
                        style: const TextStyle(
                          color: VColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tf('wallet_label', {'name': widget.info.name}),
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _busy ? null : _unlock,
                        child: Text(_busy ? _busyLabel : t('unlock_ltc_btn')),
                      ),
                    ],
                  )
                else ...[
                  _buildBalanceCard(context),
                  const SizedBox(height: 16),
                  _buildActionsRow(context),
                  const SizedBox(height: 10),
                  // Обязательное предупреждение MWEB (паспорт LTC): внизу,
                  // мелко, как честная пометка — не простыня сверху.
                  Text(
                    t('ltc_mweb_warning'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: VColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBalanceCard(BuildContext context) {
    final sync = _sync;
    return SectionCard(
      title: t('balance_section'),
      icon: Icons.savings_outlined,
      children: [
        if (_sync == null && _busy)
          const Center(child: CircularProgressIndicator())
        else if (_sync == null)
          Text(
            t('not_synced_note'),
            style: const TextStyle(color: Colors.white70),
          )
        else ...[
          Text(
            '${satToBtcString(sync!.confirmedSat.toInt())} LTC',
            style:
                const TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
          ),
          Text(
            '${groupDigits(sync.confirmedSat.toInt())} ${t('ltc_unit')}',
            style: const TextStyle(color: Colors.white60),
          ),
          if (sync.unconfirmedDeltaSat != 0) ...[
            const SizedBox(height: 6),
            Text(
              tf(
                'mempool_row',
                {
                  'value':
                      '${signedSatToBtcString(sync.unconfirmedDeltaSat.toInt())} LTC'
                },
              ),
              style: const TextStyle(color: Colors.orangeAccent),
            ),
          ],
          const SizedBox(height: 10),
          kvRow(t('utxo_available'), '${sync.utxoCount}'),
          kvRow(t('chain_height'), '${sync.tipHeight}'),
          kvRow(t('addresses_with_history'), '${sync.usedAddresses.length}'),
        ],
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: _busy ? null : _doSync,
          icon: const Icon(Icons.sync),
          label: Text(_sync == null ? t('sync_btn') : t('refresh_btn')),
        ),
        const SizedBox(height: 8),
        Text(
          tf('server_status_row', {'value': _state?.serverUrl ?? '—'}),
          style: const TextStyle(color: VColors.textSecondary, fontSize: 11),
        ),
      ],
    );
  }

  /// Три плитки: приём/отправка/история — общий виджет BTC-центра.
  Widget _buildActionsRow(BuildContext context) {
    final unlocked = _state != null;
    return Row(
      children: [
        for (final entry in [
          (
            icon: Icons.qr_code_2_outlined,
            label: t('get_btn'),
            onTap: unlocked ? _openReceive : null,
          ),
          (
            icon: Icons.north_east,
            label: t('send_btn'),
            onTap: unlocked && _availableLit() != null ? _openSend : null,
          ),
          (
            icon: Icons.history,
            label: t('history_btn'),
            onTap: unlocked ? _openHistory : null,
          ),
        ])
          Expanded(
            child: CoinActionTile(
              icon: entry.icon,
              label: entry.label,
              enabled: entry.onTap != null,
              onTap: entry.onTap,
            ),
          ),
      ],
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
