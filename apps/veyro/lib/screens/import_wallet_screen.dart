//! Экран 6 спеки (Wallet import): восстановление кошелька из BIP39-фразы
//! на реальном restoreWallet. Passphrase (25-е слово) — опционально.

import 'package:flutter/material.dart';

import 'package:veyro/design/app_colors.dart';
import 'package:veyro/design/components.dart';
import 'package:veyro/src/rust/api/wallet.dart';
import 'package:veyro/util/app_dirs.dart';
import 'package:veyro/util/l10n.dart';
import 'package:veyro/util/ui_helpers.dart';

import 'dashboard_screen.dart';

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
          content: Text(tf(
            'wallet_restored_snack',
            {'name': restored.name},
          )),
          backgroundColor: VColors.success,
        ),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const DashboardScreen()),
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
      appBar: AppBar(title: Text(t('import_title'))),
      body: VScreen(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            VSectionHeader(
              title: t('import_from_phrase_title'),
              subtitle: t('import_from_phrase_subtitle'),
            ),
            const SizedBox(height: 16),
            VCard(
              icon: Icons.text_fields_outlined,
              title: t('wallet_card'),
              children: [
                TextField(
                  controller: _nameController,
                  autofocus: true,
                  maxLength: 40,
                  decoration: InputDecoration(
                    labelText: t('wallet_name_field'),
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
                    labelText: t('phrase_field'),
                    helperText:
                        wordCount >= 12 && wordCount <= 24
                            ? tf(
                                'words_entered',
                                {'count': '$wordCount'},
                              )
                            : tf(
                                'words_counter',
                                {'count': '$wordCount'},
                              ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passphraseController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: t('passphrase_field'),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
            const SizedBox(height: 16),
            VCard(
              icon: Icons.password_outlined,
              title: t('device_encryption_title'),
              children: [
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration:
                      InputDecoration(labelText: t('password_field')),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirmController,
                  obscureText: true,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration:
                      InputDecoration(labelText: t('password_repeat_field')),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
            const SizedBox(height: 20),
            VButton.primary(
              t('restore_wallet_btn'),
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
