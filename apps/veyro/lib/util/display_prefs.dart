//! Пользовательские настройки отображения: избранное активов, валюта
//! фиата, режим скрытия балансов, выбранный кошелёк. Хранятся в SQLite-
//! настройках ядра (db_set_setting/db_get_setting); если БД недоступна —
//! значения держатся только в памяти процесса и НЕ позиционируются как
//! сохранённые (degraded = true).

import 'dart:convert';

import 'package:veyro/src/rust/api/storage.dart';

class DisplayPrefs {
  static const String _kFavorites = 'assets.favorites';
  static const String _kFiat = 'ui.fiat_currency';
  static const String _kHide = 'ui.hide_balances';
  static const String _kWallet = 'ui.selected_wallet_id';

  /// Избранные тикеры.
  static Set<String> _favorites = {};

  /// Валюта фиата (источника курсов пока нет — только настройка).
  static String _fiatCurrency = 'USD';

  /// Режим скрытия сумм.
  static bool _hideBalances = false;

  /// Выбранный кошелёк (id) для Обзора.
  static String? _walletId;

  /// БД недоступна (значения только в памяти).
  static bool degraded = false;

  /// Валюты отображения — по мастер-плану (§13): USD, EUR, GBP, RUB.
  static const List<String> fiatCurrencies = ['USD', 'EUR', 'GBP', 'RUB'];

  static bool _loaded = false;

  /// Одна ленивая загрузка на процесс.
  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      await _readAll();
    } catch (_) {
      degraded = true;
    }
  }

  static Future<void> _readAll() async {
    final fav = await dbGetSetting(key: _kFavorites);
    if (fav != null) {
      final list = (jsonDecode(fav) as List).cast<String>();
      // В настройках могли остаться не-тикеры (старые версии) — фильтруем.
      _favorites = list.toSet();
    }
    final fiat = await dbGetSetting(key: _kFiat);
    _fiatCurrency = (fiat != null && fiat.isNotEmpty) ? fiat : 'USD';
    final hide = await dbGetSetting(key: _kHide);
    _hideBalances = hide == '1';
    _walletId = await dbGetSetting(key: _kWallet);
  }

  static Future<void> _write(String key, String value) async {
    try {
      await dbSetSetting(key: key, value: value);
    } catch (e) {
      degraded = true;
    }
  }

  static Set<String> get favorites => Set.unmodifiable(_favorites);

  static Future<void> toggleFavorite(String ticker) async {
    final next = Set<String>.from(_favorites);
    if (!next.remove(ticker)) next.add(ticker);
    _favorites = next;
    await _write(_kFavorites, jsonEncode(next.toList()));
  }

  static String get fiatCurrency => _fiatCurrency;

  static Future<void> setFiatCurrency(String code) async {
    _fiatCurrency = code;
    await _write(_kFiat, code);
  }

  static bool get hideBalances => _hideBalances;

  static Future<void> setHideBalances(bool hide) async {
    _hideBalances = hide;
    await _write(_kHide, hide ? '1' : '0');
  }

  static String? get walletId => _walletId;

  static Future<void> setWalletId(String id) async {
    _walletId = id;
    await _write(_kWallet, id);
  }
}
