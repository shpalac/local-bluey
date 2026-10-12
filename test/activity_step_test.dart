import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/activity_step.dart';

void main() {
  ActivityStep sample() => ActivityStep(
    stepId: 'step_1',
    sessionId: 'session_1',
    timestamp: DateTime.utc(2026, 10, 11, 12, 30),
    kind: ActivityKind.pointer,
    classification: ActivityClassification.internal,
    confidence: 0.75,
  );

  test('canonical round-trip', () {
    final value = sample();
    expect(ActivityStep.decode(value.encode()).encode(), value.encode());
    expect(value.toJson()['schemaVersion'], 1);
  });

  test('unknown version and extra payload fields fail closed', () {
    final json = sample().toJson();
    expect(
      () => ActivityStep.fromJson({...json, 'schemaVersion': 2}),
      throwsA(isA<ActivityStepFormatException>()),
    );
    expect(
      () => ActivityStep.fromJson({...json, 'rawScreenshot': 'secret'}),
      throwsA(isA<ActivityStepFormatException>()),
    );
    expect(
      () => ActivityStep.fromJson({...json}..remove('sessionId')),
      throwsA(isA<ActivityStepFormatException>()),
    );
  });

  test('unknown enum, malformed json and invalid types rejected', () {
    final json = sample().toJson();
    expect(
      () => ActivityStep.fromJson({...json, 'kind': 'screenshot'}),
      throwsA(isA<ActivityStepFormatException>()),
    );
    expect(
      () => ActivityStep.fromJson({...json, 'confidence': '0.5'}),
      throwsA(isA<ActivityStepFormatException>()),
    );
    expect(
      () => ActivityStep.decode('{bad'),
      throwsA(isA<ActivityStepFormatException>()),
    );
  });

  test('confidence must be finite within zero to one', () {
    final json = sample().toJson();
    for (final value in [-0.1, 1.1, double.nan, double.infinity]) {
      expect(
        () => ActivityStep.fromJson({...json, 'confidence': value}),
        throwsA(isA<ActivityStepFormatException>()),
      );
    }
    for (final value in [0, 1]) {
      expect(
        ActivityStep.fromJson({...json, 'confidence': value}).confidence,
        value.toDouble(),
      );
    }
  });

  test('UTC and opaque safe IDs required', () {
    final json = sample().toJson();
    expect(
      () => ActivityStep.fromJson({
        ...json,
        'timestamp': '2026-10-11T12:30:00+03:00',
      }),
      throwsA(isA<ActivityStepFormatException>()),
    );
    expect(
      () => ActivityStep.fromJson({...json, 'stepId': '../private'}),
      throwsA(isA<ActivityStepFormatException>()),
    );
  });

  test('no capture, IO, or lifecycle side effects in DTO', () {
    final json = sample().toJson();
    expect(json.keys.toSet(), {
      'schemaVersion',
      'stepId',
      'sessionId',
      'timestamp',
      'kind',
      'classification',
      'confidence',
    });
  });
}
