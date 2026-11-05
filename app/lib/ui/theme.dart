import 'package:flutter/material.dart';

/// Paleta e tipografia da interface.
///
/// Tons escuros com laranja como cor de destaque, no mesmo espirito do editor
/// original, mas com contraste conferido para texto pequeno: `textDim` sobre
/// `surface` fica acima de 4.5:1, o minimo AA para corpo de texto.
class AppTheme {
  static const Color background = Color(0xFF0F0F11);
  static const Color surface = Color(0xFF18181B);
  static const Color surfaceHigh = Color(0xFF242428);
  static const Color stroke = Color(0xFF323238);
  static const Color accent = Color(0xFFF59331);
  static const Color accentDim = Color(0xFF7A4A1E);
  static const Color accentSoft = Color(0x33F59331);
  static const Color text = Color(0xFFF2F2F3);
  static const Color textDim = Color(0xFF9E9EA6);
  static const Color success = Color(0xFF57C46A);
  static const Color danger = Color(0xFFE4605C);

  /// Raio padrao de cartoes e paineis.
  static const double radius = 16;

  /// Altura minima de alvo de toque (Material recomenda 48).
  static const double touch = 44;

  /// Familia de texto do app.
  ///
  /// Empacotada em `assets/fonts` junto com a fonte de icones: sem ela o
  /// Flutter cai na fonte do sistema, que no Windows quebra a acentuacao em
  /// alguns pesos.
  static const String fontFamily = 'Roboto';

  static ThemeData build() {
    final base = ThemeData.dark(useMaterial3: true);
    final scheme = base.colorScheme.copyWith(
      primary: accent,
      secondary: accent,
      surface: surface,
      surfaceContainerHighest: surfaceHigh,
      onSurface: text,
      onSurfaceVariant: textDim,
      outline: stroke,
      error: danger,
    );
    return base.copyWith(
      scaffoldBackgroundColor: background,
      colorScheme: scheme,
      textTheme: base.textTheme
          .apply(fontFamily: fontFamily, bodyColor: text, displayColor: text)
          .copyWith(
            titleMedium: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
            ),
            labelSmall: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
            bodySmall: const TextStyle(fontSize: 12, color: textDim),
          ),
      dividerTheme: const DividerThemeData(color: stroke, thickness: 1),
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: accent,
        inactiveTrackColor: surfaceHigh,
        thumbColor: accent,
        overlayColor: accentSoft,
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) =>
              states.contains(WidgetState.selected) ? background : textDim,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) =>
              states.contains(WidgetState.selected) ? accent : surfaceHigh,
        ),
        trackOutlineColor: const WidgetStatePropertyAll<Color>(stroke),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: surfaceHigh,
        selectedColor: accentSoft,
        side: const BorderSide(color: stroke),
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
      dropdownMenuTheme: const DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll<Color>(surfaceHigh),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: background,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: text,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side: const BorderSide(color: stroke),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: surfaceHigh,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: stroke),
        ),
        textStyle: const TextStyle(color: AppTheme.text, fontSize: 12),
        waitDuration: const Duration(milliseconds: 400),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceHigh,
        contentTextStyle: const TextStyle(color: text, fontSize: 13),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll<Color>(
          textDim.withValues(alpha: 0.35),
        ),
        radius: const Radius.circular(8),
      ),
    );
  }

  /// Cartao padrao da interface.
  static BoxDecoration card({bool highlighted = false}) => BoxDecoration(
    color: surface,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: highlighted ? accent.withValues(alpha: 0.55) : stroke,
    ),
  );
}
