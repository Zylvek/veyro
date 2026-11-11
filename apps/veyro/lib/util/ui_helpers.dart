//! Общие элементы интерфейса: запрос пароля, показ мнемоники, копирование,
//! честный показ ошибок. Никаких фейковых данных — ошибки ядро отдаёт как есть.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Модальный запрос пароля. Возвращает пароль (не пустой) или `null`.
Future<String?> promptPassword(
  BuildContext context, {
  required String title,
  String confirmLabel = 'Продолжить',
}) {
  final controller = TextEditingController();
  var obscure = true;
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: obscure,
          autofillHints: const [AutofillHints.password],
          onSubmitted: (v) =>
              Navigator.of(dialogContext).pop(v.trim().isEmpty ? null : v),
          decoration: InputDecoration(
            labelText: 'Пароль',
            suffixIcon: IconButton(
              icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
              onPressed: () => setDialogState(() => obscure = !obscure),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: controller.text.trim().isEmpty
                ? null
                : () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(confirmLabel),
          ),
        ],
      ),
    ),
  );
}

/// Показ мнемонической фразы (один из немногих секретов, которые легально
/// пересекают границу: пользователь сам попросил «показать»). Копируется
/// только явным действием; в логи не попадает.
Future<void> showMnemonicDialog(BuildContext context, String phrase) {
  final words = phrase.trim().split(RegExp(r'\s+'));
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Seed-фаза'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(dialogContext).colorScheme.outline),
              ),
              child: Wrap(
                spacing: 10,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < words.length; i++)
                    Text(
                      '${i + 1}. ${words[i]}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Запишите фразу на бумаге и храните в безопасном месте. '
              'Кто получит фразу — получит доступ ко всем средствам.',
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: phrase));
            ScaffoldMessenger.of(dialogContext).showSnackBar(
              const SnackBar(content: Text('Фраза скопирована в буфер обмена')),
            );
          },
          icon: const Icon(Icons.copy_outlined),
          label: const Text('Копировать'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Закрыть'),
        ),
      ],
    ),
  );
}

/// Показ разобранного адреса/суммы перед необратимым действием.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: Colors.red.shade700)
              : null,
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Скопировать значение и подтвердить SnackBar'ом.
void copyToClipboard(BuildContext context, String label, String value) {
  Clipboard.setData(ClipboardData(text: value));
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('$label скопировано')),
  );
}

/// Честный показ ошибки ядра — текст от Rust как есть, без приукрашивания.
void showError(BuildContext context, Object error) {
  final cls = Theme.of(context);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Ошибка: $error', style: const TextStyle(color: Colors.white)),
      backgroundColor: Colors.red.shade800,
      duration: const Duration(seconds: 6),
      behavior: SnackBarBehavior.floating,
      action: SnackBarAction(
        label: 'Скрыть',
        textColor: cls.colorScheme.primary,
        onPressed: () {},
      ),
    ),
  );
}

/// Секционная карточка с заголовком — базовый блок всех экранов.
class SectionCard extends StatelessWidget {
  final String title;
  final IconData? icon;
  final EdgeInsets padding;
  final List<Widget> children;

  const SectionCard({
    super.key,
    required this.title,
    this.icon,
    this.padding = const EdgeInsets.all(16),
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: scheme.primary),
                  const SizedBox(width: 8),
                ],
                Text(title, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
          Padding(padding: padding, child: Column(children: children)),
        ],
      ),
    );
  }
}

/// Строка «ключ → значение»; `mono` — выравнивание для хексов/xpub/txid.
Widget kvRow(String key, String value, {bool mono = false, bool long = false}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 150,
          child: Text(key, style: const TextStyle(color: Colors.white60)),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: mono ? const TextStyle(fontFamily: 'monospace') : null,
          ),
        ),
      ],
    ),
  );
}
