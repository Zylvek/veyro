//! Переиспользуемые компоненты дизайн-системы VEYRO (спека docs/UI_SPEC.md,
//! «Create reusable Flutter components»). Все цвета — только утверждённые
//! токены; данные не имитируются: компоненты отображают то, что им отдано.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:veyro/design/app_colors.dart';

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

/// Карточка с заголовком-иконкой — базовый блок всех экранов (замена
/// SectionCard из util/ui_helpers в новых экранах; старые экраны мигрируют
/// в ходе своих групп).
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
    return Card(
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

/// Логотип-монограмма с утверждённым свечением акцента.
class VeyroLogo extends StatelessWidget {
  final double size;

  const VeyroLogo({super.key, this.size = 88});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [VColors.primary, VColors.primaryGlow],
        ),
        boxShadow: [
          BoxShadow(
            color: VColors.primaryGlow.withValues(alpha: 0.35),
            blurRadius: 32,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Text(
        'V',
        style: TextStyle(
          fontSize: size * 0.5,
          fontWeight: FontWeight.w800,
          color: VColors.background,
        ),
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
          tooltip: 'Копировать',
          icon: Icon(Icons.copy_outlined, size: 16, color: VColors.textSecondary),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: value));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$label скопировано')),
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
