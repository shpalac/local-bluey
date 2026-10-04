import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/llm/tools.dart';
import 'package:local_bluey/services/action_log.dart';
import 'package:local_bluey/services/tool_executor.dart';

import 'tool_executor_test.dart' show FakeControl;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every executed tool is recorded under the run id', () async {
    final log = ActionLog.instance;
    log.entries.clear();
    final executor = ToolExecutor(control: FakeControl(), actionLog: log);
    executor.currentRunId = 'run-42';
    await executor.execute(ToolCall('look_at_screen', {}));
    await executor.execute(ToolCall('point_at', {'target_id': 'ok'}));
    expect(log.entries.where((e) => e.runId == 'run-42').length, 2);
    expect(log.summarizeRun('run-42'), contains('2 actions'));
  });

  test('failures carry recovery guidance in the summary', () async {
    final log = ActionLog.instance;
    log.entries.clear();
    final executor = ToolExecutor(control: FakeControl(), actionLog: log);
    executor.currentRunId = 'run-43';
    await executor.execute(ToolCall('click', {'x': 500, 'y': 500}));
    final summary = log.summarizeRun('run-43');
    expect(summary, contains('1 failed'));
    expect(summary, contains('re-look at the screen'));
  });

  test('unknown runs summarize cleanly', () {
    expect(ActionLog.instance.summarizeRun('nope'), 'No actions in this run.');
  });
}
