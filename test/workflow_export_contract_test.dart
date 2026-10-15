import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/workflows/workflow_dsl.dart';
import 'package:local_bluey/workflows/workflow_import.dart';

void main() {
  const importer = WorkflowImporter();
  const workflow = WorkflowDefinition(
    id: 'export-check',
    trigger: 'manual',
    steps: [WorkflowStep(type: 'notify', target: 'done')],
  );

  test('versioned export is deterministic and round-trips', () {
    final first = importer.exportJson(workflow);
    final second = importer.exportJson(workflow);
    final imported = importer.importJson(first);

    expect(first, second);
    expect(imported.definition.encode(), first);
    expect(imported.definition.id, 'export-check');
    expect(imported.definition.steps.single.target, 'done');
  });

  test('export refuses documents above the import size limit', () {
    const bounded = WorkflowImporter(maxBytes: 10);

    expect(
      () => bounded.exportJson(workflow),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Workflow import exceeds size limit',
        ),
      ),
    );
  });
}
