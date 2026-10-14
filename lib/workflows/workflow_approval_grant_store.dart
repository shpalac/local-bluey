import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Only the expiry and revocation state may be persisted. No workflow payload.
abstract interface class WorkflowApprovalGrantStorage {
  Future<void> write(String key, WorkflowApprovalGrantRecord record);
  Future<WorkflowApprovalGrantRecord?> read(String key);
  Future<void> remove(String key);
}

final class WorkflowApprovalGrantRecord {
  const WorkflowApprovalGrantRecord({
    required this.expiresAt,
    this.revoked = false,
  });

  final DateTime expiresAt;
  final bool revoked;

  bool get isExpired => !DateTime.now().isBefore(expiresAt);

  Map<String, Object> toJson() => {
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'revoked': revoked,
  };

  factory WorkflowApprovalGrantRecord.fromJson(Map<String, dynamic> json) {
    if (json.length != 2 ||
        json['expiresAt'] is! String ||
        json['revoked'] is! bool) {
      throw const FormatException('Invalid approval metadata');
    }
    return WorkflowApprovalGrantRecord(
      expiresAt: DateTime.parse(json['expiresAt'] as String).toUtc(),
      revoked: json['revoked'] as bool,
    );
  }
}

final class MemoryWorkflowApprovalGrantStorage
    implements WorkflowApprovalGrantStorage {
  final Map<String, String> _records = {};

  @override
  Future<void> write(String key, WorkflowApprovalGrantRecord record) async {
    _records[key] = jsonEncode(record.toJson());
  }

  @override
  Future<WorkflowApprovalGrantRecord?> read(String key) async {
    final value = _records[key];
    if (value == null) return null;
    return WorkflowApprovalGrantRecord.fromJson(
      jsonDecode(value) as Map<String, dynamic>,
    );
  }

  @override
  Future<void> remove(String key) async {
    _records.remove(key);
  }
}

/// Explicit opt-in file-backed storage for non-secret approval metadata.
///
/// Each atomic replacement uses a temporary file and a same-directory rename.
/// The filename is a digest so workflow IDs and action targets are not exposed.
final class FileWorkflowApprovalGrantStorage
    implements WorkflowApprovalGrantStorage {
  const FileWorkflowApprovalGrantStorage(this.directory);

  final Directory directory;

  File _file(String key) {
    final digest = sha256.convert(utf8.encode(key)).toString();
    return File('${directory.path}${Platform.pathSeparator}$digest.json');
  }

  @override
  Future<WorkflowApprovalGrantRecord?> read(String key) async {
    final file = _file(key);
    if (!await file.exists()) return null;
    final data = jsonDecode(await file.readAsString());
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid approval metadata');
    }
    return WorkflowApprovalGrantRecord.fromJson(data);
  }

  @override
  Future<void> write(String key, WorkflowApprovalGrantRecord record) async {
    await directory.create(recursive: true);
    final file = _file(key);
    final temporary = File('${file.path}.pending');
    await temporary.writeAsString(jsonEncode(record.toJson()), flush: true);
    await temporary.rename(file.path);
  }

  @override
  Future<void> remove(String key) async {
    final file = _file(key);
    if (await file.exists()) await file.delete();
  }
}
