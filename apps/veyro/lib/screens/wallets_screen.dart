//! Экран 1: список кошельков — реестр (list_wallets из ядра), создание нового
//! кошелька (мнемоника показывается ровно один раз), восстановление из фразы.
//! Выбор кошелька открывает портфель. Все данные из ядра, без моков.

import 'package:flutter/material.dart';

import 'package:veyro/src/rust/api/wallet.dart';
import 'package:veyro/util/app_dirs.dart';
import 'package:veyro/util/ui_helpers.dart';

import 'portfolio_screen.dart';

class WalletsScreen extends StatefulWidget {
  const WalletsScreen({super.key});

  @override
  State<WalletsScreen> createState() => _WalletsScreenState();
}

class _WalletsScreenState extends State<WalletsScreen> {
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

  Future<void> _createWallet() async {
    final nameController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    var wordCount = 24;

    await showDialog<CreatedWalletDto>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Новый кошелёк'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Название'),
                  onChanged: (_) => setDialogState(() {}),
                ),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Пароль'),
                  onChanged: (_) => setDialogState(() {}),
                ),
                TextField(
                  controller: confirmController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Повтор пароля'),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: wordCount,
                  decoration: const InputDecoration(labelText: 'Длина мнемоники'),
                  items: const [
                    DropdownMenuItem(value: 12, child: Text('12 слов')),
                    DropdownMenuItem(value: 24, child: Text('24 слова')),
                  ],
                  onChanged: (v) => setDialogState(() => wordCount = v ?? 24),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: passwordController.text.isEmpty ||
                      passwordController.text != confirmController.text
                  ? null
                  : () async {
                      final name = nameController.text.trim();
                      if (name.isEmpty) return;
                      Navigator.of(dialogContext).pop();
                      try {
                        final result = await createWallet(
                          walletsDir: walletsDir(),
                          name: name,
                          password: passwordController.text,
                          wordCount: wordCount,
                        );
                        if (!mounted) return;
                        passwordController.text = '';
                        confirmController.text = '';
                        await showMnemonicDialog(context, result.mnemonicPhrase);
                        await _reload();
                      } catch (e) {
                        if (!mounted) return;
                        showError(context, e);
                      }
                    },
              child: const Text('Создать'),
            ),
          ],
        ),
      ),
    );
    // created обрабатывается внутри диалога; переменная не нужна.
  }

  Future<void> _restoreWallet() async {
    final nameController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    final phraseController = TextEditingController();
    final passphraseController = TextEditingController();

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Восстановить кошелёк'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Название'),
              ),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Пароль'),
              ),
              TextField(
                controller: confirmController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Повтор пароля'),
              ),
              TextField(
                controller: phraseController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'BIP39-фраза (12 или 24 слова)',
                ),
              ),
              TextField(
                controller: passphraseController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Passphrase (25-е слово, необязательно)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: passwordController.text.isEmpty ||
                    passwordController.text != confirmController.text ||
                    phraseController.text.trim().isEmpty
                ? null
                : () async {
                    Navigator.of(dialogContext).pop();
                    try {
                      await restoreWallet(
                        walletsDir: walletsDir(),
                        name: nameController.text.trim(),
                        password: passwordController.text,
                        phrase: phraseController.text.trim(),
                        passphrase: passphraseController.text,
                      );
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Кошелёк восстановлен')),
                      );
                      await _reload();
                    } catch (e) {
                      if (!mounted) return;
                      showError(context, e);
                    }
                  },
            child: const Text('Восстановить'),
          ),
        ],
      ),
    );
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
      appBar: AppBar(title: const Text('Кошельки')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          showModalBottomSheet<void>(
            context: context,
            builder: (sheetContext) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.add_circle_outline),
                    title: const Text('Создать новый кошелёк'),
                    subtitle: const Text('Новая мнемоника, показывается один раз'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _createWallet();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.restore_outlined),
                    title: const Text('Восстановить из фразы'),
                    subtitle: const Text('Существующая BIP39-мнемоника'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _restoreWallet();
                    },
                  ),
                ],
              ),
            ),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Добавить'),
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
    if (wallets.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.account_balance_wallet_outlined,
                size: 48, color: Colors.white38),
            const SizedBox(height: 12),
            const Text(
              'Кошельков пока нет',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 6),
            const Text(
              'Создайте новый кошелёк или восстановите существующий '
              'из BIP39-фразы.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: wallets.length,
      itemBuilder: (itemContext, index) {
        final info = wallets[index];
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(itemContext).colorScheme.primaryContainer,
              child: Text(
                info.name.isEmpty ? '?' : info.name.characters.first.toUpperCase(),
                style: TextStyle(
                  color: Theme.of(itemContext).colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            title: Text(info.name),
            subtitle: Text('ID: ${info.id.substring(0, info.id.length.clamp(0, 8))}…'),
            trailing: IconButton(
              tooltip: 'Показать seed-фразу',
              icon: const Icon(Icons.key_outlined),
              onPressed: () => _revealMnemonic(info),
            ),
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => PortfolioScreen(info: info),
              ));
              // Состояние могло измениться (открыта/закрыта BTC-сессия).
              if (mounted) await _reload();
            },
          ),
        );
      },
    );
  }
}
