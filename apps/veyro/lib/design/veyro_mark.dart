//! Фирменный знак VEYRO из системы лого-анимаций владельца (HTML-референс
//! DeepSeek). Знак — два круга с вырезанным пересечением (evenodd),
//! градиент primary→accent→primary по диагонали; круги вращаются по
//! орбите, дышат радиусом и сближаются-отдаляются.
//!
//! Система (референс 01/02/03):
//! - [VeyroMarkSpinner] — орбитальная загрузка (01);
//! - [VeyroMarkIntro] — вход в приложение: кругы из-за краёв, оборот,
//!   сход к знаку + колбек по завершении (02);
//! - [VeyroMarkBackdrop] — приглушённый вращающийся знак-фон (03).

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:veyro/design/app_colors.dart';

// ---------------------------------------------------------------------------
// Геометрия и константы системы (числа владельца).
// ---------------------------------------------------------------------------

Path _circlePath(double cx, double cy, double r) {
  return Path()
    ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
}

/// Знак: два окружност-контура, пересечение вырезано (evenodd).
Path _markPath(double ax, double ay, double ar, double bx, double by,
    double br) {
  return Path.combine(
    PathOperation.difference,
    _circlePath(ax, ay, ar),
    _circlePath(bx, by, br),
  );
}

const double kMarkRadius = 100;
const double kMarkDistance = 55;

/// Параметры орбитальной загрузки (референс LOAD).
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
// Отрисовщик знака.
// ---------------------------------------------------------------------------

class _MarkPainter extends CustomPainter {
  final double ax, ay, ar;

  _MarkPainter({
    required this.ax,
    required this.ay,
    required this.ar,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Координаты знака: −200..200, Y вверх (как в SVG-референсе).
    final s = math.min(size.width, size.height) / 400.0;
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(s, -s);

    final path = _markPath(ax, ay, ar, -ax, -ay, ar);
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..shader = ui.Gradient.linear(
        const Offset(-200, -200),
        const Offset(200, 200),
        const [VColors.primaryGlow, VColors.secondary, VColors.primary],
        const [0, 0.5, 1.0],
      );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) =>
      oldDelegate.ax != ax ||
      oldDelegate.ay != ay ||
      oldDelegate.ar != ar;
}

// ---------------------------------------------------------------------------
// Статичный знак.
// ---------------------------------------------------------------------------

/// Бренд-знак в статике (пропорции референса STATIC_D).
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
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Анимация 01: орбитальная загрузка.
// ---------------------------------------------------------------------------

/// Бесконечная орбитальная загрузка: круги ходят по орбите, дышат
/// радиусом и дистанцией (числа владельца из LOAD).
class VeyroMarkSpinner extends StatefulWidget {
  final double size;

  const VeyroMarkSpinner({super.key, this.size = 220});

  @override
  State<VeyroMarkSpinner> createState() => _VeyroMarkSpinnerState();
}

class _VeyroMarkSpinnerState extends State<VeyroMarkSpinner>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  MarkOrbitState _state = const MarkOrbitState(angle: 0, radius: 72, distance: 42);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      setState(() => _state =
          _loadingState(elapsed.inMicroseconds / 1000.0));
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
// Анимация 02: вход в приложение (интро перед экраном пароля).
// ---------------------------------------------------------------------------

double _easeOutCubic(double x) => 1 - math.pow(1 - x, 3).toDouble();
double _easeInOutCubic(double x) =>
    x < 0.5 ? 4 * x * x * x : 1 - math.pow(-2 * x + 2, 3) / 2;
double _lerp(double a, double b, double t) => a + (b - a) * t;

/// Интро (референс anim2, DUR 2600мс): большие круги выезжают из-за
/// краёв, делают один полный оборот, уменьшаются к знаку; по завершении
/// вызывается [onDone] — экран сменяется формой входа.
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
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _MarkPainter(ax: math.cos(ang) * d, ay: math.sin(ang) * d, ar: r),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Анимация 03: приглушённый вращающийся знак-фон.
// ---------------------------------------------------------------------------

/// Приглушённый знак (референс bg3: r 88, d 46, opacity 0.18),
/// вращающийся по той же орбите — фоновая декорация экрана пароля.
class VeyroMarkBackdrop extends StatefulWidget {
  final double size;

  const VeyroMarkBackdrop({super.key, this.size = 300});

  @override
  State<VeyroMarkBackdrop> createState() => _VeyroMarkBackdropState();
}

class _VeyroMarkBackdropState extends State<VeyroMarkBackdrop>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  MarkOrbitState _state = const MarkOrbitState(angle: 0, radius: 88, distance: 46);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final live = _loadingState(elapsed.inMicroseconds / 1000.0);
      setState(() => _state = MarkOrbitState(
            angle: live.angle,
            radius: 88,
            distance: 46,
          ));
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
    return Opacity(
      opacity: 0.18,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: _MarkPainter(
            ax: math.cos(_state.angle) * _state.distance,
            ay: math.sin(_state.angle) * _state.distance,
            ar: _state.radius,
          ),
        ),
      ),
    );
  }
}

