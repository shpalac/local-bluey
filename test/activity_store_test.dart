import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/activity_step.dart';
import 'package:local_bluey/services/activity_store.dart';

void main() {
  var clock = DateTime.utc(2026, 10, 12, 10);
  ActivityStore store({
    Duration retention = const Duration(hours: 1),
    Duration session = const Duration(minutes: 5),
    int capacity = 2,
  }) => ActivityStore.memoryOnly(
    now: () => clock,
    retention: retention,
    sessionLength: session,
    capacity: capacity,
  );

  ActivityStep step(String id, {DateTime? at}) => ActivityStep(
    stepId: id,
    sessionId: 'session_1',
    timestamp: at ?? clock,
    kind: ActivityKind.navigation,
    classification: ActivityClassification.internal,
    confidence: 0.5,
  );

  setUp(() => clock = DateTime.utc(2026, 10, 12, 10));

  test(
    'observation cannot record without per-session consent and approval',
    () {
      final history = store();
      expect(history.isActive, isFalse);
      expect(history.startSession(consentConfirmed: false), isFalse);
      expect(history.add(step('a'), approved: true), isFalse);
      expect(history.startSession(consentConfirmed: true), isTrue);
      expect(history.add(step('a'), approved: false), isFalse);
      expect(history.snapshot, isEmpty);
      expect(history.add(step('a'), approved: true), isTrue);
      expect(history.snapshot.single.stepId, 'a');
      history.dispose();
    },
  );

  test('stop and fresh instance never resurrect observation data', () {
    final history = store();
    expect(history.startSession(consentConfirmed: true), isTrue);
    expect(history.add(step('a'), approved: true), isTrue);
    history.stopSession();
    expect(history.snapshot, isEmpty);
    expect(history.add(step('b'), approved: true), isFalse);
    final restarted = store();
    expect(restarted.isActive, isFalse);
    expect(restarted.snapshot, isEmpty);
    expect(restarted.startSession(consentConfirmed: true), isTrue);
    expect(restarted.snapshot, isEmpty);
    history.dispose();
    restarted.dispose();
  });

  test('session expiration clears data and requires fresh consent', () {
    final history = store(session: const Duration(minutes: 1));
    expect(history.startSession(consentConfirmed: true), isTrue);
    expect(history.add(step('a'), approved: true), isTrue);
    clock = clock.add(const Duration(minutes: 1));
    expect(history.isActive, isFalse);
    expect(history.snapshot, isEmpty);
    expect(history.add(step('b'), approved: true), isFalse);
    expect(history.startSession(consentConfirmed: false), isFalse);
    history.dispose();
  });

  test('TTL prunes stale records and refuses future timestamps', () {
    final history = store(session: const Duration(hours: 2));
    expect(history.startSession(consentConfirmed: true), isTrue);
    expect(
      history.add(
        step('old', at: clock.subtract(const Duration(hours: 1))),
        approved: true,
      ),
      isFalse,
    );
    expect(
      history.add(
        step('future', at: clock.add(const Duration(seconds: 1))),
        approved: true,
      ),
      isFalse,
    );
    expect(history.add(step('recent'), approved: true), isTrue);
    clock = clock.add(const Duration(minutes: 1));
    expect(history.snapshot, hasLength(1));
    clock = clock.add(const Duration(hours: 1));
    expect(history.snapshot, isEmpty);
    history.dispose();
  });

  test('capacity, duplicates and immutable snapshots are enforced', () {
    final history = store();
    expect(history.startSession(consentConfirmed: true), isTrue);
    expect(history.add(step('a'), approved: true), isTrue);
    final before = history.snapshot;
    expect(history.add(step('a'), approved: true), isFalse);
    expect(history.add(step('b'), approved: true), isTrue);
    expect(history.add(step('c'), approved: true), isTrue);
    expect(history.snapshot.map((item) => item.stepId), ['b', 'c']);
    expect(before.map((item) => item.stepId), ['a']);
    expect(() => history.snapshot.clear(), throwsUnsupportedError);
    history.dispose();
  });

  test('clear purges data without granting consent', () async {
    final history = store();
    expect(history.startSession(consentConfirmed: true), isTrue);
    expect(history.add(step('a'), approved: true), isTrue);
    await history.clear();
    expect(history.snapshot, isEmpty);
    expect(history.isActive, isFalse);
    expect(history.add(step('b'), approved: true), isFalse);
    expect(history.startSession(consentConfirmed: false), isFalse);
    expect(history.startSession(consentConfirmed: true), isTrue);
    expect(history.add(step('c'), approved: true), isTrue);
    await history.clear();
    expect(history.snapshot, isEmpty);
    expect(history.isActive, isFalse);
    history.dispose();
    expect(history.startSession(consentConfirmed: true), isFalse);
  });

  test('invalid storage bounds fail closed', () {
    expect(() => store(capacity: 0), throwsArgumentError);
    expect(() => store(retention: Duration.zero), throwsArgumentError);
    expect(() => store(session: Duration.zero), throwsArgumentError);
  });
}
