import 'package:flutter/material.dart';

import 'src/rust/frb_generated.dart';

Future<void> main() async {
  // Подключение Rust-ядра через FFI. Должно завершиться до запуска UI:
  // все экраны обращаются к ядру через RustLib.
  await RustLib.init();
  runApp(const VeyroApp());
}

/// VEYRO — некастодиальный мультивалютный криптовалютный кошелёк.
///
/// Каркас интерфейса (Phase 6). Ядро кошелька на Rust подключено через
/// flutter_rust_bridge (RustLib.init в main). Никаких фейковых балансов
/// и данных — экран честно сообщает текущее состояние интеграции.
class VeyroApp extends StatelessWidget {
  const VeyroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VEYRO',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: const WelcomeScreen(),
    );
  }

  ThemeData _buildTheme() {
    const arcticTeal = Color(0xFF45D6C5);
    final scheme = ColorScheme.fromSeed(
      seedColor: arcticTeal,
      brightness: Brightness.dark,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF0A1118),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        centerTitle: true,
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        color: Color(0xFF121A24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: Color(0xFF1E2A38)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
        ),
      ),
    );
  }
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 32),
                  const _VeyroLogo(),
                  const SizedBox(height: 12),
                  Text(
                    'VEYRO',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Некастодиальный мультивалютный кошелёк',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge
                        ?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 40),
                  const _IntegrationStatusCard(),
                  const SizedBox(height: 32),
                  // Кнопки создания/импорта кошелька появятся вместе с
                  // подключением ядра (flutter_rust_bridge). Пока честно скрыты.
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VeyroLogo extends StatelessWidget {
  const _VeyroLogo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF45D6C5), Color(0xFF1FA896)],
        ),
      ),
      child: const Text(
        'V',
        style: TextStyle(
          fontSize: 44,
          fontWeight: FontWeight.w800,
          color: Color(0xFF0A1118),
        ),
      ),
    );
  }
}

class _IntegrationStatusCard extends StatelessWidget {
  const _IntegrationStatusCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.construction_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  'Идёт сборка кошелька',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Ядро кошелька на Rust подключено к интерфейсу через '
              'flutter_rust_bridge: шифрование секретов (Argon2id + '
              'XChaCha20-Poly1305), BIP39-мнемоники, зашифрованные бэкапы и '
              'хранение данных уже работают.\n\n'
              'Балансы и транзакции появятся только после интеграции с '
              'реальными блокчейнами — никаких имитаций.',
              style: TextStyle(color: Colors.white60, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
