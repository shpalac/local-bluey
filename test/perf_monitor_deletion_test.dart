import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/perf_monitor.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late File store;
  late PerfMonitor monitor;
  Completer<void>? writeGate;
  var writesEntered = 0;
  var deletesEntered = 0;
  var lookupFails = false;
  var tick = DateTime(2026, 1, 1);
  var failDelete = false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('perf_del');
    store = File('${tmp.path}/perf.jsonl');
    writeGate = null;
    writesEntered = 0;
    deletesEntered = 0;
    lookupFails = false;
    tick = DateTime(2026, 1, 1);
    failDelete = false;
    monitor = PerfMonitor.forTest(
      clock: () => tick,
      file: () async {
        if (lookupFails) throw StateError('no documents dir');
        return store;
      },
      appendLine: (f, line) async {
        writesEntered++;
        final gate = writeGate;
        if (gate != null) await gate.future;
        await f.writeAsString(line, mode: FileMode.append);
      },
      deleteFile: (f) async {
        deletesEntered++;
        if (failDelete) throw FileSystemException('disk busy', f.path);
        await f.delete();
      },
    );
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> until(bool Function() cond) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!cond()) {
      if (DateTime.now().isAfter(deadline)) throw StateError('never reached');
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
  }

  int lines() => store.existsSync() ? store.readAsLinesSync().length : 0;

  test('measure records and persists; semantics preserved', () async {
    expect(await monitor.measure('a', () async => 7), 7);
    await monitor.flush();
    expect(monitor.medians().keys, ['a']);
    expect(lines(), 1);
    await expectLater(
      monitor.measure('b', () async => throw StateError('x')),
      throwsStateError,
    );
    await monitor.flush();
    expect(monitor.medians().keys, containsAll(['a', 'b']));
    expect(lines(), 2);
  });

  test('clear during measured work: old sample never returns', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final running = monitor.measure('old', () async {
      entered.complete();
      await release.future;
    });
    await entered.future;
    await monitor.clear();
    release.complete();
    await running;
    await monitor.flush();
    expect(monitor.medians(), isEmpty);
    expect(store.existsSync(), isFalse);
    expect(monitor.overlayEnabled.value, isFalse);
  });

  test('clear during a queued append wins', () async {
    writeGate = Completer<void>();
    await monitor.measure('q', () async {});
    await until(() => writesEntered == 1); // writeAsString entered, blocked
    final clearing = monitor.clear();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(deletesEntered, 0); // deletion waits behind the entered write
    writeGate!.complete();
    await clearing;
    await monitor.flush();
    expect(deletesEntered, 1);
    expect(store.existsSync(), isFalse);
    expect(monitor.medians(), isEmpty);
  });

  test(
    'multiple writes then clear leaves nothing; repeated clear ok',
    () async {
      for (var i = 0; i < 3; i++) {
        await monitor.measure('m', () async {});
      }
      await monitor.clear();
      expect(store.existsSync(), isFalse);
      await monitor.clear();
      await monitor.flush();
      expect(store.existsSync(), isFalse);
      expect(monitor.lastStorageError.value, isNull);
    },
  );

  test('fresh measurement after clear is accepted', () async {
    await monitor.measure('old', () async {});
    await monitor.clear();
    await monitor.measure('new', () async {});
    await monitor.flush();
    expect(monitor.medians().keys, ['new']);
    expect(lines(), 1);
    expect(store.readAsStringSync(), contains('"new"'));
  });

  test('append failure is reported, not thrown', () async {
    final bad = PerfMonitor.forTest(
      file: () async => File('${tmp.path}/missing/dir/perf.jsonl'),
    );
    await bad.measure('x', () async {});
    await bad.flush();
    expect(bad.lastStorageError.value, contains('write failed'));
    expect(bad.medians().keys, ['x']);
  });

  test(
    'failed delete reaches the caller, keeps bytes, retry succeeds',
    () async {
      await monitor.measure('a', () async {});
      await monitor.flush();
      expect(lines(), 1);
      failDelete = true;
      await expectLater(monitor.clear(), throwsA(isA<PerfStorageException>()));
      expect(store.readAsLinesSync(), hasLength(1)); // bytes retained
      expect(deletesEntered, 1); // File.delete itself was entered and failed
      expect(monitor.lastStorageError.value, contains('clear failed'));
      expect(monitor.medians(), isEmpty);
      expect(monitor.overlayEnabled.value, isFalse);
      failDelete = false;
      await monitor.clear(); // queue is still alive; retry works
      expect(store.existsSync(), isFalse);
      expect(monitor.lastStorageError.value, isNull);
      await monitor.measure('b', () async {});
      await monitor.flush();
      expect(lines(), 1);
    },
  );

  test('a measurement that starts after clear begins is kept', () async {
    await monitor.measure('old', () async {});
    final clearing = monitor.clear(); // generation already bumped
    final entered = Completer<void>();
    final release = Completer<void>();
    final fresh = monitor.measure('fresh', () async {
      entered.complete();
      await release.future;
    });
    await entered.future;
    release.complete();
    await fresh;
    await clearing;
    await monitor.flush();
    expect(monitor.medians().keys, ['fresh']);
    expect(store.readAsStringSync(), contains('"fresh"'));
    expect(store.readAsStringSync(), isNot(contains('"old"')));
  });

  test('storage lookup failure on clear is reported too', () async {
    lookupFails = true;
    await expectLater(monitor.clear(), throwsA(isA<PerfStorageException>()));
    expect(deletesEntered, 0);
    lookupFails = false;
    await monitor.clear();
  });

  test('medians come from the injected clock', () async {
    for (final ms in [10, 50, 30]) {
      await monitor.measure('s', () async {
        tick = tick.add(Duration(milliseconds: ms));
      });
    }
    expect(monitor.medians(), {'s': 30});
    await monitor.flush();
    expect(lines(), 3);
  });
}
