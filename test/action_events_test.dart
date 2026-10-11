import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/action_events.dart';
import 'package:local_bluey/services/watch_pipeline.dart';

final _t0 = DateTime.utc(2026, 1, 1, 9);

WatchEvent _w(
  WatchEventKind kind,
  String app,
  int seconds, {
  String detail = '',
}) => WatchEvent(
  kind: kind,
  at: _t0.add(Duration(seconds: seconds)),
  app: app,
  detail: detail,
);

ActionEventNormalizer _n({
  Set<String> allowed = const {'notes', 'safari'},
  Duration debounce = const Duration(seconds: 2),
  Duration gap = const Duration(minutes: 10),
  int max = 200,
}) => ActionEventNormalizer(
  isAppAllowed: allowed.contains,
  debounce: debounce,
  sessionGap: gap,
  maxEvents: max,
);

List<String> _trace(Iterable<ActionEvent> events) => [
  for (final e in events)
    '${e.sequence}/s${e.sessionId} ${e.kind.name} ${e.app} ${e.confidence}',
];

void main() {
  test('golden trace maps kinds, confidence, sequence and session', () {
    final n = _n();
    final source = [
      _w(WatchEventKind.appSwitch, 'notes', 0, detail: 'secret title'),
      _w(WatchEventKind.meaningfulChange, 'notes', 10, detail: 'diff 0.20'),
      _w(WatchEventKind.visionCall, 'notes', 11, detail: 'vision words'),
      _w(WatchEventKind.appSwitch, 'safari', 20),
    ];
    for (final s in source) {
      expect(n.normalize(s), isNotNull);
    }
    expect(_trace(n.events), [
      '0/s0 appActivated notes 0.9',
      '1/s0 screenChanged notes 0.6',
      '2/s0 screenDescribed notes 0.7',
      '3/s0 appActivated safari 0.9',
    ]);
    // Titles and vision text never reach the normalized event.
    expect(n.events.join(' '), isNot(contains('secret')));
    expect(n.events.join(' '), isNot(contains('vision words')));
  });

  test('apps that are not allowed are absent, not just hidden', () {
    final n = _n();
    expect(n.normalize(_w(WatchEventKind.appSwitch, '1Password', 0)), isNull);
    expect(n.normalize(_w(WatchEventKind.appSwitch, 'notes', 1)), isNotNull);
    expect(n.events.map((e) => e.app), ['notes']);
  });

  test('a throwing allowlist fails closed', () {
    final n = ActionEventNormalizer(
      isAppAllowed: (_) => throw StateError('permission denied'),
    );
    expect(n.normalize(_w(WatchEventKind.appSwitch, 'notes', 0)), isNull);
    expect(n.events, isEmpty);
  });

  test('malformed input is dropped: empty and oversized app names', () {
    final long = 'a' * (WatchPipeline.maxAppLength + 1);
    final n = _n(allowed: {'', long, 'notes'});
    expect(n.normalize(_w(WatchEventKind.appSwitch, '', 0)), isNull);
    expect(n.normalize(_w(WatchEventKind.appSwitch, long, 1)), isNull);
    expect(n.events, isEmpty);
  });

  test('same kind and app inside the debounce window is one event', () {
    final n = _n();
    expect(n.normalize(_w(WatchEventKind.appSwitch, 'notes', 0)), isNotNull);
    expect(n.normalize(_w(WatchEventKind.appSwitch, 'notes', 1)), isNull);
    expect(n.normalize(_w(WatchEventKind.appSwitch, 'notes', 3)), isNotNull);
    // A different kind or app is never debounced against it.
    expect(
      n.normalize(_w(WatchEventKind.meaningfulChange, 'notes', 3)),
      isNotNull,
    );
    expect(n.normalize(_w(WatchEventKind.appSwitch, 'safari', 3)), isNotNull);
  });

  test('timestamps that go backwards are dropped', () {
    final n = _n();
    expect(n.normalize(_w(WatchEventKind.appSwitch, 'notes', 100)), isNotNull);
    expect(n.normalize(_w(WatchEventKind.appSwitch, 'safari', 50)), isNull);
    expect(n.events, hasLength(1));
  });

  test('a long silence starts a new session', () {
    final n = _n(gap: const Duration(minutes: 10));
    n.normalize(_w(WatchEventKind.appSwitch, 'notes', 0));
    n.normalize(_w(WatchEventKind.appSwitch, 'safari', 600)); // exactly 10 min
    n.normalize(_w(WatchEventKind.appSwitch, 'notes', 1201)); // > 10 min
    expect(n.events.map((e) => e.sessionId), [0, 0, 1]);
  });

  test('endSession cancels debounce and starts a new session', () {
    final n = _n();
    n.normalize(_w(WatchEventKind.appSwitch, 'notes', 0));
    n.endSession();
    final next = n.normalize(_w(WatchEventKind.appSwitch, 'notes', 1));
    expect(next, isNotNull);
    expect(next!.sessionId, 1);
    expect(n.sessionId, 1);
  });

  test(
    'interleaved same kind and app inside the window is still collapsed',
    () {
      final n = _n();
      n.normalize(_w(WatchEventKind.appSwitch, 'notes', 0));
      n.normalize(_w(WatchEventKind.meaningfulChange, 'notes', 0));
      final again = n.normalize(_w(WatchEventKind.appSwitch, 'notes', 1));
      expect(again, isNull);
      expect(n.events, hasLength(2));
      // Outside the window it is accepted again.
      expect(n.normalize(_w(WatchEventKind.appSwitch, 'notes', 5)), isNotNull);
    },
  );

  test('endSession then a long gap advances the session only once', () {
    final n = _n();
    n.normalize(_w(WatchEventKind.appSwitch, 'notes', 0));
    n.endSession();
    final next = n.normalize(_w(WatchEventKind.appSwitch, 'notes', 3000));
    expect(next!.sessionId, 1);
    final later = n.normalize(_w(WatchEventKind.appSwitch, 'safari', 3001));
    expect(later!.sessionId, 1);
  });

  test('invalid configuration is rejected at runtime', () {
    bool allow(String a) => true;
    expect(
      () => ActionEventNormalizer(
        isAppAllowed: allow,
        debounce: const Duration(seconds: -1),
      ),
      throwsArgumentError,
    );
    expect(
      () => ActionEventNormalizer(
        isAppAllowed: allow,
        sessionGap: const Duration(seconds: -1),
      ),
      throwsArgumentError,
    );
    expect(
      () => ActionEventNormalizer(isAppAllowed: allow, maxEvents: 0),
      throwsArgumentError,
    );
    expect(
      () => ActionEventNormalizer(isAppAllowed: allow, maxEvents: -5),
      throwsArgumentError,
    );
    // Zero is a valid boundary for both durations.
    expect(
      ActionEventNormalizer(
        isAppAllowed: allow,
        debounce: Duration.zero,
        sessionGap: Duration.zero,
        maxEvents: 1,
      ).events,
      isEmpty,
    );
  });

  test('debounce keys are hard-capped; the oldest key is evicted', () {
    final apps = {for (var i = 0; i < 50; i++) 'app$i'};
    final n = _n(allowed: apps, max: 3);
    // Same timestamp, high cardinality: key count never exceeds the cap.
    for (var i = 0; i < 50; i++) {
      n.normalize(_w(WatchEventKind.appSwitch, 'app$i', 0));
      expect(n.debounceKeyCount, lessThanOrEqualTo(3));
    }
    expect(n.debounceKeyCount, 3);
    // Cap boundary: the 3 most recent keys are still debounced...
    expect(n.normalize(_w(WatchEventKind.appSwitch, 'app49', 1)), isNull);
    expect(n.normalize(_w(WatchEventKind.appSwitch, 'app47', 1)), isNull);
    // ...but an evicted key is NOT debounced any more (documented limit).
    expect(n.normalize(_w(WatchEventKind.appSwitch, 'app0', 1)), isNotNull);
  });

  test('cap of one keeps one key and still debounces that key', () {
    final n = _n(max: 1);
    n.normalize(_w(WatchEventKind.appSwitch, 'notes', 0));
    expect(n.debounceKeyCount, 1);
    expect(n.normalize(_w(WatchEventKind.appSwitch, 'notes', 1)), isNull);
    n.normalize(_w(WatchEventKind.appSwitch, 'safari', 1));
    expect(n.debounceKeyCount, 1);
  });

  test('timestamps stay monotonic across endSession', () {
    final n = _n();
    n.normalize(_w(WatchEventKind.appSwitch, 'notes', 100));
    n.endSession();
    // Older than the last accepted event: dropped even in the new session.
    expect(n.normalize(_w(WatchEventKind.appSwitch, 'safari', 50)), isNull);
    expect(n.sessionId, 1);
    // Equal or newer is accepted and belongs to the new session.
    final ok = n.normalize(_w(WatchEventKind.appSwitch, 'safari', 100));
    expect(ok!.sessionId, 1);
    // clear() forgets the last time, so an older event is fine afterwards.
    n.clear();
    expect(n.normalize(_w(WatchEventKind.appSwitch, 'notes', 1)), isNotNull);
  });

  test('retained events are capped and the snapshot is immutable', () {
    final n = _n(max: 3);
    for (var i = 0; i < 5; i++) {
      n.normalize(
        _w(WatchEventKind.appSwitch, i.isEven ? 'notes' : 'safari', i * 5),
      );
    }
    expect(n.events.map((e) => e.sequence), [2, 3, 4]);
    expect(
      () => n.events.add(n.events.first),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('clear behaves like a restart: nothing remembered', () {
    final n = _n();
    n.normalize(_w(WatchEventKind.appSwitch, 'notes', 0));
    n.endSession();
    n.clear();
    expect(n.events, isEmpty);
    final first = n.normalize(_w(WatchEventKind.appSwitch, 'notes', 0));
    expect(first!.sequence, 0);
    expect(first.sessionId, 0);
  });

  test('bind maps a stream and stops when the subscriber cancels', () async {
    final n = _n();
    final source = StreamController<WatchEvent>();
    final seen = <ActionEvent>[];
    final sub = n.bind(source.stream).listen(seen.add);
    source.add(_w(WatchEventKind.appSwitch, 'notes', 0));
    source.add(_w(WatchEventKind.appSwitch, 'bank', 1));
    source.add(_w(WatchEventKind.appSwitch, 'safari', 10));
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    source.add(_w(WatchEventKind.appSwitch, 'notes', 20));
    await Future<void>.delayed(Duration.zero);
    unawaited(source.close());
    expect(seen.map((e) => e.app), ['notes', 'safari']);
    expect(n.events, hasLength(2));
  });
}
