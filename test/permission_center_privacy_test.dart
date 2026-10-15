import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/permission_center.dart';
import 'package:local_bluey/services/safety_gate.dart';

class _RecordingGate extends SafetyGate {
  _RecordingGate(this.verdict, this.seenTools);

  final bool verdict;
  final List<String> seenTools;
  @override
  Future<bool> authorize(String tool, Map<String, dynamic> arguments) {
    seenTools.add(tool);
    return Future<bool>.value(verdict);
  }
}

void main() {
  test('ac3 center keeps label-only provenance without transport', () {
    final source = File('lib/services/permission_center.dart')
        .readAsStringSync();
    expect(
      source.contains(RegExp("import '(dart:io|package:http|dart:convert)")),
      isFalse,
      reason: 'the center must not gain transport or serialization misuse',
    );
    expect(
      source.contains(RegExp(r'HttpClient|writeAsBytes|writeAsString|File\(')),
      isFalse,
      reason: 'the center must not gain artifact writers',
    );
    // No new storage: the registry stays in-memory and label-only.
    expect(source.contains('SharedPreferences'), isFalse);
  });

  test('ac3 grant lifecycle leaves no payload or secret echo', () async {
    final seen = <String>[];
    final center = PermissionCenter(safetyGate: _RecordingGate(false, seen));
    final grant = center.grant('camera');
    expect(await center.allows('camera'), isFalse);
    center.revoke('camera');
    expect(seen, contains('camera'));
    // The registry carries the identifier only; the default toString
    // carries nothing: no payload, identifier or exception text leaks
    // into logs through ObjectDiagnostic rendering.
    expect(grant.toString(), isNot(contains('camera')));
    final serialized = center.grants
        .map<String>((g) => '${g.id}:${g.isRevoked}')
        .join('|');
    expect(serialized, 'camera:true');

    // Re-granting the same identifier replaces the broken grant and the
    // previous grant object stays revoked (no resurrection on re-grant).
    final replacement = center.grant('camera');
    expect(replacement.id, 'camera');
    expect(replacement, isNot(same(grant)));
    expect(grant.isRevoked, isTrue);
  });
}
