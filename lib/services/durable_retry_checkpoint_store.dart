import 'dart:convert';
import 'dart:io';

import 'idempotent_retry.dart';

class DurableRetryCheckpointStore implements RetryCheckpointStore {
  DurableRetryCheckpointStore(this.directory);

  final Directory directory;

  File _file(String id) => File('${directory.path}/$id.json');

  @override
  Future<RetryCheckpoint?> read(String operationId) async {
    final file = _file(operationId);
    if (!await file.exists()) return null;
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return RetryCheckpoint(
        operationId: json['operationId'] as String,
        phase: RetryPhase.values.byName(json['phase'] as String),
      );
    } catch (e) {
      throw StateError('Corrupt retry checkpoint: $operationId');
    }
  }

  @override
  Future<bool> claim(String operationId) async {
    await directory.create(recursive: true);
    final file = _file(operationId);
    try {
      await file.create(exclusive: true);
      await file.writeAsString(
        jsonEncode({
          'operationId': operationId,
          'phase': RetryPhase.started.name,
        }),
      );
      return true;
    } on PathExistsException {
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> write(RetryCheckpoint checkpoint) async {
    await directory.create(recursive: true);
    final target = _file(checkpoint.operationId);
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(
      jsonEncode({
        'operationId': checkpoint.operationId,
        'phase': checkpoint.phase.name,
      }),
    );
    await temp.rename(target.path);
  }
}
