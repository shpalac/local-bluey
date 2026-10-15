import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/capture_monitor.dart';
import 'package:local_bluey/services/screen_watch.dart';
import 'package:local_bluey/teach_mode/capture_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secrets = [
    'topsecret',
    'sample@fixture.invalid',
    '4111-1111-1111-1111',
  ];

  ScreenWatch newWatch() => ScreenWatch.forTesting(
    localOnly: () async => true,
    allowlist: () async => ['editor'],
    denylist: () async => <String>[],
  );

  test(
    'ac3 teach capture retains no payloads and uses no io or network',
    () async {
      // Static contract: the Teach Mode lib surface is memory-only. Any
      // transport, persistence or artifact-writer dependency would break it.
      for (final path in [
        'lib/teach_mode/capture_session.dart',
        'lib/teach_mode/draft_builder.dart',
      ]) {
        final source = File(path).readAsStringSync();
        expect(
          source.contains(RegExp("import '(dart:io|package:http)")),
          isFalse,
          reason: '$path must not gain transport or filesystem access',
        );
        expect(
          source.contains(RegExp(r'HttpClient|SharedPreferencesWithCache')),
          isFalse,
          reason: '$path must not gain network or storage calls',
        );
        expect(
          source.contains('writeAsBytes') ||
              source.contains('writeAsString') ||
              source.contains('File('),
          isFalse,
          reason: '$path must not gain artifact writers',
        );
      }

      final session = TeachCaptureSession(watch: newWatch());
      expect(await session.start(consentConfirmed: true), isNull);

      // Secret-bearing payloads are gated out at capture: every extra key is
      // an untrusted payload and the step is rejected, not silently redacted.
      for (final secret in secrets) {
        for (final key in ['value', 'text', 'fieldValue', 'settings']) {
          expect(
            await session.observe(
              frontApp: 'editor',
              capture: () async => {
                'action': 'type',
                'target': 'password',
                key: secret,
              },
            ),
            isFalse,
            reason: 'payload key "$key" must not be captured',
          );
        }
      }
      expect(session.stepCount, 0);

      // Only clean steps are retained; every projection of session state is
      // free of the secret corpus.
      expect(
        await session.observe(
          frontApp: 'editor',
          capture: () async => {'action': 'type', 'target': 'username'},
        ),
        isTrue,
      );
      expect(session.stepCount, 1);
      final preview = session.review();
      expect(preview.steps.single.variablePlaceholder, 'input_1');
      for (final secret in secrets) {
        expect(session.toString(), isNot(contains(secret)));
        expect(preview.toString(), isNot(contains(secret)));
        expect(
          preview.steps
              .map((s) => '${s.target}:${s.variablePlaceholder}')
              .join('|'),
          isNot(contains(secret)),
        );
        expect(preview.warnings.join('|'), isNot(contains(secret)));
        expect(session.finish().warnings.join('|'), isNot(contains(secret)));
      }
      expect(session.stepCount, 0);

      // The in-memory buffers are forgotten when the session ends, never
      // handed to a store; the finished draft is the only projection left.
      expect(await session.start(consentConfirmed: true), isNull);
      expect(
        await session.observe(
          frontApp: 'editor',
          capture: () async => {'action': 'click', 'target': 'save'},
        ),
        isTrue,
      );
      session.cancel();
      final discarded = session.review();
      expect(discarded.steps, isEmpty);
      for (final secret in secrets) {
        expect(discarded.toString(), isNot(contains(secret)));
      }
      session.dispose();
    },
  );
}
