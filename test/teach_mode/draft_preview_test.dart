import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/teach_mode/draft_builder.dart';

void main() {
  const builder = TeachDraftBuilder();

  test('preview flags unknown steps and never authorizes execution', () {
    final preview = builder.preview([
      {'action': 'unknown', 'target': 'submit'},
    ]);
    expect(preview.steps.single.kind, DraftStepKind.unknown);
    expect(preview.steps.single.requiresReview, isTrue);
    expect(preview.requiresReview, isTrue);
    expect(preview.canAutoExecute, isFalse);
  });

  test(
    'preview handles empty and malformed observations deterministically',
    () {
      final empty = builder.preview([]);
      expect(empty.steps, isEmpty);
      expect(empty.canAutoExecute, isFalse);

      final malformed = builder.preview([
        {'action': null, 'target': 42},
        {'action': 'click', 'target': 'bad target'},
      ]);
      expect(malformed.steps, hasLength(2));
      expect(malformed.warnings, hasLength(2));
      expect(malformed.steps.every((step) => step.requiresReview), isTrue);
      expect(() => malformed.steps.clear(), throwsUnsupportedError);
    },
  );

  test('preview exposes placeholders without retaining typed secrets', () {
    final preview = builder.preview([
      {'action': 'type', 'target': 'username'},
      {'action': 'type', 'target': 'password', 'value': 'topsecret'},
    ]);
    expect(preview.steps.first.variablePlaceholder, 'input_1');
    expect(preview.steps.first.target, 'username');
    expect(preview.steps.last.variablePlaceholder, isNull);
    expect(preview.steps.last.requiresReview, isTrue);
    expect(preview.toString(), isNot(contains('topsecret')));
    expect(preview.canAutoExecute, isFalse);
  });
}
