//! Общие элементы интерфейса: запрос пароля, показ мнемоники, копирование,
//! честный показ ошибок. Никаких фейковых данных — ошибки ядро отдаёт как есть.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:veyro/design/components.dart';
import 'package:veyro/util/l10n.dart';

/// Модальный запрос пароля. Возвращает пароль (не пустой) или `null`.
/// Кнопка подтверждения оживает прямо при наборе: на каждый ввод текста
/// диалог перерисовывается (раньше кнопка оставалась серой, пока её
/// случайно не тронешь глазик — перерисовку дёргал только он).
///
/// Гигиена секрета: контроллер освобождается сразу после закрытия диалога —
/// строка пароля выпадает из памяти UI как можно раньше (секрет честно
/// пересекает FFI по контракту, но Dart-копия не должна жить дольше нужного).
Future<String?> promptPassword(
  BuildContext context, {
  required String title,
  String confirmLabel = '',
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
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.password],
          onChanged: (_) => setDialogState(() {}),
          onSubmitted: (v) =>
              Navigator.of(dialogContext).pop(v.trim().isEmpty ? null : v),
          decoration: InputDecoration(
            labelText: t('password_prompt'),
            hintText: t('password_hint'),
            suffixIcon: IconButton(
              icon: Icon(
                obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              onPressed: () => setDialogState(() => obscure = !obscure),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(t('cancel')),
          ),
          FilledButton(
            onPressed: controller.text.trim().isEmpty
                ? null
                : () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(
              confirmLabel.isEmpty ? t('continue_default') : confirmLabel,
            ),
          ),
        ],
      ),
    ),
  ).whenComplete(controller.dispose);
}

/// Показ мнемонической фразы (один из немногих секретов, которые легально
/// пересекают границу: пользователь сам попросил «показать»). Сетка 4×6
/// в красивых окошках, на телефоне — две колонки; без кнопки копирования
/// (решение владельца: слова переписывают руками).
Future<void> showMnemonicDialog(BuildContext context, String phrase) {
  final words = phrase.trim().split(RegExp(r'\s+'));
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(t('mnemonic_dialog_title')),
      content: SingleChildScrollView(child: VMnemonicGrid(words: words)),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(t('close_btn')),
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
          child: Text(t('cancel')),
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
    SnackBar(content: Text(tf('copied_snackbar', {'label': label}))),
  );
}

/// Честный показ ошибки ядра — текст от Rust как есть, без приукрашивания.
void showError(BuildContext context, Object error) {
  final cls = Theme.of(context);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        tf('error_prefix', {'error': '$error'}),
        style: const TextStyle(color: Colors.white),
      ),
      backgroundColor: Colors.red.shade800,
      duration: const Duration(seconds: 6),
      behavior: SnackBarBehavior.floating,
      action: SnackBarAction(
        label: t('dismiss_snackbar'),
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
          Padding(
            padding: padding,
            child: Column(children: children),
          ),
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
