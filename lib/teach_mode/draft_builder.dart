/// In-memory, non-executable Teach Mode draft conversion.
/// No persistence, host control, network access, or secret payloads.
enum DraftStepKind { click, type, scroll, unknown }

class DraftStep {
  const DraftStep(this.kind, this.target, {this.uncertain = false});
  final DraftStepKind kind;
  final String target;
  final bool uncertain;
}

class TeachDraft {
  const TeachDraft(this.steps, this.warnings);
  final List<DraftStep> steps;
  final List<String> warnings;

  /// Drafts must be explicitly reviewed by a separate approval system.
  bool get canAutoExecute => false;
}

class TeachDraftBuilder {
  const TeachDraftBuilder();

  TeachDraft build(List<Map<String, Object?>> observations) {
    final steps = <DraftStep>[];
    final warnings = <String>[];
    for (var index = 0; index < observations.length; index++) {
      final item = observations[index];
      final action = item['action'];
      final target = item['target'];
      final kind = switch (action) {
        'click' => DraftStepKind.click,
        'type' => DraftStepKind.type,
        'scroll' => DraftStepKind.scroll,
        _ => DraftStepKind.unknown,
      };
      // Reject payloads and untrusted target data rather than retaining secrets.
      final safeTarget =
          target is String &&
              target.isNotEmpty &&
              RegExp(r'^[a-zA-Z0-9_.-]{1,80}$').hasMatch(target)
          ? target
          : '';
      final uncertain =
          kind == DraftStepKind.unknown ||
          safeTarget.isEmpty ||
          item.keys.any((key) => key != 'action' && key != 'target');
      if (uncertain) warnings.add('Step ${index + 1} needs review');
      steps.add(DraftStep(kind, safeTarget, uncertain: uncertain));
    }
    return TeachDraft(List.unmodifiable(steps), List.unmodifiable(warnings));
  }
}
