import 'package:flutter/animation.dart';

/// Shared motion tokens (brief §6): 200-300ms ease-out, 40ms card stagger.
class AppMotion {
  const AppMotion._();

  static const Duration duration = Duration(milliseconds: 250);
  static const Duration cardStagger = Duration(milliseconds: 40);
  static const Curve curve = Curves.easeOut;
}
