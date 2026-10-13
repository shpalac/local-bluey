import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/teach_mode/draft_builder.dart';

void main() {
  const builder = TeachDraftBuilder();

  test('typed happy path remains non-executable', () {
    final draft = builder.build([
      {'action': 'click', 'target': 'submit'},
    ]);
    expect(draft.steps.single.kind, DraftStepKind.click);
    expect(draft.warnings, isEmpty);
    expect(draft.canAutoExecute, isFalse);
  });

  test('unknown and malformed observations require review', () {
    final draft = builder.build([
      {'action': 'unknown', 'target': 'button'},
      {'action': 'type', 'target': 'password field', 'value': 'secret'},
      {'action': null},
    ]);
    expect(draft.warnings, hasLength(3));
    expect(draft.steps[1].target, isEmpty);
    expect(draft.canAutoExecute, isFalse);
    expect(draft.toString(), isNot(contains('secret')));
  });

  test('empty observations are safe and immutable', () {
    final draft = builder.build([]);
    expect(draft.steps, isEmpty);
    expect(draft.canAutoExecute, isFalse);
    expect(
      () => draft.steps.add(const DraftStep(DraftStepKind.click, 'x')),
      throwsUnsupportedError,
    );
  });
}
