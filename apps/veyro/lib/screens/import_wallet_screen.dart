//! Экран 6 спеки (Wallet import): восстановление кошелька из BIP39-фразы
//! на реальном restoreWallet. Passphrase (25-е слово) — опционально.
//! Решение владельца: вместо ручного ввода всей фразы — подсказки слов из
//! официального BIP39-словаря (2048 слов, comes from the audited bip39
//! crate): точный префикс, иначе ближайшие по правкам; несловарные слова
//! честно помечаются.

import 'package:flutter/material.dart';

import 'package:veyro/design/app_colors.dart';
import 'package:veyro/design/components.dart';
import 'package:veyro/src/rust/api/wallet.dart';
import 'package:veyro/util/app_dirs.dart';
import 'package:veyro/util/l10n.dart';
import 'package:veyro/util/ui_helpers.dart';

import 'dashboard_screen.dart';

class ImportWalletScreen extends StatefulWidget {
  const ImportWalletScreen({super.key});

  @override
  State<ImportWalletScreen> createState() => _ImportWalletScreenState();
}

class _ImportWalletScreenState extends State<ImportWalletScreen> {
  final _nameController = TextEditingController();
  final _phraseController = TextEditingController();
  final _passphraseController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  var _busy = false;

  /// BIP39 English wordlist (lazily fetched from the core once per run).
  List<String>? _dictionary;

  @override
  void initState() {
    super.initState();
    _loadDictionary();
  }

  Future<void> _loadDictionary() async {
    try {
      final words = await bip39Wordlist();
      if (!mounted || words.isEmpty) return;
      setState(() => _dictionary = words);
    } catch (e) {
      // Словарь недоступен (старая DLL?) — ввод без подсказок, честно.
      debugPrint('veyro-flow: bip39 wordlist unavailable: $e');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phraseController.dispose();
    _passphraseController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  List<String> get _phraseWords {
    final text = _phraseController.text.trim();
    if (text.isEmpty) return const [];
    return text.split(RegExp(r'\s+'));
  }

  /// Последний (недописанный) токен фразы — для подсказок.
  String get _currentToken {
    final text = _phraseController.text;
    if (text.isEmpty || text.endsWith(' ') || text.endsWith('\n')) return '';
    final words = _phraseWords;
    return words.isEmpty ? '' : words.last.toLowerCase();
  }

  /// Честная проверка словаря: какие введённые слова отсутствуют в BIP39
  /// (последний токен — исключение: он может быть недописан).
  List<String> get _unknownWords {
    final dict = _dictionary;
    if (dict == null || dict.isEmpty) return const [];
    final set = Set<String>.from(dict);
    final words = _phraseWords;
    final editingLast = !_phraseController.text.endsWith(' ');
    final unknown = <String>{};
    for (var i = 0; i < words.length; i++) {
      final w = words[i].toLowerCase();
      if (w.isEmpty) continue;
      if (editingLast && i == words.length - 1) continue;
      if (!set.contains(w)) unknown.add(w);
    }
    return unknown.take(6).toList();
  }

  /// Варианты слов (решение владельца): точный префикс, иначе ближайшие
  /// по правкам (расстояние ≤ 2, отсортированные). Полное слово словаря —
  /// вариантов не нужно.
  List<String> get _suggestions {
    final dict = _dictionary;
    if (dict == null || dict.isEmpty) return const [];
    final token = _currentToken;
    if (token.length < 2 || dict.contains(token)) return const [];
    final byPrefix = dict.where((w) => w.startsWith(token)).take(6).toList();
    if (byPrefix.isNotEmpty) return byPrefix;
    final scored = <MapEntry<String, int>>[];
    for (final w in dict) {
      final d = _levenshtein(token, w, maxDistance: 2);
      if (d <= 2) scored.add(MapEntry(w, d));
    }
    scored.sort((a, b) => a.value.compareTo(b.value));
    return scored.take(6).map((e) => e.key).toList();
  }

  void _applySuggestion(String word) {
    final words = _phraseWords;
    if (words.isEmpty) {
      _phraseController.text = '$word ';
    } else {
      words[words.length - 1] = word;
      _phraseController.text = '${words.join(' ')} ';
    }
    _phraseController.selection = TextSelection.collapsed(
      offset: _phraseController.text.length,
    );
    setState(() {});
  }

  /// Расстояние Левенштейна с ранним выходом.
  static int _levenshtein(String a, String b, {required int maxDistance}) {
    if ((a.length - b.length).abs() > maxDistance) return maxDistance + 1;
    final prev =
        List<int>.generate(b.length + 1, (j) => j, growable: false);
    final row = List<int>.filled(b.length + 1, 0, growable: false);
    for (var i = 1; i <= a.length; i++) {
      row[0] = i;
      var best = row[0];
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        row[j] = [
          prev[j] + 1,
          row[j - 1] + 1,
          prev[j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
        if (row[j] < best) best = row[j];
      }
      if (best > maxDistance) return maxDistance + 1;
      for (var j = 0; j <= b.length; j++) {
        prev[j] = row[j];
      }
    }
    return prev[b.length];
  }

  bool get _valid =>
      _nameController.text.trim().isNotEmpty &&
      _phraseController.text.trim().split(RegExp(r'\s+')).length >= 12 &&
      _phraseController.text.trim().split(RegExp(r'\s+')).length <= 24 &&
      _passwordController.text.isNotEmpty &&
      _passwordController.text == _confirmController.text;

  Future<void> _restore() async {
    if (_busy || !_valid) return;
    setState(() => _busy = true);
    try {
      final restored = await restoreWallet(
        walletsDir: walletsDir(),
        name: _nameController.text.trim(),
        password: _passwordController.text,
        phrase: _phraseController.text.trim(),
        passphrase: _passphraseController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tf(
            'wallet_restored_snack',
            {'name': restored.name},
          )),
          backgroundColor: VColors.success,
        ),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const DashboardScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wordCount =
        _phraseController.text.trim().split(RegExp(r'\s+')).length;
    return Scaffold(
      appBar: AppBar(title: Text(t('import_title'))),
      body: VScreen(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            VSectionHeader(
              title: t('import_from_phrase_title'),
              subtitle: t('import_from_phrase_subtitle'),
            ),
            const SizedBox(height: 16),
            VCard(
              icon: Icons.text_fields_outlined,
              title: t('wallet_card'),
              children: [
                TextField(
                  controller: _nameController,
                  autofocus: true,
                  maxLength: 40,
                  decoration: InputDecoration(
                    labelText: t('wallet_name_field'),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phraseController,
                  maxLines: 3,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: t('phrase_field'),
                    helperText:
                        wordCount >= 12 && wordCount <= 24
                            ? tf(
                                'words_entered',
                                {'count': '$wordCount'},
                              )
                            : tf(
                                'words_counter',
                                {'count': '$wordCount'},
                              ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                // Подсказки BIP39 (решение владельца): чипы похожих слов.
                Builder(builder: (context) {
                  final suggestions = _suggestions;
                  final unknown = _unknownWords;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (suggestions.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final word in suggestions)
                              ActionChip(
                                label: Text(word),
                                labelStyle: const TextStyle(fontSize: 12.5),
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _applySuggestion(word),
                              ),
                          ],
                        ),
                      ],
                      if (unknown.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          tf(
                            'unknown_words',
                            {'words': unknown.join(', ')},
                          ),
                          style: TextStyle(
                            color: VColors.error,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ],
                  );
                }),
                const SizedBox(height: 12),
                TextField(
                  controller: _passphraseController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: t('passphrase_field'),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
            const SizedBox(height: 16),
            VCard(
              icon: Icons.password_outlined,
              title: t('device_encryption_title'),
              children: [
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration:
                      InputDecoration(labelText: t('password_field')),
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
              ],
            ),
            const SizedBox(height: 20),
            VButton.primary(
              t('restore_wallet_btn'),
              icon: Icons.restore_outlined,
              busy: _busy,
              onPressed: _valid ? _restore : null,
            ),
          ],
        ),
      ),
    );
  }
}
