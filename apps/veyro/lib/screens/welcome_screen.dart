//! Экран 1 (спека: Welcome). Бренд-блок + честный статус интеграции ядра +
//! реальные входы: создание кошелька, импорт из фразы, каталог кошельков
//! (если они есть), импорт зашифрованного бэкапа. Фейковые балансы и
//! «быстрые демо» запрещены спекой.

import 'package:flutter/material.dart';

import 'package:veyro/design/app_colors.dart';
import 'package:veyro/design/components.dart';
import 'package:veyro/src/rust/api/wallet.dart';
import 'package:veyro/util/app_dirs.dart';

import 'create_wallet_flow.dart';
import 'import_backup_screens.dart';
import 'import_wallet_screen.dart';
import '../navigation/app_shell.dart';

/// Welcome. `walletCountLoader` — точка замены в виджет-тестах (нормально
/// возвращает реальный реестр; тест передаёт статическую функцию).
class WelcomeScreen extends StatefulWidget {
  final Future<int?> Function()? walletCountLoader;

  const WelcomeScreen({super.key, this.walletCountLoader});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  int? _walletCount;
  bool _counting = true;

  @override
  void initState() {
    super.initState();
    _loadWalletCount();
  }

  Future<void> _loadWalletCount() async {
    setState(() {
      _counting = true;
      _walletCount = null;
    });
    try {
      final loader = widget.walletCountLoader ??
          () async => (await listWallets(walletsDir: walletsDir())).length;
      final count = await loader();
      if (!mounted) return;
      setState(() {
        _walletCount = count;
        _counting = false;
      });
    } catch (_) {
      // Реестр недоступен (например, ядро без базы) — Welcome продолжает
      // работать: кнопки создания и импорта не зависят от реестра.
      if (!mounted) return;
      setState(() {
        _walletCount = null;
        _counting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasWallets = (_walletCount ?? 0) > 0;
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          color: VColors.background,
          gradient: RadialGradient(
            center: const Alignment(-0.75, -0.65),
            radius: 1.1,
            colors: [
              VColors.primaryGlow.withValues(alpha: 0.14),
              VColors.background,
            ],
            stops: const [0, 1],
          ),
        ),
        child: SafeArea(
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
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Некастодиальный мультивалютный кошелёк.\n'
                      'Ядро — Rust, подпись транзакций — локально.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 22),
                    const Center(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          VStatusChip('Ядро: FFI подключено', kind: VChipKind.success),
                          VStatusChip('BTC: Send — проверено на testnet', kind: VChipKind.info),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    if (_counting)
                      const Center(child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (hasWallets) ...[
                            VButton.primary(
                              'Войти в кошелёк',
                              icon: Icons.login,
                              onPressed: () => _openShell(),
                            ),
                            const SizedBox(height: 10),
                          ],
                          VButton.primary(
                            'Создать кошелёк',
                            icon: Icons.add_circle_outline,
                            onPressed: () => _push(const CreateWalletFlow()),
                          ),
                          const SizedBox(height: 10),
                          VButton.secondary(
                            'Импорт кошелька из фразы',
                            icon: Icons.restore_outlined,
                            onPressed: () => _push(const ImportWalletScreen()),
                          ),
                          const SizedBox(height: 10),
                          TextButton.icon(
                            onPressed: () =>
                                _push(const BackupImportScreen()),
                            icon: const Icon(Icons.unarchive_outlined, size: 18),
                            label: const Text('Импорт зашифрованного бэкапа'),
                          ),
                        ],
                      ),
                    const SizedBox(height: 30),
                    Text(
                      'Адреса и балансы отображаются только на сетях с '
                      'реализованными адаптерами. Остальные активы — '
                      'справочно, после своих обновлений.\n'
                      'Секреты не покидают устройство.',
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
      ),
    );
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) await _loadWalletCount();
  }

  void _openShell() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const VeyroShell()),
      (route) => false,
    );
  }
}
