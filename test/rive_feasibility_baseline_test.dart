import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// BLU-032 baseline: Rive is not adopted yet, so the native painter is the
/// only renderer and acts as the no-Rive fallback. This guards that baseline
/// so a Rive dependency cannot land without an explicit feasibility decision.
void main() {
  test(
    'no Rive runtime dependency is declared, native painter is the fallback',
    () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final declared = RegExp(r'^\s+(rive|rive_native)\s*:', multiLine: true);
      expect(declared.hasMatch(pubspec), isFalse);

      final lock = File('pubspec.lock').readAsStringSync();
      expect(
        RegExp(r'^  (rive|rive_native):', multiLine: true).hasMatch(lock),
        isFalse,
      );

      final painter = File('lib/ui/bluey_character.dart').readAsStringSync();
      expect(painter, contains('CustomPainter'));
      expect(RegExp(r'package:rive').hasMatch(painter), isFalse);
    },
  );
}
