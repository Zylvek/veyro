//! Резервное копирование: экспорт выбранных кошельков в один зашифрованный
//! файл (.veybackup) и импорт на это устройство. Поверх реальных FFI-вызовов
//! моста (api/backup.rs); секреты через FFI не проходят — только вводимые
//! пароли.
//!
//! Договор паролей (см. rust/crates/backup_manager):
//! - экспорт требует пароль КАЖДОГО выбранного кошелька (его vault один
//!   последний раз расшифровывается внутри Rust) и ОТДЕЛЬНЫЙ пароль самого
//!   файла бэкапа, независимый от паролей кошельков;
//! - импорт требует пароль файла и НОВЫЙ пароль устройства, общий для всех
//!   импортированных кошельков.

import 'dart:io';

import 'package:flutter/material.dart';

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

/// Импорт: полный путь к файлу, пароль файла, новый пароль кошельков этого
/// устройства (общий для всех импортированных). После успеха показывает
/// список импортированных; реестр обновляет вызывающий экран.
Future<void> showBackupImportDialog(BuildContext context) async {
  final pathController = TextEditingController();
  final backupPasswordController = TextEditingController();
  final newPasswordController = TextEditingController();
  final confirmController = TextEditingController();
  List<WalletInfoDto>? imported;
  var busy = false;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        final result = imported;
        if (result != null) {
          return AlertDialog(
            title: Text('Импортировано кошельков: ${result.length}'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final wallet in result)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.account_balance_wallet_outlined),
                      title: Text(wallet.name),
                      subtitle: Text(
                        'ID: ${wallet.id.substring(0, wallet.id.length.clamp(0, 8))}…',
                      ),
                    ),
                  const SizedBox(height: 8),
                  const Text(
                    'Все импортированные кошельки получили новый пароль '
                    'этого устройства. Файл бэкапа можно удалить, когда '
                    'убедитесь, что кошельки открываются.',
                    style: TextStyle(fontSize: 12, color: Colors.white60),
                  ),
                ],
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Готово'),
              ),
            ],
          );
        }

        final valid = pathController.text.trim().isNotEmpty &&
            backupPasswordController.text.isNotEmpty &&
            newPasswordController.text.isNotEmpty &&
            confirmController.text == newPasswordController.text;

        return AlertDialog(
          title: const Text('Импорт бэкапа'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Кошельки из зашифрованного файла перезаписываются в '
                    'хранилище этого устройства с НОВЫМ паролем — общим '
                    'для всех импортированных.',
                    style: TextStyle(fontSize: 12, color: Colors.white60),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: pathController,
                    enabled: !busy,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Файл бэкапа (полный путь)',
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  TextField(
                    controller: backupPasswordController,
                    obscureText: true,
                    enabled: !busy,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(
                      labelText: 'Пароль файла бэкапа',
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  TextField(
                    controller: newPasswordController,
                    obscureText: true,
                    enabled: !busy,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: const InputDecoration(
                      labelText: 'Новый пароль кошельков',
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  TextField(
                    controller: confirmController,
                    obscureText: true,
                    enabled: !busy,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: const InputDecoration(
                      labelText: 'Повтор нового пароля',
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
                      setDialogState(() => busy = true);
                      try {
                        final list = await importBackup(
                          walletsDir: walletsDir(),
                          backupPath: pathController.text.trim(),
                          backupPassword: backupPasswordController.text,
                          newWalletPassword: newPasswordController.text,
                        );
                        if (!dialogContext.mounted) return;
                        setDialogState(() {
                          imported = list;
                          busy = false;
                        });
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
                  : const Icon(Icons.unarchive_outlined),
              label: const Text('Импортировать'),
            ),
          ],
        );
      },
    ),
  );
}
