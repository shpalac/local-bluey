/// Durable recovery metadata used by startup reconciliation.
///
/// Persistence implementations must store interrupted executions before process
/// termination. The memory implementation is deterministic for tests.
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
