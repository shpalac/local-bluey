import 'dart:convert';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/ui/execution_audit_panel.dart';
import 'package:local_bluey/workflows/workflow_dsl.dart';
import 'package:local_bluey/workflows/workflow_execution.dart';
import 'package:local_bluey/services/execution_audit.dart';

void main() {
  auditIntegrationTests();
  test('stop blocks the next step', () {
    final audit = ExecutionAudit();
    expect(audit.canStartNextStep, isTrue);
    audit.requestStop();
    expect(audit.canStartNextStep, isFalse);
    expect(audit.entries.last.status, 'stopped');
  });

  test('unknown fields and diagnostics are redacted', () {
    final audit = ExecutionAudit();
    audit.record('password=secret', 'token=secret', diagnostic: 'secret');
    expect(audit.exportRedacted(consent: true), isNot(contains('secret')));
  });

  test('export fails closed without consent', () {
    final audit = ExecutionAudit();
    expect(() => audit.exportRedacted(consent: false), throwsStateError);
  });

  test('bounded memory and valid JSON', () {
    final audit = ExecutionAudit(maxEntries: 2);
    for (var i = 0; i < 5; i++) {
      audit.record('execution', 'completed');
    }
    expect(jsonDecode(audit.exportRedacted(consent: true)), hasLength(2));
  });
}

class _AuditHost implements WorkflowHost {
  final events = <String>[];
  final Completer<void> pending = Completer<void>();
  bool hold = false;
  bool deny = false;

  @override
  Future<bool> approve(WorkflowStep step) async {
    events.add('approve');
    return !deny;
  }

  @override
  Future<void> execute(WorkflowStep step) async {
    events.add('execute');
    if (hold) await pending.future;
  }

  @override
  Future<bool> verify(WorkflowStep step) async {
    events.add('verify');
    return true;
  }
}

WorkflowDefinition _twoStepDefinition() => WorkflowDefinition.fromJson({
  'version': 1,
  'id': 'audit-test',
  'trigger': 'manual',
  'steps': [
    {'type': 'hostAction', 'target': 'fake'},
    {'type': 'hostAction', 'target': 'fake'},
  ],
});

void auditIntegrationTests() {
  test('success produces only allowlisted step events', () async {
    final audit = ExecutionAudit();
    final host = _AuditHost();
    final execution = WorkflowExecution(
      _twoStepDefinition(),
      host,
      deadline: const Duration(seconds: 2),
      audit: audit,
    );
    expect(await execution.run(), WorkflowStatus.completed);
    expect(host.events.length, 6);
    expect(audit.entries.where((e) => e.status == 'completed').length, 3);
    expect(audit.entries.where((e) => e.stepIndex == 1).isNotEmpty, true);
  });

  test('stop during host action prevents second step', () async {
    final audit = ExecutionAudit();
    final host = _AuditHost()..hold = true;
    final execution = WorkflowExecution(
      _twoStepDefinition(),
      host,
      deadline: const Duration(seconds: 2),
      audit: audit,
    );
    final result = execution.run();
    await Future<void>.delayed(Duration.zero);
    execution.cancel();
    host.pending.complete();
    expect(await result, WorkflowStatus.cancelled);
    expect(host.events, ['approve', 'execute']);
    expect(audit.stopRequested, true);
  });

  test('permission denial redacts and fails closed', () async {
    final audit = ExecutionAudit();
    final host = _AuditHost()..deny = true;
    final execution = WorkflowExecution(
      _twoStepDefinition(),
      host,
      deadline: const Duration(seconds: 2),
      audit: audit,
    );
    expect(await execution.run(), WorkflowStatus.failed);
    expect(host.events, ['approve']);
    expect(audit.entries.last.status, 'denied');
  });

  testWidgets('stop UI cancels and export requires explicit consent', (
    tester,
  ) async {
    final audit = ExecutionAudit();
    final host = _AuditHost()..hold = true;
    final execution = WorkflowExecution(
      _twoStepDefinition(),
      host,
      deadline: const Duration(seconds: 5),
      audit: audit,
    );
    final running = execution.run();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExecutionAuditPanel(execution: execution, audit: audit),
        ),
      ),
    );
    await tester.tap(find.text('Export diagnostics'));
    await tester.pumpAndSettle();
    expect(find.text('Export diagnostics?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Redacted diagnostics'), findsNothing);
    await tester.tap(find.text('Stop execution'));
    await tester.pump();
    expect(audit.stopRequested, isTrue);
    host.pending.complete();
    expect(await running, WorkflowStatus.cancelled);
  });
}
