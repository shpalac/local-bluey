import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Design tokens: semantic colors, spacing, and type (#87).
class AppTokens {
  AppTokens._();

  // Semantic colors - single source for light and dark (#87).
  static const lightPrimary = Color(0xFF1565C0);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightOnSurface = Color(0xFF1A1C1E);
  static const darkPrimary = Color(0xFF90CAF9);
  static const darkSurface = Color(0xFF1A1C1E);
  static const darkOnSurface = Color(0xFFE3E2E6);

  static const statusOkLight = Color(0xFF1B5E20);
  static const statusOkDark = Color(0xFFA5D6A7);
  static const statusErrLight = Color(0xFFB71C1C);
  static const statusErrDark = Color(0xFFEF9A9A);

  // Spacing scale.
  static const spaceS = 8.0;
  static const spaceM = 16.0;
  static const spaceL = 24.0;

  // Type scale.
  static const typeBody = 16.0;
  static const typeTitle = 20.0;

  /// WCAG contrast ratio between two colors (1..21).
  static double contrastRatio(Color a, Color b) {
    double lum(Color c) {
      double ch(double v) => v <= 0.03928
          ? v / 12.92
          : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
      return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
    }

    final l1 = math.max(lum(a), lum(b));
    final l2 = math.min(lum(a), lum(b));
    return (l1 + 0.05) / (l2 + 0.05);
  }

  static const wcagAA = 4.5;

  /// True when every semantic text/status color passes WCAG AA on its
  /// surface, in both themes (#87).
  static bool contrastPassesAA() {
    final pairs = <(Color, Color)>[
      (lightOnSurface, lightSurface),
      (darkOnSurface, darkSurface),
      (statusOkLight, lightSurface),
      (statusErrLight, lightSurface),
      (statusOkDark, darkSurface),
      (statusErrDark, darkSurface),
      (lightPrimary, lightSurface),
      (darkPrimary, darkSurface),
    ];
    return pairs.every((p) => contrastRatio(p.$1, p.$2) >= wcagAA);
  }
}

/// Light and dark themes built from the same token set (#87).
class AppTheme {
  AppTheme._();

  static ThemeData light() => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: const ColorScheme.light(
      primary: AppTokens.lightPrimary,
      surface: AppTokens.lightSurface,
      onSurface: AppTokens.lightOnSurface,
    ),
  );

  static ThemeData dark() => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: AppTokens.darkPrimary,
      surface: AppTokens.darkSurface,
      onSurface: AppTokens.darkOnSurface,
    ),
  );
}

/// System-following theme with a persisted manual override (#87).
class ThemeController extends ChangeNotifier {
  ThemeController._();
  static final ThemeController instance = ThemeController._();

  static const _kMode = 'theme.mode';

  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  Future<void> load() async {
    final v = (await SharedPreferences.getInstance()).getString(_kMode);
    _mode = ThemeMode.values.asNameMap()[v] ?? ThemeMode.system;
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    _mode = mode;
    await (await SharedPreferences.getInstance()).setString(_kMode, mode.name);
    notifyListeners();
  }
}
