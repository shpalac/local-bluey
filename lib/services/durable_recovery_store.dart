import 'dart:convert';
import 'dart:io';

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


/// File-backed recovery metadata. The caller supplies an application-private path.
///
/// Writes use a sibling staging file followed by an atomic rename on supported
/// filesystems. An empty file represents acknowledged or absent recovery.
class FileDurableRecoveryStore implements DurableRecoveryStore {
  FileDurableRecoveryStore(this.file);

  final File file;

  @override
  Future<void> save(RecoveryMetadata metadata) async {
    if (metadata.executionId.isEmpty) {
      throw ArgumentError.value(metadata.executionId, 'executionId');
    }
    await file.parent.create(recursive: true);
    final staging = File('${file.path}.pending');
    await staging.writeAsString(
      jsonEncode({
        'version': 1,
        'executionId': metadata.executionId,
        'interrupted': metadata.interrupted,
      }),
      flush: true,
    );
    await staging.rename(file.path);
  }

  @override
  Future<RecoveryMetadata?> load() async {
    if (!await file.exists()) return null;
    final raw = await file.readAsString();
    if (raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> ||
        decoded['version'] != 1 ||
        decoded['executionId'] is! String ||
        (decoded['executionId'] as String).isEmpty ||
        decoded['interrupted'] is! bool) {
      throw const FormatException('Invalid recovery metadata');
    }
    return RecoveryMetadata(
      executionId: decoded['executionId'] as String,
      interrupted: decoded['interrupted'] as bool,
    );
  }

  @override
  Future<void> clear() async {
    await file.parent.create(recursive: true);
    await file.writeAsString('', flush: true);
  }
}
