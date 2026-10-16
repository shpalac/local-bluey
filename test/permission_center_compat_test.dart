import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/permission_center.dart';
import 'package:local_bluey/services/routines.dart';
import 'package:local_bluey/services/safety_gate.dart';

class _AllowAllGate extends SafetyGate {
  _AllowAllGate(this.verdict);
  final bool verdict;
  @override
  Future<bool> authorize(String tool, Map<String, dynamic> arguments) =>
      Future<bool>.value(verdict);
}

void main() {
  test('ac4 center stays per-flavor identical with no platform branch', () {
    final source = File('lib/services/permission_center.dart')
        .readAsStringSync();
    expect(source.contains('TargetPlatform'), isFalse);
    expect(source.contains('defaultTargetPlatform'), isFalse);
  });

  test('ac4 the same lifecycle holds on every supported flavor', () async {
    for (final platform in [
      TargetPlatform.iOS,
      TargetPlatform.android,
      TargetPlatform.macOS,
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final center = PermissionCenter(safetyGate: _AllowAllGate(true));
        final grant = center.grant('camera');
        expect(await center.allows('camera'), isTrue);
        center.revoke('camera');
        expect(await center.allows('camera'), isFalse, reason: '$platform');
        expect(await center.allows('unknown'), isFalse, reason: '$platform');
        final again = center.grant('camera');

        // Fresh grant object: the old one remains revoked forever.
        expect(again.isRevoked, isFalse);
        expect(grant.isRevoked, isTrue);
        expect(await center.allows('camera'), isTrue);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }
  });

  test('ac4 legacy routines remain untouched by the center', () async {
    const original = Routine(
      name: 'Reminder',
      trigger: 'remind me',
      instructions: 'notify:Take a break',
    );
    final before = original.toJson();
    final center = PermissionCenter(safetyGate: _AllowAllGate(true));
    center.grant('routine-reminder');
    expect(center.grants.single.id, 'routine-reminder');
    center.revoke('routine-reminder');
    expect(await center.allows('routine-reminder'), isFalse);
    // Fail closed for unknown identifiers on every call path.
    expect(await center.allows('never-granted'), isFalse);
    expect(original.toJson(), before);
  });
}
