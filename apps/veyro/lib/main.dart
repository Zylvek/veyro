//! Точка входа VEYRO. Только подключение ядра и сборка MaterialApp на
//! утверждённой теме; экраны живут в screens/, каркас — в navigation/.

import 'package:flutter/material.dart';

import 'package:veyro/design/v_theme.dart';
import 'package:veyro/src/rust/api/storage.dart';
import 'package:veyro/src/rust/frb_generated.dart';
import 'package:veyro/util/app_dirs.dart';

import 'screens/welcome_screen.dart';

Future<void> main() async {
  // Подключение Rust-ядра через FFI. Должно завершиться до запуска UI:
  // все экраны обращаются к ядру через RustLib.
  await RustLib.init();

  // SQLite-хранилище метаданных (настройки сети BTC: btc.network,
  // node_endpoints.*). Один коннект на старт; сбой не блокирует приложение —
  // экран настроек честно покажет причину при попытке чтения.
  try {
    await dbOpen(path: appDbPath());
  } catch (e) {
    debugPrint('veyro: db_open failed, settings unavailable: $e');
  }

  runApp(const VeyroApp());
}

/// VEYRO — некастодиальный мультивалютный криптовалютный кошелёк.
///
/// Ядро на Rust подключено через flutter_rust_bridge (RustLib.init в main).
/// Дизайн-система: docs/UI_SPEC.md (Electric Blue Dark), тема — design/.
/// Что не реализовано — не показывается как доступное.
class VeyroApp extends StatelessWidget {
  const VeyroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VEYRO',
      debugShowCheckedModeBanner: false,
      theme: buildVeyroTheme(),
      home: const WelcomeScreen(),
    );
  }
}
