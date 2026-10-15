import 'package:flutter/material.dart';

import '../services/execution_audit.dart';
import '../workflows/workflow_execution.dart';

/// Opt-in view: callers explicitly supply an execution and its local audit.
/// No background capture, persistence, clipboard write or network transport.
class ExecutionAuditPanel extends StatefulWidget {
  const ExecutionAuditPanel({
    required this.execution,
    required this.audit,
    super.key,
  });

  final WorkflowExecution execution;
  final ExecutionAudit audit;

  @override
  State<ExecutionAuditPanel> createState() => _ExecutionAuditPanelState();
}

class _ExecutionAuditPanelState extends State<ExecutionAuditPanel> {
  Future<void> _showDiagnostics() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export diagnostics?'),
        content: const Text(
          'Only redacted, memory-only workflow event labels will be shown. '
          'Review the information before sharing it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Show redacted data'),
          ),
        ],
      ),
    );
    if (!mounted || approved != true) return;
    final redacted = widget.audit.exportRedacted(consent: true);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Redacted diagnostics'),
        content: SingleChildScrollView(child: SelectableText(redacted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stopped =
        widget.audit.stopRequested ||
        widget.execution.status == WorkflowStatus.completed ||
        widget.execution.status == WorkflowStatus.failed ||
        widget.execution.status == WorkflowStatus.cancelled;
    final failure = widget.audit.entries.reversed
        .where((entry) => entry.status == 'denied' || entry.status == 'timeout' || entry.status == 'failed' || entry.status == 'offline')
        .firstOrNull;
    final failureMessage = switch (failure?.status) {
      'denied' => 'Permission denied. Review approval settings before retrying.',
      'timeout' => 'Workflow timed out. Check the host and retry manually.',
      'offline' => 'Host offline. Reconnect before retrying.',
      'failed' => 'Workflow failed. Review redacted diagnostics before retrying.',
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Execution timeline'),
        if (failureMessage != null)
          Text(failureMessage, key: const Key('workflow-failure-message')),
        for (final entry in widget.audit.entries)
          ListTile(
            dense: true,
            title: Text(
              entry.stepIndex == null
                  ? entry.step
                  : 'Step ${entry.stepIndex! + 1}',
            ),
            subtitle: Text(entry.status),
          ),
        Row(
          children: [
            TextButton(
              onPressed: stopped
                  ? null
                  : () {
                      widget.execution.cancel();
                      setState(() {});
                    },
              child: const Text('Stop execution'),
            ),
            TextButton(
              onPressed: _showDiagnostics,
              child: const Text('Export diagnostics'),
            ),
          ],
        ),
      ],
    );
  }
}
