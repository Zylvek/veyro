//! Система движений VEYRO (спека UI §12): сдержанно, 150–250 мс, без
//! декоративного свечения. Один источник правды для длительностей, кривых
//! и переходов страниц — никаких разнобойных MaterialPageRoute-переходов.

import 'package:flutter/material.dart';

/// Длительности движений (мс) — утверждённый диапазон спеки.
abstract final class VMotion {
  /// Микровзаимодействия (чипы, тапы, hover).
  static const Duration micro = Duration(milliseconds: 150);

  /// Стандартный переход страницы.
  static const Duration page = Duration(milliseconds: 220);

  /// Мягкая смена содержимого (балансы, статусы) — число «дышит»,
  /// а не прыгает.
  static const Duration contentSwap = Duration(milliseconds: 200);

  /// Full-replace (вход в каркас, Welcome) — чуть длиннее, это смена сцены.
  static const Duration scene = Duration(milliseconds: 260);

  /// Фирменные кривые: вход — мягкое затухание, выход — ускорение.
  static const Curve easeIn = Curves.easeOutCubic;
  static const Curve easeOut = Curves.easeInCubic;
}

/// Страница с брендовым переходом «fade-through»: новая страница мягко
/// проявляется с подъёмом на 20px, уходящая тает и опускается —
/// иерархия «вперёд/вглубь» читается без качелей-параллакса.
class VeyroRoute<T> extends PageRouteBuilder<T> {
  VeyroRoute({
    required WidgetBuilder builder,
    super.settings,
    super.fullscreenDialog,
  }) : super(
         pageBuilder: (context, animation, secondaryAnimation) =>
             builder(context),
         transitionDuration: VMotion.page,
         reverseTransitionDuration: VMotion.page,
         transitionsBuilder: (context, animation, secondaryAnimation, child) {
           final forward = CurvedAnimation(
             parent: animation,
             curve: VMotion.easeIn,
             reverseCurve: VMotion.easeOut,
           );
           final backward = CurvedAnimation(
             parent: secondaryAnimation,
             curve: VMotion.easeOut,
             reverseCurve: VMotion.easeIn,
           );
           // Уважение к системному «убрать анимации»: честный fade.
           final reduced = MediaQuery.of(context).disableAnimations;
           final slide = reduced ? 0.0 : (1 - forward.value) * 20;
           return FadeTransition(
             opacity: Tween<double>(begin: 0, end: 1).animate(forward),
             child: FadeTransition(
               opacity: Tween<double>(begin: 1, end: 0).animate(backward),
               child: Transform.translate(
                 offset: Offset(0, slide),
                 child: child,
               ),
             ),
           );
         },
       );
}

/// Полная смена сцены (lock → каркас, Welcome → каркас): только кросс-фейд,
/// без «прыжка» содержимого — резкий слайд на смене сцены читается дёшево.
class VeyroSceneRoute<T> extends PageRouteBuilder<T> {
  VeyroSceneRoute({required WidgetBuilder builder})
    : super(
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        transitionDuration: VMotion.scene,
        reverseTransitionDuration: VMotion.scene,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final t = CurvedAnimation(
            parent: animation,
            curve: VMotion.easeIn,
            reverseCurve: VMotion.easeOut,
          );
          return FadeTransition(
            opacity: Tween<double>(begin: 0, end: 1).animate(t),
            child: child,
          );
        },
      );
}

/// push с брендовым переходом (везде вместо MaterialPageRoute).
Future<T?> pushVeyro<T>(
  BuildContext context,
  Widget page, {
  bool fullscreenDialog = false,
}) => Navigator.of(
  context,
).push(VeyroRoute<T>(builder: (_) => page, fullscreenDialog: fullscreenDialog));

/// Заменить вершину стека с брендовым переходом.
Future<T?> pushReplacementVeyro<T>(BuildContext context, Widget page) =>
    Navigator.of(context).pushReplacement(VeyroRoute<T>(builder: (_) => page));

/// Сменить сцену целиком (каркас приложения): old stack — fade out.
Future<T?> resetToVeyro<T extends Object?>(BuildContext context, Widget page) =>
    Navigator.of(context).pushAndRemoveUntil(
      VeyroSceneRoute<T>(builder: (_) => page),
      (route) => false,
    );
