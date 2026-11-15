//! Переиспользуемые компоненты дизайн-системы VEYRO (спека docs/UI_SPEC.md,
//! «Create reusable Flutter components»). Все цвета — только утверждённые
//! токены; данные не имитируются: компоненты отображают то, что им отдано.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:veyro/design/app_colors.dart';
import 'package:veyro/design/ambience.dart';
import 'package:veyro/util/l10n.dart';

/// Максимальная ширина основного содержимого на desktop (аудит UI:
/// «ориентировочно 1400 px»; экраны перестают быть узкой колонкой).
const double kContentMaxWidth = 1400;

/// Двухколоночная раскладка рабочего стола: на широком экране — две
/// равные колонки со свободным пространством, на узком — стопка.
/// Каждая колонка сама решает, что в неё положить; пустые секции
/// возвращают SizedBox.shrink().
class VTwoColumn extends StatelessWidget {
  final Widget left;
  final Widget right;
  final double breakpoint;
  final double gap;

  const VTwoColumn({
    super.key,
    required this.left,
    required this.right,
    this.breakpoint = 1024,
    this.gap = 16,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= breakpoint) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: left),
              SizedBox(width: gap),
              Expanded(child: right),
            ],
          );
        }
        return Column(
          children: [
            SizedBox(width: double.infinity, child: left),
            SizedBox(height: gap),
            SizedBox(width: double.infinity, child: right),
          ],
        );
      },
    );
  }
}

/// Карточка-стекло с заголовком-иконкой — базовый блок всех экранов.
/// Матовый blur + полупрозрачная заливка поверх ambient-фона; данные
/// не имитируются: компонент отображает то, что ему отдано.
class VCard extends StatelessWidget {
  final String? title;
  final IconData? icon;
  final EdgeInsets padding;
  final List<Widget> children;

  const VCard({
    super.key,
    this.title,
    this.icon,
    this.padding = const EdgeInsets.all(16),
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: VColors.primary),
                    const SizedBox(width: 8),
                  ],
                  // Expanded: длинные заголовки переносятся, а не ломают
                  // строку переполнением.
                  Expanded(
                    child: Text(title!,
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                ],
              ),
            ),
          Padding(padding: padding, child: Column(children: children)),
        ],
      ),
    );
  }
}

/// Моноширинный текст для адресов, хешей и идентификаторов.
class VMono extends StatelessWidget {
  final String text;
  final bool selectable;
  final double fontSize;
  final Color? color;

  const VMono(
    this.text, {
    super.key,
    this.selectable = true,
    this.fontSize = 13,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: kMonoFont,
      fontSize: fontSize,
      color: color ?? VColors.textPrimary,
    );
    return selectable
        ? SelectableText(text, style: style)
        : Text(text, style: style);
  }
}

/// Отображение баланса: табличные цифры Inter (tnum), суффикс актива.
/// Компонент только форматирует отданное значение — никаких вычислений
/// и никакого фейка.
class VAmount extends StatelessWidget {
  final String value;
  final String? suffix;
  final double fontSize;
  final Color? color;

  const VAmount(
    this.value, {
    super.key,
    this.suffix,
    this.fontSize = 28,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          value,
          style: TextStyle(
            fontFamily: kInterFont,
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: color ?? scheme.onSurface,
          ),
        ),
        if (suffix != null) ...[
          const SizedBox(width: 6),
          Text(
            suffix!,
            style: TextStyle(
              fontSize: fontSize * 0.45,
              fontWeight: FontWeight.w500,
              color: VColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

/// Чип статуса. Цвета — по утверждённым семантическим токенам.
enum VChipKind { neutral, info, success, warning, error }

class VStatusChip extends StatelessWidget {
  final String label;
  final VChipKind kind;

  const VStatusChip(this.label, {super.key, this.kind = VChipKind.neutral});

  Color get _color {
    switch (kind) {
      case VChipKind.neutral:
        return VColors.textSecondary;
      case VChipKind.info:
        return VColors.secondary;
      case VChipKind.success:
        return VColors.success;
      case VChipKind.warning:
        return VColors.warning;
      case VChipKind.error:
        return VColors.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: VColors.elevated,
        border: Border.all(color: _color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: _color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          // Flexible: длинные подписи (например, состояние сессии с именем
          // кошелька) переносятся внутри чипа, а не ломают строку
          // переполнением.
          Flexible(
            child: Text(
              label,
              softWrap: true,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: _color,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Кнопка основного действия с индикатором занятости. Обёртка над
/// FilledButton/OutlinedButton с темой формы из темы; busy блокирует нажатия.
class VButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool busy;
  final bool secondary;
  final bool destructive;

  const VButton.primary(
    this.label, {
    super.key,
    this.icon,
    this.onPressed,
    this.busy = false,
  })  : secondary = false,
        destructive = false;

  const VButton.secondary(
    this.label, {
    super.key,
    this.icon,
    this.onPressed,
    this.busy = false,
  })  : secondary = true,
        destructive = false;

  const VButton.destructive(
    this.label, {
    super.key,
    this.icon,
    this.onPressed,
    this.busy = false,
  })  : secondary = false,
        destructive = true;

  @override
  Widget build(BuildContext context) {
    if (secondary) {
      return OutlinedButton.icon(
        onPressed: busy ? null : onPressed,
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        icon: _iconOrProgress(),
        label: Text(label),
      );
    }
    return FilledButton.icon(
      onPressed: busy ? null : onPressed,
      style:
          destructive ? FilledButton.styleFrom(backgroundColor: VColors.error) : null,
      icon: _iconOrProgress(),
      label: Text(label),
    );
  }

  Widget _iconOrProgress() {
    if (!busy) return Icon(icon ?? Icons.arrow_forward_outlined, size: 18);
    return const SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}

/// Экранная обёртка: одинаковая ширина контента на desktop и не растянутый
/// вид на широких окнах.
class VScreen extends StatelessWidget {
  final Widget child;
  final bool scrollable;

  const VScreen({super.key, required this.child, this.scrollable = true});

  @override
  Widget build(BuildContext context) {
    final content = SizedBox(
      width: 640,
      child: scrollable ? SingleChildScrollView(child: child) : child,
    );
    return Center(child: Padding(padding: const EdgeInsets.all(20), child: content));
  }
}

/// Заголовок раздела: крупный заголовок + подпись.
class VSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const VSectionHeader({super.key, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ],
    );
  }
}

/// Честное пустое состояние: почему пусто и что делать. Никаких имитаций.
class VEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const VEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 44, color: VColors.textSecondary),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
          ),
          if (action != null) ...[
            const SizedBox(height: 16),
            action!,
          ],
        ],
      ),
    );
  }
}

/// Логотип VEYRO: фирменный знак из assets/brand/logo.png
/// (скруглённый тёмно-фиолетовый квадрат, два пересекающихся круга).
/// Поставка — растровый PNG 512px авторского знака владельца; рисуется
/// на прозрачном фоне — тёмный интерфейс сам даёт контраст.
class VeyroLogo extends StatelessWidget {
  final double size;

  const VeyroLogo({super.key, this.size = 88});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        'assets/brand/logo.png',
        fit: BoxFit.contain,
      ),
    );
  }
}

/// Идентификатор типа «значение уже в буфере» — копирование тех. строк.
class VMonoCopyRow extends StatelessWidget {
  final String label;
  final String value;

  const VMonoCopyRow({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Expanded(child: VMono(value, fontSize: 12.5)),
        IconButton(
          tooltip: t('copy_tooltip'),
          icon: Icon(Icons.copy_outlined, size: 16, color: VColors.textSecondary),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: value));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(tf('copied_snackbar', {'label': label}))),
            );
          },
        ),
      ],
    );
  }
}

/// Сетка слов BIP39-фразы: 4 колонки по 6 слов (24 слова) на широких
/// экранах, 2 колонки на узких (телефон). Номер — маленькая плашка,
/// слово — моноширинно. Кнопки копирования нет намеренно: фразу
/// переписывают руками на бумагу.
class VMnemonicGrid extends StatelessWidget {
  final List<String> words;

  const VMnemonicGrid({super.key, required this.words});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 460 ? 4 : 2;
        final rowCount = (words.length / columns).ceil();
        return Column(
          children: [
            for (var r = 0; r < rowCount; r++) ...[
              if (r > 0) const SizedBox(height: 8),
              Row(
                children: [
                  for (var c = 0; c < columns; c++) ...[
                    if (c > 0) const SizedBox(width: 8),
                    Expanded(child: _cell(r * columns + c)),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _cell(int index) {
    if (index >= words.length) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: VColors.elevated),
        color: VColors.elevated.withValues(alpha: 0.35),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${index + 1}',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: VColors.textSecondary.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              words[index],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: kMonoFont,
                fontSize: 12.5,
                color: VColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Hero-карта баланса Обзора (референс владельца: большая тёмная карта
/// с радиальной подсветкой справа-сверху, светлая рамка, мягкая тень).
/// Реализована чистой Decoration'ом — без Stack, чтобы жить внутри
/// ленивого списка; контент свободный, поверхность рисует компонент.
class VHeroPanel extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;

  const VHeroPanel({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(22)),
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            offset: const Offset(0, 24),
            blurRadius: 60,
            spreadRadius: -20,
          ),
        ],
        // Подсветка primary из правого верхнего угла, как в референсе.
        gradient: const RadialGradient(
          center: Alignment(1.0, -1.1),
          radius: 1.6,
          colors: [VColors.primary, VColors.card],
          stops: [0.0, 0.6],
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          gradient: LinearGradient(
            begin: Alignment.bottomLeft,
            end: Alignment.center,
            colors: [
              VColors.secondary.withValues(alpha: 0.08),
              VColors.secondary.withValues(alpha: 0.0),
            ],
          ),
        ),
        child: child,
      ),
    );
  }
}

/// Линия реального курса ([values] — цены от старых к новым, [hints] —
/// подписи точек для наведения, той же длины; плоская серия рисуется
/// горизонталью). Наведение (как в референсе владельца): вертикальный
/// курсор, точка и подпись цены курса.
class VSparkline extends StatefulWidget {
  final List<double> values;
  final List<String>? hints;
  final double height;

  const VSparkline({
    super.key,
    required this.values,
    this.hints,
    this.height = 120,
  });

  /// Координаты точки серии внутри отрисовки (используются и painter'ом,
  /// и hover-оверлеем, чтобы курсор сидел точно на линии).
  static ({double x, double y}) pointOf(
    List<double> values,
    int index,
    Size size,
  ) {
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final span = max - min;
    final n = values.length;
    final x = n == 1 ? size.width : index * size.width / (n - 1);
    final double y;
    if (span == 0) {
      y = size.height * 0.62;
    } else {
      y = size.height * 0.92 - (values[index] - min) / span * size.height * 0.84;
    }
    return (x: x, y: y);
  }

  @override
  State<VSparkline> createState() => _VSparklineState();
}

class _VSparklineState extends State<VSparkline>
    with SingleTickerProviderStateMixin {
  int? _hover;

  /// Отрисовка линии «выезжанием» слева направо (как в референсе
  /// владельца); при смене серии (период 1Д→1Г) прокрут заново.
  late final AnimationController _draw = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 750),
  )..forward();

  static final Animatable<double> _drawCurve =
      CurveTween(curve: const Cubic(0.3, 0.9, 0.35, 1.0));

  bool _sameAs(List<double> a, List<double> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void didUpdateWidget(covariant VSparkline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameAs(oldWidget.values, widget.values)) {
      _hover = null;
      _draw.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _draw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final values = widget.values;
    final hints = widget.hints;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, widget.height);
        final hover = _hover;
        final settled = _draw.status == AnimationStatus.completed;
        return Stack(
          children: [
            SizedBox(
              height: widget.height,
              width: double.infinity,
              child: AnimatedBuilder(
                animation: _draw,
                builder: (context, _) => CustomPaint(
                  painter: _SparklinePainter(
                    values,
                    drawProgress: _drawCurve.evaluate(_draw),
                  ),
                ),
              ),
            ),
            // Наведение работает, когда линия полностью отрисована.
            if (settled && hover != null && hover >= 0 && hover < values.length) ...[
              _cursor(hover, values, size),
              _dot(hover, values, size),
              if (hints != null && hover < hints.length)
                _tooltip(hover, hints, values, size),
            ],
            // Полотно наведения — самый верхний слой.
            Positioned.fill(
              child: MouseRegion(
                cursor: SystemMouseCursors.precise,
                onHover: (event) {
                  final n = values.length;
                  if (n < 2) return;
                  final i =
                      ((event.localPosition.dx / size.width) * (n - 1))
                          .round()
                          .clamp(0, n - 1);
                  if (i != _hover) setState(() => _hover = i);
                },
                onExit: (_) {
                  if (_hover != null) setState(() => _hover = null);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Positioned _cursor(int index, List<double> values, Size size) {
    final p = VSparkline.pointOf(values, index, size);
    return Positioned(
      left: p.x - 0.5,
      top: 0,
      bottom: 0,
      width: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              VColors.primary.withValues(alpha: 0.0),
              VColors.primary.withValues(alpha: 0.55),
              VColors.primary.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    );
  }

  Positioned _dot(int index, List<double> values, Size size) {
    final p = VSparkline.pointOf(values, index, size);
    return Positioned(
      left: p.x - 5,
      top: p.y - 5,
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(color: VColors.primary, width: 2),
          boxShadow: [
            BoxShadow(
              color: VColors.primary.withValues(alpha: 0.45),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }

  Positioned _tooltip(
    int index,
    List<String> hints,
    List<double> values,
    Size size,
  ) {
    final p = VSparkline.pointOf(values, index, size);
    return Positioned(
      left: p.x.clamp(52, size.width - 52),
      top: (p.y - 12).clamp(0, widget.height),
      child: FractionalTranslation(
        translation: const Offset(-0.5, -1),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: VColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.11)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Text(
            hints[index],
            style: const TextStyle(
              fontFamily: kMonoFont,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: VColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;

  /// Доля отрисованной линии (0..1): «выезжание» слева направо.
  final double drawProgress;

  _SparklinePainter(this.values, {this.drawProgress = 1.0});

  /// Путь линии до доли [t] длины (последний сегмент интерполируется).
  Path pathUpTo(Size size, double t) {
    final path = Path();
    final n = values.length;
    final lastF = (n - 1) * t;
    final full = lastF.floor();
    var moved = false;
    for (var i = 0; i <= full && i < n; i++) {
      final p = VSparkline.pointOf(values, i, size);
      if (!moved) {
        path.moveTo(p.x, p.y);
        moved = true;
      } else {
        path.lineTo(p.x, p.y);
      }
    }
    if (full < n - 1) {
      final frac = lastF - full;
      final a = VSparkline.pointOf(values, full, size);
      final b = VSparkline.pointOf(values, full + 1, size);
      path.lineTo(a.x + (b.x - a.x) * frac, a.y + (b.y - a.y) * frac);
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final t = drawProgress.clamp(0.0, 1.0);
    final line = pathUpTo(size, t);

    final fill = Path.from(line);
    final endX = VSparkline.pointOf(values, values.length - 1, size).x * t;
    fill.lineTo(endX, size.height);
    fill.lineTo(
      VSparkline.pointOf(values, 0, size).x,
      size.height,
    );
    fill.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          VColors.primary.withValues(alpha: 0.30),
          VColors.primary.withValues(alpha: 0.0),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fill, fillPaint);

    final linePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [VColors.primaryGlow, VColors.primary, VColors.secondary],
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(line, linePaint);
  }

  @override
  bool shouldRepaint(_SparklinePainter oldDelegate) =>
      !identical(oldDelegate.values, values) ||
      oldDelegate.values.length != values.length ||
      oldDelegate.drawProgress != drawProgress;
}
