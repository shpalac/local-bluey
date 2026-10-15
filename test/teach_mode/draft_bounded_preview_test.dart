import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/teach_mode/draft_builder.dart';

void main() {
  const builder = TeachDraftBuilder();

  test('ac2 preview is bounded on oversized untrusted input', () {
    final observations = List<Map<String, Object?>>.generate(
      TeachDraftBuilder.maxReviewSteps + 1,
      (index) => {'action': 'click', 'target': 'element_$index'},
    );
    final preview = builder.preview(observations);

    expect(preview.steps, hasLength(TeachDraftBuilder.maxReviewSteps));
    expect(preview.steps.first.target, 'element_0');
    expect(
      preview.steps.last.target,
      'element_${TeachDraftBuilder.maxReviewSteps - 1}',
    );
    expect(preview.warnings, contains(contains('omitted')));
    expect(preview.requiresReview, isTrue);
    expect(preview.canAutoExecute, isFalse);
    expect(
      () => preview.steps.clear(),
      throwsUnsupportedError,
    );
    expect(
      () => preview.warnings.clear(),
      throwsUnsupportedError,
    );
  });

  test('ac2 exact preview boundary retains all sanitized steps', () {
    final observations = List<Map<String, Object?>>.generate(
      TeachDraftBuilder.maxReviewSteps,
      (index) => {'action': 'click', 'target': 'button_$index'},
    );
    final preview = builder.preview(observations);

    expect(preview.steps, hasLength(TeachDraftBuilder.maxReviewSteps));
    expect(preview.warnings, isEmpty);
    expect(preview.requiresReview, isFalse);
    expect(preview.canAutoExecute, isFalse);

    final empty = builder.preview([]);
    expect(empty.steps, isEmpty);
    expect(empty.warnings, isEmpty);
  });
}
