//! Настройки единым разделом: General + Кошельки (создание, импорт,
//! реестр и удаление) + Security + Notifications + Ссылки. Реализовано
//! честно: валюта фиата (SQLite-настройки моста), ручная блокировка
//! BTC-сессии (btc_lock), удаление кошелька (vault-файл снимается с
//! диска с подтверждением). Чего нет в ядре — нет и в UI: авто-блокировка,
//! биометрия, смена пароля и уведомления описаны статически, БЕЗ
//! переключателей (правило спеки: не добавлять переключатели для
//! нереализованных функций).

import 'dart:io';

import 'package:flutter/material.dart';

import 'package:veyro/design/app_colors.dart';
import 'package:veyro/design/components.dart';
import 'package:veyro/design/motion.dart';
import 'package:veyro/src/rust/api/btc.dart' show btcLock;
import 'package:veyro/src/rust/api/ltc.dart' show ltcLock;
import 'package:veyro/src/rust/api/session.dart';
import 'package:veyro/src/rust/api/wallet.dart';
import 'package:veyro/util/app_dirs.dart';
import 'package:veyro/util/btc_state_cache.dart';
import 'package:veyro/util/ltc_state_cache.dart';
import 'package:veyro/util/l10n.dart';
import 'package:veyro/util/price_source.dart';
import 'package:veyro/util/display_prefs.dart';
import 'package:veyro/util/format.dart';
import 'package:veyro/util/network_names.dart';
import 'package:veyro/util/ui_helpers.dart';

import 'create_wallet_flow.dart';
import 'import_wallet_screen.dart';
import 'portfolio_screen.dart';

class SettingsScreen extends StatefulWidget {
  /// Точка замены для тестов: состояние BTC-сессии.
  final Future<BtcSessionStateDto?> Function()? sessionLoader;

  /// Точка замены для тестов: действие блокировки (по умолчанию btcLock).
  final Future<void> Function()? lockAction;

  const SettingsScreen({super.key, this.sessionLoader, this.lockAction});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _prefsReady = false;
  bool _lockBusy = false;

  BtcSessionStateDto? _session;
  bool _sessionChecked = false;
  String? _sessionError;

  /// Реестр кошельков (для карточки «Кошельки»).
  List<WalletInfoDto>? _wallets;
  String? _walletsError;
  bool _walletsLoading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await DisplayPrefs.ensureLoaded();
    if (!mounted) return;
    setState(() => _prefsReady = true);
    await _loadSession();
    await _reloadWallets();
  }

  Future<void> _loadSession() async {
    try {
      final loader = widget.sessionLoader;
      final session = loader != null ? await loader() : await btcSessionState();
      if (!mounted) return;
      setState(() {
        _session = session;
        _sessionChecked = true;
        _sessionError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _session = null;
        _sessionChecked = true;
        _sessionError = e.toString();
      });
    }
  }

  Future<void> _reloadWallets() async {
    try {
      final list = await listWallets(walletsDir: walletsDir());
      if (!mounted) return;
      setState(() {
        _wallets = list;
        _walletsLoading = false;
        _walletsError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _walletsLoading = false;
        _walletsError = e.toString();
      });
    }
  }

  Future<void> _lockBtc() async {
    if (_lockBusy) return;
    setState(() => _lockBusy = true);
    try {
      final action = widget.lockAction ?? btcLock;
      await action();
      if (!mounted) return;
      setState(() => _lockBusy = false);
      await _loadSession();
    } catch (e) {
      if (!mounted) return;
      setState(() => _lockBusy = false);
      showError(context, e);
    }
  }

  /// Удаление кошелька: подтверждение → закрыть его монетные сессии (если
  /// они принадлежат удалённому активному кошельку), стереть пароль из
  /// кэша ядра, снять vault-файл (`<id>.wallet.json`) с диска — реестр
  /// ядра перечитывает каталог. Секреты не выживают удаление: сессия с
  /// seed и кэш пароля для этого id вычищаются до снятия файла.
  Future<void> _deleteWallet(WalletInfoDto info) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tf('delete_wallet_title', {'name': info.name})),
        content: Text(t('delete_wallet_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: VColors.error),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(t('delete_forever')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final wasActive = DisplayPrefs.walletId == info.id;
      if (wasActive) {
        // Сессии ядра держат seed в памяти: блокируем обе монеты (худший
        // случай для владельца — повторный ввод пароля; честность выше
        // удобства при необратимом удалении), кэши монет сбрасываем.
        try {
          await btcLock();
        } catch (_) {}
        try {
          await ltcLock();
        } catch (_) {}
        BtcStateCache.instance.clear();
        LtcStateCache.instance.clear();
      }
      // Пароль удалённого кошелька не переживёт удаление (owner decision).
      try {
        await sessionPasswordEraseFor(walletId: info.id);
      } catch (_) {}
      // Снятие файла — асинхронно: блокирующий IO в UI-потоке не нужен.
      final vaultFile = File(
        '${walletsDir()}${Platform.pathSeparator}${info.id}.wallet.json',
      );
      if (await vaultFile.exists()) await vaultFile.delete();
      // Зависший tmp-писатель создания (crash mid-write) подчищаем заодно.
      final tmp = File(
        '${walletsDir()}${Platform.pathSeparator}${info.id}.wallet.tmp',
      );
      if (await tmp.exists()) await tmp.delete();
      await DisplayPrefs.forgetWalletIf(info.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tf('wallet_deleted', {'name': info.name}))),
      );
      await _reloadWallets();
    } catch (e) {
      if (!mounted) return;
      showError(context, e);
    }
  }

  /// Показ seed-фразы по паролю (тот же честный путь ядра, что был
  /// на вкладке кошельков).
  Future<void> _revealMnemonic(WalletInfoDto info) async {
    final password = await promptPassword(
      context,
      title: tf('reveal_title', {'name': info.name}),
    );
    if (password == null || !mounted) return;
    try {
      final phrase = await revealMnemonic(
        walletsDir: walletsDir(),
        id: info.id,
        password: password,
      );
      if (!mounted) return;
      await showMnemonicDialog(context, phrase);
    } catch (e) {
      if (!mounted) return;
      showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('settings_title'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildGeneral(context),
              const SizedBox(height: 12),
              _buildWallets(context),
              const SizedBox(height: 12),
              _buildSecurity(context),
              const SizedBox(height: 12),
              _buildNotifications(context),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGeneral(BuildContext context) {
    return VCard(
      title: t('settings_general'),
      icon: Icons.tune_outlined,
      children: _prefsReady
          ? [
              Row(
                children: [
                  Text(
                    t('display_currency'),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const Spacer(),
                  DropdownButton<String>(
                    value: DisplayPrefs.fiatCurrency,
                    underline: const SizedBox.shrink(),
                    hint: const Text('—'),
                    items: [
                      for (final code in DisplayPrefs.fiatCurrencies)
                        DropdownMenuItem(value: code, child: Text(code)),
                    ],
                    onChanged: (code) {
                      if (code == null) return;
                      DisplayPrefs.setFiatCurrency(code);
                      setState(() {});
                    },
                  ),
                ],
              ),
              // Монета линии графика (решение владельца: настройка
              // графика — «осматривать другие монеты») — здесь, в
              // настройках; Обзор подхватывает её при возврате.
              Row(
                children: [
                  Text(
                    t('chart_coin_label'),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const Spacer(),
                  DropdownButton<String>(
                    value:
                        PriceSource.chartCoins.containsKey(
                          DisplayPrefs.chartCoin,
                        )
                        ? DisplayPrefs.chartCoin
                        : 'ETH',
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final symbol in PriceSource.chartCoins.keys)
                        DropdownMenuItem(value: symbol, child: Text(symbol)),
                    ],
                    onChanged: (symbol) {
                      if (symbol == null || symbol == DisplayPrefs.chartCoin) {
                        return;
                      }
                      DisplayPrefs.setChartCoin(symbol);
                      setState(() {});
                    },
                  ),
                ],
              ),
              // Язык интерфейса (решение владельца: «добавь поддержку
              // других языков») — словарь lib/util/l10n.dart.
              Row(
                children: [
                  Text(
                    t('language_label'),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const Spacer(),
                  DropdownButton<String>(
                    value: DisplayPrefs.language,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final entry in DisplayPrefs.languages.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                    ],
                    onChanged: (code) {
                      if (code == null) return;
                      DisplayPrefs.setLanguage(code);
                      bumpLanguageRevision();
                      setState(() {});
                    },
                  ),
                ],
              ),
              // Тумблер «Скрывать суммы» убран (решение владельца): эту
              // функцию делает глазик в шапке Обзора.
              if (DisplayPrefs.degraded)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: VStatusChip(t('db_note'), kind: VChipKind.warning),
                  ),
                ),
            ]
          : const [
              Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            ],
    );
  }

  Widget _buildSecurity(BuildContext context) {
    return VCard(
      title: t('settings_security'),
      icon: Icons.shield_outlined,
      children: [
        if (!_sessionChecked)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_sessionError != null)
          Text(
            tf('session_state_error', {'error': '$_sessionError'}),
            style: Theme.of(context).textTheme.bodySmall!
                .copyWith(color: VColors.error),
          )
        else
          _sessionStatusColumn(context),
        Text(
          t('manual_lock_note'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const Divider(height: 20),
        _honestRow(context, t('idle_lock_label'), t('idle_lock_note')),
        _honestRow(context, t('biometry_label'), t('biometry_note')),
        _honestRow(
          context,
          t('password_change_label'),
          t('password_change_note'),
        ),
        _honestRow(context, t('secrets_label'), t('secrets_note')),
      ],
    );
  }

  Widget _sessionStatusColumn(BuildContext context) {
    final session = _session;
    final sessionActive = session != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            VStatusChip(
              sessionActive
                  ? tf('session_keys_active', {
                      'network': ruNetworkText(session.networkDisplay) ?? 'BTC',
                    })
                  : t('btc_locked_chip'),
              kind: sessionActive ? VChipKind.warning : VChipKind.success,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: VButton.secondary(
            _lockBusy ? t('locking_now') : t('lock_btc_btn'),
            icon: Icons.lock_outline,
            onPressed: sessionActive && !_lockBusy ? _lockBtc : null,
          ),
        ),
      ],
    );
  }

  Widget _honestRow(BuildContext context, String title, String note) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              '$title:',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(note, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }

  Widget _buildNotifications(BuildContext context) {
    return VCard(
      title: t('settings_notifications'),
      icon: Icons.notifications_outlined,
      children: [
        Text(
          t('notifications_note'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  /// Карточка «Кошельки» в Настройках (решение владельца: вкладка
  /// кошельков в навигации не нужна — создание, импорт, реестр и
  /// удаление здесь).
  Widget _buildWallets(BuildContext context) {
    final wallets = _wallets;
    return VCard(
      title: t('settings_wallets'),
      icon: Icons.wallet_outlined,
      children: [
        Row(
          children: [
            Expanded(
              child: VButton.secondary(
                t('wallets_create'),
                icon: Icons.add_circle_outline,
                onPressed: () async {
                  // ДОЖИДАЕМСЯ возврата: иначе реестр перечитывается до
                  // создания кошелька, и новый кошелёк не появляется.
                  await pushVeyro<void>(context, const CreateWalletFlow());
                  if (mounted) await _reloadWallets();
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: VButton.secondary(
                t('wallets_import'),
                icon: Icons.restore_outlined,
                onPressed: () async {
                  await pushVeyro<void>(context, const ImportWalletScreen());
                  if (mounted) await _reloadWallets();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_walletsLoading)
          const Center(child: CircularProgressIndicator(strokeWidth: 2))
        else if (_walletsError != null)
          Text(
            tf('wallets_registry_error', {'error': '$_walletsError'}),
            style: Theme.of(context).textTheme.bodySmall!
                .copyWith(color: VColors.error),
          )
        else if (wallets == null || wallets.isEmpty)
          Text(t('wallets_empty'), style: Theme.of(context).textTheme.bodySmall)
        else
          for (final info in wallets)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: CircleAvatar(
                  backgroundColor: VColors.elevated,
                  child: Text(
                    info.name.isEmpty
                        ? '?'
                        : info.name.characters.first.toUpperCase(),
                    style: const TextStyle(
                      color: VColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                title: Text(info.name),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 2),
                    Text(
                      tf('wallet_created', {
                        'date': formatWalletDate(info.createdAtUnix.toInt()),
                      }),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tf('wallet_id', {'id': info.id}),
                      style: const TextStyle(
                        fontFamily: kMonoFont,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                isThreeLine: true,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: t('seed_reveal_tooltip'),
                      icon: const Icon(Icons.key_outlined),
                      onPressed: () => _revealMnemonic(info),
                    ),
                    IconButton(
                      tooltip: t('delete_wallet_tooltip'),
                      icon: const Icon(
                        Icons.delete_outline,
                        color: VColors.error,
                      ),
                      onPressed: () => _deleteWallet(info),
                    ),
                  ],
                ),
                onTap: () async {
                  await pushVeyro<void>(context, PortfolioScreen(info: info));
                  if (mounted) await _reloadWallets();
                },
              ),
            ),
      ],
    );
  }

  /// Секция «Разделы» удалена (решение владельца: «полностью откажемся от
  /// бекапов и О VEYRO — ненужное только место занимает»). Карточки
  /// бэкапа и About вместе с их экранами вырезаны из приложения.
}
