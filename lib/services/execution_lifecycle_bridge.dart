/// Production-safe lifecycle state bridge for BLU-020.
///
/// This keeps recovery metadata explicit and in-memory. It does not replay
/// host actions. Native HostControl/TCC validation remains a manual gap.
final class ExecutionLifecycleBridge {
  ExecutionLifecycleBridge();

  String? _pendingExecutionId;
  bool _restartDetected = false;

  String? get pendingExecutionId => _pendingExecutionId;
  bool get restartDetected => _restartDetected;

  void markStarted(String executionId) {
    if (executionId.trim().isEmpty) {
      throw ArgumentError.value(executionId, 'executionId');
    }
    _pendingExecutionId = executionId;
    _restartDetected = false;
  }

  void markRestart() {
    _restartDetected = _pendingExecutionId != null;
  }

  /// Returns true when an interrupted execution requires reconciliation.
  /// The bridge intentionally never resumes execution automatically.
  bool requiresRecovery() => _restartDetected && _pendingExecutionId != null;

  void acknowledgeRecovery() {
    _pendingExecutionId = null;
    _restartDetected = false;
  }
}
