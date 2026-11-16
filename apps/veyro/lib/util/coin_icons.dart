//! Значки валют — Iconify API (решение владельца:
//! https://iconify.design/docs/api/ — прямой клиент с api.iconify.design,
//! без нашего сервера, мастер-план §13-стиль). Приоритет источников:
//! 1) bundle-иконка apps/assets/coins/*.png (оффлайн, официальный
//! логотип), 2) Iconify цветная крипто-иконка (`cryptocurrency-color`,
//! затем монохромная `cryptocurrency`), 3) честная монограмма.
//! Загруженный SVG кэшируется: память → диск (%APPDATA%/veyro/
//! icon-cache) → при следующих запусках работает без сети.
//! Ошибка/нет такой иконки — null, CoinIcon рисует монограмму.
//!
//! БЕЗОПАСНОСТЬ КЭША: содержимое — сторонний контент (Iconify), который
//! попадает в файлы %APPDATA% (ACL не строгие) и потом рендерится
//! flutter_svg (не исполняет скрипты, но всё равно вход из сети).
//! Валидация на ГРАНИЦЕ и при записи, и при каждом чтении с диска:
//! - размер ≤ 256 KiB (нет DoS-рендера гигантским файлом);
//! - только честный <svg> без <script>, обработчиков on*=, внешних
//!   ссылок href на http(s):/data: и DOCTYPE/ENTITY (XML-инъекции).
//! Невалидное содержимое игнорируется, битый файл кэша удаляется.

import 'dart:convert';
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

  /// Тикеры, которых у Iconify нет (и ошибки сети): не дёргать сеть.
  final Set<String> _missing = {};

  final Map<String, Future<Uint8List?>> _inflight = {};

  /// Успешные ключи (после валидации) — байты SVG в памяти.
  final Map<String, Uint8List> _validMemory = {};

  Future<Uint8List?> load(String ticker) {
    final key = ticker.toUpperCase();
    if (!isValidKey(key)) return Future.value(null);
    final memory = _validMemory[key];
    if (memory != null) return Future.value(memory);
    if (_missing.contains(key)) return Future.value(null);
    final disk = useDiskCache ? _readDisk(key) : null;
    if (disk != null) {
      _validMemory[key] = disk;
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
      if (bytes == null || bytes.isEmpty || !isValidSvg(bytes)) {
        _missing.add(key);
        return null;
      }
      final data = Uint8List.fromList(bytes);
      _validMemory[key] = data;
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
      // Размер ответа ограничен ЗВЕРСКИ честно: гигантский ответ провайдера
      // (или подменённого хоста) не превращается в OOM.
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != 200) return null;
      final chunks = <int>[];
      await for (final chunk in response) {
        if (chunks.length + chunk.length > maxSvgBytes) return null;
        chunks.addAll(chunk);
      }
      return chunks;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  String _diskPath(String key) =>
      '${iconCacheDir()}${Platform.pathSeparator}${key.toLowerCase()}.svg';

  Uint8List? _readDisk(String key) {
    final file = File(_diskPath(key));
    try {
      if (!file.existsSync()) return null;
      final bytes = file.readAsBytesSync();
      // Кэш — это тоже недоверенный вход (файл мог заменить другой
      // процесс в %APPDATA%): рендерим только валидированное.
      if (!isValidSvg(bytes)) {
        try {
          file.deleteSync();
        } catch (_) {}
        return null;
      }
      return bytes;
    } catch (_) {
      // Кэш не критичен: отсутствие файла — нормальный путь.
      return null;
    }
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
    _missing.clear();
    _inflight.clear();
    _validMemory.clear();
  }

  /// Тикер попадает в имя файла диска — принимаем только честные
  /// тикеры реестра (латиница/цифры, ≤ 10) — любые посторонние символы
  /// не имеют права превратиться в путь.
  static bool isValidKey(String key) {
    if (key.isEmpty || key.length > 10) return false;
    return key.toUpperCase() == key &&
        RegExp(r'^[A-Z0-9]+$').hasMatch(key);
  }
}

/// Жёсткий лимит размера SVG (текущие иконки ≤ 3 КиБ; 256 КиБ — запас).
const int maxSvgBytes = 256 * 1024;

/// Валидация содержимого SVG (и из сети, и из диска — один и тот же вход):
/// честный корневой `svg`-элемент без скриптов/обработчиков/внешних ссылок.
bool isValidSvg(List<int> raw) {
  if (raw.isEmpty || raw.length > maxSvgBytes) return false;
  List<int> bytes = raw;
  // BOM/прозрачное UTF-8: декодируем честно, мусор — отклоняем.
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    bytes = bytes.sublist(3);
  }
  late final String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    return false;
  }
  final trimmed = text.trimLeft();
  if (!trimmed.startsWith('<svg') && !trimmed.startsWith('<?xml')) {
    return false;
  }
  final lower = text.toLowerCase();
  const forbidden = <String>[
    '<script',
    '<!doctype',
    '<!entity',
    'onafterload=',
    'onbegin=',
    'onend=',
    'onerror=',
    'onfocusin=',
    'onload=',
    'onunload=',
    'data:image/svg',
    'href="http',
    'href="data:',
    'xlink:href="http',
    'xlink:href="data:',
    '<foreignobject',
  ];
  for (final needle in forbidden) {
    if (lower.contains(needle)) return false;
  }
  return true;
}
