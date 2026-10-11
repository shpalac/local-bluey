import 'dart:convert';

/// A deliberately narrow, memory-only record. No raw text, frames or paths.
enum ActivityKind { pointer, keyboard, navigation, observation }

/// Non-sensitive classification only; sensitive events must not be recorded.
enum ActivityClassification { public, internal }

/// Invalid and future schema data is rejected rather than silently downgraded.
final class ActivityStepFormatException implements Exception {
  const ActivityStepFormatException(this.reason);
  final String reason;
  @override
  String toString() => 'ActivityStepFormatException: $reason';
}

/// Immutable, canonical and strictly validated BLU-002 activity event.
///
/// This is a transport DTO, not a capture service or persistence permission.
final class ActivityStep {
  ActivityStep({
    required this.stepId,
    required this.sessionId,
    required this.timestamp,
    required this.kind,
    required this.classification,
    required this.confidence,
  }) {
    _validateId(stepId, 'stepId');
    _validateId(sessionId, 'sessionId');
    if (!timestamp.isUtc ||
        timestamp.isBefore(DateTime.utc(2000)) ||
        timestamp.isAfter(DateTime.utc(2100))) {
      throw const ActivityStepFormatException('invalid UTC timestamp');
    }
    if (!confidence.isFinite || confidence < 0 || confidence > 1) {
      throw const ActivityStepFormatException('confidence out of range');
    }
  }

  static const int schemaVersion = 1;
  static final RegExp _idPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  final String stepId;
  final String sessionId;
  final DateTime timestamp;
  final ActivityKind kind;
  final ActivityClassification classification;
  final double confidence;

  static void _validateId(String value, String name) {
    if (!_idPattern.hasMatch(value)) {
      throw ActivityStepFormatException('invalid $name');
    }
  }

  /// Canonical insertion order and UTC millisecond precision.
  Map<String, Object> toJson() => {
    'schemaVersion': schemaVersion,
    'stepId': stepId,
    'sessionId': sessionId,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'kind': kind.name,
    'classification': classification.name,
    'confidence': confidence,
  };

  String encode() => jsonEncode(toJson());

  static ActivityStep decode(String source) {
    try {
      return fromJson(jsonDecode(source));
    } on ActivityStepFormatException {
      rethrow;
    } catch (_) {
      throw const ActivityStepFormatException('malformed JSON');
    }
  }

  static ActivityStep fromJson(Object? source) {
    if (source is! Map<String, dynamic>) {
      throw const ActivityStepFormatException('expected JSON object');
    }
    const fields = {
      'schemaVersion', 'stepId', 'sessionId', 'timestamp',
      'kind', 'classification', 'confidence',
    };
    if (source.length != fields.length || !source.keys.toSet().containsAll(fields)) {
      throw const ActivityStepFormatException('unknown or missing field');
    }
    if (source['schemaVersion'] != schemaVersion ||
        source['schemaVersion'] is! int) {
      throw const ActivityStepFormatException('unsupported schema version');
    }
    final stepId = source['stepId'];
    final sessionId = source['sessionId'];
    final timestamp = source['timestamp'];
    final kind = source['kind'];
    final classification = source['classification'];
    final confidence = source['confidence'];
    if (stepId is! String || sessionId is! String ||
        timestamp is! String || kind is! String ||
        classification is! String || confidence is! num) {
      throw const ActivityStepFormatException('invalid field type');
    }
    // Require explicit UTC Z, not an ambiguous local time or offset.
    if (!timestamp.endsWith('Z')) {
      throw const ActivityStepFormatException('timestamp must be UTC');
    }
    final parsedTime = DateTime.tryParse(timestamp);
    if (parsedTime == null || !parsedTime.isUtc) {
      throw const ActivityStepFormatException('invalid timestamp');
    }
    final parsedKind = ActivityKind.values.where((v) => v.name == kind).firstOrNull;
    final parsedClass = ActivityClassification.values
        .where((v) => v.name == classification).firstOrNull;
    if (parsedKind == null || parsedClass == null) {
      throw const ActivityStepFormatException('unknown enum');
    }
    return ActivityStep(
      stepId: stepId,
      sessionId: sessionId,
      timestamp: parsedTime,
      kind: parsedKind,
      classification: parsedClass,
      confidence: confidence.toDouble(),
    );
  }
}
