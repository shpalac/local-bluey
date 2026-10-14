import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/workflows/workflow_import.dart';

void main() {
  const importer = WorkflowImporter();

  const valid =
      '{"version":1,"id":"test","trigger":"manual","steps":[{"type":"notify","target":"hello"}]}';

  test('imports workflow without enabling it', () {
    final result = importer.importJson(valid);

    expect(result.definition.id, 'test');
    expect(result.enabled, isFalse);
  });

  test('rejects unsupported workflow schema version', () {
    expect(
      () =>
          importer.importJson(valid.replaceFirst('"version":1', '"version":2')),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects oversized workflow documents deterministically', () {
    const smallImporter = WorkflowImporter(maxBytes: 10);

    expect(
      () => smallImporter.importJson(valid),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects malformed workflow JSON with explicit error', () {
    expect(
      () => importer.importJson('{broken'),
      throwsA(isA<FormatException>()),
    );
  });
}
