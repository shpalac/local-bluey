import 'dart:convert';

/// Persistence boundary for explicit workflow approvals.
///
/// Implementations must store only approval metadata. Secrets and action data
/// are intentionally not retained.
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

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Map<String, Object> toJson() => {
        'expiresAt': expiresAt.toIso8601String(),
        'revoked': revoked,
      };

  factory WorkflowApprovalGrantRecord.fromJson(Map<String, Object?> json) {
    return WorkflowApprovalGrantRecord(
      expiresAt: DateTime.parse(json['expiresAt']! as String),
      revoked: json['revoked']! as bool,
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
      jsonDecode(value) as Map<String, Object?>,
    );
  }

  @override
  Future<void> remove(String key) async {
    _records.remove(key);
  }
}
