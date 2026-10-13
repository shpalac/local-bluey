import 'dart:async';

import 'workflow_dsl.dart';
import 'workflow_execution.dart';

/// A display-only description. Never persist previews or log action targets.
final class WorkflowActionPreview {
  const WorkflowActionPreview({
    required this.workflowId,
    required this.stepIndex,
    required this.type,
    required this.target,
    required this.permissions,
    required this.risky,
  });

  final String workflowId;
  final int stepIndex;
  final String type;
  final String target;
  final List<String> permissions;
  final bool risky;
}

/// An ephemeral, exact-action grant. A fresh process starts without grants.
final class WorkflowApprovalGrant {
  WorkflowApprovalGrant._();
  bool _revoked = false;

  void revoke() => _revoked = true;
  bool get isRevoked => _revoked;
}

abstract interface class WorkflowApprovalPrompt {
  /// null is denial, including dismiss, unavailable UI and offline operation.
  Future<bool> request(WorkflowActionPreview preview);
}

abstract interface class WorkflowSafetyCheck {
  /// Must consult the existing SafetyGate immediately before any host action.
  Future<bool> allows(WorkflowActionPreview preview);
}

/// Opt-in adapter for WorkflowExecution. Existing hosts remain unchanged.
///
/// The delegate must separately enforce SafetyGate and cooperate with
/// cancellation while performing long-running native actions.
final class WorkflowApprovalHost implements WorkflowHost {
  WorkflowApprovalHost({
    required WorkflowDefinition definition,
    required WorkflowHost delegate,
    required WorkflowApprovalPrompt prompt,
    required WorkflowSafetyCheck safetyGate,
  }) : _definition = WorkflowDefinition.fromJson(definition.toJson()),
       _delegate = delegate,
       _prompt = prompt,
       _safetyGate = safetyGate;

  final WorkflowDefinition _definition;
  final WorkflowHost _delegate;
  final WorkflowApprovalPrompt _prompt;
  final WorkflowSafetyCheck _safetyGate;
  final Map<int, WorkflowApprovalGrant> _grants = {};
  bool _cancelled = false;
  int _stepIndex = 0;

  void revokeAll() {
    _cancelled = true;
    for (final grant in _grants.values) {
      grant.revoke();
    }
    _grants.clear();
  }

  void revokeStep(int index) {
    _grants.remove(index)?.revoke();
  }

  WorkflowActionPreview preview(int index) {
    if (index < 0 || index >= _definition.steps.length) {
      throw RangeError.index(index, _definition.steps);
    }
    final step = _definition.steps[index];
    return WorkflowActionPreview(
      workflowId: _definition.id,
      stepIndex: index,
      type: step.type,
      target: step.target,
      permissions: List.unmodifiable(_definition.permissions),
      risky: step.type == 'hostAction',
    );
  }

  int _index(WorkflowStep step) {
    // Steps are validated copies; only the currently active step can act.
    if (_stepIndex >= _definition.steps.length) {
      throw StateError('Workflow already completed');
    }
    final expected = _definition.steps[_stepIndex];
    if (expected.type != step.type || expected.target != step.target) {
      throw StateError('Unexpected workflow action');
    }
    return _stepIndex;
  }

  @override
  Future<bool> approve(WorkflowStep step) async {
    if (_cancelled) return false;
    final index = _index(step);
    revokeStep(index);
    final action = preview(index);
    // All actions need explicit consent; risky actions additionally need gate.
    final accepted = await _prompt.request(action);
    if (_cancelled || !accepted) return false;
    final grant = WorkflowApprovalGrant._();
    _grants[index] = grant;
    return true;
  }

  @override
  Future<void> execute(WorkflowStep step) async {
    final index = _index(step);
    final grant = _grants[index];
    if (_cancelled || grant == null || grant.isRevoked) {
      throw StateError('Action approval missing or revoked');
    }
    final action = preview(index);
    final allowed = await _safetyGate.allows(action);
    if (_cancelled ||
        grant.isRevoked ||
        !identical(_grants[index], grant) ||
        !allowed) {
      throw StateError('Action blocked by safety policy');
    }
    // Check once more synchronously at the side-effect boundary.
    if (_cancelled || grant.isRevoked) {
      throw StateError('Action approval revoked');
    }
    await _delegate.execute(step);
  }

  @override
  Future<bool> verify(WorkflowStep step) async {
    final index = _index(step);
    final grant = _grants[index];
    if (_cancelled || grant == null || grant.isRevoked) return false;
    try {
      return await _delegate.verify(step);
    } finally {
      revokeStep(index);
      _stepIndex++;
    }
  }
}
