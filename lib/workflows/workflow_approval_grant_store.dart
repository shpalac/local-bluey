import 'dart:convert';
import 'dart:io';

/// Persistence boundary for approval metadata only.
/// Action payloads and secrets must never be stored here.
abstract interface class WorkflowApprovalGrantStore {
  Future<void> write(String key, Map<String, Object?> value);
  Future<Map<String, Object?>?> read(String key);
  Future<void> remove(String key);
}

final class FileWorkflowApprovalGrantStore
    implements WorkflowApprovalGrantStore {
  FileWorkflowApprovalGrantStore(this.directory);

  final Directory directory;

  File _file(String key) => File('${directory.path}/approval_$key.json');

  @override
  Future<void> write(String key, Map<String, Object?> value) async {
    await directory.create(recursive: true);
    final file = _file(key);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(value));
    await temporary.rename(file.path);
  }

  @override
  Future<Map<String, Object?>?> read(String key) async {
    final file = _file(key);
    if (!await file.exists()) return null;
    try {
      return jsonDecode(await file.readAsString()) as Map<String, Object?>;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> remove(String key) async {
    final file = _file(key);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
