import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/undo.dart';
import 'package:local_bluey/services/user_feedback.dart';

void main() {
  test('every known failure maps to a pattern (#89)', () {
    for (final kind in FailureKind.values) {
      final spec = feedbackFor(kind);
      expect(spec.title, isNotEmpty, reason: kind.name);
      expect(spec.why, isNotEmpty, reason: kind.name);
      expect(spec.actionLabel, isNotEmpty, reason: kind.name);
    }
  });

  test('empty states are the no-content cases only', () {
    for (final kind in FailureKind.values) {
      final spec = feedbackFor(kind);
      const empties = {
        FailureKind.macNotFound,
        FailureKind.noProviderConfigured,
        FailureKind.noHistory,
      };
      expect(spec.isEmptyState, empties.contains(kind), reason: kind.name);
    }
  });

  test('classifier maps tool error text to known failures', () {
    expect(
      classifyFailure('Screen knowledge is stale - call look_at_screen first.'),
      FailureKind.staleTarget,
    );
    expect(
      classifyFailure('Refused by the safety gate'),
      FailureKind.actionRefused,
    );
    expect(
      classifyFailure('Connection refused'),
      FailureKind.providerUnreachable,
    );
    expect(classifyFailure('Mac offline'), FailureKind.macOffline);
    expect(classifyFailure('everything is fine'), isNull);
  });

  test('undo is offered only for reversible actions (#89)', () {
    expect(undoFor('type_text', {'text': 'hi'}), isNotNull);
    expect(undoFor('click', {'x': 1, 'y': 2}), isNull);
    expect(undoFor('scroll', {}), isNull);
    expect(undoFor('open_app', {'name': 'Safari'}), isNull);
    expect(undoFor('press_keys', {'keys': 'cmd+t'}), isNull);
  });
}
