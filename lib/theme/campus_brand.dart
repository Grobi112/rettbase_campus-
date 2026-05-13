import 'package:flutter/material.dart';

/// RettBase Campus – Markenfarben und Light-Theme.
/// Spezifikation: `design.md` im Projektroot.
abstract final class CampusBrand {
  /// Hero Red – Primär, Hilfe / Sanitätsdienst.
  static const Color heroRed = Color(0xFFE63946);

  /// Deep Slate – Konturen, sekundäre UI-Kanten (Rahmen der Felder), **Material-Buttons** (Fläche).
  static const Color deepSlate = Color(0xFF2B2D42);

  /// Fließtext, AppBar-Typo und Floating-Labels (#2B2D24).
  static const Color bodyText = Color(0xFF2B2D24);

  /// Soft Shell – neutrale Flächen, medizinisch-sauber; **Schrift auf Buttons** (auf Deep Slate).
  static const Color softShell = Color(0xFFF8F9FA);

  /// Alert Orange – wichtige, nicht lebenskritische Hinweise.
  static const Color alertOrange = Color(0xFFF4A261);

  /// Für echte Fehlerzustände (nicht identisch mit Hero Red).
  static const Color errorRed = Color(0xFFBA1A1A);

  static ColorScheme _colorScheme() {
    final slate = deepSlate;
    const ink = bodyText;
    return ColorScheme.fromSeed(
      seedColor: heroRed,
      brightness: Brightness.light,
      primary: heroRed,
      onPrimary: Colors.white,
      secondary: alertOrange,
      onSecondary: slate,
      surface: Colors.white,
      onSurface: ink,
      error: errorRed,
      onError: Colors.white,
    ).copyWith(
      primaryContainer: const Color(0xFFFFDAD8),
      onPrimaryContainer: ink,
      secondaryContainer: const Color(0xFFFFDCC4),
      onSecondaryContainer: ink,
      tertiary: slate,
      onTertiary: Colors.white,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: softShell,
      surfaceContainer: softShell,
      surfaceContainerHigh: const Color(0xFFEEEFF1),
      surfaceContainerHighest: const Color(0xFFE8E8EC),
      onSurfaceVariant: ink.withValues(alpha: 0.62),
      outline: slate.withValues(alpha: 0.35),
      outlineVariant: slate.withValues(alpha: 0.2),
      surfaceTint: heroRed,
    );
  }

  /// Light-Theme für Campus-App und Admin-Einstieg.
  static ThemeData theme() {
    final scheme = _colorScheme();
    final slate = deepSlate;
    const ink = bodyText;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: softShell,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: Colors.white,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: ink),
        titleTextStyle: TextStyle(
          color: ink,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        indicatorColor: heroRed,
        labelColor: heroRed,
        unselectedLabelColor: ink.withValues(alpha: 0.55),
        dividerColor: slate.withValues(alpha: 0.12),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        surfaceTintColor: heroRed,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          foregroundColor: softShell,
          backgroundColor: slate,
          disabledForegroundColor: softShell.withValues(alpha: 0.55),
          disabledBackgroundColor: slate.withValues(alpha: 0.45),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          foregroundColor: softShell,
          backgroundColor: slate,
          elevation: 0,
          shadowColor: Colors.transparent,
          disabledForegroundColor: softShell.withValues(alpha: 0.55),
          disabledBackgroundColor: slate.withValues(alpha: 0.45),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: softShell,
          backgroundColor: slate,
          disabledForegroundColor: softShell.withValues(alpha: 0.55),
          disabledBackgroundColor: slate.withValues(alpha: 0.45),
          side: BorderSide(color: slate),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: softShell,
          backgroundColor: slate,
          disabledForegroundColor: softShell.withValues(alpha: 0.55),
          disabledBackgroundColor: slate.withValues(alpha: 0.45),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: slate.withValues(alpha: 0.35)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: slate.withValues(alpha: 0.28)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: heroRed, width: 2),
        ),
        labelStyle: const TextStyle(color: ink),
        floatingLabelStyle: const TextStyle(color: ink),
        helperStyle: TextStyle(color: ink.withValues(alpha: 0.62)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: deepSlate,
        foregroundColor: softShell,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: heroRed),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: slate,
        contentTextStyle: const TextStyle(color: Colors.white),
        actionTextColor: alertOrange,
        behavior: SnackBarBehavior.floating,
      ),
      dividerTheme: DividerThemeData(color: slate.withValues(alpha: 0.12)),
      listTileTheme: ListTileThemeData(
        iconColor: ink.withValues(alpha: 0.65),
        textColor: ink,
      ),
    );
  }

  /// Outline-Eingabefelder wie Login/Admin: [InputDecoration.applyDefaults] auf das Theme-`inputDecorationTheme`.
  static InputDecoration outlineField(
    BuildContext context, {
    required String labelText,
    String? helperText,
    String? errorText,
    Widget? prefixIcon,
    Widget? suffixIcon,
    bool isDense = false,
  }) {
    return InputDecoration(
      labelText: labelText,
      helperText: helperText,
      errorText: errorText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      isDense: isDense,
      floatingLabelBehavior: FloatingLabelBehavior.always,
    ).applyDefaults(Theme.of(context).inputDecorationTheme);
  }
}
