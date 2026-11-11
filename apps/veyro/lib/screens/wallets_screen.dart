//! Экран 19 спеки (Wallet manager): реестр кошельков ядра (list_wallets),
//! показ фразы только по паролю, вход в портфель. Создание и импорт —
//! отдельные полноэкранные сценарии (create_wallet_flow /
//! import_wallet_screen); резервное копирование — через AppBar и раздел
//! «Бэкап». Группа 4: честное состояние BTC-сессии (глобальное — DTO
//! сессии не содержит id кошелька, поэтому блокировка показывается общим
//! чипом, а не по-кошельково), тип «vault» и дата создания; переименование
//! и удаление ядром не поддерживаются — честные пометки, без имитации
//! кнопками. Все данные из ядра, без моков.

import 'package:flutter/material.dart';

import 'package:veyro/design/app_colors.dart';
import 'package:veyro/design/components.dart';
import 'package:veyro/src/rust/api/session.dart';
import 'package:veyro/src/rust/api/wallet.dart';
import 'package:veyro/util/app_dirs.dart';
import 'package:veyro/util/ui_helpers.dart';

import 'backup_screens.dart';
import 'create_wallet_flow.dart';
import 'import_wallet_screen.dart';
import 'portfolio_screen.dart';

class WalletsScreen extends StatefulWidget {
  /// Точка замены для виджет-тестов (без RustLib): состояние BTC-сессии.
  final Future<BtcSessionStateDto?> Function()? sessionLoader;

  /// Точка замены для виджет-тестов: реестр кошельков (по умолчанию —
  /// реальный listWallets по vault-директории).
  final Future<List<WalletInfoDto>> Function()? walletLoader;

  const WalletsScreen({super.key, this.sessionLoader, this.walletLoader});

  @override
  State<WalletsScreen> createState() => _WalletsScreenState();
}

class _WalletsScreenState extends State<WalletsScreen> {
  List<WalletInfoDto>? _wallets;
  String? _error;
  bool _loading = true;

  BtcSessionStateDto? _session;
  bool _sessionChecked = false;
  String? _sessionError;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final loader = widget.walletLoader;
      final list =
          loader != null ? await loader() : await listWallets(walletsDir: walletsDir());
      if (!mounted) return;
      setState(() {
        _wallets = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
    await _loadSession();
  }

  Future<void> _loadSession() async {
    try {
      final loader = widget.sessionLoader;
      final session =
          loader != null ? await loader() : await btcSessionState();
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

  /// Меню резервных копий (AppBar): экспорт выбранных кошельков в один
  /// зашифрованный файл и импорт на это устройство. Диалоги в
  /// backup_screens.dart; после импорта реестр перечитывается.
  Future<void> _openBackupMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: const Text('Экспорт бэкапа'),
              subtitle: const Text('Выбранные кошельки — в зашифрованный файл'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _exportBackup();
              },
            ),
            ListTile(
              leading: const Icon(Icons.unarchive_outlined),
              title: const Text('Импорт бэкапа'),
              subtitle: const Text('Кошельки из файла-копии на это устройство'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _importBackup();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportBackup() async {
    final wallets = _wallets ?? const [];
    if (wallets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Экспортировать нечего: кошельков нет')),
      );
      return;
    }
    await showBackupExportDialog(context, wallets: wallets);
  }

  Future<void> _importBackup() async {
    await showBackupImportDialog(context);
    // Импорт меняет реестр кошельков — перечитать список.
    if (mounted) await _reload();
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    // Сценарии могут изменить реестр (создание/импорт) — перечитать.
    if (mounted) await _reload();
  }

  Future<void> _revealMnemonic(WalletInfoDto info) async {
    final password = await promptPassword(
      context,
      title: 'Показать seed-фразу «${info.name}»',
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
      appBar: AppBar(
        title: const Text('Кошельки'),
        actions: [
          IconButton(
            tooltip: 'Резервная копия',
            icon: const Icon(Icons.archive_outlined),
            onPressed: _openBackupMenu,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: _buildBody(context),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 40, color: Colors.white54),
            const SizedBox(height: 12),
            Text('Не удалось прочитать реестр: $_error'),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: _reload, child: const Text('Повторить')),
          ],
        ),
      );
    }
    final wallets = _wallets ?? const [];
    final isEmpty = wallets.isEmpty;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSessionCard(context),
          const SizedBox(height: 12),
          VCard(
            icon: Icons.tune_outlined,
            title: 'Кошельки',
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _push(const CreateWalletFlow()),
                      icon: const Icon(Icons.add_circle_outline, size: 18),
                      label: const Text('Создать'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _push(const ImportWalletScreen()),
                      icon: const Icon(Icons.restore_outlined, size: 18),
                      label: const Text('Импорт'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                isEmpty
                    ? 'Реестр пуст. Первый кошелёк появится после создания '
                        'или восстановления фразы.'
                    : 'Нажмите на кошелёк, чтобы открыть его обзор. Фраза '
                        'показывается только по паролю кошелька.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              Text(
                'Переименование и удаление кошельков ядром не '
                'поддерживаются (API отсутствует) — кнопок-имитаций нет. '
                'Блокировка ключей — кнопкой BTC-сессии; экспорт — '
                'иконкой бэкапа выше.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (isEmpty)
            VEmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Кошельков пока нет',
              message: 'Создайте новый кошелёк или восстановите существующий '
                  'из BIP39-фразы. Резервная копия восстанавливается из '
                  '.veybackup-файла.',
            )
          else
            for (final info in wallets)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: ListTile(
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
                          'Тип: vault · создан ${_formatDate(info.createdAtUnix)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'ID: ${info.id.substring(0, info.id.length.clamp(0, 8))}…',
                          style: const TextStyle(
                              fontFamily: 'JetBrainsMono', fontSize: 12),
                        ),
                      ],
                    ),
                    isThreeLine: true,
                    trailing: IconButton(
                      tooltip: 'Показать seed-фразу',
                      icon: const Icon(Icons.key_outlined),
                      onPressed: () => _revealMnemonic(info),
                    ),
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => PortfolioScreen(info: info),
                      ));
                      // Состояние могло измениться (сессия открыта/закрыта).
                      if (mounted) await _reload();
                    },
                  ),
                ),
              ),
        ],
      ),
    );
  }

  /// Состояние блокировки BTC-сессии. Честное ограничение: DTO сессии
  /// не содержит id кошелька, поэтому состояние — глобальное по ядру,
  /// а не по-кошельково (так и подписано).
  Widget _buildSessionCard(BuildContext context) {
    final session = _session;
    return VCard(
      icon: Icons.lock_outline,
      title: 'Состояние BTC-сессии',
      children: [
        if (!_sessionChecked)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_sessionError != null)
                const VStatusChip('Сессия не прочитана', kind: VChipKind.warning)
              else if (session != null)
                VStatusChip(
                  'Ключи в памяти ядра · ${session.networkDisplay}',
                  kind: VChipKind.warning,
                )
              else
                const VStatusChip(
                  'Не загружены (заблокирована / не открывалась)',
                  kind: VChipKind.success,
                ),
            ],
          ),
          if (_sessionError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Не удалось прочитать состояние сессии: $_sessionError',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall!
                    .copyWith(color: VColors.error),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            'Открыть/заблокировать сессию — в центре управления BTC '
            '(портфель кошелька); состояние общее для ядра: DTO сессии '
            'не содержит id кошелька.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  String _formatDate(BigInt createdUnix) {
    final d = DateTime.fromMillisecondsSinceEpoch(createdUnix.toInt());
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '$dd.$mm.${d.year}';
  }
}
