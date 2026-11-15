//! Автоматический подбор Electrum-сервера (решение владельца: никакой
//! ручной настройки — «найди лучший для человека»). Перед каждым
//! unlock BTC кандидаты проверяются РЕАЛЬНЫМ Electrum-хэндшейком
//! (server.version по TLS/plain, как это делает ядро), а не только
//! TCP-коннектом: сервер, чей порт жив, но протокол падает
//! («unexpected end of file»), честно отбраковывается. Кэш 3 минуты,
//! чтобы повторные входы не ждали; сбрасывается после неудачного
//! unlock (invalidateProbe). Genesis-проверка ядра при unlock всё
//! равно отвергнет сервер чужой сети — безопасность не зависит от
//! подбора.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:veyro/util/network_config.dart';

/// Кандидаты Electrum-серверов по коду сети. Для каждого есть
/// верифицированный дефолт, плюс альтернативы.
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

/// Сброс кэша подбора: после неудачного unlock следующая попытка
/// прониует кандидатов заново.
void invalidateProbe() {
  _bestCache.clear();
}

/// Лучший ЖИВЫЙ сервер для сети: минимальная задержка среди тех, кто
/// ответил на Electrum-запрос server.version (то, что нужно протоколу).
/// null — никто не ответил (unlock честно выдаст ошибку подключения).
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
    candidates.map(_electrumLatency),
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

/// Полный Electrum-зонд: соединение (TLS для ssl://, сертификат
/// проверяется системой) + запрос server.version; сервер жив, только
/// если ответил протоколом. Возвращает суммарную задержку, null —
/// мёртв/сломан.
Future<int?> _electrumLatency(String url) async {
  final match =
      RegExp(r'^(?:ssl|tcp)://([^:/]+):(\d+)').firstMatch(url);
  if (match == null) return null;
  final host = match.group(1)!;
  final port = int.parse(match.group(2)!);
  final secure = url.startsWith('ssl://');
  final watch = Stopwatch()..start();
  Socket? socket;
  StreamSubscription<Uint8List>? sub;
  try {
    socket = secure
        ? await SecureSocket.connect(
            host,
            port,
            timeout: const Duration(milliseconds: 2500),
            // Сертификат проверяется системным хранилищем: MITM не пропускаем.
            onBadCertificate: (_) => false,
          )
        : await Socket.connect(
            host,
            port,
            timeout: const Duration(milliseconds: 2500),
          );
    // Electrum — JSON-RPC по строкам; server.version самый дешёвый вызов.
    socket.write(
        '{"id":0,"method":"server.version","params":["veyro","1.4"]}\n');
    final answered = Completer<bool>();
    final buffer = <int>[];
    sub = socket.listen(
      (data) {
        buffer.addAll(data);
        final text = utf8.decode(buffer, allowMalformed: true);
        if (text.contains('"result"') || text.contains('"error"')) {
          if (!answered.isCompleted) answered.complete(true);
        }
      },
      onDone: () {
        if (!answered.isCompleted) answered.complete(false);
      },
      onError: (_) {
        if (!answered.isCompleted) answered.complete(false);
      },
      cancelOnError: true,
    );
    final ok = await answered.future
        .timeout(const Duration(milliseconds: 2500), onTimeout: () => false);
    watch.stop();
    socket.destroy();
    await sub.cancel();
    return ok ? watch.elapsedMilliseconds : null;
  } catch (_) {
    socket?.destroy();
    await sub?.cancel();
    return null;
  }
}
