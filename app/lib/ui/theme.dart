import 'package:flutter/material.dart';

/// Paleta da interface.
///
/// Tons escuros com laranja como cor de destaque, no mesmo espírito do editor
/// original, mas com contraste verificado para texto pequeno.
class AppTheme {
  static const Color background = Color(0xFF121212);
  static const Color surface = Color(0xFF1C1C1E);
  static const Color surfaceHigh = Color(0xFF262629);
  static const Color accent = Color(0xFFF28A2E);
  static const Color accentDim = Color(0xFF7A4A1E);
  static const Color text = Color(0xFFEDEDED);
  static const Color textDim = Color(0xFF9A9A9F);
  static const Color success = Color(0xFF4CAF50);
  static const Color danger = Color(0xFFE05252);

  static ThemeData build() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: background,
      colorScheme: base.colorScheme.copyWith(
        primary: accent,
        secondary: accent,
        surface: surface,
        onSurface: text,
      ),
      textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: accent,
        inactiveTrackColor: surfaceHigh,
        thumbColor: accent,
      ),
      tooltipTheme: const TooltipThemeData(
        decoration: BoxDecoration(
          color: surfaceHigh,
          borderRadius: BorderRadius.all(Radius.circular(6)),
        ),
        textStyle: TextStyle(color: text, fontSize: 12),
      ),
    );
  }
}
