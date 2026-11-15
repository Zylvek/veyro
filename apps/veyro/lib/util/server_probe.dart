//! Автоматический подбор Electrum-сервера (решение владельца: никакой
//! ручной настройки — «найди лучший для человека»). Перед каждым
//! unlock BTC коротким TCP-коннектом пингуем известных кандидатов
//! выбранной сети и берём самый быстрый живой (кэш 3 минуты, чтобы
//! повторные входы не ждали).genesis-проверка ядра при unlock всё
//! равно отвергнет сервер чужой сети — безопасность не зависит от подбора.

import 'dart:async';
import 'dart:io';

import 'package:veyro/util/network_config.dart';

/// Кандидаты Electrum-серверов по коду сети. Для каждого уже есть
/// верифицированный дефолт (e2e_probe), плюс альтернативы.
List<String> serverCandidates(int code) {
  switch (code) {
    case 0:
      return const [
        'ssl://fulcrum.bullbitcoin.com:50002',
        'ssl://electrum.blockstream.info:50002',
        'tcp://electrum.blockstream.info:50001',
      ];
    case 1:
      return const [
        'ssl://electrum.blockstream.info:60002',
      ];
    case 2:
      return const [
        'ssl://blackie.c3-soft.com:57010',
      ];
    default:
      return const [];
  }
}

/// Кэш подобранного сервера: сеть → url (3 минуты свежести).
final Map<int, _CacheEntry> _bestCache = {};

class _CacheEntry {
  final String url;
  final DateTime at;
  const _CacheEntry(this.url, this.at);
}

/// Сброс кэша подбора: после неудачного unlock (TCP прошёл, а
/// Electrum-протокол упал — «unexpected end of file») следующая попытка
/// прониует кандидатов заново и возьмёт другого здорового сервера.
void invalidateProbe() {
  _bestCache.clear();
}

/// Лучший живой сервер для сети: минимальная задержка TCP-коннекта
/// среди кандидатов. null — никто не ответил (unlock честно выдаст
/// ошибку подключения по дефолту).
Future<String?> probeBestServer(int networkCode) async {
  final cached = _bestCache[networkCode];
  if (cached != null &&
      DateTime.now().difference(cached.at) <=
          const Duration(minutes: 3)) {
    return cached.url;
  }
  final candidates = [...serverCandidates(networkCode)];
  final def = defaultServerUrl(networkCode);
  if (def != null && !candidates.contains(def)) {
    candidates.insert(0, def);
  }
  final latencies = await Future.wait(
    candidates.map(_tcpLatency),
  );
  String? best;
  int bestMs = 1 << 31;
  for (var i = 0; i < candidates.length; i++) {
    final ms = latencies[i];
    if (ms != null && ms < bestMs) {
      bestMs = ms;
      best = candidates[i];
    }
  }
  if (best != null) {
    _bestCache[networkCode] = _CacheEntry(best, DateTime.now());
  }
  return best;
}

/// Задержка TCP-коннекта к host:port (3с таймаут); null — не отвечает.
Future<int?> _tcpLatency(String url) async {
  final match = RegExp(r'^(?:\w+)://([^:/]+):(\d+)').firstMatch(url);
  if (match == null) return null;
  final host = match.group(1)!;
  final port = int.parse(match.group(2)!);
  final watch = Stopwatch()..start();
  try {
    final socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(seconds: 3),
    );
    watch.stop();
    socket.destroy();
    return watch.elapsedMilliseconds;
  } catch (_) {
    return null;
  }
}
