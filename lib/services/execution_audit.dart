import 'dart:convert';

/// Bounded, memory-only execution history. Never stores user-supplied labels.
class ExecutionAudit {
  ExecutionAudit({this.maxEntries = 100})
    : assert(maxEntries >= 0, 'maxEntries cannot be negative');

  final int maxEntries;
  final List<AuditEntry> _entries = [];
  bool _stopRequested = false;

  List<AuditEntry> get entries => List.unmodifiable(_entries);
  bool get stopRequested => _stopRequested;
  bool get canStartNextStep => !_stopRequested;

  void requestStop() {
    if (_stopRequested) return;
    _stopRequested = true;
    record('execution', 'stopped');
  }

  void record(
    String step,
    String status, {
    int? stepIndex,
    String? diagnostic,
  }) {
    if (maxEntries == 0) return;
    _entries.add(
      AuditEntry(
        step: _safeLabel(step),
        status: _safeLabel(status),
        stepIndex: stepIndex != null && stepIndex >= 0 ? stepIndex : null,
        diagnostic: diagnostic == null ? null : '[redacted]',
      ),
    );
    if (_entries.length > maxEntries) _entries.removeAt(0);
  }

  /// Only an explicitly consented, local caller receives serialized data.
  /// This API performs no clipboard, disk, or network access.
  String exportRedacted({required bool consent}) {
    if (!consent) throw StateError('Explicit consent required');
    return jsonEncode(_entries.map((entry) => entry.toJson()).toList());
  }

  static String _safeLabel(String value) {
    const allowed = <String>{
      'execution',
      'step',
      'started',
      'approval',
      'verifying',
      'completed',
      'failed',
      'stopped',
      'cancelled',
      'timeout',
      'denied',
      'offline',
      'recovered',
    };
    return allowed.contains(value) ? value : '[redacted]';
  }
}

class AuditEntry {
  const AuditEntry({
    required this.step,
    required this.status,
    this.stepIndex,
    this.diagnostic,
  });

  final String step;
  final String status;
  final int? stepIndex;
  final String? diagnostic;

  Map<String, Object> toJson() => {
    'step': step,
    'status': status,
    if (stepIndex != null) 'stepIndex': stepIndex!,
    if (diagnostic != null) 'diagnostic': diagnostic!,
  };
}
