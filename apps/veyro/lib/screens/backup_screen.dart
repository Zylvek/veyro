//! Раздел «Бэкап» (спека экраны 7/20, переработка по аудиту UI §6):
//! Экспорт и Импорт разделены, есть честное состояние последнего
//! резервного копирования (локальная запись в SQLite-настройках — путь и
//! время пишутся только после реального успешного экспорта), целостность
//! описана как проверку при восстановлении. Технические детали шифрования
//! — в раскрывающемся блоке. QR-импорт честно помечен нереализованным.

import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:veyro/design/app_colors.dart';
import 'package:veyro/design/components.dart';
import 'package:veyro/src/rust/api/storage.dart';
import 'package:veyro/src/rust/api/wallet.dart';
import 'package:veyro/util/app_dirs.dart';
import 'package:veyro/util/format.dart';
import 'package:veyro/util/ui_helpers.dart';

import 'backup_screens.dart';
import 'import_backup_screens.dart';

/// Ключ SQLite-настроек с записью о последнем успешном экспорте.
const String kLastBackupKey = 'backup.last';

/// Локальная не-секретная запись о последнем экспорте (время, путь,
/// число кошельков). Пишется только реальным действием пользователя;
/// ни секретов, ни имитации — нет записи, значит свежих экспортов не было.
Future<void> recordBackupExport({
  required String path,
  required List<String> walletNames,
}) async {
  final record = jsonEncode({
    'ts': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    'path': path,
    'names': walletNames,
  });
  try {
    await dbSetSetting(key: kLastBackupKey, value: record);
  } catch (_) {
    // Метаданные записи некритичны: секреты в бэкапе зашифрованы ядром
    // независимо от того, сохранилась ли эта строка.
  }
}

/// Чтение записи о последнем экспорте; null — записи нет.
Future<Map<String, dynamic>?> readLastBackupRecord() async {
  try {
    final raw = await dbGetSetting(key: kLastBackupKey);
    if (raw == null || raw.isEmpty) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  List<WalletInfoDto>? _wallets;
  String? _error;
  bool _loading = true;
  Map<String, dynamic>? _lastBackup;

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
      final list = await listWallets(walletsDir: walletsDir());
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
    final last = await readLastBackupRecord();
    if (!mounted) return;
    setState(() => _lastBackup = last);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Бэкап')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
          child: RefreshIndicator(
            onRefresh: _reload,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    children: [
                      VTwoColumn(
                        left: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildExportCard(context),
                            const SizedBox(height: 16),
                            _buildImportCard(context),
                          ],
                        ),
                        right: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildLastBackupCard(context),
                            const SizedBox(height: 16),
                            _buildIntegrityCard(context),
                            const SizedBox(height: 16),
                            _buildSecurityDetails(context),
                          ],
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

  Widget _buildExportCard(BuildContext context) {
    final hasWallets = _wallets?.isNotEmpty ?? false;
    return VCard(
      icon: Icons.archive_outlined,
      title: 'Экспорт',
      children: [
        Text(
          _error != null
              ? 'Реестр недоступен: $_error'
              : 'Выбранные кошельки — в один зашифрованный файл '
                  '(.veybackup). Для каждого нужен его пароль.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: VButton.primary(
            'Экспорт бэкапа',
            icon: Icons.archive_outlined,
            onPressed: hasWallets
                ? () => showBackupExportDialog(context, wallets: _wallets!)
                : null,
          ),
        ),
      ],
    );
  }

  Widget _buildImportCard(BuildContext context) {
    return VCard(
      icon: Icons.unarchive_outlined,
      title: 'Импорт',
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.folder_outlined),
          title: const Text('Из файла .veybackup'),
          subtitle: const Text('Полный путь + пароль файла'),
          onTap: () => _push(const BackupImportScreen()),
        ),
        const Divider(height: 1),
        ListTile(
          enabled: false,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.qr_code_2),
          title: const Text('По QR'),
          subtitle: const Text('Не реализовано — Android-группа'),
          onTap: null,
        ),
        const Divider(height: 1),
        ListTile(
          enabled: false,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.visibility_outlined),
          title: const Text('Watch-only'),
          subtitle: const Text('Не реализовано в ядре'),
          onTap: null,
        ),
      ],
    );
  }

  /// Состояние последнего резервного копирования: только реальная
  /// локальная запись (пишется после успешного экспорта). Не подменяется
  /// «судьбой» файла: файл мог быть удалён вне приложения.
  Widget _buildLastBackupCard(BuildContext context) {
    final record = _lastBackup;
    return VCard(
      icon: Icons.history_outlined,
      title: 'Последняя резервная копия',
      children: [
        if (record == null)
          Text(
            'Записи нет: экспортов после этой версии сборки не выполнялось. '
            'Запись появляется автоматически после успешного экспорта.',
            style: Theme.of(context).textTheme.bodySmall,
          )
        else ...[
          kvRow(
            'Когда',
            formatWalletDate((record['ts'] as num).toInt()),
          ),
          const SizedBox(height: 6),
          VMonoCopyRow(
            label: 'Файл',
            value: (record['path'] as String?) ?? '—',
          ),
          const SizedBox(height: 6),
          kvRow(
            'Кошельков',
            '${(record['names'] as List?)?.length ?? 0}',
          ),
        ],
      ],
    );
  }

  Widget _buildIntegrityCard(BuildContext context) {
    return VCard(
      icon: Icons.verified_outlined,
      title: 'Проверка целостности',
      children: [
        Text(
          'Содержимое копии проверяется при восстановлении: ядро сверяет '
          'формат файла, поддерживаемую версию и расшифровку — неверный '
          'пароль или повреждённый файл дают отказ, а не молчаливый '
          '«импорт как получится». Отдельного фонового сканера в ядре '
          'нет — и он не имитируется.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  /// Технические детали — раскрывающийся блок (аудит §6: «перенеси в
  /// раскрывающийся блок или отдельную справку»).
  Widget _buildSecurityDetails(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Card(
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: const Icon(Icons.info_outline, color: VColors.textSecondary),
          title: const Text('Технические детали шифрования',
              style: TextStyle(fontSize: 14)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          children: [
            Text(
              'Файл .veybackup шифруется собственным паролем: Argon2id + '
              'XChaCha20-Poly1305 в Rust-ядре. Внутри — фразы и passphrase '
              'выбранных кошельков в зашифрованном виде. Пароль файла не '
              'совпадает с паролями кошельков; при импорте задаётся новый '
              'пароль устройства. Приватные ключи и фразы в UI и логи не '
              'выводятся.',
              style: TextStyle(color: VColors.textSecondary, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) await _reload();
  }
}
