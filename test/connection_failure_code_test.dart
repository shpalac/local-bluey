import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/connection_error.dart';

void main() {
  test('every connection kind has an explicit unique stable code', () {
    final expected = {
      ConnectionFailureKind.refused: 'connection.refused',
      ConnectionFailureKind.timeout: 'connection.timeout',
      ConnectionFailureKind.unreachableHost: 'connection.unreachable_host',
      ConnectionFailureKind.tls: 'connection.tls',
      ConnectionFailureKind.unauthorized: 'connection.unauthorized',
      ConnectionFailureKind.wrongPath: 'connection.wrong_path',
      ConnectionFailureKind.modelMissing: 'connection.model_missing',
      ConnectionFailureKind.other: 'connection.other',
    };
    expect(expected.keys.toSet(), ConnectionFailureKind.values.toSet());
    expect(expected.values.toSet(), hasLength(expected.length));
    for (final entry in expected.entries) {
      final failure = ConnectionFailure(
        kind: entry.key,
        summary: 'fabricated summary',
        details: 'fabricated-secret',
        target: 'fixture.invalid:443',
      );
      expect(entry.key.code, entry.value);
      expect(failure.code, entry.value);
      expect(failure.code, isNot(contains(failure.details)));
      expect(failure.code, isNot(contains(failure.target)));
    }
  });
  test('classification exposes same code without changing raw details', () {
    final timeout = TimeoutException('fabricated-private-error');
    final result = describeConnectionFailure(
      timeout,
      'https://fixture.invalid',
    );
    expect(result.code, 'connection.timeout');
    expect(result.details, timeout.toString());
    expect(result.summary, contains('fixture.invalid:443'));
    expect(result.code, isNot(contains('private')));
  });
}
