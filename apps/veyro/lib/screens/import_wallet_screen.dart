//! Экран 6 спеки (Wallet import): восстановление кошелька из BIP39-фразы
//! на реальном restoreWallet. Passphrase (25-е слово) — опционально.

import 'package:flutter/material.dart';

import 'package:veyro/design/app_colors.dart';
import 'package:veyro/design/components.dart';
import 'package:veyro/src/rust/api/wallet.dart';
import 'package:veyro/util/app_dirs.dart';
import 'package:veyro/util/ui_helpers.dart';

import '../navigation/app_shell.dart';

class ImportWalletScreen extends StatefulWidget {
  const ImportWalletScreen({super.key});

  @override
  State<ImportWalletScreen> createState() => _ImportWalletScreenState();
}

class _ImportWalletScreenState extends State<ImportWalletScreen> {
  final _nameController = TextEditingController();
  final _phraseController = TextEditingController();
  final _passphraseController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  var _busy = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phraseController.dispose();
    _passphraseController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool get _valid =>
      _nameController.text.trim().isNotEmpty &&
      _phraseController.text.trim().split(RegExp(r'\s+')).length >= 12 &&
      _phraseController.text.trim().split(RegExp(r'\s+')).length <= 24 &&
      _passwordController.text.isNotEmpty &&
      _passwordController.text == _confirmController.text;

  Future<void> _restore() async {
    if (_busy || !_valid) return;
    setState(() => _busy = true);
    try {
      final restored = await restoreWallet(
        walletsDir: walletsDir(),
        name: _nameController.text.trim(),
        password: _passwordController.text,
        phrase: _phraseController.text.trim(),
        passphrase: _passphraseController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Кошелёк «${restored.name}» восстановлен'),
          backgroundColor: VColors.success,
        ),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const VeyroShell()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wordCount =
        _phraseController.text.trim().split(RegExp(r'\s+')).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Импорт кошелька')),
      body: VScreen(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const VSectionHeader(
              title: 'Восстановление из фразы',
              subtitle: 'Собственный BIP39-фразы достаточно для полного '
                  'восстановления. Фраза остаётся на устройстве.',
            ),
            const SizedBox(height: 16),
            VCard(
              icon: Icons.text_fields_outlined,
              title: 'Кошелёк',
              children: [
                TextField(
                  controller: _nameController,
                  autofocus: true,
                  maxLength: 40,
                  decoration: const InputDecoration(
                    labelText: 'Название кошелька',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phraseController,
                  maxLines: 3,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'BIP39-фраза (12 или 24 слова)',
                    helperText: wordCount >= 12 && wordCount <= 24
                        ? 'Слов введено: $wordCount'
                        : 'Слов: $wordCount — нужно 12 или 24',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passphraseController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Passphrase (25-е слово, необязательно)',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
            const SizedBox(height: 16),
            VCard(
              icon: Icons.password_outlined,
              title: 'Шифрование на этом устройстве',
              children: [
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: const InputDecoration(labelText: 'Пароль'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirmController,
                  obscureText: true,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: const InputDecoration(labelText: 'Повтор пароля'),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
            const SizedBox(height: 20),
            VButton.primary(
              'Восстановить кошелёк',
              icon: Icons.restore_outlined,
              busy: _busy,
              onPressed: _valid ? _restore : null,
            ),
          ],
        ),
      ),
    );
  }
}
