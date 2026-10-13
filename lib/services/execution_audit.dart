import 'dart:convert';

/// Memory-only, explicitly redacted execution history.
class ExecutionAudit {
  ExecutionAudit({this.maxEntries = 100});

  final int maxEntries;
  final List<AuditEntry> _entries = [];
  bool _stopRequested = false;

  List<AuditEntry> get entries => List.unmodifiable(_entries);
  bool get stopRequested => _stopRequested;
  bool get canStartNextStep => !_stopRequested;

  void requestStop() {
    _stopRequested = true;
    record('execution', 'stopped');
  }

  void record(String step, String status, {String? diagnostic}) {
    if (maxEntries <= 0) return;
    _entries.add(AuditEntry(
      step: _safeLabel(step),
      status: _safeLabel(status),
      diagnostic: diagnostic == null ? null : '[redacted]',
    ));
    if (_entries.length > maxEntries) _entries.removeAt(0);
  }

  /// Export requires an explicit user action; no file or network I/O occurs.
  String exportRedacted({required bool consent}) {
    if (!consent) throw StateError('Explicit consent required');
    return jsonEncode(_entries.map((entry) => entry.toJson()).toList());
  }

  static String _safeLabel(String value) {
    const allowed = <String>{
      'execution', 'started', 'completed', 'failed', 'stopped',
      'cancelled', 'timeout', 'denied', 'offline', 'recovered',
    };
    return allowed.contains(value) ? value : '[redacted]';
  }
}

class AuditEntry {
  const AuditEntry({
    required this.step,
    required this.status,
    this.diagnostic,
  });

  final String step;
  final String status;
  final String? diagnostic;

  Map<String, String> toJson() => {
    'step': step,
    'status': status,
    if (diagnostic != null) 'diagnostic': diagnostic!,
  };
}
