//! Экраны 2–5 спеки: Wallet creation → Wallet password → Recovery phrase →
//! Recovery phrase verification. Один пошаговый сценарий на реальном вызове
//! ядра createWallet (фраза показывается ровно один раз, потом проверка
//! знания 4 позиций). Никаких локальных моков.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:veyro/design/app_colors.dart';
import 'package:veyro/design/components.dart';
import 'package:veyro/src/rust/api/wallet.dart';
import 'package:veyro/util/app_dirs.dart';
import 'package:veyro/util/l10n.dart';
import 'package:veyro/util/ui_helpers.dart';

import 'dashboard_screen.dart';

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
        content: Text(tf(
          'wallet_created_snack',
          {'name': _created!.info.name},
        )),
        backgroundColor: VColors.success,
      ),
    );
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const DashboardScreen()),
      (route) => false,
    );
  }

  Future<bool> _confirmLeave() async {
    if (_created == null) return true; // до создания кошелька выход свободен
    // Кошелёк уже записан на диск, но сценарий не завершён (фраза или
    // проверка). Отмена = полностью удалить недоделанный кошелёк
    // (решение владельца: «отменил — значит не создался»). Удаляем
    // строго vault-файл этого сценария, другой трогать нельзя.
    final leave = await confirmAction(
      context,
      title: t('abort_title'),
      body: t('abort_body'),
      confirmLabel: t('delete_and_exit'),
      destructive: true,
    );
    if (!leave) return false;
    try {
      final id = _created!.info.id;
      final file = File(
        '${walletsDir()}${Platform.pathSeparator}$id.wallet.json',
      );
      if (await file.exists()) {
        await file.delete();
      }
      return true;
    } catch (e) {
      if (!mounted) return false;
      showError(context, e);
      return false;
    }
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
        appBar: AppBar(title: Text(t('create_title'))),
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
                      child: Text(t('back_btn')),
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
        return t('step_next');
      case _Step.password:
        return t('step_create');
      case _Step.phrase:
        return t('step_to_check');
      case _Step.verify:
        return t('step_done');
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
        VSectionHeader(
          title: t('step_name_title'),
          subtitle: t('step_name_subtitle'),
        ),
        const SizedBox(height: 16),
        VCard(
          icon: Icons.badge_outlined,
          title: t('step_prefs_title'),
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              maxLength: 40,
              decoration: InputDecoration(labelText: t('name_field')),
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
        VSectionHeader(
          title: t('lock_password_field'),
          subtitle: t('step_password_subtitle'),
        ),
        const SizedBox(height: 16),
        VCard(
          icon: Icons.password_outlined,
          title: t('encryption_title'),
          children: [
            TextField(
              controller: _passwordController,
              autofocus: true,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: t('password_field'),
                helperText: tf(
                  'password_min_helper',
                  {'n': '$_kMinPasswordLength'},
                ),
              ),
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
            if (_passwordController.text.length < _kMinPasswordLength) ...[
              const SizedBox(height: 8),
              Text(
                tf(
                  'password_min_note',
                  {'n': '$_kMinPasswordLength'},
                ),
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
        VSectionHeader(
          title: t('step_seed_title'),
          subtitle: t('step_seed_subtitle'),
        ),
        const SizedBox(height: 16),
        VCard(
          icon: Icons.key_outlined,
          title: t('seed_header'),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: VStatusChip(t('shown_once_chip'), kind: VChipKind.warning),
            ),
            const SizedBox(height: 12),
            VMnemonicGrid(words: words),
            const Divider(height: 20),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _wroteItDown,
              title: Text(t('wrote_it_down_btn')),
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
        VSectionHeader(
          title: t('step_check_title'),
          subtitle: t('step_check_subtitle'),
        ),
        const SizedBox(height: 16),
        VCard(
          icon: Icons.fact_check_outlined,
          title: t('enter_words_title'),
          children: [
            for (final entry in _phraseChecks.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: entry.key,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z ]'))],
                  decoration: InputDecoration(
                    labelText: tf(
                      'word_n_field',
                      {'n': '${entry.value + 1}'},
                    ),
                    helperText: tf(
                      'position_n_of_m',
                      {
                        'n': '${entry.value + 1}',
                        'm': '${words.length}',
                      },
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            if (!_canProceed)
              Text(
                t('check_after_all_words'),
                style: Theme.of(context).textTheme.bodySmall,
              )
            else ...[
              const SizedBox(height: 2),
              VStatusChip(t('matches_chip'), kind: VChipKind.success),
            ],
          ],
        ),
      ],
    );
  }
}
