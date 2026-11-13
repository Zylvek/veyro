//! Экраны 22/23/24 спеки одним разделом: General settings + Security +
//! Notifications. Реализовано честно: валюта фиата и скрытие сумм
//! (SQLite-настройки моста), ручная блокировка BTC-сессии (btc_lock),
//! версия схемы БД настроек (db_schema_version), переходы в сеть/бэкап/
//! «О VEYRO». Чего нет в ядре — нет и в UI: авто-блокировка, биометрия,
//! смена пароля и уведомления описаны статически, БЕЗ переключателей
//! (правило спеки: не добавлять переключатели для нереализованных функций).

import 'package:flutter/material.dart';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show PlatformInt64;
import 'package:veyro/design/app_colors.dart';
import 'package:veyro/design/components.dart';
import 'package:veyro/src/rust/api/btc.dart' show btcLock;
import 'package:veyro/src/rust/api/session.dart';
import 'package:veyro/util/display_prefs.dart';
import 'package:veyro/util/network_names.dart';
import 'package:veyro/util/ui_helpers.dart';

import 'about_screen.dart';
import 'backup_screen.dart';
import 'create_wallet_flow.dart';
import 'import_wallet_screen.dart';
import 'wallets_screen.dart';

class SettingsScreen extends StatefulWidget {
  /// Точка замены для тестов: версия схемы БД настроек.
  final Future<PlatformInt64> Function()? schemaLoader;

  /// Точка замены для тестов: состояние BTC-сессии.
  final Future<BtcSessionStateDto?> Function()? sessionLoader;

  /// Точка замены для тестов: действие блокировки (по умолчанию btcLock).
  final Future<void> Function()? lockAction;

  const SettingsScreen({super.key, this.schemaLoader, this.sessionLoader, this.lockAction});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _prefsReady = false;
  bool _lockBusy = false;


  BtcSessionStateDto? _session;
  bool _sessionChecked = false;
  String? _sessionError;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
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
              const SizedBox(height: 12),
              _buildLinks(context),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGeneral(BuildContext context) {
    return VCard(
      title: 'Общие',
      icon: Icons.tune_outlined,
      children: _prefsReady
          ? [
              Row(
                children: [
                  const Text('Валюта отображения:',
                      style: TextStyle(fontSize: 13)),
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
              // Тумблер «Скрывать суммы» убран (решение владельца): эту
              // функцию делает глазик в шапке Обзора.
              if (DisplayPrefs.degraded)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: VStatusChip(
                      'БД настроек недоступна: изменения действуют только '
                      'текущую сессию',
                      kind: VChipKind.warning,
                    ),
                  ),
                ),
              Text(
                'Язык: русский — единственный в этой сборке. Выбор языка и '
                'альтернативные форматы чисел не реализованы в ядре и '
                'не имитируются.',
                style: Theme.of(context).textTheme.bodySmall,
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
      title: 'Безопасность',
      icon: Icons.shield_outlined,
      children: [
        if (!_sessionChecked)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_sessionError != null)
          Text(
            'Состояние сессии не прочитано: $_sessionError',
            style: Theme.of(context)
                .textTheme
                .bodySmall!
                .copyWith(color: VColors.error),
          )
        else
          _sessionStatusColumn(context),
        Text(
          'Ручная блокировка выгружает ключи сессии из памяти ядра: '
          'повторная разблокировка требует пароля кошелька.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const Divider(height: 20),
        _honestRow(context, 'Авто-блокировка по бездействию',
            'не реализовано в ядре (нет таймера бездействия) — '
            'переключатель не добавляется'),
        _honestRow(context, 'Биометрия',
            'не реализовано в этой сборке (планируется в Android-группе)'),
        _honestRow(context, 'Смена пароля',
            'API смены пароля в ядре отсутствует; честный путь — экспорт '
            'и импорт с новым паролем'),
        _honestRow(context, 'Хранение секретов',
            'seed и ключи — только в зашифрованном vault ядра; показ фразы '
            'требует пароля'),
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
                  ? 'Ключи сессии в памяти ядра (${ruNetworkText(session.networkDisplay)})'
                  : 'BTC заблокирован: ключи сессии не загружены',
              kind: sessionActive ? VChipKind.warning : VChipKind.success,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: VButton.secondary(
            _lockBusy ? 'Блокировка…' : 'Заблокировать BTC',
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
            child: Text('$title:',
                style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            flex: 3,
            child: Text(
              note,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotifications(BuildContext context) {
    return VCard(
      title: 'Уведомления',
      icon: Icons.notifications_outlined,
      children: [
        Text(
          'Уведомления не реализованы в этой сборке — переключателей '
          'и имитации здесь нет. Если функция появится, допустимые '
          'события (по спецификации): подтверждение входящей '
          'транзакции, сбои и восстановление сетевого подключения, '
          'завершение синхронизации, статус бэкапа. Маркетинг и '
          'реклама исключены безусловно.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  /// Карточка «Кошельки» в Настройках (решение владельца: вкладка
  /// кошельков в навигации не нужна — создание, импорт и реестр здесь).
  Widget _buildWallets(BuildContext context) {
    return VCard(
      title: 'Кошельки',
      icon: Icons.wallet_outlined,
      children: [
        Row(
          children: [
            Expanded(
              child: VButton.secondary(
                'Создать',
                icon: Icons.add_circle_outline,
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => const CreateWalletFlow(),
                  ));
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: VButton.secondary(
                'Импорт',
                icon: Icons.restore_outlined,
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => const ImportWalletScreen(),
                  ));
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: VButton.secondary(
            'Открыть кошельки',
            icon: Icons.list_alt,
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const WalletsScreen(),
              ));
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLinks(BuildContext context) {
    return VCard(
      title: 'Разделы',
      icon: Icons.link_outlined,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: VButton.secondary(
            'Бэкап и восстановление',
            icon: Icons.backup_outlined,
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const BackupScreen(),
              ));
            },
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: VButton.secondary(
            'О VEYRO',
            icon: Icons.info_outline,
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const AboutScreen(),
              ));
            },
          ),
        ),
      ],
    );
  }
}
