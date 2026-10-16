import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/execution_audit.dart';
import 'package:local_bluey/workflows/workflow_dsl.dart';
import 'package:local_bluey/ui/execution_audit_panel.dart';
import 'package:local_bluey/workflows/workflow_execution.dart';

class _GreenHost implements WorkflowHost {
  @override
  Future<bool> approve(WorkflowStep step) async => true;
  @override
  Future<void> execute(WorkflowStep step) async {}
  @override
  Future<bool> verify(WorkflowStep step) async => true;
}

WorkflowDefinition singleStep(String id) => WorkflowDefinition.fromJson({
  'version': 1,
  'id': id,
  'trigger': 'manual',
  'steps': [
    {'type': 'notify', 'target': 'safe-target'},
  ],
});

const secrets = ['topsecret', 'sample@fixture.invalid', '4111-1111-1111-1111'];

void main() {
  test('ac3 history surface keeps no-io, no-network, no-writer provenance', () {
    for (final path in [
      'lib/services/execution_audit.dart',
      'lib/ui/execution_audit_panel.dart',
    ]) {
      final source = File(path).readAsStringSync();
      // jsonEncode is allowed (consented redacted export); transports are not.
      expect(
        source.contains(RegExp("import '(dart:io|package:http)")),
        isFalse,
        reason: '$path must not gain transport or filesystem access',
      );
      expect(
        source.contains(RegExp(r'HttpClient|SharedPreferencesWithCache')),
        isFalse,
        reason: '$path must not gain network or storage calls',
      );
      expect(
        source.contains('writeAsBytes') ||
            source.contains('writeAsString') ||
            source.contains('File('),
        isFalse,
        reason: '$path must not gain artifact writers',
      );
    }
  });

  test('ac3 audit retains no payload text for any corpus secret', () {
    final audit = ExecutionAudit();
    for (final secret in secrets) {
      audit.record('execution', 'started', diagnostic: secret);
      audit.record('execution:$secret', 'failed');
      audit.record('execution', 'status:$secret');
    }
    final export = audit.exportRedacted(consent: true);
    for (final secret in secrets) {
      expect(export, isNot(contains(secret)));
      expect(jsonEncode(audit.entries), isNot(contains(secret)));
    }
    expect(
      audit.entries.every(
        (e) => e.diagnostic == null || e.diagnostic == '[redacted]',
      ),
      isTrue,
    );
    // Unknown, payload-shaped labels collapse to the redaction marker.
    expect(
      audit.entries.every(
        (e) => e.step == 'execution' || e.step == '[redacted]',
      ),
      isTrue,
    );

    // Unconsented export is refused outright, not silently emptied.
    expect(
      () => ExecutionAudit().exportRedacted(consent: false),
      throwsStateError,
    );
  });

  testWidgets('ac3 panel shows targets neither secrets nor raw payloads', (
    tester,
  ) async {
    final audit = ExecutionAudit();
    final execution = WorkflowExecution(
      singleStep('privacy-panel'),
      _GreenHost(),
      deadline: const Duration(seconds: 2),
      audit: audit,
    );
    expect(await execution.run(), WorkflowStatus.completed);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExecutionAuditPanel(execution: execution, audit: audit),
        ),
      ),
    );
    await tester.pump();

    // The timeline shows labels only; the step target never appears.
    expect(find.text('Step 1'), findsWidgets);
    expect(find.text('safe-target'), findsNothing);
    for (final secret in secrets) {
      final body = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .whereType<String>()
          .join('|');
      expect(body, isNot(contains(secret)));
    }

    // Rejecting the consent dialog shows no data at all.
    await tester.tap(find.text('Export diagnostics'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Only redacted, memory-only workflow event labels will be shown. '
        'Review the information before sharing it.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Redacted diagnostics'), findsNothing);

    // Consented export shows exactly the redacted payload: labels plus
    // redaction markers, and never a secret.
    await tester.tap(find.text('Export diagnostics'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show redacted data'));
    await tester.pumpAndSettle();
    final retained = audit.exportRedacted(consent: true);
    final shown = tester.widget<SelectableText>(find.byType(SelectableText));
    final rendered = shown.data ?? '';
    expect(rendered, retained);
    for (final secret in secrets) {
      expect(rendered, isNot(contains(secret)));
    }
  });
}
