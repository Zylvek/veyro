//! Генератор windows/runner/resources/app_icon.ico из фирменного знака
//! VEYRO — 1-в-1 параметры отрисовщика знака в приложении
//! (lib/design/veyro_mark.dart): два круга r 100 с чётным вырезом
//! пересечения, дистанция центров 55, знак повёрнут на +45°,
//! градиент #638CFF→#48C8F5→#638CFF по диагонали (в системе знака),
//! тёмная плашка #080D19 со скруглением 20% и прозрачными углами.
//!
//! Чистый Dart (без Flutter): антивысвеченная отрисовка суперсэмплом,
//! кадры 16..128 в ICO-BMP (BGRA), 256 — вложенный PNG.
//! Запуск: dart run tool/gen_app_icon.dart (из apps/veyro).

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

// --- Константы знака (идентичны painter'у приложения). ---------------
const double _scene = 400.0;
const double _markRadius = 100.0;
const double _markDistance = 55.0;
const double _cornerShare = 0.20; // радиус скругления плашки, доля стороны

const List<int> _gradA = [0x63, 0x8C, 0xFF]; // #638CFF
const List<int> _gradB = [0x48, 0xC8, 0xF5]; // #48C8F5
const List<int> _bg = [0x08, 0x0D, 0x19]; // #080D19

int _lerp8(int a, int b, double t) =>
    (a + (b - a) * t).round().clamp(0, 255);

/// RGBA (straight) кадр размера [size] × [size].
Uint8List _render(int size) {
  const ss = 3; // суперсэмплинг 3×3 на пиксель
  const ss2 = ss * ss;
  final data = Uint8List(size * size * 4);
  final c = math.sqrt(0.5), s = math.sqrt(0.5);
  final cornerHalf = 200.0 - _cornerShare * 200.0;
  final cornerR = _cornerShare * 200.0;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      double bgCov = 0, mkCov = 0, cr = 0, cg = 0, cb = 0;
      for (var sy = 0; sy < ss; sy++) {
        for (var sx = 0; sx < ss; sx++) {
          // Координаты сцены (−200..200, Y вниз — как в painter'е).
          final px = (x + (sx + 0.5) / ss) / size * _scene - 200;
          final py = (y + (sy + 0.5) / ss) / size * _scene - 200;
          // Плашка: квадрат с прозрачными скруглёнными углами.
          final dx = math.max(0.0, px.abs() - cornerHalf);
          final dy = math.max(0.0, py.abs() - cornerHalf);
          if (dx * dx + dy * dy <= cornerR * cornerR) bgCov += 1;
          // Знак живёт в системе ДО поворота: обратный ход +45°.
          final qx = c * px + s * py;
          final qy = -s * px + c * py;
          final inA = (qx + _markDistance) * (qx + _markDistance) +
                  qy * qy <=
              _markRadius * _markRadius;
          final inB = (qx - _markDistance) * (qx - _markDistance) +
                  qy * qy <=
              _markRadius * _markRadius;
          // evenodd: залиты оба круга, пересечение (линза) — прозрачное.
          if (inA != inB) {
            mkCov += 1;
            final t = ((qx + qy + 400) / 800).clamp(0.0, 1.0);
            final rr = t <= 0.5 ? _gradA[0] : _gradB[0];
            final gg = t <= 0.5 ? _gradA[1] : _gradB[1];
            final bb = t <= 0.5 ? _gradA[2] : _gradB[2];
            final k = t <= 0.5 ? t * 2 : (t - 0.5) * 2;
            cr += _lerp8(rr, t <= 0.5 ? _gradB[0] : _gradA[0], k);
            cg += _lerp8(gg, t <= 0.5 ? _gradB[1] : _gradA[1], k);
            cb += _lerp8(bb, t <= 0.5 ? _gradB[2] : _gradA[2], k);
          }
        }
      }
      final idx = (y * size + x) * 4;
      final mkA = mkCov / ss2;
      final bgA = bgCov / ss2;
      final outA = mkA + bgA * (1 - mkA);
      if (outA <= 0) continue; // прозрачный угол
      final mkR = mkCov > 0 ? cr / mkCov : 0.0;
      final mkG = mkCov > 0 ? cg / mkCov : 0.0;
      final mkB = mkCov > 0 ? cb / mkCov : 0.0;
      final bgW = bgA * (1 - mkA);
      data[idx] = ((mkR * mkA + _bg[0] * bgW) / outA).round().clamp(0, 255);
      data[idx + 1] =
          ((mkG * mkA + _bg[1] * bgW) / outA).round().clamp(0, 255);
      data[idx + 2] =
          ((mkB * mkA + _bg[2] * bgW) / outA).round().clamp(0, 255);
      data[idx + 3] = (outA * 255).round().clamp(0, 255);
    }
  }
  return data;
}

// --- ICO-BMP кадр (BGRA снизу вверх + нулевая AND-маска). ------------
Uint8List _icoBmpFrame(int size, Uint8List rgba) {
  final andRow = ((size + 31) ~/ 32) * 4;
  final header = ByteData(40)
    ..setUint32(0, 40, Endian.little) // biSize
    ..setInt32(4, size, Endian.little) // biWidth
    ..setInt32(8, size * 2, Endian.little) // biHeight = XOR + AND
    ..setUint16(12, 1, Endian.little) // biPlanes
    ..setUint16(14, 32, Endian.little) // biBitCount
    ..setUint32(16, 0, Endian.little) // BI_RGB
    ..setUint32(20, size * size * 4 + andRow * size, Endian.little);
  final out = BytesBuilder()..add(header.buffer.asUint8List());
  for (var y = size - 1; y >= 0; y--) {
    for (var x = 0; x < size; x++) {
      final i = (y * size + x) * 4;
      out.add([rgba[i + 2], rgba[i + 1], rgba[i], rgba[i + 3]]);
    }
  }
  out.add(Uint8List(andRow * size));
  return out.toBytes();
}

// --- PNG-вложение (для кадра 256). ------------------------------------
final List<int> _crcTable = () {
  final table = List<int>.generate(256, (n) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
    }
    return c;
  });
  return table;
}();

int _crc32(List<int> data) {
  var crc = -1;
  for (final byte in data) {
    crc = _crcTable[(crc ^ byte) & 0xFF] ^ (crc >>> 8);
  }
  return (crc ^ -1) & 0xFFFFFFFF;
}

void _chunk(BytesBuilder out, String type, List<int> data) {
  final len = ByteData(4)..setUint32(0, data.length, Endian.big);
  out.add(len.buffer.asUint8List());
  out.add(type.codeUnits);
  out.add(data);
  final crc = ByteData(4)
    ..setUint32(0, _crc32([...type.codeUnits, ...data]), Endian.big);
  out.add(crc.buffer.asUint8List());
}

Uint8List _pngEncode(int size, Uint8List rgba) {
  final out = BytesBuilder()
    ..add([137, 80, 78, 71, 13, 10, 26, 10]); // подпись PNG
  final ihdr = ByteData(13)
    ..setUint32(0, size, Endian.big)
    ..setUint32(4, size, Endian.big)
    ..setUint8(8, 8) // глубина
    ..setUint8(9, 6) // RGBA
    ..setUint8(12, 0); // without interlace
  _chunk(out, 'IHDR', ihdr.buffer.asUint8List());
  final stride = size * 4;
  final raw = Uint8List(size * (stride + 1));
  for (var y = 0; y < size; y++) {
    raw.setRange(y * (stride + 1) + 1, (y + 1) * (stride + 1),
        Uint8List.sublistView(rgba, y * stride, (y + 1) * stride));
  }
  _chunk(out, 'IDAT', zlib.encode(raw));
  _chunk(out, 'IEND', const <int>[]);
  return out.toBytes();
}

// --- Сборка ICO. -------------------------------------------------------
void main() {
  const sizes = [16, 24, 32, 48, 64, 128, 256];
  final frames = <Uint8List>[];
  final asPng = <bool>[];
  for (final size in sizes) {
    final rgba = _render(size);
    if (size <= 128) {
      frames.add(_icoBmpFrame(size, rgba));
      asPng.add(false);
    } else {
      frames.add(_pngEncode(size, rgba));
      asPng.add(true);
    }
    stdout.writeln('frame $size done');
  }
  final entry =
      BytesBuilder(); // 6 байт каталога + 16*count байт описаний кадров
  final dir = ByteData(6)
    ..setUint16(0, 0, Endian.little) // reserved
    ..setUint16(2, 1, Endian.little) // тип: иконка
    ..setUint16(4, sizes.length, Endian.little);
  entry.add(dir.buffer.asUint8List());
  var offset = 6 + sizes.length * 16;
  final entries = <int>[];
  for (var i = 0; i < sizes.length; i++) {
    final size = sizes[i];
    final w = size >= 256 ? 0 : size;
    final e = ByteData(16)
      ..setUint8(0, w)
      ..setUint8(1, w)
      ..setUint8(2, 0) // цветов в палитре нет
      ..setUint8(3, 0) // reserved
      ..setUint16(4, 1, Endian.little) // planes
      ..setUint16(6, 32, Endian.little) // bitCount
      ..setUint32(8, frames[i].length, Endian.little)
      ..setUint32(12, offset, Endian.little);
    entries.addAll(e.buffer.asUint8List());
    offset += frames[i].length;
  }
  entry.add(entries);
  for (final f in frames) {
    entry.add(f);
  }
  final file = File('windows/runner/resources/app_icon.ico');
  file.writeAsBytesSync(entry.toBytes(), flush: true);
  stdout.writeln('written ${file.path} '
      '(${file.lengthSync()} bytes, ${sizes.length} frames)');
}
