//! Экраны вариантов импорта по спеке:
//! 7 — Encrypted backup import (реальный, поверх BackupImportForm);
//! 8 — QR backup import (нужен модуль сканирования; честно помечен);
//! 9 — Watch-only import (не реализован в ядре; имитация запрещена).
//!
//! Правило спеки «Clearly mark unavailable functionality» соблюдено:
//! недоступные сценарии объясняют причину, кнопки блокированы.

import 'package:flutter/material.dart';

import 'package:veyro/design/components.dart';

import 'dashboard_screen.dart';
import 'backup_screens.dart';

/// Экран 7: импорт зашифрованного бэкапа из файла — реальная функция моста.
class BackupImportScreen extends StatelessWidget {
  const BackupImportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Импорт бэкапа')),
      body: VScreen(
        child: BackupImportForm(
          doneLabel: 'В кошельки',
          onDone: () {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute<void>(builder: (_) => const DashboardScreen()),
              (route) => false,
            );
          },
        ),
      ),
    );
  }
}

/// Экран 8: импорт бэкапа по QR. Требует камеры и модуля сканирования
/// (мобильная группа). На desktop недоступен по определению. НЕ имитируем.
class QrBackupImportScreen extends StatelessWidget {
  const QrBackupImportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Импорт бэкапа по QR')),
      body: VScreen(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const VSectionHeader(
              title: 'QR-сценарий появится в мобильной группе',
              subtitle: 'Экран готов принять функцию, когда в проекте '
                  'появится проверенный модуль сканирования.',
            ),
            const SizedBox(height: 16),
            VCard(
              icon: Icons.qr_code_2,
              title: 'Что планируется',
              children: [
                Text(
                  'Файл .veybackup — длинная зашифрованная байтовая '
                  'последовательность. Перенос по QR планируется как '
                  'серия QR-кадров (чанкование) с контрольными суммами: '
                  'в одном кадре файл не помещается. Секреты остаются '
                  'шифрованными: QR несёт только сам файл, пароли '
                  'вводятся вручную.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const Divider(height: 24),
                Text(
                  'Статус по платформам: Windows — без камеры недоступен; '
                  'Android — требуется интеграция сканера (следующие '
                  'мобильные шаги). До этого момента кнопка заблокирована.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                const VButton.secondary('Сканировать QR', icon: Icons.center_focus_weak),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Экран 9: watch-only импорт. Ядро не реализует импорт расширенного
/// публичного ключа (xpub) — экран честно объясняет статус.
class WatchOnlyImportScreen extends StatelessWidget {
  const WatchOnlyImportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Watch-only импорт')),
      body: VScreen(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const VSectionHeader(
              title: 'Watch-only не реализован в ядре',
              subtitle: 'Спека запрещает фейковые индикаторы и имитацию '
                  'функциональности — экран пока объясняет статус.',
            ),
            const SizedBox(height: 16),
            VCard(
              icon: Icons.visibility_outlined,
              title: 'Что отсутствует',
              children: [
                Text(
                  'Watch-only для BTC требует в Rust-ядре: импорт/наследование '
                  'xpub (без секретного ключа), сканирование адресов от '
                  'чужого xpub и сборку неподписанных транзакций для '
                  'внешней подписи. В ядре реализована подпись от исходной '
                  'фразы (BIP84), этот путь ещё не строился.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const Divider(height: 24),
                Text(
                  'Когда режим будет реализован в ядре, экран станет '
                  'рабочим: адрес получателя, сеть и сумма с честной '
                  'подписью «только мониторинг, без переводов».',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                const VStatusChip('Недоступно в текущей версии', kind: VChipKind.warning),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
