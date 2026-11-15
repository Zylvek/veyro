//! Фирменный знак VEYRO из системы лого-анимаций владельца (HTML-референс
//! DeepSeek). Знак — два круга с вырезанным пересечением (evenodd),
//! градиент #638CFF→#48C8F5→#638CFF по диагонали; весь знак повёрнут
//! на 45° (в анимации 02 — на −45°); круги вращаются по орбите, дышат
//! радиусом и сближаются-отдаляются.
//!
//! Компонент и режимы (ТЗ владельца):
//! - [LogoLoader] — единый компонент с `mode`:
//!   loading / appEntry / backgroundToLoading;
//! - [VeyroMarkSpinner] — анимация 01, бесконечная загрузка;
//! - [VeyroMarkIntro] — анимация 02, вход в приложение (2600 мс, −45°);
//! - [VeyroMarkBackgroundToLoading] — анимация 03, из приглушённого
//!   фона (0.18) в живую загрузку (1800 мс) без остановки вращения;
//! - [VeyroMarkBackdrop] — приглушённый живой знак-фон экрана пароля;
//! - [VeyroMark] — статичный знак.
//!
//! Технические требования ТЗ: никаких drop-shadow-фильтров (лаги),
//! только AnimationController/Ticker; вырез пересечения — evenodd.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:veyro/design/app_colors.dart';

// ---------------------------------------------------------------------------
// Геометрия и константы системы (числа владельца).
// ---------------------------------------------------------------------------

/// Знак: ОДИН путь с двумя кругами и fill-type evenodd — прямой
/// аналог SVG-референса (`logoD = circleD + circleD`,
/// `fill-rule="evenodd"`): залиты оба круга, а их пересечение (линза)
/// прозрачное. Важно: Path.combine(difference) здесь не годится — он
/// вычитает один круг из другого и оставляет один полумесяц вместо
/// двух кругов.
Path _markPath(double ax, double ay, double ar, double bx, double by,
    double br) {
  return Path()
    ..fillType = PathFillType.evenOdd
    ..addOval(Rect.fromCircle(center: Offset(ax, ay), radius: ar))
    ..addOval(Rect.fromCircle(center: Offset(bx, by), radius: br));
}

/// Пропорции статичного знака (референс STATIC_D).
const double kMarkRadius = 100;
const double kMarkDistance = 55;

/// Приглушённый знак-фон (референс anim3 start): r 88, d 46, opacity 0.18.
const double kBackdropRadius = 88;
const double kBackdropDistance = 46;
const double kBackdropOpacity = 0.18;

/// Длина перехода «фон → загрузка», мс (референс anim3).
const int kBgToLoadingMs = 1800;

/// Общая эпоха системы лого-анимаций — аналог `performance.now() − tStart`
/// в HTML-референсе: все живые знаки (фон, загрузка) крутятся и дышат
/// в одной фазе, поэтому смена виджетов «фон → загрузка» не рвёт вращение.
final Stopwatch _systemClock = Stopwatch()..start();

/// Миллисекунды общего хода времени системы (однократное интро живёт
/// по своему собственному таймеру — как в референсе).
double _systemMs() => _systemClock.elapsedMicroseconds / 1000.0;

/// Живая загрузка: угол орбиты, радиус и дистанция дышат синусоидами
/// (числа владельца из LOAD; d < r всегда — вырез не исчезает).
MarkOrbitState _loadingState(double elapsedMs) {
  const angSpeed = 0.0018;
  const rBase = 72.0, rAmp = 10.0, rSpeed = 0.0009, rPhase = 1.2;
  const dBase = 42.0, dAmp = 3.0, dSpeed = 0.0006;
  return MarkOrbitState(
    angle: elapsedMs * angSpeed,
    radius: rBase + rAmp * math.sin(elapsedMs * rSpeed + rPhase),
    distance: dBase + dAmp * math.sin(elapsedMs * dSpeed),
  );
}

/// Текущее состояние орбиты знака.
class MarkOrbitState {
  final double angle; // рад
  final double radius;
  final double distance;

  const MarkOrbitState({
    required this.angle,
    required this.radius,
    required this.distance,
  });
}

// ---------------------------------------------------------------------------
// Отрисовщик знака (круги + evenodd + градиент + поворот ±45°).
// ---------------------------------------------------------------------------

class _MarkPainter extends CustomPainter {
  final double ax, ay, ar;

  /// Поворот всего знака, градусы: +45 — норма (референс
  /// transform="rotate(45)"), −45 — анимация 02 «вход в приложение».
  final double angleDeg;

  /// Прозрачность знака — штампуется прямо в краску (без слоёв/фильтров).
  final double opacity;

  _MarkPainter({
    required this.ax,
    required this.ay,
    required this.ar,
    this.angleDeg = 45,
    this.opacity = 1,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Координаты знака: −200..200, Y вверх (как в SVG-референсе).
    final s = math.min(size.width, size.height) / 400.0;
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(s, -s);
    // Весь знак повёрнут на 45° (и градиент вместе с ним).
    canvas.rotate(angleDeg * math.pi / 180);

    final path = _markPath(ax, ay, ar, -ax, -ay, ar);
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..shader = ui.Gradient.linear(
        const Offset(-200, -200),
        const Offset(200, 200),
        const [VColors.primary, VColors.secondary, VColors.primary],
        const [0, 0.5, 1.0],
      );
    if (opacity < 1) paint.color = paint.color.withValues(alpha: opacity);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) =>
      oldDelegate.ax != ax ||
      oldDelegate.ay != ay ||
      oldDelegate.ar != ar ||
      oldDelegate.angleDeg != angleDeg ||
      oldDelegate.opacity != opacity;
}

// ---------------------------------------------------------------------------
// Статичный знак.
// ---------------------------------------------------------------------------

/// Бренд-знак в статике (пропорции референса STATIC_D), поворот +45°.
class VeyroMark extends StatelessWidget {
  final double size;
  final double opacity;

  const VeyroMark({super.key, this.size = 88, this.opacity = 1});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _MarkPainter(
          ax: kMarkDistance,
          ay: 0,
          ar: kMarkRadius,
          opacity: opacity,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Анимация 01: орбитальная загрузка (режим loading).
// ---------------------------------------------------------------------------

/// Бесконечная орбитальная загрузка: круги ходят по орбите, дышат
/// радиусом и дистанцией (числа владельца из LOAD). Время берётся из
/// общего хода системы — как performance.now() в референсе.
class VeyroMarkSpinner extends StatefulWidget {
  final double size;

  const VeyroMarkSpinner({super.key, this.size = 220});

  @override
  State<VeyroMarkSpinner> createState() => _VeyroMarkSpinnerState();
}

class _VeyroMarkSpinnerState extends State<VeyroMarkSpinner>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  MarkOrbitState _state =
      const MarkOrbitState(angle: 0, radius: 72, distance: 42);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      setState(() => _state = _loadingState(_systemMs()));
    });
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: CustomPaint(
        painter: _MarkPainter(
          ax: math.cos(_state.angle) * _state.distance,
          ay: math.sin(_state.angle) * _state.distance,
          ar: _state.radius,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Подготовленные функции (ТЗ): lerp и ослабления.
// ---------------------------------------------------------------------------

double _easeOutQuad(double x) => 1 - (1 - x) * (1 - x);
double _easeOutCubic(double x) => 1 - math.pow(1 - x, 3).toDouble();
double _easeInOutCubic(double x) =>
    x < 0.5 ? 4 * x * x * x : 1 - math.pow(-2 * x + 2, 3) / 2;
double _lerp(double a, double b, double t) => a + (b - a) * t;

// ---------------------------------------------------------------------------
// Анимация 02: вход в приложение (режим app-entry).
// ---------------------------------------------------------------------------

/// Интро (референс anim2, 2600 мс): большие круги выезжают из-за краёв,
/// делают один полный оборот, уменьшаются к знаку; знак повёрнут на
/// −45°; после 62% прогресса плавно тает до 0.12 — на его фоне
/// появляется UI экрана пароля. По завершении вызывается [onDone].
class VeyroMarkIntro extends StatefulWidget {
  final double size;
  final VoidCallback? onDone;

  const VeyroMarkIntro({super.key, this.size = 260, this.onDone});

  @override
  State<VeyroMarkIntro> createState() => _VeyroMarkIntroState();
}

class _VeyroMarkIntroState extends State<VeyroMarkIntro>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 2600);
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          widget.onDone?.call();
        }
      })
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final p = math.min(_controller.value, 1.0);
        final eRot = _easeInOutCubic(p);
        final eSz = _easeOutCubic(p);
        // Формулы владельца: старт из-за краёв (d 820, r 330).
        final ang = -math.pi / 2 + eRot * math.pi * 2;
        final d = _lerp(820, 78, eSz);
        final r = _lerp(330, 150, eSz);
        // Таяние знака после 62% прогресса (до 0.12, референс anim2).
        final fade =
            p <= 0.62 ? 1.0 : _lerp(1.0, 0.12, (p - 0.62) / 0.38);
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _MarkPainter(
              ax: math.cos(ang) * d,
              ay: math.sin(ang) * d,
              ar: r,
              angleDeg: -45,
              opacity: fade,
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Приглушённый знак-фон экрана пароля.
// ---------------------------------------------------------------------------

/// Живой приглушённый знак (r 88, d 46, opacity 0.18): ходит по той же
/// орбите в общей фазе системы — при переходе в загрузку вращение не
/// заметит смены виджета.
class VeyroMarkBackdrop extends StatefulWidget {
  final double size;

  const VeyroMarkBackdrop({super.key, this.size = 300});

  @override
  State<VeyroMarkBackdrop> createState() => _VeyroMarkBackdropState();
}

class _VeyroMarkBackdropState extends State<VeyroMarkBackdrop>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _angle = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      setState(() => _angle = _loadingState(_systemMs()).angle);
    });
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: CustomPaint(
        painter: _MarkPainter(
          ax: math.cos(_angle) * kBackdropDistance,
          ay: math.sin(_angle) * kBackdropDistance,
          ar: kBackdropRadius,
          opacity: kBackdropOpacity,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Анимация 03: из приглушённого фона в живую загрузку.
// ---------------------------------------------------------------------------

/// Переход «фон → загрузка» (референс anim3, 1800 мс) без единой
/// остановки: угол ВСЕГДА берётся из живой загрузки и не
/// интерполируется; первые 1800 мс через easeOutQuad плавно едут
/// только радиус, дистанция и прозрачность
/// (r: 88→liveR, d: 46→liveD, opacity: 0.18→1). Дальше — чистая
/// загрузка, тот же Ticker продолжается без перезапуска.
class VeyroMarkBackgroundToLoading extends StatefulWidget {
  final double size;

  const VeyroMarkBackgroundToLoading({super.key, this.size = 300});

  @override
  State<VeyroMarkBackgroundToLoading> createState() =>
      _VeyroMarkBackgroundToLoadingState();
}

class _VeyroMarkBackgroundToLoadingState
    extends State<VeyroMarkBackgroundToLoading>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  MarkOrbitState _state = const MarkOrbitState(
    angle: 0,
    radius: kBackdropRadius,
    distance: kBackdropDistance,
  );
  double _opacity = kBackdropOpacity;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      // Прогресс перехода — от момента запуска этого виджета.
      final localMs = elapsed.inMicroseconds / 1000.0;
      final p = math.min(localMs / kBgToLoadingMs, 1.0);
      final e = _easeOutQuad(p);
      // Живое состояние загрузки — общий ход времени системы.
      final live = _loadingState(_systemMs());
      setState(() {
        _state = MarkOrbitState(
          angle: live.angle, // Вращение НЕ интерполируется.
          radius: _lerp(kBackdropRadius, live.radius, e),
          distance: _lerp(kBackdropDistance, live.distance, e),
        );
        _opacity = _lerp(kBackdropOpacity, 1.0, e);
      });
    });
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: CustomPaint(
        painter: _MarkPainter(
          ax: math.cos(_state.angle) * _state.distance,
          ay: math.sin(_state.angle) * _state.distance,
          ar: _state.radius,
          opacity: _opacity,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Фасад системы лого-анимаций (один компонент, prop mode).
// ---------------------------------------------------------------------------

/// Режимы [LogoLoader] (ТЗ владельца, референс 01/02/03).
enum LogoLoaderMode {
  /// Анимация 01 — бесконечная орбитальная загрузка.
  loading,

  /// Анимация 02 — вход в приложение: 2600 мс, знак повёрнут на −45°,
  /// по завершении вызывается [LogoLoader.onDone].
  appEntry,

  /// Анимация 03 — из приглушённого знака-фона (0.18) в живую загрузку
  /// (1800 мс) без остановки вращения.
  backgroundToLoading,
}

/// Единая точка входа в систему лого-анимаций владельца:
/// `LogoLoader(mode: ...)`.
class LogoLoader extends StatelessWidget {
  final LogoLoaderMode mode;
  final double size;

  /// Колбек по завершении (используется в режиме appEntry).
  final VoidCallback? onDone;

  const LogoLoader({
    super.key,
    required this.mode,
    this.size = 220,
    this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    switch (mode) {
      case LogoLoaderMode.loading:
        return VeyroMarkSpinner(size: size);
      case LogoLoaderMode.appEntry:
        return VeyroMarkIntro(size: size, onDone: onDone);
      case LogoLoaderMode.backgroundToLoading:
        return VeyroMarkBackgroundToLoading(size: size);
    }
  }
}
