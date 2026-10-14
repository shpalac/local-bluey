import 'package:flutter_test/flutter_test.dart';

import 'package:local_bluey/services/execution_lifecycle_bridge.dart';

void main() {
  test('restart requires manual recovery and never resumes automatically', () {
    final bridge = ExecutionLifecycleBridge();

    bridge.markStarted('execution-1');
    bridge.markRestart();

    expect(bridge.requiresRecovery(), isTrue);
    expect(bridge.pendingExecutionId, 'execution-1');

    bridge.acknowledgeRecovery();

    expect(bridge.requiresRecovery(), isFalse);
    expect(bridge.pendingExecutionId, isNull);
  });

  test('empty execution ids are rejected', () {
    final bridge = ExecutionLifecycleBridge();

    expect(() => bridge.markStarted(''), throwsArgumentError);
  });
}
