import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/routines.dart';

void main() {
  final store = RoutineStore.instance;

  setUp(() => store.routines.clear());

  test('trigger matches case-insensitively inside the utterance', () {
    store.routines.add(
      const Routine(
        name: 'work mode',
        trigger: 'work mode',
        instructions: 'Silence notifications, open the editor.',
      ),
    );
    final hit = store.match('hey, switch to Work Mode please');
    expect(hit?.name, 'work mode');
    expect(store.match('what is the weather'), isNull);
  });

  test('disabled routines never fire', () {
    store.routines.add(
      const Routine(
        name: 'sleep',
        trigger: 'sleep',
        instructions: 'Go dark.',
        enabled: false,
      ),
    );
    expect(store.match('go to sleep'), isNull);
  });

  test('export/import round-trips as a shareable skill pack', () async {
    store.routines.add(
      const Routine(
        name: 'standup',
        trigger: 'standup',
        instructions: 'Open the board and read blockers.',
      ),
    );
    final pack = store.export();
    store.routines.clear();
    expect(await store.importFrom(pack), 1);
    expect(store.match('start my standup')?.name, 'standup');
  });

  test('import skips malformed entries', () async {
    expect(await store.importFrom('[{"name": ""}]'), 0);
  });
}
