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
  static const String _kLanguage = 'ui.language';
  static const String _kChartCoin = 'ui.chart_coin';

  /// Избранные тикеры.
  static Set<String> _favorites = {};

  /// Валюта фиата (источника курсов пока нет — только настройка).
  static String _fiatCurrency = 'USD';

  /// Язык интерфейса (словарь lib/util/l10n.dart).
  static String _language = 'ru';

  /// Монета линии графика Обзора (тикер из [DisplayPrefs.chartCoins]).
  static String _chartCoin = 'ETH';

  /// Режим скрытия сумм.
  static bool _hideBalances = false;

  /// Выбранный кошелёк (id) для Обзора.
  static String? _walletId;

  /// БД недоступна (значения только в памяти).
  static bool degraded = false;

  /// Валюты отображения — по мастер-плану (§13): USD, EUR, GBP, RUB.
  static const List<String> fiatCurrencies = ['USD', 'EUR', 'GBP', 'RUB'];

  static bool _loaded = false;
  static Future<void>? _loadingOnce;

  /// Одна ленивая загрузка на процесс. Параллельные вызовы дожидаются той
  /// же самой загрузки (race «второй вызов получает дефолты до конца
  /// чтения» устранён): флаг ставится строго после чтения.
  static Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    return _loadingOnce ??= _doLoad();
  }

  static Future<void> _doLoad() async {
    try {
      await _readAll();
    } catch (_) {
      degraded = true;
    }
    _loaded = true;
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
    final lang = await dbGetSetting(key: _kLanguage);
    if (lang != null && languages.containsKey(lang)) _language = lang;
    final chart = await dbGetSetting(key: _kChartCoin);
    if (chart != null && chart.isNotEmpty) _chartCoin = chart;
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

  /// Языки интерфейса: код → нативное имя (как видит владелец).
  static const Map<String, String> languages = {
    'ru': 'Русский',
    'en': 'English',
  };

  static String get language => _language;

  static Future<void> setLanguage(String code) async {
    _language = code;
    await _write(_kLanguage, code);
  }

  static String get chartCoin => _chartCoin;

  static Future<void> setChartCoin(String symbol) async {
    _chartCoin = symbol;
    await _write(_kChartCoin, symbol);
  }

  static bool get hideBalances => _hideBalances;

  /// Единая маскировка сумм («глазик» на Обзоре): включён — прочерки,
  /// иначе значение как есть. Использовать для ВСЕХ денежных строк
  /// (балансы, дельты мемпула, центры монет).
  static String maskAmount(String value) => _hideBalances ? '••••••' : value;

  static Future<void> setHideBalances(bool hide) async {
    _hideBalances = hide;
    await _write(_kHide, hide ? '1' : '0');
  }

  static String? get walletId => _walletId;

  static Future<void> setWalletId(String? id) async {
    _walletId = id;
    // null — активный кошелёк удалён: сбрасываем настройку, выбор вернётся
    // к первому живому кошельку при следующем входе.
    await _write(_kWallet, id ?? '');
  }

  /// Очистить выбор, если он указывал на удалённый кошелёк.
  static Future<void> forgetWalletIf(String id) async {
    if (_walletId == id) await setWalletId(null);
  }
}
