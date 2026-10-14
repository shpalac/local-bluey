/// Durable recovery metadata contract used during startup reconciliation.
///
/// Implementations must persist state before process termination. The in-memory
/// fake exists for deterministic restart simulation tests only.
class RecoveryMetadata {
  const RecoveryMetadata({
    required this.executionId,
    required this.interrupted,
  });

  final String executionId;
  final bool interrupted;
}

abstract interface class DurableRecoveryStore {
  Future<void> save(RecoveryMetadata metadata);

  Future<RecoveryMetadata?> load();

  Future<void> clear();
}

class MemoryDurableRecoveryStore implements DurableRecoveryStore {
  RecoveryMetadata? _metadata;

  @override
  Future<void> save(RecoveryMetadata metadata) async {
    _metadata = metadata;
  }

  @override
  Future<RecoveryMetadata?> load() async => _metadata;

  @override
  Future<void> clear() async {
    _metadata = null;
  }
}
