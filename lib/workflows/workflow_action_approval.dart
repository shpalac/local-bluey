import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'workflow_approval_grant_store.dart';
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

/// An exact-action grant; persistence is available only through opt-in setup.
final class WorkflowApprovalGrant {
  WorkflowApprovalGrant._({this.expiresAt, DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final DateTime? expiresAt;
  final DateTime Function() _now;
  bool _revoked = false;

  void revoke() => _revoked = true;
  bool get isRevoked =>
      _revoked || (expiresAt != null && !_now().isBefore(expiresAt!));
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
  factory WorkflowApprovalHost({
    required WorkflowDefinition definition,
    required WorkflowHost delegate,
    required WorkflowApprovalPrompt prompt,
    required WorkflowSafetyCheck safetyGate,
  }) {
    return WorkflowApprovalHost._(
      WorkflowDefinition.fromJson(definition.toJson()),
      delegate,
      prompt,
      safetyGate,
    );
  }

  /// Persistent grants are loaded only on explicit opt-in. Corrupt records
  /// never authorize actions and a live SafetyGate check is always required.
  static Future<WorkflowApprovalHost> openWithStorage({
    required WorkflowDefinition definition,
    required WorkflowHost delegate,
    required WorkflowApprovalPrompt prompt,
    required WorkflowSafetyCheck safetyGate,
    required WorkflowApprovalGrantStorage storage,
    Duration grantTtl = const Duration(minutes: 5),
    DateTime Function()? now,
  }) async {
    if (grantTtl <= Duration.zero) {
      throw ArgumentError.value(grantTtl, 'grantTtl');
    }
    final host = WorkflowApprovalHost._(
      WorkflowDefinition.fromJson(definition.toJson()),
      delegate,
      prompt,
      safetyGate,
      storage: storage,
      grantTtl: grantTtl,
      now: now ?? DateTime.now,
    );
    try {
      for (var i = 0; i < host._definition.steps.length; i++) {
        final record = await storage.read(host._key(i));
        if (record != null &&
            !record.revoked &&
            host._now().isBefore(record.expiresAt)) {
          host._grants[i] = WorkflowApprovalGrant._(
            expiresAt: record.expiresAt,
            now: host._now,
          );
        }
      }
    } catch (_) {
      host._grants.clear();
      host._cancelled = true;
    }
    return host;
  }

  WorkflowApprovalHost._(
    this._definition,
    this._delegate,
    this._prompt,
    this._safetyGate, {
    WorkflowApprovalGrantStorage? storage,
    Duration grantTtl = const Duration(minutes: 5),
    DateTime Function()? now,
  }) : _storage = storage,
       _grantTtl = grantTtl,
       _now = now ?? DateTime.now;

  final WorkflowDefinition _definition;
  final WorkflowHost _delegate;
  final WorkflowApprovalPrompt _prompt;
  final WorkflowSafetyCheck _safetyGate;
  final WorkflowApprovalGrantStorage? _storage;
  final Duration _grantTtl;
  final DateTime Function() _now;
  final Map<int, WorkflowApprovalGrant> _grants = {};
  bool _cancelled = false;
  int _stepIndex = 0;

  String _key(int index) {
    // Include permissions and the validated definition, not merely the
    // visible target: a changed workflow must never inherit an old grant.
    return sha256.convert(
      utf8.encode('${jsonEncode(_definition.toJson())}:$index'),
    ).toString();
  }

  Future<void> revokeAll() async {
    _cancelled = true;
    for (var i = 0; i < _definition.steps.length; i++) {
      await revokeStep(i);
    }
  }

  Future<void> revokeStep(int index) async {
    final grant = _grants.remove(index);
    grant?.revoke();
    if (_storage != null) {
      try {
        await _storage.write(
          _key(index),
          WorkflowApprovalGrantRecord(
            expiresAt: grant?.expiresAt ?? _now().toUtc(),
            revoked: true,
          ),
        );
      } catch (_) {
        _cancelled = true;
        rethrow;
      }
    }
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
    if (_storage == null) {
      // Keep the legacy prompt on the same synchronous turn. This also
      // prevents a pre-failed prompt Future from becoming unhandled.
      revokeStep(index);
    } else {
      try {
        await revokeStep(index);
      } catch (_) {
        return false;
      }
    }
    final action = preview(index);
    // All actions need explicit consent; risky actions additionally need gate.
    final accepted = await _prompt.request(action);
    if (_cancelled || !accepted) return false;
    final expires = _storage == null ? null : _now().add(_grantTtl);
    final grant = WorkflowApprovalGrant._(
      expiresAt: expires,
      now: _now,
    );
    _grants[index] = grant;
    if (_storage != null) {
      try {
        await _storage.write(
          _key(index),
          WorkflowApprovalGrantRecord(expiresAt: expires!),
        );
      } catch (_) {
        _grants.remove(index);
        grant.revoke();
        return false;
      }
    }
    if (_cancelled || grant.isRevoked) {
      try {
        await revokeStep(index);
      } catch (_) {
        _cancelled = true;
      }
      return false;
    }
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
      await revokeStep(index);
      _stepIndex++;
    }
  }
}
