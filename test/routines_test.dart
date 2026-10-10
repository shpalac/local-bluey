import 'dart:convert';
import 'dart:io';

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
    final tmpDir = Directory.systemTemp.createTempSync('routines_rt');
    addTearDown(() => tmpDir.deleteSync(recursive: true));
    final store = RoutineStore.forTest(
      file: () async => File('${tmpDir.path}/routines.json'),
    );
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

  test('an empty pack imports nothing', () async {
    expect(await store.importFrom('[]'), 0);
  });

  group('import (#287)', () {
    late Directory tmp;
    late File file;
    late RoutineStore s;
    var writes = 0;
    var failStage = false;
    var failCommit = false;

    String pack(List<Map<String, Object?>> items) => jsonEncode(items);
    Map<String, Object?> item(String name, {Object? enabled}) => {
      'name': name,
      'trigger': name,
      'instructions': 'Do $name.',
      'enabled': ?enabled,
    };

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('routines_imp');
      file = File('${tmp.path}/routines.json');
      writes = 0;
      failStage = false;
      failCommit = false;
      s = RoutineStore.forTest(
        file: () async => file,
        stage: (f, contents) async {
          writes++;
          if (failStage) {
            // Partial bytes hit the staging file, then the write fails.
            await f.writeAsString(contents.substring(0, 5));
            throw FileSystemException('disk full', f.path);
          }
          await f.writeAsString(contents);
        },
        commit: (f, path) async {
          if (failCommit) throw FileSystemException('rename failed', path);
          await f.rename(path);
        },
      );
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    Future<void> expectRejected(String payload) async {
      s.routines.removeWhere((r) => true);
      s.routines.clear();
      s.routines.add(
        const Routine(name: 'keep', trigger: 'keep', instructions: 'x'),
      );
      final before = file.existsSync() ? file.readAsStringSync() : null;
      await expectLater(
        s.importFrom(payload),
        throwsA(isA<RoutineImportException>()),
      );
      expect(s.routines.map((r) => r.name), ['keep']);
      expect(file.existsSync() ? file.readAsStringSync() : null, before);
      expect(writes, 0);
    }

    test('valid pack: accurate count, one write, wrapped format too', () async {
      expect(await s.importFrom(pack([item('a'), item('b')])), 2);
      expect(writes, 1);
      expect(jsonDecode(file.readAsStringSync()), hasLength(2));
      final wrapped = jsonEncode({
        'version': 1,
        'routines': [item('c')],
      });
      expect(await s.importFrom(wrapped), 1);
      expect(writes, 2);
      expect(s.routines.map((r) => r.name), ['a', 'b', 'c']);
    });

    test('malformed JSON and top-level shapes are rejected', () async {
      await expectRejected('{not json');
      await expectRejected('"text"');
      await expectRejected('{"routines": []}'); // no version
      await expectRejected('{"version": 2, "routines": []}');
      await expectRejected('{"version": 1, "routines": {}}');
    });

    test('a late bad item rejects the whole pack', () async {
      await expectRejected(
        pack([
          item('ok'),
          item('ok2'),
          {'name': 'bad'},
        ]),
      );
      await expectRejected(jsonEncode([item('ok'), 5]));
    });

    test('invalid field types and empty values are rejected', () async {
      await expectRejected(pack([item('a', enabled: 'yes')]));
      await expectRejected(
        jsonEncode([
          {'name': 1, 'trigger': 't', 'instructions': 'i'},
        ]),
      );
      await expectRejected(pack([item('')]));
      await expectRejected(
        jsonEncode([
          {'name': 'n', 'trigger': 't', 'instructions': '  '},
        ]),
      );
    });

    test(
      'duplicates in the pack and collisions with existing are rejected',
      () async {
        await expectRejected(pack([item('d'), item('d')]));
        await expectRejected(pack([item('keep')]));
      },
    );

    test('oversized pack and too many routines are rejected', () async {
      await expectRejected('[${'1,' * 200000}1]');
      await expectRejected(pack([for (var i = 0; i < 101; i++) item('r$i')]));
      await expectRejected(
        jsonEncode([
          {'name': 'n' * 81, 'trigger': 't', 'instructions': 'i'},
        ]),
      );
    });

    for (final mode in ['stage', 'commit']) {
      test(
        '$mode failure keeps original bytes, memory, no staging; retry works',
        () async {
          await s.importFrom(pack([item('first')]));
          final before = file.readAsStringSync();
          failStage = mode == 'stage';
          failCommit = mode == 'commit';
          await expectLater(
            s.importFrom(pack([item('second')])),
            throwsA(isA<RoutineImportException>()),
          );
          expect(s.routines.map((r) => r.name), ['first']);
          expect(file.readAsStringSync(), before);
          expect(File('${file.path}.tmp').existsSync(), isFalse);
          failStage = false;
          failCommit = false;
          expect(await s.importFrom(pack([item('second')])), 1);
          expect(s.routines.map((r) => r.name), ['first', 'second']);
          expect(jsonDecode(file.readAsStringSync()), hasLength(2));
          expect(File('${file.path}.tmp').existsSync(), isFalse);
        },
      );
    }

    test('field limits are exact and enabled null means true', () async {
      Map<String, Object?> lim(int t, int i) => {
        'name': 'lim',
        'trigger': 't' * t,
        'instructions': 'i' * i,
      };
      await expectRejected(jsonEncode([lim(121, 5)]));
      await expectRejected(jsonEncode([lim(5, 4001)]));
      s.routines.clear();
      expect(await s.importFrom(jsonEncode([lim(120, 4000)])), 1);
      final n = {...item('nullable'), 'enabled': null};
      expect(await s.importFrom(jsonEncode([n])), 1);
      expect(s.routines.last.enabled, isTrue);
    });

    test('add, remove and export keep their behavior', () async {
      await s.add(const Routine(name: 'x', trigger: 'X', instructions: 'i'));
      await s.add(const Routine(name: 'x', trigger: 'y', instructions: 'j'));
      expect(s.routines, hasLength(1));
      expect(jsonDecode(s.export()), hasLength(1));
      await s.remove('x');
      expect(s.routines, isEmpty);
    });
  });
}
