//! Экран 1 (спека: Welcome). Бренд-блок + реальные входы: создание
//! кошелька, импорт из фразы, вход в каркас (если кошельки есть), импорт
//! зашифрованного бэкапа. Фейковые балансы и «быстрые демо» запрещены
//! спекой; технические статусы ядра на бренд-экране не показываются
//! (решение владельца — не шуметь техникой на первом экране).

import 'package:flutter/material.dart';

import 'package:veyro/design/app_colors.dart';
import 'package:veyro/design/components.dart';
import 'package:veyro/src/rust/api/wallet.dart';
import 'package:veyro/util/app_dirs.dart';
import 'package:veyro/util/l10n.dart';

import 'create_wallet_flow.dart';
import 'import_wallet_screen.dart';
import 'dashboard_screen.dart';

/// Welcome. `walletCountLoader` — точка замены в виджет-тестах (нормально
/// возвращает реальный реестр; тест передаёт статическую функцию).
class WelcomeScreen extends StatefulWidget {
  final Future<int?> Function()? walletCountLoader;

  const WelcomeScreen({super.key, this.walletCountLoader});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _counting = true;

  @override
  void initState() {
    super.initState();
    _loadWalletCount();
  }

  Future<void> _loadWalletCount() async {
    setState(() => _counting = true);
    try {
      final loader = widget.walletCountLoader ??
          () async => (await listWallets(walletsDir: walletsDir())).length;
      final count = await loader();
      if (!mounted) return;
      setState(() => _counting = false);
      // Сразу в кошелёк (решение владельца): если кошельки есть, Welcome
      // показывать не нужно — перебрасываем в каркас (кошелёк далее
      // сам откроется и запросит пароль). Один раз на вход в Welcome.
      if (count != null && count > 0 && mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const DashboardScreen()),
          (route) => false,
        );
      }
    } catch (_) {
      // Реестр недоступен (например, ядро без базы) — Welcome продолжает
      // работать: кнопки создания и импорта не зависят от реестра.
      if (!mounted) return;
      setState(() => _counting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 24),
                    Center(child: const VeyroLogo(size: 96)),
                    const SizedBox(height: 20),
                    const Text(
                      'VEYRO',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 8,
                        color: VColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'YOUR CRYPTO. YOUR CONTROL.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2.4,
                        color: VColors.secondary,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 28),
                    if (_counting)
                      const Center(child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // «Войти в кошелёк» не нужен: при наличии
                          // кошельков Welcome сразу перебрасывает в каркас
                          // (решение владельца).
                          VButton.primary(
                            t('welcome_create'),
                            icon: Icons.add_circle_outline,
                            onPressed: () => _push(const CreateWalletFlow()),
                          ),
                          const SizedBox(height: 10),
                          VButton.secondary(
                            t('welcome_import_phrase'),
                            icon: Icons.restore_outlined,
                            onPressed: () => _push(const ImportWalletScreen()),
                          ),
                        ],
                      ),
                    const SizedBox(height: 30),
                    Text(
                      t('welcome_note'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall!
                          .copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ),
          ),
    );
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) await _loadWalletCount();
  }
}
