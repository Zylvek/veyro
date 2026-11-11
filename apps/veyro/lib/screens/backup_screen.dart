//! Раздел-хаб «Бэкап» (спека, экраны 7/20 + вход в экспорт). Реальные
//! функции моста + честные объяснения. Кошельки читаются из ядра
//! (listWallets) — экспорт недоступен, если реестр пуст или не читается.

import 'package:flutter/material.dart';

import 'package:veyro/design/app_colors.dart';
import 'package:veyro/design/components.dart';
import 'package:veyro/src/rust/api/wallet.dart';
import 'package:veyro/util/app_dirs.dart';

import 'backup_screens.dart';
import 'import_backup_screens.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  List<WalletInfoDto>? _wallets;
  String? _error;
  bool _loading = true;

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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Бэкап')),
      body: VScreen(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const VSectionHeader(
                title: 'Резервное копирование',
                subtitle: 'Зашифрованная копия фраз и настроек кошельков — '
                    'единственный способ восстановить доступ без фразы '
                    'на руках.',
              ),
              const SizedBox(height: 16),
              VCard(
                icon: Icons.archive_outlined,
                title: 'Экспорт',
                children: [
                  Text(
                    _loading
                        ? 'Читаю реестр…'
                        : _error != null
                            ? 'Реестр недоступен: $_error'
                            : 'Кошельков в реестре: ${_wallets?.length ?? 0}. '
                                'Экспорт включает выбранные кошельки, для '
                                'каждого нужен его пароль.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (!_loading &&
                      _error == null &&
                      (_wallets?.isNotEmpty ?? false)) ...[
                    const SizedBox(height: 12),
                    VButton.primary(
                      'Экспорт бэкапа',
                      icon: Icons.archive_outlined,
                      onPressed: () => showBackupExportDialog(
                        context,
                        wallets: _wallets!,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              VCard(
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
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.qr_code_2),
                    title: const Text('По QR'),
                    subtitle: const Text('Мобильная группа — честная заглушка'),
                    onTap: () => _push(const QrBackupImportScreen()),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.visibility_outlined),
                    title: const Text('Watch-only'),
                    subtitle: const Text('Не реализовано в ядре'),
                    onTap: () => _push(const WatchOnlyImportScreen()),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const VCard(
                icon: Icons.info_outline,
                title: 'Как это работает',
                children: [
                  Text(
                    'Файл .veybackup шифруется отдельным паролем:'
                    'Argon2id + XChaCha20-Poly1305 в Rust-ядре. Внутри — '
                    'фразы и passphrase выбранных кошельков в зашифрованном '
                    'виде. Пароль файла не совпадает с паролями кошельков; '
                    'при импорте задаётся новый пароль устройства.',
                    style: TextStyle(color: VColors.textSecondary, height: 1.5),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) await _reload();
  }
}
