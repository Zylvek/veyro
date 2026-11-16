//! Значки валют — Iconify API (решение владельца:
//! https://iconify.design/docs/api/ — прямой клиент с api.iconify.design,
//! без нашего сервера, мастер-план §13-стиль). Приоритет источников:
//! 1) bundle-иконка apps/assets/coins/*.png (оффлайн, официальный
//! логотип), 2) Iconify цветная крипто-иконка (`cryptocurrency-color`,
//! затем монохромная `cryptocurrency`), 3) честная монограмма.
//! Загруженный SVG кэшируется: память → диск (%APPDATA%/veyro/
//! icon-cache) → при следующих запусках работает без сети.
//! Ошибка/нет такой иконки — null, CoinIcon рисует монограмму.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:veyro/util/app_dirs.dart';

class CoinIconService {
  CoinIconService._();
  static final CoinIconService instance = CoinIconService._();

  /// Точка замены в тестах (реальный HTTP не вызывается).
  static Future<List<int>?> Function(String ticker)? fetcher;

  /// Отключение дискового кэша — для тестов (не читать %APPDATA%).
  static bool useDiskCache = true;

  /// Память: тикер → байты SVG.
  final Map<String, Uint8List> _memory = {};

  /// Тикеры, которых у Iconify нет (и ошибки сети): не дёргать сеть.
  final Set<String> _missing = {};

  final Map<String, Future<Uint8List?>> _inflight = {};

  Future<Uint8List?> load(String ticker) {
    final key = ticker.toUpperCase();
    final memory = _memory[key];
    if (memory != null) return Future.value(memory);
    if (_missing.contains(key)) return Future.value(null);
    final disk = useDiskCache ? _readDisk(key) : null;
    if (disk != null) {
      _memory[key] = disk;
      return Future.value(disk);
    }
    final inflight = _inflight[key];
    if (inflight != null) return inflight;
    final future = _fetchAndStore(key);
    _inflight[key] = future;
    return future;
  }

  Future<Uint8List?> _fetchAndStore(String key) async {
    try {
      final fetch = fetcher ?? httpFetch;
      final bytes = await fetch(key);
      if (bytes == null || bytes.isEmpty) {
        _missing.add(key);
        return null;
      }
      final data = Uint8List.fromList(bytes);
      _memory[key] = data;
      if (useDiskCache) _writeDisk(key, data);
      return data;
    } catch (_) {
      _missing.add(key);
      return null;
    } finally {
      _inflight.remove(key);
    }
  }

  /// Iconify API: сначала цветная иконка, затем монохромная.
  static Future<List<int>?> httpFetch(String ticker) async {
    final name = ticker.toLowerCase();
    final colored = await _get(
      'https://api.iconify.design/cryptocurrency-color/$name.svg',
    );
    if (colored != null) return colored;
    return _get('https://api.iconify.design/cryptocurrency/$name.svg');
  }

  static Future<List<int>?> _get(String url) async {
    final client = HttpClient();
    try {
      final request = await client
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != 200) return null;
      return await response.expand((chunk) => chunk).toList();
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  String _diskPath(String key) =>
      '${iconCacheDir()}${Platform.pathSeparator}${key.toLowerCase()}.svg';

  Uint8List? _readDisk(String key) {
    try {
      final file = File(_diskPath(key));
      if (file.existsSync()) return file.readAsBytesSync();
    } catch (_) {
      // Кэш не критичен: отсутствие файла — нормальный путь.
    }
    return null;
  }

  void _writeDisk(String key, Uint8List bytes) {
    try {
      final dir = Directory(iconCacheDir());
      if (!dir.existsSync()) dir.createSync(recursive: true);
      File(_diskPath(key)).writeAsBytesSync(bytes, flush: true);
    } catch (_) {
      // Не удалось сохранить — иконка останется в памяти сессии.
    }
  }

  /// Сброс состояний между тестами.
  @visibleForTesting
  void resetForTest() {
    _memory.clear();
    _missing.clear();
    _inflight.clear();
  }
}
