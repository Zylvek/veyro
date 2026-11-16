//! Общий BIP39-словарь + подсказки «похожих слов» (решение владельца:
//! вместо ручного ввода сид-фразы предлагать варианты). Один источник —
//! ядро (audited bip39 crate, 2048 English слов). Пользуются экраны
//! импорта и проверки фразы при создании.

import 'package:veyro/src/rust/api/wallet.dart';

class Bip39Dictionary {
  Bip39Dictionary._();
  static final Bip39Dictionary instance = Bip39Dictionary._();

  List<String>? _words;
  Future<void>? _loading;

  /// Загрузить один раз на процесс (безопасно вызывать многократно).
  Future<void> ensureLoaded() async {
    if (_words != null) return;
    _loading ??= _load();
    return _loading;
  }

  Future<void> _load() async {
    try {
      final words = await bip39Wordlist();
      if (words.isNotEmpty) _words = words;
    } catch (_) {
      // Словарь недоступен (старая DLL?) — ввод без подсказок, честно.
    }
  }

  bool get available => _words != null && _words!.isNotEmpty;

  /// Последний (недописанный) токен строки фразы.
  static String lastToken(String text) {
    if (text.isEmpty || text.endsWith(' ')) return '';
    final parts = text.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? '' : parts.last.toLowerCase();
  }

  /// Варианты для печатаемого токена: точный префикс, иначе ближайшие по
  /// правкам (Levenshtein ≤ 2, отсортированные). Точное слово словаря —
  /// вариантов не нужно.
  List<String> suggestions(String token) {
    final dict = _words;
    if (dict == null || dict.isEmpty) return const [];
    final t = token.toLowerCase().trim();
    if (t.length < 2 || dict.contains(t)) return const [];
    final byPrefix = dict.where((w) => w.startsWith(t)).take(6).toList();
    if (byPrefix.isNotEmpty) return byPrefix;
    final scored = <MapEntry<String, int>>[];
    for (final w in dict) {
      final d = _levenshtein(t, w, maxDistance: 2);
      if (d <= 2) scored.add(MapEntry(w, d));
    }
    scored.sort((a, b) => a.value.compareTo(b.value));
    return scored.take(6).map((e) => e.key).toList();
  }

  /// Несловарные слова фразы (последний токен исключается: он может быть
  /// недописан). Пустой список — всё из словаря.
  List<String> unknownWords(List<String> phraseWords) {
    final dict = _words;
    if (dict == null || dict.isEmpty) return const [];
    final set = Set<String>.from(dict);
    final unknown = <String>{};
    for (var i = 0; i < phraseWords.length; i++) {
      final w = phraseWords[i].toLowerCase();
      if (w.isEmpty) continue;
      if (i == phraseWords.length - 1) continue;
      if (!set.contains(w)) unknown.add(w);
    }
    return unknown.take(6).toList();
  }

  /// Расстояние Левенштейна с ранним выходом.
  static int _levenshtein(String a, String b, {required int maxDistance}) {
    if ((a.length - b.length).abs() > maxDistance) return maxDistance + 1;
    final prev = List<int>.generate(b.length + 1, (j) => j, growable: false);
    final row = List<int>.filled(b.length + 1, 0, growable: false);
    for (var i = 1; i <= a.length; i++) {
      row[0] = i;
      var best = row[0];
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        row[j] = [prev[j] + 1, row[j - 1] + 1, prev[j - 1] + cost]
            .reduce((x, y) => x < y ? x : y);
        if (row[j] < best) best = row[j];
      }
      if (best > maxDistance) return maxDistance + 1;
      for (var j = 0; j <= b.length; j++) {
        prev[j] = row[j];
      }
    }
    return prev[b.length];
  }
}
