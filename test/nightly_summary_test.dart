import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/nightly_test_summary.dart';

void main() {
  test('nightly summary gives actionable failure triage', () {
    const events = '''
{"type":"testDone","result":"success","test":{"name":"safe"}}
{"type":"error","error":"secret-user-data","testID":2}
{"type":"testDone","result":"failure","test":{"name":"private-case"}}
{"type":"testDone","result":"success","skipped":true}
''';
    final result = NightlyTestSummary.parse(events);
    final report = result.toMarkdown();

    expect(result.passed, 1);
    expect(result.failed, 1);
    expect(result.skipped, 1);
    expect(report, contains('Status: FAIL'));
    expect(report, contains('flutter test --reporter expanded'));
    expect(report, isNot(contains('secret-user-data')));
    expect(report, isNot(contains('private-case')));
  });

  test('nightly results are deterministic and invalid input fails closed', () {
    const input = '''
{"type":"start","time":10}
{"type":"testDone","result":"success"}
{"type":"testDone","result":"failure"}
''';
    final first = NightlyTestSummary.parse(input).toMarkdown();
    final second = NightlyTestSummary.parse(input).toMarkdown();

    expect(first, second);
    expect(first, contains('Status: FAIL'));
    expect(
      () => NightlyTestSummary.parse('{"type":"start"}'),
      throwsFormatException,
    );
    expect(
      () => NightlyTestSummary.parse('not-json'),
      throwsFormatException,
    );
    expect(
      () => NightlyTestSummary.parse('{"type":"testDone","result":"unknown"}'),
      throwsFormatException,
    );
  });
}
