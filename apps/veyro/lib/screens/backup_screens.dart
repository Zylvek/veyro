//! Резервное копирование: экспорт выбранных кошельков в один зашифрованный
//! файл (.veybackup) и импорт на это устройство. Поверх реальных FFI-вызовов
//! моста (api/backup.rs); секреты через FFI не проходят — только вводимые
//! пароли.
//!
//! Договор паролей (см. rust/crates/backup_manager):
//! - экспорт требует пароль КАЖДОГО выбранного кошелька (его vault один
//!   последний раз расшифровывается внутри Rust) и ОТДЕЛЬНЫЙ пароль самого
//!   файла бэкапа;
//! - импорт требует пароль файла и НОВЫЙ пароль устройства, общий для всех
//!   импортированных кошельков.
//!
//! Форма импорта (BackupImportForm) используется и диалогом, и
//! полноэкранным сценарием import_backup_screens.dart.

import 'dart:io';

import 'package:flutter/material.dart';

import 'package:veyro/design/components.dart';
import 'package:veyro/src/rust/api/backup.dart';
import 'package:veyro/src/rust/api/wallet.dart';
import 'package:veyro/util/app_dirs.dart';
import 'package:veyro/util/ui_helpers.dart';

/// Экспорт: мультиселект кошельков с паролем для каждого выбранного, затем
/// пароль файла (дважды) и полный путь к файлу. Каталог создаётся рекурсивно:
/// Rust пишет файл обычной `fs::write` и родителей не создаёт.
Future<void> showBackupExportDialog(
  BuildContext context, {
  required List<WalletInfoDto> wallets,
}) {
  final selectedIds = <String>{};
  final passwordControllers = <String, TextEditingController>{};
  final backupPasswordController = TextEditingController();
  final backupConfirmController = TextEditingController();
  // Предзаполнение: каталог бэкапов приложения, имя с меткой времени.
  // Пользователь может заменить путь (например, на флешку или Documents).
  final pathController = TextEditingController(text: defaultBackupPath());
  var busy = false;

  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        final valid = selectedIds.isNotEmpty &&
            passwordControllers.entries
                .where((e) => selectedIds.contains(e.key))
                .every((e) => e.value.text.isNotEmpty) &&
            backupPasswordController.text.isNotEmpty &&
            backupConfirmController.text == backupPasswordController.text &&
            pathController.text.trim().isNotEmpty;

        return AlertDialog(
          title: const Text('Экспорт бэкапа'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Файл защищается отдельным паролем. Пароль каждого '
                    'выбранного кошелька нужен, чтобы последний раз '
                    'расшифровать его хранилище и включить фразу в копию.',
                    style: TextStyle(fontSize: 12, color: Colors.white60),
                  ),
                  const SizedBox(height: 10),
                  if (wallets.isEmpty)
                    const Text('Кошельков нет — экспортировать нечего.'),
                  for (final wallet in wallets) ...[
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: selectedIds.contains(wallet.id),
                      title: Text(wallet.name),
                      subtitle: Text(
                        'ID: ${wallet.id.substring(0, wallet.id.length.clamp(0, 8))}…',
                      ),
                      onChanged: busy
                          ? null
                          : (checked) => setDialogState(() {
                                if (checked ?? false) {
                                  selectedIds.add(wallet.id);
                                  passwordControllers.putIfAbsent(
                                    wallet.id,
                                    TextEditingController.new,
                                  );
                                } else {
                                  selectedIds.remove(wallet.id);
                                }
                              }),
                    ),
                    if (selectedIds.contains(wallet.id))
                      Padding(
                        padding: const EdgeInsets.fromLTRB(32, 0, 0, 8),
                        child: TextField(
                          controller: passwordControllers[wallet.id],
                          obscureText: true,
                          enabled: !busy,
                          autofillHints: const [AutofillHints.password],
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: 'Пароль кошелька «${wallet.name}»',
                          ),
                          onChanged: (_) => setDialogState(() {}),
                        ),
                      ),
                  ],
                  const Divider(height: 24),
                  TextField(
                    controller: backupPasswordController,
                    obscureText: true,
                    enabled: !busy,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: const InputDecoration(
                      labelText: 'Пароль файла бэкапа',
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  TextField(
                    controller: backupConfirmController,
                    obscureText: true,
                    enabled: !busy,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: const InputDecoration(
                      labelText: 'Повтор пароля файла',
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: pathController,
                    enabled: !busy,
                    decoration: const InputDecoration(
                      labelText: 'Файл бэкапа (полный путь)',
                      helperText: 'Каталог будет создан при необходимости',
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.of(dialogContext).pop(),
              child: const Text('Отмена'),
            ),
            FilledButton.icon(
              onPressed: (valid && !busy)
                  ? () async {
                      final outPath = pathController.text.trim();
                      final requests = [
                        for (final wallet in wallets)
                          if (selectedIds.contains(wallet.id))
                            BackupWalletRequest(
                              walletId: wallet.id,
                              password: passwordControllers[wallet.id]!.text,
                            ),
                      ];
                      setDialogState(() => busy = true);
                      try {
                        if (await File(outPath).exists()) {
                          if (!dialogContext.mounted) return;
                          final overwrite = await confirmAction(
                            dialogContext,
                            title: 'Файл существует',
                            body: 'Файл\n$outPath\nбудет перезаписан.',
                            confirmLabel: 'Перезаписать',
                            destructive: true,
                          );
                          if (!overwrite) {
                            if (!dialogContext.mounted) return;
                            setDialogState(() => busy = false);
                            return;
                          }
                        }
                        await File(outPath).parent.create(recursive: true);
                        await exportBackup(
                          walletsDir: walletsDir(),
                          requests: requests,
                          backupPassword: backupPasswordController.text,
                          outPath: outPath,
                        );
                        if (!dialogContext.mounted) return;
                        Navigator.of(dialogContext).pop();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Резервная копия сохранена: $outPath'),
                          ),
                        );
                      } catch (e) {
                        if (!dialogContext.mounted) return;
                        setDialogState(() => busy = false);
                        showError(dialogContext, e);
                      }
                    }
                  : null,
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.archive_outlined),
              label: const Text('Экспортировать'),
            ),
          ],
        );
      },
    ),
  );
}

/// Форма импорта бэкапа (экран 7 спеки). После успеха показывает честный
/// список импортированных кошельков и действие [onDone] («Готово»).
class BackupImportForm extends StatefulWidget {
  /// Метка финального действия (например «Готово» / «В кошельки»).
  final String doneLabel;

  /// Действие после успешного импорта. null — действие не показывается.
  final VoidCallback? onDone;

  const BackupImportForm({super.key, required this.doneLabel, this.onDone});

  @override
  State<BackupImportForm> createState() => _BackupImportFormState();
}

class _BackupImportFormState extends State<BackupImportForm> {
  final _pathController = TextEditingController();
  final _backupPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmController = TextEditingController();
  List<WalletInfoDto>? _imported;
  var _busy = false;

  @override
  void dispose() {
    _pathController.dispose();
    _backupPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool get _valid =>
      _pathController.text.trim().isNotEmpty &&
      _backupPasswordController.text.isNotEmpty &&
      _newPasswordController.text.isNotEmpty &&
      _confirmController.text == _newPasswordController.text;

  Future<void> _import() async {
    if (_busy || !_valid) return;
    setState(() => _busy = true);
    try {
      final list = await importBackup(
        walletsDir: walletsDir(),
        backupPath: _pathController.text.trim(),
        backupPassword: _backupPasswordController.text,
        newWalletPassword: _newPasswordController.text,
      );
      if (!mounted) return;
      setState(() {
        _imported = list;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final imported = _imported;
    if (imported != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          VCard(
            icon: Icons.check_circle_outline,
            title: 'Импортировано кошельков: ${imported.length}',
            children: [
              for (final wallet in imported)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: Text(wallet.name),
                  subtitle: Text(
                    'ID: ${wallet.id.substring(0, wallet.id.length.clamp(0, 8))}…',
                  ),
                ),
              const Divider(height: 24),
              Text(
                'Все импортированные кошельки получили новый пароль этого '
                'устройства. Файл бэкапа можно удалить, когда убедитесь, '
                'что кошельки открываются.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (widget.onDone != null)
            FilledButton(
              onPressed: widget.onDone,
              child: Text(widget.doneLabel),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Кошельки из зашифрованного файла восстанавливаются в хранилище '
          'этого устройства с НОВЫМ паролем — общим для всех импортированных.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        VCard(
          icon: Icons.unarchive_outlined,
          title: 'Файл бэкапа',
          children: [
            TextField(
              controller: _pathController,
              enabled: !_busy,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Полный путь к файлу .veybackup',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _backupPasswordController,
              obscureText: true,
              enabled: !_busy,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(
                labelText: 'Пароль файла бэкапа',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
        const SizedBox(height: 16),
        VCard(
          icon: Icons.password_outlined,
          title: 'Новый пароль кошельков',
          children: [
            TextField(
              controller: _newPasswordController,
              obscureText: true,
              enabled: !_busy,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(
                labelText: 'Новый пароль (для всех импортированных)',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmController,
              obscureText: true,
              enabled: !_busy,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(labelText: 'Повтор пароля'),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: (_valid && !_busy) ? _import : null,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.unarchive_outlined),
          label: const Text('Импортировать'),
        ),
      ],
    );
  }
}

/// Диалог импорта поверх той же формы (используется экраном кошельков).
Future<void> showBackupImportDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Импорт бэкапа'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: BackupImportForm(
            doneLabel: 'Готово',
            onDone: () => Navigator.of(dialogContext).pop(),
          ),
        ),
      ),
    ),
  );
}
