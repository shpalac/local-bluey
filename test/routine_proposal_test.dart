import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/routine_proposal.dart';
import 'package:local_bluey/services/routines.dart';

void main() {
  Map<String, Object?> valid() => {
    'name': 'דוגמה',
    'trigger': 'HELLO שלום',
    'instructions': 'הצעה בלבד',
  };
  test(
    'Hebrew retained, trigger canonicalized and proposal always disabled',
    () {
      final proposal = RoutineProposal.fromFields(valid());
      expect(proposal.routine.name, 'דוגמה');
      expect(proposal.routine.trigger, 'hello שלום');
      expect(proposal.routine.instructions, 'הצעה בלבד');
      expect(proposal.routine.enabled, isFalse);
    },
  );
  test('missing, extra and activation fields rejected', () {
    for (final fields in [
      valid()..remove('name'),
      valid()..['enabled'] = true,
      valid()..['tool'] = 'fabricated',
      <String, Object?>{},
    ]) {
      expect(
        () => RoutineProposal.fromFields(fields),
        throwsA(isA<RoutineProposalException>()),
      );
    }
  });
  for (final key in ['name', 'trigger', 'instructions']) {
    test('$key invalid types/empty content rejected without raw errors', () {
      for (final value in [null, true, 4, [], {}, '', ' \n\t']) {
        try {
          RoutineProposal.fromFields(valid()..[key] = value);
          fail('invalid fields admitted');
        } on RoutineProposalException catch (error) {
          expect(error.toString(), 'Routine proposal fields are invalid.');
        }
      }
    });
  }
  test('existing store field limits reused exactly', () {
    final limits = {
      'name': RoutineStore.maxNameChars,
      'trigger': RoutineStore.maxTriggerChars,
      'instructions': RoutineStore.maxInstructionsChars,
    };
    for (final entry in limits.entries) {
      expect(
        RoutineProposal.fromFields(valid()..[entry.key] = 'א' * entry.value)
            .routine
            .enabled,
        isFalse,
      );
      expect(
        () => RoutineProposal.fromFields(
          valid()..[entry.key] = 'א' * (entry.value + 1),
        ),
        throwsA(isA<RoutineProposalException>()),
      );
    }
  });
  test('source mutation does not alter accepted fields or enable a match', () {
    final fields = valid();
    final proposal = RoutineProposal.fromFields(fields);
    fields['instructions'] = 'changed';
    fields['enabled'] = true;
    expect(proposal.routine.instructions, 'הצעה בלבד');
    RoutineStore.instance.seed([proposal.routine]);
    addTearDown(() => RoutineStore.instance.seed([]));
    expect(RoutineStore.instance.match('hello שלום'), isNull);
  });
}
