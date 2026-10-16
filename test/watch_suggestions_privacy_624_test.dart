import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/privacy_guard.dart';
import 'package:local_bluey/services/watch_pipeline.dart';
import 'package:local_bluey/services/watch_suggestions.dart';
import 'package:shared_preferences/shared_preferences.dart';

WatchEvent _vision(String app, String detail) => WatchEvent(
  kind: WatchEventKind.visionCall,
  at: DateTime(2026, 10, 15, 12),
  app: app,
  detail: detail,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('ac3 suggestion layer keeps read-only-into-memory provenance', () {
    final source = File('lib/services/watch_suggestions.dart')
        .readAsStringSync();
    expect(
      source.contains(RegExp("import '(dart:io|package:http)")),
      isFalse,
      reason: 'the suggestion layer must not gain transport access',
    );
    expect(
      source.contains(RegExp(r'HttpClient|writeAsBytes|writeAsString|File\(')),
      isFalse,
      reason: 'the suggestion layer must not gain artifact writers',
    );
    // The only storage call is the opaque, canonical never-apps list.
    expect(source, contains("getStringList(_kNeverApps)"));
    expect(source, contains("setStringList(_kNeverApps"));
    expect(
      RegExp('setString(?!List)').hasMatch(source),
      isFalse,
      reason: 'no non-list preference writes',
    );
  });

  testWidgets('ac3 a screen-corpus secret stays quoted and unpersisted', (
    tester,
  ) async {
    final collected = <WatchSuggestion>[];
    final suggestions = WatchSuggestions();
    suggestions.stream.listen(collected.add);
    try {
      final repeated = List.generate(
        3,
        (i) => _vision(
          'Terminal',
          'Password hunter2 rejected by sample@fixture.invalid',
        ),
      );
      expect(await suggestions.onEvent(repeated[0]), isNull);
      expect(await suggestions.onEvent(repeated[1]), isNull);
      final fired = await suggestions.onEvent(repeated[2]);
      expect(fired, isNotNull);

      // The screen text is quoted as data — displayed, never parsed,
      // never acted on. The quoted evidence is the repeat reason framing.
      expect(fired!.evidence, contains('hunter2'));
      expect(fired.localEvidence, contains('hunter2'));

      // Preferences persisted during the flow contain app names only --
      // never the screen detail.
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList('watch.suggestNeverApps');
      expect(
        stored ?? const <String>[],
        everyElement(isNot(contains('hunter2'))),
      );
      expect(stored ?? const <String>[], isNot(contains(contains('sample'))));

      // Sensitive gate semantics dominate upstream in the pipeline (the
      // capture path refuses such text before suggestion ever fires).
      for (final secret in ['sample@fixture.invalid', '4111-1111-1111-1111']) {
        expect(PrivacyGuard.hasSensitive('rejected by $secret'), isTrue);
      }
    } finally {
      await suggestions.dispose();
    }
  });

  test(
    'ac3 oversized payloads stay silent instead of truncating evidence',
    () async {
      final suggestions = WatchSuggestions();
      final oversized = _vision(
        'Terminal',
        'x' * (WatchSuggestions.maxDetailLength + 1),
      );
      expect(await suggestions.onEvent(oversized), isNull);

      final oversizedApp = _vision(
        'a' * (WatchSuggestions.maxAppLength + 1),
        'same repeated failure',
      );
      if (oversizedApp.app.length > WatchSuggestions.maxAppLength) {
        expect(await suggestions.onEvent(oversizedApp), isNull);
      }
      await suggestions.dispose();
    },
  );
}
