//! Источник фиатных цен — прямой клиент CoinGecko (мастер-план §13:
//! «Price requests must go directly from the client to the selected
//! provider», никакого своего бэкенда). Цены BTC и ETH в выбранной
//! валюте отображения тем же запросом; кэш в памяти С ДИСКОВЫМ
//! ДОЖИВАНИЕМ: свежие курс и линия графика переживают перезапуск,
//! а при сбое сети держится последний известный курс — решение
//! владельца («сохранять тот же самый курс, чтобы меньше тратилось
//! данных»). Ошибка/нет сети → null только если данных нет вообще
//! (честное отсутствие курса, UI скрывает фиатные строки).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:veyro/util/app_dirs.dart';

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

  // ------------------------------------------------------------------
  // Дисковый кэш цен: курс и серия переживают перезапуск приложения
  // (решение владельца: «сохранять тот же самый курс, чтобы меньше
  // тратилось данных»). В проде включается из main; в тестах выключен.
  // ------------------------------------------------------------------

  static bool _persistenceEnabled = false;

  /// Включить сохранение кэша цен на диск (вызывается из main).
  static void enablePersistence() => _persistenceEnabled = true;

  bool _loaded = false;
  Future<void>? _loadFuture;

  Future<void> _ensureLoaded() async {
    if (_loaded || !_persistenceEnabled) return;
    _loadFuture ??= _loadFromDisk();
    await _loadFuture;
    _loaded = true;
  }

  Future<void> _loadFromDisk() async {
    try {
      final file = File(priceCachePath());
      if (!await file.exists()) return;
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final ratesJson = json['rates'];
      final ratesAt = json['ratesAt'];
      if (ratesJson is Map<String, dynamic> && ratesAt is num) {
        final btc = _decodePriceMap(ratesJson['btc']);
        final eth = _decodePriceMap(ratesJson['eth']);
        if (btc.isNotEmpty || eth.isNotEmpty) {
          _rates = FiatRates(btc: btc, eth: eth);
          _at = DateTime.fromMillisecondsSinceEpoch(ratesAt.toInt());
        }
      }
      final seriesJson = json['series'];
      if (seriesJson is Map<String, dynamic>) {
        seriesJson.forEach((key, raw) {
          if (raw is! Map<String, dynamic>) return;
          final values = _decodePoints(raw['values']);
          final at = raw['at'];
          if (values != null && values.isNotEmpty && at is num) {
            _seriesCache[key] = _SeriesEntry(
              values,
              DateTime.fromMillisecondsSinceEpoch(at.toInt()),
            );
          }
        });
      }
      debugPrint('veyro: price cache restored from disk');
    } catch (e) {
      // Битый файл/нет прав — живём с кэшем в памяти, перезапись
      // обновит файл следующим успешным запросом.
      debugPrint('veyro: price cache load skipped: $e');
    }
  }

  Map<String, double> _decodePriceMap(Object? raw) {
    if (raw is! Map<String, dynamic>) return const {};
    return {
      for (final entry in raw.entries)
        if (entry.value is num) entry.key: (entry.value as num).toDouble(),
    };
  }

  List<MarketPoint>? _decodePoints(Object? raw) {
    if (raw is! List) return null;
    final points = <MarketPoint>[];
    for (final point in raw) {
      if (point is List &&
          point.length == 2 &&
          point[0] is num &&
          point[1] is num) {
        points.add(MarketPoint(
          DateTime.fromMillisecondsSinceEpoch((point[0] as num).toInt()),
          (point[1] as num).toDouble(),
        ));
      }
    }
    return points;
  }

  /// Бесшумная запись кэша на диск после успешной загрузки.
  Future<void> _persist() async {
    if (!_persistenceEnabled) return;
    try {
      final file = File(priceCachePath());
      await file.parent.create(recursive: true);
      final rates = _rates;
      final at = _at;
      final payload = <String, dynamic>{
        if (rates != null && at != null) ...{
          'rates': {'btc': rates.btc, 'eth': rates.eth},
          'ratesAt': at.millisecondsSinceEpoch,
        },
        'series': {
          for (final entry in _seriesCache.entries)
            entry.key: {
              'values': [
                for (final point in entry.value.values)
                  [point.time.millisecondsSinceEpoch, point.price],
              ],
              'at': entry.value.at.millisecondsSinceEpoch,
            },
        },
      };
      await file.writeAsString(jsonEncode(payload), flush: true);
    } catch (e) {
      debugPrint('veyro: price cache save skipped: $e');
    }
  }

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
    await _ensureLoaded();
    final at = _at;
    final cached = _rates;
    if (cached != null &&
        at != null &&
        DateTime.now().difference(at) <= _maxAge) {
      return cached; // Свежий курс: ноль сетевых запросов.
    }
    final load = loader ?? httpLoader;
    final rates = await load();
    if (rates == null) {
      // Нет сети/сброс лимита: держим последний известный курс
      // (решение владельца), честная пустота — только если его нет.
      return cached;
    }
    _rates = rates;
    _at = DateTime.now();
    unawaited(_persist());
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
  // По требованию владельца — линия ЭФИРА (как в референсе Nexus),
  // реальный курс от того же провайдера.
  // ============================================================

  /// Точка замены в тестах для исторической серии (без сети).
  static Future<List<MarketPoint>?> Function(
          String coinId, String fiat, int days)?
      marketLoader;

  /// Кэш серий по ключу «валюта:монета:окно». Линия истории меняется
  /// редко (для окна от 30 дней — вообще по суткам провайдера), поэтому
  /// живёт заметно дольше мгновенного курса — меньше тратится данных.
  static const Duration _seriesMaxAge = Duration(minutes: 30);
  final Map<String, _SeriesEntry> _seriesCache = {};

  /// Реальный сетевой загрузчик исторической линии курса.
  static Future<List<MarketPoint>?> httpMarketLoader(
    String coinId,
    String fiat,
    int days,
  ) async {
    final client = HttpClient();
    try {
      final request = await client
          .getUrl(Uri.parse(
              'https://api.coingecko.com/api/v3/coins/$coinId/market_chart'
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
      final points = <MarketPoint>[];
      for (final point in prices) {
        final list = point as List;
        final ts = list[0];
        final price = list[1];
        if (ts is num && price is num) {
          points.add(MarketPoint(
            DateTime.fromMillisecondsSinceEpoch(ts.toInt()),
            price.toDouble(),
          ));
        }
      }
      return points;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Реальная линия курса монеты [coinId] (например, 'ethereum' —
  /// график на Обзоре, как в референсе) за окно [days] в валюте
  /// отображения, с метками времени провайдера (для наведения).
  /// Ошибка/нет сети → null (график честно скрыт в UI).
  Future<List<MarketPoint>?> marketSeries(
    String coinId,
    String fiat,
    int days,
  ) async {
    final code = fiat.toLowerCase();
    if (!_supported.contains(code)) return null;
    final key = '$code:$coinId:$days';
    await _ensureLoaded();
    final entry = _seriesCache[key];
    if (entry != null &&
        DateTime.now().difference(entry.at) <= _seriesMaxAge) {
      return entry.values; // Свежая линия: ноль сетевых запросов.
    }
    final load = marketLoader ?? httpMarketLoader;
    final values = await load(coinId, code, days);
    if (values == null) {
      // Нет сети: держим последнюю известную линию, честная пустота —
      // только если её никогда не было.
      return entry?.values;
    }
    _seriesCache[key] = _SeriesEntry(values, DateTime.now());
    unawaited(_persist());
    return values;
  }
}

/// Точка реального курса: метка времени провайдера + цена.
class MarketPoint {
  final DateTime time;
  final double price;

  const MarketPoint(this.time, this.price);
}

class _SeriesEntry {
  final List<MarketPoint> values;
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
