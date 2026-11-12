//! Ambient-фон VEYRO (glass-слой): тёмная база + мягкие световые пятна
//! (primary/secondary в малой альфе), поверх которых лежат матовые
//! стеклянные карточки (VCard с BackdropFilter). Один и тот же слой
//! используется в каркасе, на входе и на бренд-экране — стекло читается
//! именно потому, что за карточками есть что размывать.

import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:veyro/design/app_colors.dart';

/// Ambient-фон: цвет базы + 3 мягких радиальных свечения. Всё рисуется
/// в одном виджете, чтобы карточки-стёкла размывали именно его.
class AmbienceSurface extends StatelessWidget {
  final Widget child;

  const AmbienceSurface({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: VColors.background),
      child: Stack(
        children: [
          // Свечение 1: синее — верхний левый угол.
          Positioned(
            left: -160,
            top: -220,
            child: _glow(560, VColors.primaryGlow.withValues(alpha: 0.10)),
          ),
          // Свечение 2: бирюзовое (secondary) — правый край.
          Positioned(
            right: -220,
            bottom: -260,
            child:
                _glow(640, VColors.secondary.withValues(alpha: 0.07)),
          ),
          // Свечение 3: слабый центр снизу.
          Positioned(
            left: 80,
            bottom: -320,
            child:
                _glow(520, VColors.primary.withValues(alpha: 0.05)),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }

  Widget _glow(double size, Color color) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}

/// Матовая стеклянная поверхность: размытие того, что за ней, + слегка
/// прозрачная заливка + светлая рамка сверху. Используется карточками,
/// сайдбаром, панелью входа и диалогами.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final double sigma;
  final double fillOpacity;

  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.sigma = 16,
    this.fillOpacity = 0.72,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        // Material(canvas) держит заливку и красит ink НАД ней — иначе
        // ListTile бросает предупреждение о невидимых сплешах.
        child: Material(
          color: VColors.card.withValues(alpha: fillOpacity),
          shape: RoundedRectangleBorder(
            borderRadius: borderRadius,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.05),
                  Colors.white.withValues(alpha: 0.0),
                ],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
