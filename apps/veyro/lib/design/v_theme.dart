//! Тема VEYRO: сборка ThemeData из утверждённых токенов (app_colors.dart).
//! Один источник стиля для всех платформ: desktop и Android используют
//! одинаковые цвет и форму; различается только навигация (сайдбар/бар).

import 'package:flutter/material.dart';

import 'package:veyro/design/app_colors.dart';

/// Собранная тема приложения. Экспортируется для MaterialApp и виджетов.
ThemeData buildVeyroTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: VColors.primary,
    onPrimary: VColors.background,
    primaryContainer: VColors.elevated,
    onPrimaryContainer: VColors.textPrimary,
    secondary: VColors.secondary,
    onSecondary: VColors.background,
    secondaryContainer: VColors.elevated,
    onSecondaryContainer: VColors.textPrimary,
    error: VColors.error,
    onError: VColors.background,
    errorContainer: VColors.card,
    onErrorContainer: VColors.textPrimary,
    surface: VColors.surface,
    onSurface: VColors.textPrimary,
    surfaceContainerHighest: VColors.elevated,
    onSurfaceVariant: VColors.textSecondary,
    outline: VColors.elevated,
    outlineVariant: VColors.elevated,
  );

  final base = ThemeData.dark().textTheme;
  final textTheme = base
      .apply(
        bodyColor: VColors.textPrimary,
        displayColor: VColors.textPrimary,
        fontFamily: kInterFont,
      )
      .copyWith(
        headlineLarge: const TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
          color: VColors.textPrimary,
        ),
        headlineMedium: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
          color: VColors.textPrimary,
        ),
        titleLarge: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: VColors.textPrimary,
        ),
        titleMedium: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: VColors.textPrimary,
        ),
        bodyLarge: const TextStyle(fontSize: 15, color: VColors.textPrimary),
        bodyMedium: const TextStyle(
          fontSize: 13.5,
          height: 1.5,
          color: VColors.textSecondary,
        ),
        bodySmall: const TextStyle(
          fontSize: 12,
          height: 1.4,
          color: VColors.textSecondary,
        ),
      );

  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: VColors.elevated),
  );

  return ThemeData(
    useMaterial3: true,
    fontFamily: kInterFont,
    colorScheme: scheme,
    // Scaffold/ AppBar прозрачные: под КАЖДЫМ экраном лежит глобальный
    // бренд-фон (амбьент-свечения + приглушённый знак) из builder'а
    // MaterialApp (решение владельца «добавь их везде»).
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: VColors.background,
    textTheme: textTheme,
    // Мягкие переходы между экранами: fade + микроподъём вместо резкой
    // системной анимации.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.windows: _VeyroPageTransition(),
        TargetPlatform.linux: _VeyroPageTransition(),
        TargetPlatform.android: _VeyroPageTransition(),
      },
    ),
    dividerTheme: const DividerThemeData(
      color: VColors.elevated,
      thickness: 1,
      space: 1,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      foregroundColor: VColors.textPrimary,
      titleTextStyle: TextStyle(
        fontFamily: kInterFont,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: VColors.textPrimary,
      ),
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      color: Colors.transparent, // карточка-стекло рисует VCard (GlassPanel)
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: Color(0xCC14213A), // стеклянный диалог (85% card)
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: VColors.surface,
      modalBackgroundColor: VColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: VColors.background,
      hintStyle: const TextStyle(color: VColors.textSecondary, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: VColors.primary, width: 1.5),
      ),
      disabledBorder: border,
      errorBorder: border.copyWith(
        borderSide: const BorderSide(color: VColors.error),
      ),
      focusedErrorBorder: border.copyWith(
        borderSide: const BorderSide(color: VColors.error, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: VColors.primary,
        foregroundColor: VColors.background,
        minimumSize: const Size.fromHeight(48),
        textStyle: const TextStyle(
          fontFamily: kInterFont,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: VColors.primary,
        minimumSize: const Size.fromHeight(48),
        side: const BorderSide(color: VColors.elevated),
        textStyle: const TextStyle(
          fontFamily: kInterFont,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: VColors.primary,
        textStyle: const TextStyle(
          fontFamily: kInterFont,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: VColors.elevated,
      contentTextStyle: TextStyle(color: VColors.textPrimary),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? VColors.primary
            : VColors.card,
      ),
      side: const BorderSide(color: VColors.textSecondary),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: VColors.primary,
      linearTrackColor: VColors.elevated,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: VColors.surface,
      indicatorColor: VColors.elevated,
    ),
    listTileTheme: const ListTileThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    dropdownMenuTheme: const DropdownMenuThemeData(
      textStyle: TextStyle(color: VColors.textPrimary, fontSize: 15),
    ),
  );
}

/// Переход экранов VEYRO: fade + мягкий микроподъём, коротко и дорого.
class _VeyroPageTransition extends PageTransitionsBuilder {
  const _VeyroPageTransition();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.02),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
