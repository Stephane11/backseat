import 'package:flutter/material.dart';

/// Exact design-token colors from the Backseat design system, exposed as a
/// [ThemeExtension] so bespoke widgets (cards, chips, pill bar, transcript)
/// can read them directly instead of approximating via [ColorScheme] slots.
@immutable
class AppColorTokens extends ThemeExtension<AppColorTokens> {
  const AppColorTokens({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
    required this.severityHigh,
    required this.severityMedium,
    required this.severityLow,
  });

  final Color background;
  final Color surface;
  final Color surfaceRaised;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color accent;
  final Color severityHigh;
  final Color severityMedium;
  final Color severityLow;

  static const dark = AppColorTokens(
    background: Color(0xFF1C1B1A),
    surface: Color(0xFF262624),
    surfaceRaised: Color(0xFF30302E),
    border: Color(0xFF3A3936),
    textPrimary: Color(0xFFECEAE4),
    textSecondary: Color(0xFFA3A09A),
    accent: Color(0xFFE07A5F),
    severityHigh: Color(0xFFE5674F),
    severityMedium: Color(0xFFE0A458),
    severityLow: Color(0xFF7FA88A),
  );

  static const light = AppColorTokens(
    background: Color(0xFFFAF9F5),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFF0EEE6),
    border: Color(0xFFE5E2D9),
    textPrimary: Color(0xFF1F1E1D),
    textSecondary: Color(0xFF6B6862),
    accent: Color(0xFFC9603F),
    severityHigh: Color(0xFFE5674F),
    severityMedium: Color(0xFFE0A458),
    severityLow: Color(0xFF7FA88A),
  );

  @override
  AppColorTokens copyWith({
    Color? background,
    Color? surface,
    Color? surfaceRaised,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? accent,
    Color? severityHigh,
    Color? severityMedium,
    Color? severityLow,
  }) {
    return AppColorTokens(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      accent: accent ?? this.accent,
      severityHigh: severityHigh ?? this.severityHigh,
      severityMedium: severityMedium ?? this.severityMedium,
      severityLow: severityLow ?? this.severityLow,
    );
  }

  @override
  AppColorTokens lerp(ThemeExtension<AppColorTokens>? other, double t) {
    if (other is! AppColorTokens) return this;
    return AppColorTokens(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      severityHigh: Color.lerp(severityHigh, other.severityHigh, t)!,
      severityMedium: Color.lerp(severityMedium, other.severityMedium, t)!,
      severityLow: Color.lerp(severityLow, other.severityLow, t)!,
    );
  }
}

extension AppColorTokensContext on BuildContext {
  AppColorTokens get colors => Theme.of(this).extension<AppColorTokens>()!;
}
