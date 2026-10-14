import 'package:flutter/material.dart';

import '../core/models/analysis.dart';
import '../core/theme/app_color_tokens.dart';

class SeverityDot extends StatelessWidget {
  const SeverityDot({super.key, required this.severity, this.size = 10});

  final Severity severity;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = context.colors;
    final color = switch (severity) {
      Severity.high => tokens.severityHigh,
      Severity.medium => tokens.severityMedium,
      Severity.low => tokens.severityLow,
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
