//! Экран входа (решение владельца: «на весь экран окно пароля; как введу
//! пароль — сразу на Обзор»). Полноэкранная разблокировка: пароль →
//! btc_unlock (KDF в Rust, ключи не покидают ядро) → btc_sync → Обзор.
//! Загрузка и фон — фирменная система лого-анимаций владельца (знак).
//! Пароль нигде не хранится; лог не содержит секретов.

import 'package:flutter/material.dart';

import 'package:veyro/design/app_colors.dart';
import 'package:veyro/design/ambience.dart';
import 'package:veyro/design/components.dart';
import 'package:veyro/design/veyro_mark.dart';
import 'package:veyro/src/rust/api/btc.dart';
import 'package:veyro/src/rust/api/session.dart';
import 'package:veyro/src/rust/api/wallet.dart';
import 'package:veyro/util/app_dirs.dart';
import 'package:veyro/util/btc_state_cache.dart';
import 'package:veyro/util/format.dart';
import 'package:veyro/util/server_probe.dart';
import 'package:veyro/util/display_prefs.dart';
import 'package:veyro/util/network_config.dart';

import 'dashboard_screen.dart';
import 'welcome_screen.dart';

class LockScreen extends StatefulWidget {
  /// Точка замены для тестов: чтение реестра.
  final Future<List<WalletInfoDto>> Function()? walletsLoader;
  final Future<BtcSessionStateDto?> Function()? sessionLoader;
  final Future<void> Function(String walletId, String password)? unlockAction;

  const LockScreen(
      {super.key, this.walletsLoader, this.sessionLoader, this.unlockAction});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

enum _LockPhase { checking, needsPassword, unlocking, enter, noWallets }

class _LockScreenState extends State<LockScreen> with WidgetsBindingObserver {
  _LockPhase _phase = _LockPhase.checking;
  List<WalletInfoDto> _wallets = const [];
  WalletInfoDto? _wallet;
  BtcSessionStateDto? _session;
  String? _error;
  final _passwordController = TextEditingController();

  /// Интро «вход в приложение» (система лого-анимаций, референс 02)
  /// показывается один раз за запуск; «Другой кошелёк» его не повторяет.
  static bool _introShown = false;
  bool _introActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!_introShown) {
      _introShown = true;
      _introActive = true;
    }
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _passwordController.dispose();
    super.dispose();
  }

  Future<List<WalletInfoDto>> _loadWallets() async =>
      widget.walletsLoader != null
          ? await widget.walletsLoader!()
          : await listWallets(walletsDir: walletsDir());

  Future<BtcSessionStateDto?> _loadSession() async =>
      widget.sessionLoader != null
          ? await widget.sessionLoader!()
          : await btcSessionState();

  /// Старт: сессия активна → сразу каркас; сессия закрыта и есть
  /// кошельки → форма входа; кошельков нет → Welcome.
  Future<void> _check() async {
    setState(() {
      _phase = _LockPhase.checking;
      _error = null;
    });
    await DisplayPrefs.ensureLoaded();
    try {
      _wallets = await _loadWallets();
      _session = await _loadSession();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _LockPhase.enter;
        _error = 'Реестр кошельков недоступен: $e';
        _wallets = const [];
      });
      return;
    }
    if (!mounted) return;
    final preferredId = DisplayPrefs.walletId;
    WalletInfoDto? chosen;
    for (final w in _wallets) {
      if (w.id == preferredId) chosen = w;
    }
    chosen ??= _wallets.isEmpty ? null : _wallets.first;
    if (_session != null) {
      setState(() => _phase = _LockPhase.enter);
      _enterShell();
      return;
    }
    setState(() {
      _wallet = chosen;
      _phase =
          chosen == null ? _LockPhase.noWallets : _LockPhase.needsPassword;
    });
  }

  void _finishIntro() {
    if (!mounted) return;
    setState(() => _introActive = false);
  }

  void _enterShell() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const DashboardScreen()),
      (route) => false,
    );
  }

  void _enterWelcome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  Future<void> _submit() async {
    debugPrint('veyro-flow: lock submit phase=$_phase wallet=${_wallet?.name} '
        'passLen=${_passwordController.text.length}');
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() => _error = 'Введите пароль кошелька.');
      return;
    }
    if (_wallet == null || _phase == _LockPhase.unlocking) {
      return;
    }
    setState(() {
      _phase = _LockPhase.unlocking;
      _error = null;
    });
    try {
      final action = widget.unlockAction;
      if (action != null) {
        // Тестовый путь: настройки сети не нужны (FFI недоступен).
        await action(_wallet!.id, password);
      } else {
        final settings = await loadSettings();
        if (!mounted) return;
        // Автоподбор лучшего живого сервера (решение владельца):
        // короткий пинг кандидатов, самый быстрый — подключаемся к нему.
        final best = await probeBestServer(settings.networkCode)
            .timeout(const Duration(seconds: 5), onTimeout: () => null);
        await btcUnlock(
          walletsDir: walletsDir(),
          walletId: _wallet!.id,
          password: password,
          networkCode: settings.networkCode,
          serverUrl: best ?? settings.serverUrl,
        );
      }
      if (!mounted) return;
      try {
        final sync = await btcSync(gapLimit: 20);
        // Результат — в кэш: центр управления покажет баланс мгновенно,
        // без второго gap-скана (жалоба владельца на двойную синхронизацию).
        BtcStateCache.instance.store(sync);
      } catch (e) {
        // Сессия уже открыта: синхронизация дочитает позже из центра
        // BTC (там кнопка Повторить). Не блокируем вход.
        debugPrint('veyro-flow: post-login sync deferred: $e');
      }
      if (!mounted) return;
      setState(() => _phase = _LockPhase.enter);
      _enterShell();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _LockPhase.needsPassword;
        final raw = e.toString();
        _error = raw.contains('decryption failed')
            ? 'Неверный пароль для «${_wallet!.name}». '
                'Если у кошельков разные пароли — смените кошелёк ниже.'
            : raw;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Анимация 02 (app-entry) идёт ПОВЕРХ живого экрана и показывается
    // один раз за запуск: подложка держит экран до 62%, затем тает и
    // UI проявляется под тающим знаком; знак сходится ровно в фон
    // формы (тот же размер, поза и общие часы) — перескока нет.
    if (_introActive) {
      return Stack(
        children: [
          _phaseScreen(),
          Positioned.fill(
            child: IgnorePointer(
              child: VeyroMarkIntro(
                size: 480,
                withReveal: true,
                onDone: _finishIntro,
              ),
            ),
          ),
        ],
      );
    }
    return _phaseScreen();
  }

  Widget _phaseScreen() {
    switch (_phase) {
      case _LockPhase.checking:
        // Проверка сессии — молча, без экрана загрузки (решение
        // владельца: «обычную загрузку просто убрать»). Интро при
        // первом пуске всё равно закрывает этот кадр.
        return const Scaffold(body: SizedBox.shrink());
      case _LockPhase.unlocking:
        // Анимация 03: неподвижный фоновый знак сразу начинает
        // вращаться, плавно набирает яркость и размер — и без остановок
        // переходит в орбитальную загрузку (1800 мс, разгон из покоя).
        // Непрозрачный фон: глобальный знак не должен просвечивать
        // вторым слоем под анимацией.
        return Scaffold(
          backgroundColor: VColors.background,
          body: Center(
            child: LogoLoader(
              mode: LogoLoaderMode.backgroundToLoading,
              size: 480,
            ),
          ),
        );
      case _LockPhase.enter:
        // Мгновение до replace-навигации — молча, без загрузки.
        return const Scaffold(body: SizedBox.shrink());
      case _LockPhase.noWallets:
        WidgetsBinding.instance.addPostFrameCallback((_) => _enterWelcome());
        return const Scaffold(body: SizedBox.shrink());
      case _LockPhase.needsPassword:
        // Пока играет интро, знак-фон формы не ставим: интро сам
        // сходится в него по общим часам (иначе знак был бы двойным).
        return _buildForm(context, withBackdrop: !_introActive);
    }
  }

  Widget _buildForm(BuildContext context, {required bool withBackdrop}) {
    return Scaffold(
      body: AmbienceSurface(
        child: Stack(
          children: [
            // Фон формы — НЕподвижный приглушённый знак, крупнее панели:
            // выглядывает из-под стекла сверху и снизу (решение
            // владельца: «а где лого с фона?»). При входе он станет
            // стартом анимации 03 (разгон в загрузку).
            if (withBackdrop)
              const Positioned.fill(
                child: Center(
                  child: VeyroMark(
                    size: 480,
                    distance: kBackdropDistance,
                    radius: kBackdropRadius,
                    opacity: kBackdropOpacity,
                  ),
                ),
              ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: GlassPanel(
                      borderRadius:
                          const BorderRadius.all(Radius.circular(24)),
                      sigma: 22,
                      // Панель почти прозрачная: матовое стекло без
                      // плотной заливки (решение владельца).
                      fillOpacity: 0.2,
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _passwordController,
                              autofocus: true,
                              obscureText: true,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.password],
                              onChanged: (_) => setState(() {}),
                              onSubmitted: (_) => _submit(),
                              decoration: const InputDecoration(
                                labelText: 'Пароль кошелька',
                              ),
                            ),
                            const SizedBox(height: 14),
                            VButton.primary(
                              'Войти',
                              icon: Icons.login,
                              onPressed: _submit,
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                _error!,
                                style: TextStyle(
                                    color: VColors.error, fontSize: 13),
                              ),
                            ],
                            if (_wallets.length > 1) ...[
                              const SizedBox(height: 10),
                              Center(
                                child: TextButton.icon(
                                  onPressed: () => _chooseWallet(context),
                                  icon:
                                      const Icon(Icons.swap_horiz, size: 18),
                                  label: const Text('Другой кошелёк'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _chooseWallet(BuildContext context) async {
    final picked = await showDialog<WalletInfoDto>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Кошелёк для входа'),
        children: [
          for (final w in _wallets)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(w),
              child: ListTile(
                dense: true,
                title: Text(w.name),
                subtitle: Text(
                  'создан ${formatWalletDate(w.createdAtUnix.toInt())}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    await DisplayPrefs.setWalletId(picked.id);
    if (!mounted) return;
    setState(() {
      _wallet = picked;
      _error = null;
      _passwordController.clear();
    });
  }
}
