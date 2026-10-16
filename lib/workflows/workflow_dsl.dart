import 'dart:convert';

/// Declarative only: parsing never performs actions or requests permissions.
final class WorkflowDefinition {
  const WorkflowDefinition({
    required this.id,
    required this.trigger,
    required this.steps,
    this.permissions = const [],
    this.preconditions = const [],
    this.postconditions = const [],
    this.retryLimit = 0,
  });

  static const schemaVersion = 1;
  final String id;
  final String trigger;
  final List<WorkflowStep> steps;
  final List<String> permissions;
  final List<String> preconditions;
  final List<String> postconditions;
  final int retryLimit;

  factory WorkflowDefinition.fromJson(Map<String, dynamic> json) {
    const allowedFields = {
      'version',
      'id',
      'trigger',
      'steps',
      'permissions',
      'preconditions',
      'postconditions',
      'retryLimit',
    };
    if (json.keys.any((key) => !allowedFields.contains(key))) {
      throw const FormatException('Unknown workflow field');
    }
    if (json['version'] != schemaVersion) {
      throw const FormatException('Unsupported workflow schema version');
    }
    final id = _requiredString(json['id'], 'id');
    final trigger = _requiredString(json['trigger'], 'trigger');
    if (!const {'manual', 'scheduled', 'event'}.contains(trigger)) {
      throw const FormatException('Unsupported trigger');
    }
    final rawSteps = json['steps'];
    if (rawSteps is! List || rawSteps.isEmpty) {
      throw const FormatException('Workflow requires steps');
    }
    final steps = rawSteps
        .map((step) {
          if (step is! Map<String, dynamic>) {
            throw const FormatException('Invalid step');
          }
          return WorkflowStep.fromJson(step);
        })
        .toList(growable: false);
    final retry = json['retryLimit'] ?? 0;
    if (retry is! int || retry < 0 || retry > 3) {
      throw const FormatException('Invalid retry limit');
    }
    return WorkflowDefinition(
      id: id,
      trigger: trigger,
      steps: List.unmodifiable(steps),
      permissions: _stringList(json['permissions']),
      preconditions: _stringList(json['preconditions']),
      postconditions: _stringList(json['postconditions']),
      retryLimit: retry,
    );
  }

  static WorkflowDefinition decode(String source) {
    final value = jsonDecode(source);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Expected workflow object');
    }
    return WorkflowDefinition.fromJson(value);
  }

  Map<String, dynamic> toJson() => {
    'version': schemaVersion,
    'id': id,
    'trigger': trigger,
    'steps': steps.map((step) => step.toJson()).toList(),
    'permissions': permissions,
    'preconditions': preconditions,
    'postconditions': postconditions,
    'retryLimit': retryLimit,
  };

  String encode() => jsonEncode(toJson());
}

final class WorkflowStep {
  const WorkflowStep({required this.type, required this.target});
  final String type;
  final String target;

  factory WorkflowStep.fromJson(Map<String, dynamic> json) {
    if (json.keys.any((key) => key != 'type' && key != 'target')) {
      throw const FormatException('Unknown workflow step field');
    }
    final type = _requiredString(json['type'], 'step.type');
    if (!const {'notify', 'wait', 'hostAction'}.contains(type)) {
      throw const FormatException('Unsupported step type');
    }
    return WorkflowStep(type: type, target: _safeTarget(json['target']));
  }

  Map<String, dynamic> toJson() => {'type': type, 'target': target};
}

String _requiredString(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Invalid $field');
  }
  return value;
}

List<String> _stringList(Object? value) {
  if (value == null) return const [];
  if (value is! List ||
      value.any((item) => item is! String || item.trim().isEmpty)) {
    throw const FormatException('Invalid string list');
  }
  return List.unmodifiable(value.cast<String>());
}

String _safeTarget(Object? value) {
  final target = _requiredString(value, 'step.target');
  if (target.runes.any((codePoint) => codePoint < 0x20 || codePoint == 0x7f)) {
    throw const FormatException('Invalid step target control character');
  }
  return target;
}
