import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/request_runner.dart';

void main() {
  for (final limit in [-1, -100]) {
    test('negative queue and tool budgets rejected: $limit', () {
      expect(() => RequestRunner(maxQueued: limit), throwsArgumentError);
      expect(() => RequestRunner(maxToolSteps: limit), throwsArgumentError);
    });
  }
  for (final duration in [Duration.zero, const Duration(microseconds: -1)]) {
    test('nonpositive stage and job timeout rejected: $duration', () {
      expect(() => RequestRunner(stepTimeout: duration), throwsArgumentError);
      expect(() => RequestRunner(jobTimeout: duration), throwsArgumentError);
    });
  }
  test('zero waiting and zero tool budgets remain valid finite modes', () {
    final runner = RequestRunner(
      maxQueued: 0,
      maxToolSteps: 0,
      stepTimeout: const Duration(microseconds: 1),
      jobTimeout: const Duration(microseconds: 1),
    );
    expect(runner.maxQueued, 0);
    expect(runner.maxToolSteps, 0);
    expect(runner.queuedCount, 0);
  });
}
