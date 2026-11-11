//! Раздел «О VEYRO» (спека, экран 25): бренд, честный статус и открытые
//! лицензии. Никаких заявлений о функциях, которых нет.

import 'package:flutter/material.dart';

import 'package:veyro/design/app_colors.dart';
import 'package:veyro/design/components.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('О VEYRO')),
      body: VScreen(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: const VeyroLogo(size: 84)),
            const SizedBox(height: 16),
            const Text(
              'VEYRO',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                letterSpacing: 5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'YOUR CRYPTO. YOUR CONTROL.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
                color: VColors.secondary,
              ),
            ),
            const SizedBox(height: 16),
            const VCard(
              icon: Icons.workspace_premium_outlined,
              title: 'Принципы',
              children: [
                Text(
                  'VEYRO IS A WALLET, NOT AN EXCHANGE.\n\n'
                  '• Некастодиальность: ключи и фразы только на устройстве.\n'
                  '• Подпись транзакций — в локальном Rust-ядре.\n'
                  '• Никаких обменов, свопов, стейкинга, NFT, DeFi и рекламы '
                  '(ограничения спеки).\n'
                  '• Никаких имитированных данных: пустой раздел значит '
                  '«функция ещё не реализована».',
                  style: TextStyle(color: VColors.textSecondary, height: 1.55),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const VCard(
              icon: Icons.verified_outlined,
              title: 'Текущий статус (честно)',
              children: [
                Text(
                  'Ядро: шифрование секретов (Argon2id + XChaCha20-Poly1305), '
                  'BIP39, зашифрованные бэкапы, SQLite-метаданные.\n'
                  'BTC: «Receive/Send tested on testnet» — полный живой цикл '
                  'на testnet4; Full support не заявляется.\n'
                  'Остальные монеты: реестр статусов в справочном каталоге '
                  'активов; адаптеры добавляются отдельно по решениям '
                  'владельцев.',
                  style: TextStyle(color: VColors.textSecondary, height: 1.55),
                ),
              ],
            ),
            const SizedBox(height: 16),
            VCard(
              icon: Icons.policy_outlined,
              title: 'Лицензии и документация',
              children: [
                TextButton.icon(
                  onPressed: () => showLicensePage(
                    context: context,
                    applicationName: 'VEYRO',
                    applicationVersion: 'разработка (см. docs/PROJECT_STATUS.md)',
                  ),
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: const Text('Открытые лицензии (Flutter, Rust, шрифты)'),
                ),
                Text(
                  'Шрифты: Inter и JetBrains Mono под SIL OFL (файлы в '
                  'assets/fonts, лицензии рядом).',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
