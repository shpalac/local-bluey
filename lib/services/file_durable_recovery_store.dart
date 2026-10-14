import 'dart:convert';
import 'dart:io';

import 'durable_recovery_store.dart';

/// Local metadata only: never persist step inputs, secrets, or host output.
///
/// Each save uses a same-directory temporary file followed by an atomic rename.
/// A corrupt file fails closed rather than silently permitting a new execution.
final class FileDurableRecoveryStore implements DurableRecoveryStore {
  FileDurableRecoveryStore(this.file);

  final File file;

  @override
  Future<void> save(RecoveryMetadata metadata) async {
    if (metadata.executionId.trim().isEmpty) {
      throw const FormatException('Recovery execution ID must not be empty');
    }
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    try {
      await temporary.writeAsString(
        jsonEncode({
          'version': 1,
          'executionId': metadata.executionId,
          'interrupted': metadata.interrupted,
        }),
        flush: true,
      );
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  @override
  Future<RecoveryMetadata?> load() async {
    if (!await file.exists()) return null;
    final Object? decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic> ||
        decoded['version'] != 1 ||
        decoded['executionId'] is! String ||
        (decoded['executionId'] as String).trim().isEmpty ||
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
    if (await file.exists()) await file.delete();
  }
}
