import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/action_events.dart';
import 'package:local_bluey/services/activity_step.dart';
import 'package:local_bluey/services/sensitive_content_gate.dart';
import 'package:local_bluey/services/watch_pipeline.dart';

// BLU-053: seeded, offline fuzzing of the pure event-normalization path.
// Every case derives from a fixed seed, so a failure reproduces exactly:
// the failing seed and index are in the assertion reason. Nothing here
// touches the network, disk, a screen or a real session.

const _seeds = [1, 7, 42, 2026, 90210];
const _secretMarker = 'FAKE-SECRET-MARKER-0000';

/// Odd Unicode on purpose: emoji (surrogate pairs), a lone surrogate, RTL and
/// bidi controls, zero-width and combining marks, NUL, CR/LF and Hebrew.
const _alphabet = <String>[
  'a',
  'Z',
  '0',
  ' ',
  '\t',
  '\n',
  '\r\n',
  '\u0000',
  '\u200b',
  '\u202e',
  '\u0301',
  '\ufeff',
  '\ud83d\ude00',
  '\ud83d',
  '\ude00',
  'שלום',
  'مرحبا',
  '日本語',
  '../',
  '"',
  '\\',
  '{',
  '[',
];

String _randomText(Random r, int maxLen) {
  final n = r.nextInt(maxLen + 1);
  final b = StringBuffer();
  for (var i = 0; i < n; i++) {
    b.write(_alphabet[r.nextInt(_alphabet.length)]);
  }
  return b.toString();
}

String _randomApp(Random r) {
  switch (r.nextInt(8)) {
    case 0:
      return '';
    case 1:
      return 'x' * (WatchPipeline.maxAppLength + 1);
    case 2:
      return 'x' * WatchPipeline.maxAppLength;
    case 3:
      return 'x' * 100000;
    case 4:
      return 'notes';
    case 5:
      return 'safari';
    default:
      return _randomText(r, 12);
  }
}

String _trace(Iterable<ActionEvent> events) => [
  for (final e in events)
    '${e.sequence}/s${e.sessionId} ${e.kind.name} ${e.app.length} '
        '${e.at.microsecondsSinceEpoch} ${e.confidence}',
].join('\n');

/// Runs one seeded stream and returns the retained trace; asserts invariants.
String _runStream(int seed, {int count = 400}) {
  final r = Random(seed);
  var allowToggle = 0;
  final n = ActionEventNormalizer(
    maxEvents: 25,
    isAppAllowed: (app) {
      allowToggle++;
      if (allowToggle % 53 == 0) throw StateError('allowlist failed');
      return app == 'notes' || app == 'safari' || app.length < 8;
    },
  );
  var t = DateTime.utc(2026, 1, 1, 9);
  var accepted = 0;
  for (var i = 0; i < count; i++) {
    // Mostly forward, sometimes a jump back or a long gap.
    switch (r.nextInt(10)) {
      case 0:
        t = t.subtract(Duration(seconds: r.nextInt(30)));
      case 1:
        t = t.add(Duration(minutes: 5 + r.nextInt(30)));
      default:
        t = t.add(Duration(milliseconds: r.nextInt(4000)));
    }
    final source = WatchEvent(
      kind: WatchEventKind.values[r.nextInt(WatchEventKind.values.length)],
      at: t,
      app: _randomApp(r),
      detail: '$_secretMarker ${_randomText(r, 40)}',
    );
    if (i % 97 == 0) n.endSession();
    if (i % 211 == 0 && i > 0) n.clear();
    ActionEvent? out;
    expect(
      () => out = n.normalize(source),
      returnsNormally,
      reason: 'seed $seed index $i',
    );
    if (out != null) accepted++;
    expect(n.events.length, lessThanOrEqualTo(25), reason: 'seed $seed');
    expect(n.debounceKeyCount, lessThanOrEqualTo(25), reason: 'seed $seed');
  }
  expect(accepted, greaterThan(0), reason: 'seed $seed accepted nothing');

  final events = n.events;
  for (var i = 0; i < events.length; i++) {
    final e = events[i];
    expect(e.app, isNotEmpty, reason: 'seed $seed');
    expect(e.app.length, lessThanOrEqualTo(WatchPipeline.maxAppLength));
    expect(e.toString(), isNot(contains(_secretMarker)), reason: 'seed $seed');
    expect(e.confidence, inInclusiveRange(0, 1));
    if (i > 0) {
      expect(e.sequence, greaterThan(events[i - 1].sequence));
      expect(
        e.at.isBefore(events[i - 1].at),
        isFalse,
        reason: 'seed $seed: retained timestamps must not go backwards',
      );
      expect(e.sessionId, greaterThanOrEqualTo(events[i - 1].sessionId));
    }
  }
  return _trace(events);
}

void main() {
  group('ActionEventNormalizer fuzz', () {
    for (final seed in _seeds) {
      test('seed $seed: never throws, caps hold, order holds, no detail', () {
        _runStream(seed);
      });
    }

    test('the same seed gives the identical retained trace', () {
      for (final seed in _seeds) {
        expect(_runStream(seed), _runStream(seed), reason: 'seed $seed');
      }
    });

    test('different seeds actually exercise different streams', () {
      expect(_runStream(1), isNot(_runStream(7)));
    });
  });

  group('ActivityStep.decode fuzz', () {
    test('arbitrary text only ever fails with ActivityStepFormatException', () {
      for (final seed in _seeds) {
        final r = Random(seed);
        for (var i = 0; i < 500; i++) {
          final text = switch (i % 4) {
            0 => _randomText(r, 200),
            1 => '{"schemaVersion":1,${_randomText(r, 60)}}',
            2 => _randomText(r, 2000),
            _ => '[' * (1 + r.nextInt(5000)),
          };
          try {
            ActivityStep.decode(text);
            fail('random text must not decode (seed $seed index $i)');
          } on ActivityStepFormatException {
            // Expected: explicit, typed failure.
          }
        }
      }
    });

    test('valid steps round-trip and random mutations never escape typed', () {
      final good = ActivityStep(
        stepId: 'step_1',
        sessionId: 'session_1',
        timestamp: DateTime.utc(2026, 10, 11, 12, 30),
        kind: ActivityKind.pointer,
        classification: ActivityClassification.internal,
        confidence: 0.5,
      ).encode();
      expect(ActivityStep.decode(good).encode(), good);
      for (final seed in _seeds) {
        final r = Random(seed);
        for (var i = 0; i < 400; i++) {
          final chars = good.split('');
          final at = r.nextInt(chars.length);
          chars[at] = _alphabet[r.nextInt(_alphabet.length)];
          try {
            final step = ActivityStep.decode(chars.join());
            // A mutation that still decodes must still be canonical.
            expect(ActivityStep.decode(step.encode()).encode(), step.encode());
          } on ActivityStepFormatException {
            // Expected.
          }
        }
      }
    });
  });

  group('SensitiveContentGate fuzz', () {
    test('unverified, blank and oversized OCR is never allowed', () {
      for (final seed in _seeds) {
        final r = Random(seed);
        for (var i = 0; i < 300; i++) {
          final text = _randomText(r, 300);
          expect(
            SensitiveContentGate.beforeEgress(
              text: text,
              exactFrameVerified: false,
            ),
            SensitiveVerdict.unverifiedText,
            reason: 'seed $seed index $i',
          );
        }
      }
      for (final blank in ['', ' ', '\n', '\t \r\n', '\u00a0']) {
        expect(
          SensitiveContentGate.beforeEgress(
            text: blank,
            exactFrameVerified: true,
          ),
          SensitiveVerdict.unverifiedText,
          reason: 'blank ${blank.codeUnits}',
        );
      }
      expect(
        SensitiveContentGate.beforeEgress(
          text: 'a' * (SensitiveContentGate.maxEvidenceLength + 1),
          exactFrameVerified: true,
        ),
        SensitiveVerdict.unverifiedText,
      );
    });

    test('garbage text and metadata never throw; fake secrets always deny', () {
      for (final seed in _seeds) {
        final r = Random(seed);
        for (var i = 0; i < 300; i++) {
          final text = _randomText(r, 400);
          expect(
            () => SensitiveContentGate.beforeEgress(
              text: text,
              exactFrameVerified: true,
            ),
            returnsNormally,
            reason: 'seed $seed index $i',
          );
          expect(
            () => SensitiveContentGate.beforeCapture(
              app: _randomApp(r),
              title: _randomText(r, 600),
            ),
            returnsNormally,
            reason: 'seed $seed index $i',
          );
          // A fake token buried in noise is always denied, never passed.
          final withToken = '$text AKIA${'A' * 16} ${_randomText(r, 50)}';
          expect(
            SensitiveContentGate.beforeEgress(
              text: withToken,
              exactFrameVerified: true,
            ),
            SensitiveVerdict.sensitiveText,
            reason: 'seed $seed index $i',
          );
        }
      }
    });

    test('maximum-length repetitive input completes and is classified', () {
      final big = 'password ' * (SensitiveContentGate.maxEvidenceLength ~/ 9);
      expect(
        SensitiveContentGate.beforeEgress(text: big, exactFrameVerified: true),
        SensitiveVerdict.sensitiveText,
      );
      final noise =
          '1234 5678 ' * (SensitiveContentGate.maxEvidenceLength ~/ 10);
      expect(
        () => SensitiveContentGate.beforeEgress(
          text: noise,
          exactFrameVerified: true,
        ),
        returnsNormally,
      );
    });
  });
}
