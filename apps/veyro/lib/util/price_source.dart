//! Источник фиатных цен — прямой клиент CoinGecko (мастер-план §13:
//! «Price requests must go directly from the client to the selected
//! provider», никакого своего бэкенда). Цены BTC и ETH в выбранной
//! валюте отображения тем же запросом; кэш в памяти с ограничением
//! свежести. Ошибка/нет сети → null (честное отсутствие курса, UI
//! скрывает фиатные строки).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

/// Курс BTC и ETH по валютам отображения — ответ провайдера одним
/// запросом (ids=bitcoin,ethereum).
class FiatRates {
  final Map<String, double> btc;
  final Map<String, double> eth;

  const FiatRates({required this.btc, required this.eth});
}

/// Кэш курсов + загрузчик. Точки замены для тестов — [loader] и
/// [marketLoader].
class PriceSource {
  FiatRates? _rates;
  DateTime? _at;

  PriceSource._();
  static final PriceSource instance = PriceSource._();

  /// Точка замены в тестах (реальный HTTP не вызывается).
  static Future<FiatRates?> Function()? loader;

  static const Duration _maxAge = Duration(minutes: 5);

  /// Реальный сетевой загрузчик: один запрос на все валюты и обе монеты.
  static Future<FiatRates?> httpLoader() async {
    final client = HttpClient();
    try {
      final request = await client
          .getUrl(Uri.parse(
              'https://api.coingecko.com/api/v3/simple/price'
              '?ids=bitcoin,ethereum&vs_currencies=usd,eur,gbp,rub'))
          .timeout(const Duration(seconds: 10));
      final response = await request.close().timeout(
            const Duration(seconds: 10),
          );
      if (response.statusCode != 200) return null;
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      Map<String, double> parse(String coin) {
        final map = json[coin] as Map<String, dynamic>?;
        if (map == null) return {};
        return {
          for (final currency in const ['usd', 'eur', 'gbp', 'rub'])
            if (map[currency] is num) currency: (map[currency] as num).toDouble(),
        };
      }

      return FiatRates(btc: parse('bitcoin'), eth: parse('ethereum'));
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Курс BTC в валюте отображения (usd/eur/gbp/rub).
  Future<double?> btcPriceIn(String fiat) async {
    final rates = await _freshRates(fiat);
    return rates?.btc[fiat.toLowerCase()];
  }

  /// Курс ETH в валюте отображения — тот же запрос, что и для BTC.
  Future<double?> ethPriceIn(String fiat) async {
    final rates = await _freshRates(fiat);
    return rates?.eth[fiat.toLowerCase()];
  }

  Future<FiatRates?> _freshRates(String fiat) async {
    final code = fiat.toLowerCase();
    if (!_supported.contains(code)) return null;
    final at = _at;
    final cached = _rates;
    if (cached != null &&
        at != null &&
        DateTime.now().difference(at) <= _maxAge) {
      return cached;
    }
    final load = loader ?? httpLoader;
    final rates = await load();
    if (rates == null) return null;
    _rates = rates;
    _at = DateTime.now();
    return rates;
  }

  /// Сброс кэша курса — для тестов, чтобы результаты не перетекали
  /// между сценариями.
  @visibleForTesting
  void resetRates() {
    _rates = null;
    _at = null;
    _seriesCache.clear();
  }

  static const Set<String> _supported = {'usd', 'eur', 'gbp', 'rub'};

  // ============================================================
  // Историческая линия курса (реальный график валюты на Обзоре).
  // ============================================================

  /// Точка замены в тестах для исторической серии (без сети).
  static Future<List<double>?> Function(String fiat, int days)?
      marketLoader;

  /// Кэш серий по ключу «валюта:окно».
  final Map<String, _SeriesEntry> _seriesCache = {};

  /// Реальный сетевой загрузчик исторической линии курса.
  static Future<List<double>?> httpMarketLoader(
    String fiat,
    int days,
  ) async {
    final client = HttpClient();
    try {
      final request = await client
          .getUrl(Uri.parse(
              'https://api.coingecko.com/api/v3/coins/bitcoin/market_chart'
              '?vs_currency=${fiat.toLowerCase()}&days=$days'))
          .timeout(const Duration(seconds: 10));
      final response = await request.close().timeout(
            const Duration(seconds: 10),
          );
      if (response.statusCode != 200) return null;
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final prices = json['prices'] as List?;
      if (prices == null) return null;
      return [
        for (final point in prices)
          double.parse((point as List)[1].toString()),
      ];
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Реальная линия курса BTC за окно [days] в валюте отображения.
  /// Ошибка/нет сети → null (график честно скрыт в UI).
  Future<List<double>?> btcMarketSeries(String fiat, int days) async {
    final code = fiat.toLowerCase();
    if (!_supported.contains(code)) return null;
    final key = '$code:$days';
    final entry = _seriesCache[key];
    if (entry != null &&
        DateTime.now().difference(entry.at) <= _maxAge) {
      return entry.values;
    }
    final load = marketLoader ?? httpMarketLoader;
    final values = await load(code, days);
    if (values == null) return null;
    _seriesCache[key] = _SeriesEntry(values, DateTime.now());
    return values;
  }
}

class _SeriesEntry {
  final List<double> values;
  final DateTime at;

  const _SeriesEntry(this.values, this.at);
}

/// Формат фиатной суммы: «12 345.67» с пробельными группами.
String formatFiat(double value) {
  final whole = value.toStringAsFixed(2);
  final parts = whole.split('.');
  final digits = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buf.write(' ');
    }
    buf.write(digits[i]);
  }
  return '${buf.toString()}.${parts[1]}';
}
