//! LTC — центр управления (receive-only milestone): разблокировка
//! (пароль; сервер подбирается автоматически из живого списка ядра с
//! genesis-чеком), синхронизация (ltcSync), баланс, приём (Receive) и
//! история. Send-плитки НЕТ: подпись LTC-переводов — следующий этап
//! (docs/coins/LTC.md, PROJECT_STATUS.md). Все данные — реальные
//! FFI-вызовы ядра. MWEB-предупреждение показывается всегда (паспорт
//! LTC): прозрачная часть видима, MWEB-переводы — нет.

import 'package:flutter/material.dart';

import 'dart:async';

import 'package:veyro/src/rust/api/ltc.dart';
import 'package:veyro/src/rust/api/session.dart';
import 'package:veyro/src/rust/api/storage.dart';
import 'package:veyro/src/rust/api/wallet.dart';
import 'package:veyro/design/app_colors.dart';
import 'package:veyro/util/app_dirs.dart';
import 'package:veyro/util/coin.dart';
import 'package:veyro/util/l10n.dart';
import 'package:veyro/util/format.dart';
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
  /// успех сброс. Экспонента копит goodwill у живых серверов.
  DateTime? _lastSeriesFailedAt;
  int _failureStreak = 0;

  /// Диалог пароля показывается автоматически один раз на вход; после
  /// отмены остаются ручные кнопки.
  var _autoPrompted = false;

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
    await _unlock();
  }

  Future<void> _refresh({required bool autosyncIfUnlocked}) async {
    try {
      final state = await ltcSessionState();
      if (!mounted) return;
      setState(() {
        _state = state;
        _busy = false;
      });
      if (state != null && autosyncIfUnlocked && _sync == null) {
        await _doSync();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _busy = false;
      });
    }
  }

 Future<void> _unlock() async {
    if (!mounted) return;
    // Единый вход (решение владельца): если пароль уже кэширован ядром
    // после первой разблокировки — монета подключается без диалога.
    String password;
    try {
      final cached = await sessionPasswordCached();
      if (!mounted) return;
      if (cached) {
        password = '';
      } else {
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
      password = '';
    }
    if (password.isEmpty) {
      // Двойная проверка: пустая строка допустима только при живом кэше
      // (иначе — это отмена диалога или нет кэша: честный запрос).
      try {
        final cached = await sessionPasswordCached();
        if (!cached) return; // диалог отменён — ничего не делаем
      } catch (_) {
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = true;
      _busyLabel = t('unlocking_now');
      _error = null;
    });
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
        // Тихая попытка (кэшированный пароль) не прошла ИЗ-ЗА НЕПОДХОДЯЩЕГО
        // пароля? Тогда один честный диалог — никакого бесконечного цикла
        // ошибок. Transport-неудачи (flaky EOF) здесь уже переборены
        // кандидатами; наружу их отдаёт повторная тихая попытка ниже.
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
              setState(() {
                _error = _cleanError(e);
                _busy = false;
              });
            }
            return;
          }
          try {
            await _unlockViaCandidates(manual);
            // Успех ручной попытки — экспонента обнуляется.
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

  /// Full unlock attempt: candidates loop (the LAST GOOD server first —
  /// persisted between runs; transient → next server, polite pauses; a
  /// per-candidate Dart timeout guarantees the loop NEVER stalls forever
  /// on a stuck server).
  Future<void> _unlockViaCandidates(String password) async {
    final stored = List<String>.from(await ltcServers());
    // Память о живом (решение владельца): прошлый удачный сервер — первым,
    // без дубликатов; экономим соединения и не зарабатываем баны.
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
      // Прогресс прямо на кнопке: какой сервер, какой по счёту.
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
          // 60 c: с быстрым коннектом ядра этого с запасом; зависший
          // кандидат не задержит цикл навсегда.
        ).timeout(const Duration(seconds: 60));
        // Success → remember the live server for next launches AND for the
        // network-info card (persisted, non-secret key-value).
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
        // Вежливая пауза — честный шанс следующему кандидату.
        await Future.delayed(const Duration(milliseconds: 1200));
      }
    }
    if (!unlocked) {
      // Честно: что именно сказал каждый кандидат (по строке на сервер).
      final summary = failures.join('\n');
      throw (summary.isEmpty
          ? StateError('no electrum-ltc candidate')
          : StateError(summary));
    }
  }

  /// Одна строка на кандидата в сводной ошибке: без ссылок/переносов.
  String _oneLine(String text) {
    var t = text.replaceAll('\n', ' ').replaceAll('  ', ' ').trim();
    if (t.length > 140) t = '${t.substring(0, 137)}…';
    return t;
  }

  Future<void> _doSync() async {
    setState(() {
      _busyLabel = t('btc_syncing_addresses_long');
      _error = null;
    });
    try {
      final sync = await ltcSync(gapLimit: 20);
      if (!mounted) return;
      setState(() {
        _sync = sync;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString();
      // Тихий авто-повтор один раз: ядро само переподключается с
      // честным хэндшейк-бэкоффом.
      final transient = raw.contains('electrum') ||
          raw.contains('unexpected end of file') ||
          raw.contains('all errored') ||
          raw.contains('timed out') ||
          raw.contains('connection');
      if (transient) {
        await Future.delayed(const Duration(milliseconds: 1600));
        if (mounted) {
          try {
            final sync = await ltcSync(gapLimit: 20);
            if (!mounted) return;
            setState(() {
              _sync = sync;
              _busy = false;
            });
            return;
          } catch (e) {
            setState(() {
              _error = e.toString();
              _busy = false;
            });
            return;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _error = raw;
        _busy = false;
      });
    }
  }

  Future<void> _lock() async {
    try {
      await ltcLock();
      if (!mounted) return;
      setState(() {
        _state = null;
        _sync = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
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
                if (state == null)
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
                  _buildMwebCard(context),
                  const SizedBox(height: 12),
                  _buildBalanceCard(context),
                  const SizedBox(height: 16),
                  _buildActionsRow(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Обязательное предупреждение MWEB-слепоты (паспорт LTC): прозрачная
  /// часть кошелька видима, MWEB-переводы — нет.
  Widget _buildMwebCard(BuildContext context) {
    return SectionCard(
      title: 'MWEB',
      icon: Icons.info_outline,
      children: [
        Text(
          t('ltc_mweb_warning'),
          style: const TextStyle(color: Colors.orangeAccent, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildBalanceCard(BuildContext context) {
    final sync = _sync;
    return SectionCard(
      title: t('balance_section'),
      icon: Icons.savings_outlined,
      children: [
        kvRow(t('network_label'), 'Litecoin mainnet'),
        kvRow(t('server_label'), _state?.serverUrl ?? '—'),
        const SizedBox(height: 6),
        if (sync == null && _busy) ...[
          const Center(child: CircularProgressIndicator()),
        ] else if (sync == null)
          Text(
            t('not_synced_note'),
            style: const TextStyle(color: Colors.white70),
          )
        else ...[
          Text(
            '${satToBtcString(sync.confirmedSat.toInt())} LTC',
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
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: _busy ? null : _lock,
            icon: const Icon(Icons.lock_outline),
            label: Text(t('lock_btn')),
          ),
        ],
        if (sync != null) const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: _busy ? null : _doSync,
          icon: const Icon(Icons.sync),
          label: Text(_sync == null ? t('sync_btn') : t('refresh_btn')),
        ),
      ],
    );
  }

  /// Три плитки: приём, отправка, история (полный цикл после send
  /// milestone).
  Widget _buildActionsRow() {
    return Row(
      children: [
        Expanded(
          child: _ActionTileLite(
            icon: Icons.qr_code_2_outlined,
            label: t('get_btn'),
            onTap: _openReceive,
          ),
        ),
        Expanded(
          child: _ActionTileLite(
            icon: Icons.north_east,
            label: t('send_btn'),
            onTap: _state == null ? null : _openSend,
          ),
        ),
        Expanded(
          child: _ActionTileLite(
            icon: Icons.history,
            label: t('history_btn'),
            onTap: _openHistory,
          ),
        ),
      ],
    );
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

/// Плитка действия центра монет: hover-подъём; аналог BTC _ActionTile
/// (без send-плитки и без свечения-из-коробки: минимально изолировано).
class _ActionTileLite extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ActionTileLite({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_ActionTileLite> createState() => _ActionTileLiteState();
}

class _ActionTileLiteState extends State<_ActionTileLite> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hover ? -2 : 0, 0),
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Column(
                children: [
                  Icon(widget.icon, size: 26),
                  const SizedBox(height: 6),
                  Text(widget.label, style: const TextStyle(fontSize: 12.5)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
