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

/// Safe storage failure from an appearance read, write or explicit clear.
class ThemeStorageException implements Exception {
  /// No raw storage details are included.
  const ThemeStorageException();

  @override
  String toString() => 'Appearance preference could not be updated.';
}

/// System-following theme with a persisted manual override (#87).
class ThemeController extends ChangeNotifier {
  ThemeController._({
    Future<String?> Function()? read,
    Future<bool> Function(String)? write,
    Future<bool> Function()? remove,
  }) : _read =
           read ??
           (() async =>
               (await SharedPreferences.getInstance()).getString(_kMode)),
       _write =
           write ??
           ((value) async => (await SharedPreferences.getInstance()).setString(
             _kMode,
             value,
           )),
       _remove =
           remove ??
           (() async => (await SharedPreferences.getInstance()).remove(_kMode));

  /// Isolated actual-storage-entry seams for synthetic tests.
  @visibleForTesting
  ThemeController.forTest({
    required Future<String?> Function() read,
    required Future<bool> Function(String) write,
    required Future<bool> Function() remove,
  }) : this._(read: read, write: write, remove: remove);

  /// App-wide appearance owner.
  static final ThemeController instance = ThemeController._();
  static const _kMode = 'theme.mode';
  final Future<String?> Function() _read;
  final Future<bool> Function(String) _write;
  final Future<bool> Function() _remove;
  Future<void> _io = Future<void>.value();
  int _generation = 0;
  bool _disposed = false;
  ThemeMode _mode = ThemeMode.system;

  /// Last successfully persisted mode, or successfully loaded preference.
  ThemeMode get mode => _mode;

  void _publish(ThemeMode mode, int generation) {
    if (_disposed || generation != _generation) return;
    _mode = mode;
    notifyListeners();
  }

  Future<void> _enqueue(Future<void> Function(int generation) action) {
    final generation = ++_generation;
    final next = _io.then((_) async {
      try {
        await action(generation);
      } catch (_) {
        // An older successful write may have reached storage before a newer
        // failed mutation. Reconcile only the current owner, never publish a
        // stale operation's proposed value or raw error.
        if (!_disposed && generation == _generation) {
          try {
            final stored = await _read();
            _publish(
              ThemeMode.values.asNameMap()[stored] ?? ThemeMode.system,
              generation,
            );
          } catch (_) {}
        }
        throw const ThemeStorageException();
      }
    });
    _io = next.catchError((_) {});
    return next;
  }

  /// Loads in the same storage order; superseded reads cannot publish.
  Future<void> load() => _enqueue((generation) async {
    final stored = await _read();
    _publish(
      ThemeMode.values.asNameMap()[stored] ?? ThemeMode.system,
      generation,
    );
  });

  /// Publishes only after storage reports success. Later intents own state.
  Future<void> setMode(ThemeMode mode) => _enqueue((generation) async {
    if (generation != _generation) return;
    if (!await _write(mode.name)) throw const ThemeStorageException();
    _publish(mode, generation);
  });

  /// Explicit registry deletion, ordered after entered writes. The active
  /// override resets to System only when removal succeeds.
  Future<void> clear() => _enqueue((generation) async {
    if (!await _remove()) throw const ThemeStorageException();
    _publish(ThemeMode.system, generation);
  });

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
