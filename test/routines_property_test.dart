import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/routines.dart';

/// Seeded, repeatable property checks for the routine pack format (#608,
/// BLU-052 groundwork). There is no property-testing package: every case
/// comes from a fixed-seed [Random], so a failure reproduces exactly and
/// the printed seed/case index is the whole counterexample. All data is
/// fabricated. This covers the existing version-1 routine pack only; it is
/// not coverage of the unmerged BLU-014 Workflow DSL.
const _seeds = [1, 7, 42, 2026];
const _casesPerSeed = 40;
const _marker = 'FABRICATED-MARKER-9f3';

void main() {
  late Directory tmp;
  late RoutineStore store;
  var writes = 0;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('routines_prop');
    writes = 0;
    store = _newStore(tmp, () => writes++);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  group('valid packs', () {
    test(
      'import exactly what they say, in both shapes, and round-trip',
      () async {
        for (final seed in _seeds) {
          final rnd = Random(seed);
          for (var i = 0; i < _casesPerSeed; i++) {
            final label = 'seed=$seed case=$i';
            final entries = _validEntries(rnd);
            final wrapped = rnd.nextBool();
            final payload = jsonEncode(
              wrapped ? {'version': 1, 'routines': entries} : entries,
            );
            final s = _newStore(tmp, () {})..seed([]);
            final n = await s.importFrom(payload);
            expect(n, entries.length, reason: label);
            expect(s.routines.length, entries.length, reason: label);
            for (var k = 0; k < entries.length; k++) {
              final e = entries[k];
              final r = s.routines[k];
              expect(r.name, e['name'], reason: label);
              expect(
                r.trigger,
                (e['trigger'] as String).toLowerCase(),
                reason: label,
              );
              expect(r.instructions, e['instructions'], reason: label);
              expect(r.enabled, (e['enabled'] as bool?) ?? true, reason: label);
            }
            // Export then import into an empty store gives the same routines.
            final again = _newStore(tmp, () {})..seed([]);
            await again.importFrom(s.export());
            expect(
              again.routines.map((r) => r.toJson()).toList(),
              s.routines.map((r) => r.toJson()).toList(),
              reason: label,
            );
          }
        }
      },
    );

    test('the same seed always produces the same packs and results', () async {
      Future<List<String>> run() async {
        final out = <String>[];
        final rnd = Random(42);
        for (var i = 0; i < _casesPerSeed; i++) {
          final payload = jsonEncode(_validEntries(rnd));
          final s = _newStore(tmp, () {})..seed([]);
          await s.importFrom(payload);
          out.add(payload + s.export());
        }
        return out;
      }

      expect(await run(), await run());
    });
  });

  group('invalid packs never import', () {
    test(
      'every single-fault mutation is rejected with nothing changed',
      () async {
        for (final seed in _seeds) {
          final rnd = Random(seed);
          for (var i = 0; i < _casesPerSeed; i++) {
            final label = 'seed=$seed case=$i';
            final entries = _validEntries(rnd, min: 1);
            final payload = _mutate(entries, rnd);
            store.seed([
              const Routine(name: 'keep', trigger: 'keep', instructions: 'x'),
            ]);
            final before = store.export();
            writes = 0;
            Object? error;
            try {
              await store.importFrom(payload);
            } catch (e) {
              error = e;
            }
            expect(error, isA<RoutineImportException>(), reason: label);
            expect(store.export(), before, reason: label);
            expect(writes, 0, reason: label);
            expect(
              (error as RoutineImportException).message.contains(_marker),
              isFalse,
              reason: '$label message must not echo pack content',
            );
          }
        }
      },
    );

    test(
      'truncated and random text only ever fails as an import error',
      () async {
        for (final seed in _seeds) {
          final rnd = Random(seed);
          for (var i = 0; i < _casesPerSeed; i++) {
            final label = 'seed=$seed case=$i';
            final good = jsonEncode(_validEntries(rnd, min: 1));
            final cut = rnd.nextInt(
              good.length,
            ); // strictly shorter: never valid
            final junk = String.fromCharCodes(
              List.generate(rnd.nextInt(60), (_) => rnd.nextInt(0xD7FF) + 1),
            );
            for (final payload in [good.substring(0, cut), junk]) {
              store.seed([]);
              writes = 0;
              try {
                await store.importFrom(payload);
                // Only a payload that is itself a valid pack may succeed.
                expect(_isValidPack(payload), isTrue, reason: label);
              } on RoutineImportException {
                expect(writes, 0, reason: label);
                expect(store.routines, isEmpty, reason: label);
              }
            }
          }
        }
      },
    );

    test('a pack colliding with an existing name changes nothing', () async {
      for (final seed in _seeds) {
        final rnd = Random(seed);
        for (var i = 0; i < 10; i++) {
          final entries = _validEntries(rnd, min: 2);
          final clash = entries[rnd.nextInt(entries.length)]['name'] as String;
          store.seed([
            Routine(name: clash, trigger: 'old', instructions: 'old'),
          ]);
          writes = 0;
          await expectLater(
            store.importFrom(jsonEncode(entries)),
            throwsA(isA<RoutineImportException>()),
            reason: 'seed=$seed case=$i',
          );
          expect(store.routines.length, 1);
          expect(store.routines.single.instructions, 'old');
          expect(writes, 0);
        }
      }
    });
  });
}

RoutineStore _newStore(Directory tmp, void Function() onWrite) {
  final file = File('${tmp.path}/routines.json');
  return RoutineStore.forTest(
    file: () async => file,
    stage: (f, contents) async {
      onWrite();
      await f.writeAsString(contents);
    },
    commit: (f, path) async => f.rename(path),
  );
}

String _word(Random rnd, int min, int max) {
  const chars =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -_é';
  final len = min + rnd.nextInt(max - min + 1);
  final s = String.fromCharCodes(
    List.generate(
      len,
      (_) => chars.runes.elementAt(rnd.nextInt(chars.runes.length)),
    ),
  );
  return s.trim().isEmpty ? 'x' : s;
}

List<Map<String, Object?>> _validEntries(Random rnd, {int min = 0}) {
  final n = min + rnd.nextInt(6);
  final names = <String>{};
  while (names.length < n) {
    names.add(
      '${_word(rnd, 1, RoutineStore.maxNameChars - 4)}-${names.length}',
    );
  }
  return [
    for (final name in names)
      {
        'name': name,
        // Sometimes exactly at the limit, which must still be accepted.
        'trigger': rnd.nextInt(5) == 0
            ? 'T' * RoutineStore.maxTriggerChars
            : _word(rnd, 1, RoutineStore.maxTriggerChars),
        'instructions': _word(rnd, 1, 200),
        // Absent, null and explicit values are all valid.
        ...switch (rnd.nextInt(3)) {
          0 => <String, Object?>{},
          1 => {'enabled': null},
          _ => {'enabled': rnd.nextBool()},
        },
      },
  ];
}

/// Applies exactly one fault to a valid entry list and returns the JSON.
String _mutate(List<Map<String, Object?>> entries, Random rnd) {
  final copy = [for (final e in entries) Map<String, Object?>.of(e)];
  final i = rnd.nextInt(copy.length);
  const fields = ['name', 'trigger', 'instructions'];
  final f = fields[rnd.nextInt(fields.length)];
  final max = {
    'name': RoutineStore.maxNameChars,
    'trigger': RoutineStore.maxTriggerChars,
    'instructions': RoutineStore.maxInstructionsChars,
  }[f]!;
  switch (rnd.nextInt(9)) {
    case 0:
      copy[i].remove(f);
    case 1:
      copy[i][f] = rnd.nextBool() ? 5 : null;
    case 2:
      copy[i][f] = '   ';
    case 3:
      copy[i][f] = (_marker + 'a' * max).substring(0, max + 1);
    case 4:
      copy[i]['enabled'] = rnd.nextBool() ? 'yes' : 1;
    case 5:
      copy.add(Map<String, Object?>.of(copy[i])); // duplicate name
    case 6:
      copy[i] = {'name': _marker}; // missing fields
    case 7:
      return jsonEncode({'version': 2 + rnd.nextInt(5), 'routines': copy});
    default:
      return jsonEncode({'routines': copy, 'note': _marker}); // no version
  }
  return jsonEncode(rnd.nextBool() ? copy : {'version': 1, 'routines': copy});
}

bool _isValidPack(String payload) {
  try {
    final d = jsonDecode(payload);
    return d is List ||
        (d is Map && d['version'] == 1 && d['routines'] is List);
  } catch (_) {
    return false;
  }
}
