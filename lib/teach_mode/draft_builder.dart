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

  /// Only a bounded prefix of untrusted observations enters a review draft.
  /// Overflow is always reported as a warning, never silently accepted.
  static const int maxReviewSteps = 256;

  /// Derives a safe review preview without granting execution rights.
  TeachDraftPreview preview(List<Map<String, Object?>> observations) =>
      TeachDraftPreview(build(observations));

  TeachDraft build(List<Map<String, Object?>> observations) {
    final steps = <DraftStep>[];
    final warnings = <String>[];
    if (observations.length > maxReviewSteps) {
      warnings.add('Additional captured steps omitted; review required');
    }
    final reviewCount = observations.length > maxReviewSteps
        ? maxReviewSteps
        : observations.length;
    for (var index = 0; index < reviewCount; index++) {
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

/// A review-only projection of captured observations. It deliberately has no
/// conversion to WorkflowDefinition or host execution API.
final class TeachDraftPreview {
  TeachDraftPreview(TeachDraft draft)
    : steps = List.unmodifiable(
        draft.steps.asMap().entries.map((entry) {
          final step = entry.value;
          return DraftPreviewStep(
            ordinal: entry.key + 1,
            kind: step.kind,
            target: step.target,
            requiresReview: step.uncertain,
            variablePlaceholder:
                step.kind == DraftStepKind.type && !step.uncertain
                ? 'input_${entry.key + 1}'
                : null,
          );
        }),
      ),
      warnings = List.unmodifiable(draft.warnings);

  final List<DraftPreviewStep> steps;
  final List<String> warnings;

  bool get requiresReview => warnings.isNotEmpty;
  bool get canAutoExecute => false;
}

final class DraftPreviewStep {
  const DraftPreviewStep({
    required this.ordinal,
    required this.kind,
    required this.target,
    required this.requiresReview,
    required this.variablePlaceholder,
  });

  final int ordinal;
  final DraftStepKind kind;
  final String target;
  final bool requiresReview;

  /// Identifier only; the typed value is never retained in the draft.
  final String? variablePlaceholder;
}
