import 'dart:convert';

/// Aggregates Flutter machine test events without retaining names or messages.
class NightlyTestSummary {
  const NightlyTestSummary({
    required this.passed,
    required this.failed,
    required this.skipped,
  });

  final int passed;
  final int failed;
  final int skipped;

  static NightlyTestSummary parse(String output) {
    var passed = 0;
    var failed = 0;
    var skipped = 0;
    var completed = 0;

    for (final line in const LineSplitter().convert(output)) {
      if (line.trim().isEmpty) continue;

      final Object? decoded;
      try {
        decoded = jsonDecode(line);
      } on FormatException {
        throw const FormatException('Invalid Flutter machine event JSON');
      }

      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid Flutter machine event shape');
      }
      if (decoded['type'] != 'testDone') continue;

      completed++;
      final result = decoded['result'];
      if (decoded['skipped'] == true || result == 'skipped') {
        skipped++;
      } else if (result == 'success') {
        passed++;
      } else if (result == 'failure' || result == 'error') {
        failed++;
      } else {
        throw const FormatException('Unknown Flutter test result');
      }
    }

    if (completed == 0) {
      throw const FormatException('No completed Flutter tests were reported');
    }

    return NightlyTestSummary(
      passed: passed,
      failed: failed,
      skipped: skipped,
    );
  }

  /// Fixed template: never includes test names, error messages or source data.
  String toMarkdown() {
    final outcome = failed == 0 ? 'PASS' : 'FAIL';
    return '''
## Nightly extended test matrix

Status: $outcome

| Passed | Failed | Skipped |
| ---: | ---: | ---: |
| $passed | $failed | $skipped |

Triage: Re-run failing suites locally with `flutter test --reporter expanded`.
Raw machine events, stack traces and screenshots are not uploaded.
''';
  }
}
