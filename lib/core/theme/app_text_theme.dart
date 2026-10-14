import 'package:flutter/material.dart';

const _serif = 'Source Serif 4';
const _sans = 'Inter';

/// Content (transcript, cards, headings) uses the serif family; UI chrome
/// (buttons, chips, labels, timestamps) uses the sans family (brief §6).
TextTheme buildAppTextTheme(Color primary, Color secondary) {
  return TextTheme(
    headlineLarge: TextStyle(
      fontFamily: _serif,
      fontSize: 28,
      fontWeight: FontWeight.w600,
      height: 1.25,
      color: primary,
    ),
    headlineMedium: TextStyle(
      fontFamily: _serif,
      fontSize: 24,
      fontWeight: FontWeight.w600,
      height: 1.25,
      color: primary,
    ),
    headlineSmall: TextStyle(
      fontFamily: _serif,
      fontSize: 22,
      fontWeight: FontWeight.w600,
      height: 1.3,
      color: primary,
    ),
    titleLarge: TextStyle(
      fontFamily: _serif,
      fontSize: 18,
      fontWeight: FontWeight.w600,
      height: 1.3,
      color: primary,
    ),
    titleMedium: TextStyle(
      fontFamily: _serif,
      fontSize: 17,
      fontWeight: FontWeight.w600,
      height: 1.4,
      color: primary,
    ),
    titleSmall: TextStyle(
      fontFamily: _sans,
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: primary,
    ),
    bodyLarge: TextStyle(
      fontFamily: _serif,
      fontSize: 17,
      fontWeight: FontWeight.w400,
      height: 1.5,
      color: primary,
    ),
    bodyMedium: TextStyle(
      fontFamily: _serif,
      fontSize: 15,
      fontWeight: FontWeight.w400,
      height: 1.5,
      color: primary,
    ),
    bodySmall: TextStyle(
      fontFamily: _sans,
      fontSize: 13,
      fontWeight: FontWeight.w400,
      color: secondary,
    ),
    labelLarge: TextStyle(
      fontFamily: _sans,
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: primary,
    ),
    labelMedium: TextStyle(
      fontFamily: _sans,
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: primary,
    ),
    labelSmall: TextStyle(
      fontFamily: _sans,
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: secondary,
    ),
  );
}
