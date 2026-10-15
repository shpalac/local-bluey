import 'dart:convert';

import 'package:local_bluey/workflows/workflow_dsl.dart';

/// Safe boundary for importing untrusted workflow documents.
///
/// This class only validates and returns a definition. It never enables,
/// registers, approves, or executes workflows.
final class WorkflowImporter {
  const WorkflowImporter({this.maxBytes = 256 * 1024});

  final int maxBytes;

  /// Exports the current versioned contract without changing workflow state.
  ///
  /// Exporting uses the same validator as importing, so unsupported or
  /// invalid definitions fail explicitly instead of producing unusable JSON.
  String exportJson(WorkflowDefinition definition) {
    final encoded = definition.encode();
    importJson(encoded);
    return encoded;
  }

  WorkflowImportResult importJson(String source) {
    if (utf8.encode(source).length > maxBytes) {
      throw const FormatException('Workflow import exceeds size limit');
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const FormatException('Invalid workflow JSON');
    }

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Expected workflow object');
    }

    final definition = WorkflowDefinition.fromJson(decoded);
    return WorkflowImportResult(definition);
  }
}

final class WorkflowImportResult {
  const WorkflowImportResult(this.definition);

  final WorkflowDefinition definition;

  bool get enabled => false;
}
