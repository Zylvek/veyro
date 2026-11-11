//! Дизайн-система VEYRO — утверждённая палитра Electric Blue Dark.
//! Источник истины: docs/UI_SPEC.md («Approved colors»). Значения совпадают
//! с утверждёнными 1-в-1; направление менять без владельца запрещено.

import 'package:flutter/material.dart';

/// Утверждённые цвета интерфейса. Никаких новых оттенков вне этой палитры:
/// производные значения — только прозрачности поверх этих цветов.
abstract final class VColors {
  /// Фон приложения.
  static const Color background = Color(0xFF080D19);

  /// Поверхности (панели,AppBar, нижняя навигация).
  static const Color surface = Color(0xFF101A2D);

  /// Карточки.
  static const Color card = Color(0xFF14213A);

  /// Приподнятые элементы (выделение, hover, шапка сайдбара).
  static const Color elevated = Color(0xFF1D2D4A);

  /// Основной акцент (кнопки, активные элементы).
  static const Color primary = Color(0xFF638CFF);

  /// Свечение акцента (градиенты, фокус).
  static const Color primaryGlow = Color(0xFF397BFF);

  /// Вторичный акцент.
  static const Color secondary = Color(0xFF48C8F5);

  /// Успешные состояния.
  static const Color success = Color(0xFF35C98A);

  /// Предупреждения.
  static const Color warning = Color(0xFFF2B85B);

  /// Ошибки.
  static const Color error = Color(0xFFF16B79);

  /// Основной текст.
  static const Color textPrimary = Color(0xFFF5F8FF);

  /// Вторичный текст.
  static const Color textSecondary = Color(0xFF8B9BB5);
}

/// Имя подключённого в pubspec шрифта интерфейса (Inter, OFL).
const String kInterFont = 'Inter';

/// Имя моноширинного шрифта для адресов, хешей и технических идентификаторов
/// (JetBrains Mono, OFL).
const String kMonoFont = 'JetBrainsMono';
