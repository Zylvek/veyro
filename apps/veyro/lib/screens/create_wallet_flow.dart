//! Экраны 2–5 спеки: Wallet creation → Wallet password → Recovery phrase →
//! Recovery phrase verification. Один пошаговый сценарий на реальном вызове
//! ядра createWallet (фраза показывается ровно один раз, потом проверка
//! знания 4 позиций). Никаких локальных моков.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:veyro/design/app_colors.dart';
import 'package:veyro/design/components.dart';
import 'package:veyro/src/rust/api/wallet.dart';
import 'package:veyro/util/app_dirs.dart';
import 'package:veyro/util/ui_helpers.dart';

import '../navigation/app_shell.dart';

/// Позиционная проверка запоминания фразы: сравнение без учёта регистра и
/// пробелов по краям. Вынесена наверх для юнит-тестов.
bool verifyPhraseAnswers(List<String> words, Map<int, String> answers) {
  if (answers.isEmpty) return false;
  for (final entry in answers.entries) {
    if (entry.key < 0 || entry.key >= words.length) return false;
    if (entry.value.trim().toLowerCase() !=
        words[entry.key].trim().toLowerCase()) {
      return false;
    }
  }
  return true;
}

class CreateWalletFlow extends StatefulWidget {
  const CreateWalletFlow({super.key});

  @override
  State<CreateWalletFlow> createState() => _CreateWalletFlowState();
}

enum _Step { profile, password, phrase, verify }

/// Минимальная длина пароля кошелька (решение владельца — 8 символов).
const int _kMinPasswordLength = 8;

class _CreateWalletFlowState extends State<CreateWalletFlow> {
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _phraseChecks = <TextEditingController, int>{};

  /// Фраза всегда 24 слова (256 бит энтропии) — выбор длины убран по
  /// решению владельца: безопасная длина по умолчанию, меньше настроек.
  static const int _wordCount = 24;

  var _wroteItDown = false;
  var _busy = false;
  CreatedWalletDto? _created;
  var _step = _Step.profile;

  @override
  void dispose() {
    _nameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    for (final controller in _phraseChecks.keys) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get _canProceed {
    switch (_step) {
      case _Step.profile:
        return _nameController.text.trim().isNotEmpty;
      case _Step.password:
        return _passwordController.text.length >= _kMinPasswordLength &&
            _passwordController.text == _confirmController.text;
      case _Step.phrase:
        return _wroteItDown;
      case _Step.verify:
        return verifyPhraseAnswers(
          _phraseWords,
          {
            for (final entry in _phraseChecks.entries)
              entry.value: entry.key.text,
          },
        );
    }
  }

  List<String> get _phraseWords =>
      _created!.mnemonicPhrase.trim().split(RegExp(r'\s+'));

  Future<void> _proceed() async {
    if (_busy || !_canProceed) return;
    switch (_step) {
      case _Step.profile:
        setState(() => _step = _Step.password);
      case _Step.password:
        await _create();
      case _Step.phrase:
        _beginVerification();
        setState(() => _step = _Step.verify);
      case _Step.verify:
        await _finish();
    }
  }

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      final created = await createWallet(
        walletsDir: walletsDir(),
        name: _nameController.text.trim(),
        password: _passwordController.text,
        wordCount: _wordCount,
      );
      if (!mounted) return;
      setState(() {
        _created = created;
        _busy = false;
        _step = _Step.phrase;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showError(context, e);
    }
  }

  void _beginVerification() {
    final words = _phraseWords;
    final positions = List.generate(words.length, (i) => i)..shuffle();
    final picked = positions.take(4).toList()..sort();
    for (final entry in _phraseChecks.keys) {
      entry.dispose();
    }
    _phraseChecks.clear();
    for (final position in picked) {
      _phraseChecks[TextEditingController()] = position;
    }
  }

  Future<void> _finish() async {
    // Кошелёк уже создан и зашифрован на диске (шаг 3). Входим в каркас.
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Кошелёк «${_created!.info.name}» создан'),
        backgroundColor: VColors.success,
      ),
    );
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const VeyroShell()),
      (route) => false,
    );
  }

  Future<bool> _confirmLeave() async {
    if (_step == _Step.profile || _step == _Step.password) return true;
    // Кошелёк уже создан: предупреждаем, что фраза показывается ещё раз
    // только по запросу (reveal на карточке кошелька).
    return confirmAction(
      context,
      title: 'Прервать сценарий?',
      body: 'Кошелёк уже создан и зашифрован в этом каталоге. Фразу можно '
          'посмотреть позже по паролю (иконка ключа на карточке кошелька). '
          'Без записанной фразы восстановление невозможно.',
      confirmLabel: 'Выйти',
      destructive: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final stepIndex = _Step.values.indexOf(_step);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final leave = await _confirmLeave();
        if (leave && mounted) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Создание кошелька')),
        body: VScreen(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  for (var i = 0; i < _Step.values.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          color: i <= stepIndex
                              ? VColors.primary
                              : VColors.elevated,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 24),
              switch (_step) {
                _Step.profile => _buildProfile(),
                _Step.password => _buildPassword(),
                _Step.phrase => _buildPhrase(),
                _Step.verify => _buildVerify(),
              },
              const SizedBox(height: 20),
              Row(
                children: [
                  if (_step != _Step.profile)
                    TextButton(
                      onPressed: _busy ? null : () => _goBack(),
                      child: const Text('Назад'),
                    ),
                  const Spacer(),
                  Expanded(
                    flex: 2,
                    child: VButton.primary(
                      _stepActionButtonLabel(),
                      busy: _busy,
                      onPressed: (_canProceed && !_busy) ? _proceed : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _stepActionButtonLabel() {
    switch (_step) {
      case _Step.profile:
        return 'Далее';
      case _Step.password:
        return 'Создать кошелёк';
      case _Step.phrase:
        return 'Перейти к проверке';
      case _Step.verify:
        return 'Готово';
    }
  }

  void _goBack() {
    switch (_step) {
      case _Step.profile:
      case _Step.password:
        Navigator.of(context).pop();
      case _Step.phrase:
        // Назад на пароль невозможен: хранилище уже создано с этим паролем.
        _confirmLeaveThenPop();
      case _Step.verify:
        setState(() => _step = _Step.phrase);
    }
  }

  void _confirmLeaveThenPop() {
    () async {
      final navigator = Navigator.of(context);
      final leave = await _confirmLeave();
      if (leave && mounted) navigator.pop();
    }();
  }

  Widget _buildProfile() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const VSectionHeader(
          title: 'Имя кошелька',
          subtitle: 'Шаг 1 из 4. Кошелёк храняется зашифрованным на этом '
              'устройстве.',
        ),
        const SizedBox(height: 16),
        VCard(
          icon: Icons.badge_outlined,
          title: 'Параметры кошелька',
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              maxLength: 40,
              decoration: const InputDecoration(labelText: 'Название'),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPassword() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const VSectionHeader(
          title: 'Пароль кошелька',
          subtitle: 'Шаг 2 из 4. Расшифровывает хранилище на этом устройстве; '
              'восстановление пароля невозможно.',
        ),
        const SizedBox(height: 16),
        VCard(
          icon: Icons.password_outlined,
          title: 'Шифрование',
          children: [
            TextField(
              controller: _passwordController,
              autofocus: true,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(
                labelText: 'Пароль',
                helperText: 'Минимум $_kMinPasswordLength символов',
              ),
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
            if (_passwordController.text.length < _kMinPasswordLength) ...[
              const SizedBox(height: 8),
              Text(
                'Пароль короче $_kMinPasswordLength символов — кнопка '
                'создания заблокирована.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall!
                    .copyWith(color: VColors.warning),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildPhrase() {
    final words = _phraseWords;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const VSectionHeader(
          title: 'Резервная фраза',
          subtitle: 'Шаг 3 из 4. Показывается один раз — запишите её на '
              'бумаге.',
        ),
        const SizedBox(height: 16),
        VCard(
          icon: Icons.key_outlined,
          title: 'BIP39-фраза — 24 слова',
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: VStatusChip('показ один раз', kind: VChipKind.warning),
            ),
            const SizedBox(height: 12),
            VMnemonicGrid(words: words),
            const Divider(height: 20),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _wroteItDown,
              title: const Text('Я записал фразу на бумаге'),
              onChanged: (v) => setState(() => _wroteItDown = v ?? false),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildVerify() {
    final words = _phraseWords;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const VSectionHeader(
          title: 'Проверка фразы',
          subtitle: 'Шаг 4 из 4. Введите слова на выбранных позициях.',
        ),
        const SizedBox(height: 16),
        VCard(
          icon: Icons.fact_check_outlined,
          title: 'Введите слова',
          children: [
            for (final entry in _phraseChecks.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: entry.key,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z ]'))],
                  decoration: InputDecoration(
                    labelText: 'Слово № ${entry.value + 1}',
                    helperText: 'Позиция '
                        '${entry.value + 1} из ${words.length}',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            if (!_canProceed)
              Text(
                'Проверка пройдёт после ввода всех четырёх слов.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else ...[
              const SizedBox(height: 2),
              const VStatusChip('Совпадает', kind: VChipKind.success),
            ],
          ],
        ),
      ],
    );
  }
}
