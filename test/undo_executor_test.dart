import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/llm/tools.dart';
import 'package:local_bluey/services/tool_executor.dart';

import 'tool_executor_test.dart' as shared show FakeControl;

void main() {
  test(
    'a successful type_text becomes the last undoable action (#89)',
    () async {
      final executor = ToolExecutor(control: shared.FakeControl());
      await executor.execute(ToolCall('look_at_screen', {}));
      expect(executor.lastUndoable, isNull);
      await executor.execute(ToolCall('type_text', {'text': 'hello'}));
      expect(executor.lastUndoable, isNotNull);
      expect(executor.lastUndoable!.keys, 'cmd+z');
    },
  );

  test('a final action clears the undo offer (#89)', () async {
    final executor = ToolExecutor(control: shared.FakeControl());
    await executor.execute(ToolCall('look_at_screen', {}));
    await executor.execute(ToolCall('type_text', {'text': 'hello'}));
    expect(executor.lastUndoable, isNotNull);
    await executor.execute(ToolCall('press_keys', {'keys': 'cmd+t'}));
    expect(executor.lastUndoable, isNull);
  });
}
