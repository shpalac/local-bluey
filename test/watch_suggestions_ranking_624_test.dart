import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/watch_pipeline.dart';
import 'package:local_bluey/services/watch_suggestions.dart';
import 'package:shared_preferences/shared_preferences.dart';

WatchEvent _vision(String app, String detail, {DateTime? at}) => WatchEvent(
  kind: WatchEventKind.visionCall,
  at: at ?? DateTime(2026, 10, 15, 12),
  app: app,
  detail: detail,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'ac2 identical event sequences leave identical verdict evidence',
    () async {
      final events = List.generate(
        3,
        (i) => _vision('Terminal', 'same repeated failure'),
      );
      Future<List<WatchSuggestion>> runAll() async {
        final suggestions = WatchSuggestions();
        final collected = <WatchSuggestion>[];
        for (final event in events) {
          final result = await suggestions.onEvent(event);
          if (result != null) collected.add(result);
        }
        await suggestions.dispose();
        return collected;
      }

      final first = await runAll();
      final second = await runAll();
      expect(first, hasLength(1));
      expect(second, hasLength(1));
      expect(first.single.evidence, second.single.evidence);
      expect(first.single.app, second.single.app);
      expect(first.single.observedDetail, second.single.observedDetail);
      expect(first.single.reason, second.single.reason);
    },
  );

  test(
    'ac2 rate limits are deterministic and re-evaluated per session',
    () async {
      final first = WatchSuggestions();
      final second = WatchSuggestions();
      final events = List.generate(4, (i) => _vision('Terminal', 'one error'));

      // The first suggestion fires on the third repeat; the next repeat
      // inside the same session is suppressed by the counter removal.
      final gotFirst = await first.onEvent(events[0]);
      expect(gotFirst, isNull, reason: 'below the repeat threshold');
      final fired = await first.onEvent(events[1]);
      expect(fired, isNull);
      final third = await first.onEvent(events[2]);
      expect(third, isNotNull, reason: 'third repeat fires');
      final fourth = await first.onEvent(events[3]);
      expect(fourth, isNull, reason: 'counter was removed after firing');

      // A fresh session must fire on the same, identical sequence.
      expect(await second.onEvent(events[0]), isNull);
      expect(await second.onEvent(events[1]), isNull);
      expect(await second.onEvent(events[2]), isNotNull);
      await first.dispose();
      await second.dispose();
    },
  );

  test('ac2 a failing never-apps read is rethrown, not swallowed', () async {
    // The read gate rethrows the caller's typed error as soon as context
    // confidence passes: the failure is explicit, never silent.
    final gate = WatchSuggestions(
      readNeverApps: () async {
        throw StateError('preferences unreachable');
      },
    );
    try {
      await expectLater(
        () => gate.onEvent(_vision('Terminal', 'a failure message')),
        throwsStateError,
      );
    } finally {
      await gate.dispose();
    }
  });

  test(
    'ac2 a restored reader deterministically resumes the sequence',
    () async {
      var failing = true;
      final suggestions = WatchSuggestions(
        readNeverApps: () async {
          if (failing) throw StateError('preferences unreachable');
          return <String>{};
        },
      );
      await expectLater(
        () => suggestions.onEvent(_vision('Terminal', 'same repeated failure')),
        throwsStateError,
      );

      // Reader restored: the same, identical detail fires on the third
      // repeat, deterministically.
      failing = false;
      expect(await suggestions.onEvent(_vision('Terminal', 'same')), isNull);
      expect(await suggestions.onEvent(_vision('Terminal', 'same')), isNull);
      expect(await suggestions.onEvent(_vision('Terminal', 'same')), isNotNull);
      await suggestions.dispose();
    },
  );
}
