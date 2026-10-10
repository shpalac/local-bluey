import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/audio_capture.dart';
import 'package:local_bluey/services/request_interfaces.dart';
import 'package:local_bluey/services/stt.dart';
import 'package:local_bluey/services/wake_word.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSpotter extends WakeWordSpotter {
  double value = 0.9;
  int calls = 0;
  bool fail = false;
  bool deletes = false;
  @override
  Future<double> score(File audioWindow) async {
    calls++;
    if (fail) throw StateError('engine crashed');
    if (deletes && audioWindow.existsSync()) audioWindow.deleteSync();
    return value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('dormant without a spotter engine', () async {
    final service = WakeWordService(spotter: null);
    final file = await File('${Directory.systemTemp.path}/ww_test.m4a')
        .create();
    expect(await service.scoreAndMaybeWake(file), isFalse);
  });

  test('below threshold never confirms', () async {
    final spotter = _FakeSpotter()..value = 0.2;
    final service = WakeWordService(spotter: spotter);
    final file = await File('${Directory.systemTemp.path}/ww_test2.m4a')
        .create();
    expect(await service.scoreAndMaybeWake(file), isFalse);
    expect(spotter.calls, 1);
  });

  test('remote endpoint: spotter alone wakes, no upload', () async {
    SharedPreferences.setMockInitialValues({
      'stt.baseUrl': 'https://api.example.com/v1',
    });
    final spotter = _FakeSpotter();
    final service = WakeWordService(spotter: spotter);
    var woke = false;
    service.onWake = () => woke = true;
    final file = await File('${Directory.systemTemp.path}/ww_test3.m4a')
        .create();
    expect(await service.scoreAndMaybeWake(file), isTrue);
    expect(woke, isTrue);
  });

  test('default is off and persisted', () async {
    expect(await WakeWordService.isEnabled(), isFalse);
    await WakeWordService.setEnabled(true);
    expect(await WakeWordService.isEnabled(), isTrue);
  });

  group('lifecycle (#280)', () {
    late Directory tmp;
    late _FakeRecorder rec;
    late List<Completer<void>> windows;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('ww_life');
      rec = _FakeRecorder();
      windows = [];
      SharedPreferences.setMockInitialValues({'wake_word.enabled': true});
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    WakeWordService make(WakeWordSpotter? spotter) => WakeWordService(
      spotter: spotter,
      capture: AudioCapture(driver: rec, tempDirProvider: () async => tmp),
      windowDelay: (_) {
        final c = Completer<void>();
        windows.add(c);
        return c.future;
      },
    );

    /// Polls an observable state (entered stage) instead of pumping time.
    Future<void> until(
      bool Function() cond, [
      String what = 'condition',
    ]) async {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (!cond()) {
        if (DateTime.now().isAfter(deadline)) {
          throw StateError('never reached: $what');
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    /// Waits until window [i] has been requested, then returns it.
    Future<Completer<void>> window(int i) async {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (windows.length <= i) {
        if (DateTime.now().isAfter(deadline)) {
          throw StateError('window $i was never requested');
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      return windows[i];
    }

    int leftover() => tmp
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('bluey_hold_'))
        .length;

    test('enabled without an engine never starts the recorder', () async {
      final service = make(null);
      await service.start();
      expect(rec.starts, 0);
      expect(service.listening.value, isFalse);
    });

    test('disabled by default does not record', () async {
      SharedPreferences.setMockInitialValues({});
      final service = make(_FakeSpotter());
      await service.start();
      expect(rec.starts, 0);
      expect(service.listening.value, isFalse);
    });

    test('permission denied reports an error and stays stopped', () async {
      rec.permission = false;
      final service = make(_FakeSpotter());
      await service.start();
      expect(rec.starts, 0);
      expect(service.listening.value, isFalse);
      expect(service.lastError.value, contains('permission'));
    });

    test('a scored window wakes once and its file is deleted', () async {
      final service = make(_FakeSpotter());
      var wakes = 0;
      service.onWake = () => wakes++;
      await service.start();
      await until(() => rec.open == 1, 'recording open');
      (await window(0)).complete();
      await until(
        () => wakes == 1 && windows.length == 2 && rec.open == 1,
        'wake and next window',
      );
      expect(wakes, 1);
      expect(leftover(), 1); // only the next window's open recording
      await service.stop();
      expect(rec.open, 0);
      expect(leftover(), 0);
    });

    test('stop during the window closes capture, no wake', () async {
      final service = make(_FakeSpotter());
      var wakes = 0;
      service.onWake = () => wakes++;
      await service.start();
      await until(() => rec.open == 1, 'recording open');
      expect(rec.open, 1);
      await service.stop();
      expect(rec.open, 0);
      expect(wakes, 0);
      expect(service.listening.value, isFalse);
      expect(leftover(), 0);
    });

    test('stop during scoring suppresses the late wake', () async {
      final gate = Completer<double>();
      final spotter = _GatedSpotter(gate);
      final service = make(spotter);
      var wakes = 0;
      service.onWake = () => wakes++;
      await service.start();
      await until(() => rec.open == 1, 'recording open');
      (await window(0)).complete();
      await until(() => spotter.calls == 1, 'scoring entered');
      final stopping = service.stop();
      gate.complete(0.95);
      await stopping;
      expect(wakes, 0);
      expect(rec.open, 0);
      expect(service.listening.value, isFalse);
      expect(leftover(), 0);
    });

    test(
      'stop then immediate restart runs one loop, old work is stale',
      () async {
        final gate = Completer<double>();
        final spotter = _GatedSpotter(gate);
        final service = make(spotter);
        var wakes = 0;
        service.onWake = () => wakes++;
        await service.start();
        await until(() => rec.open == 1, 'recording open');
        (await window(0)).complete();
        await until(() => spotter.calls == 1, 'scoring entered');
        final stopping = service.stop();
        final restarting = service.start();
        gate.complete(0.95);
        await stopping;
        await restarting;
        await until(() => windows.length == 2, 'new loop window');
        expect(wakes, 0);
        expect(service.listening.value, isTrue);
        expect(rec.maxOpen, 1);
        await window(1);
        expect(windows.length, 2);
        await service.stop();
        expect(rec.open, 0);
        expect(leftover(), 0);
      },
    );

    test('score exception stops safely and a retry works', () async {
      final spotter = _FakeSpotter()..fail = true;
      final service = make(spotter);
      await service.start();
      await until(() => rec.open == 1, 'recording open');
      (await window(0)).complete();
      await until(
        () => !service.listening.value && service.lastError.value != null,
        'score failure',
      );
      expect(service.listening.value, isFalse);
      expect(service.lastError.value, contains('Wake word stopped'));
      expect(rec.open, 0);
      expect(leftover(), 0);
      spotter.fail = false;
      await service.start();
      await until(() => rec.open == 1, 'recording open');
      expect(service.listening.value, isTrue);
      expect(service.lastError.value, isNull);
      await service.stop();
    });

    test('recorder start failure is reported, not thrown', () async {
      rec.failStart = true;
      final service = make(_FakeSpotter());
      await service.start();
      await until(
        () => service.lastError.value != null,
        'start failure reported',
      );
      expect(service.listening.value, isFalse);
      expect(service.lastError.value, isNotNull);
      expect(rec.open, 0);
    });

    test('stop during capture.start ends without waiting a window', () async {
      rec.startGate = Completer<void>();
      final service = make(_FakeSpotter());
      var wakes = 0;
      service.onWake = () => wakes++;
      await service.start();
      await until(() => rec.startCalls == 1, 'capture.start entered');
      final stopping = service.stop();
      rec.startGate!.complete();
      await stopping.timeout(const Duration(seconds: 2));
      expect(windows, isEmpty);
      expect(wakes, 0);
      expect(rec.open, 0);
      expect(service.listening.value, isFalse);
      expect(leftover(), 0);
    });

    test('a window delay that throws still cleans up the recording', () async {
      final service = WakeWordService(
        spotter: _FakeSpotter(),
        capture: AudioCapture(driver: rec, tempDirProvider: () async => tmp),
        windowDelay: (_) => Future<void>.error(StateError('timer failed')),
      );
      await service.start();
      await until(
        () => service.lastError.value != null,
        'window error reported',
      );
      expect(service.listening.value, isFalse);
      expect(service.lastError.value, contains('Wake word stopped'));
      expect(rec.open, 0);
      expect(leftover(), 0);
    });

    test('permission check finishing after stop writes no error', () async {
      rec.permissionGate = Completer<bool>();
      rec.permissionError = StateError('late denial');
      final service = make(_FakeSpotter());
      final starting = service.start();
      await until(() => rec.permissionCalls >= 1, 'permission check entered');
      await service.stop();
      rec.permissionGate!.complete(true);
      await starting;
      expect(service.lastError.value, isNull);
      expect(service.listening.value, isFalse);
      expect(rec.starts, 0);
    });

    test(
      'permission denial from an old start never hits a newer one',
      () async {
        rec.permissionGate = Completer<bool>();
        rec.permission = false;
        final service = make(_FakeSpotter());
        final first = service.start();
        await until(() => rec.permissionCalls >= 1, 'permission check entered');
        await service.stop();
        final second = service.start();
        rec.permissionGate!.complete(false);
        await first;
        await second;
        // Both calls were denied; only the newest generation may report.
        expect(service.lastError.value, contains('permission'));
        final firstOnly = make(_FakeSpotter());
        rec.permissionGate = Completer<bool>();
        final a = firstOnly.start();
        await until(() => rec.permissionCalls >= 3, 'permission check entered');
        await firstOnly.stop();
        rec.permissionGate!.complete(false);
        await a;
        expect(firstOnly.lastError.value, isNull);
      },
    );

    test('stop during local confirmation suppresses the wake', () async {
      final gate = Completer<String>();
      final transcriber = _FakeTranscriber(gate: gate);
      final service = WakeWordService(
        spotter: _FakeSpotter(),
        transcription: transcriber,
        capture: AudioCapture(driver: rec, tempDirProvider: () async => tmp),
        windowDelay: (_) {
          final c = Completer<void>();
          windows.add(c);
          return c.future;
        },
      );
      var wakes = 0;
      service.onWake = () => wakes++;
      await service.start();
      await until(() => rec.open == 1, 'recording open');
      (await window(0)).complete();
      await until(() => transcriber.calls == 1, 'transcription entered');
      final stopping = service.stop();
      gate.complete('hey bluey');
      await stopping;
      expect(wakes, 0);
      expect(rec.open, 0);
      expect(leftover(), 0);
    });

    test('transcriber exception stops safely and deletes the file', () async {
      final service = WakeWordService(
        spotter: _FakeSpotter(),
        transcription: _FakeTranscriber(fail: true),
        capture: AudioCapture(driver: rec, tempDirProvider: () async => tmp),
        windowDelay: (_) {
          final c = Completer<void>();
          windows.add(c);
          return c.future;
        },
      );
      var wakes = 0;
      service.onWake = () => wakes++;
      await service.start();
      await until(() => rec.open == 1, 'recording open');
      (await window(0)).complete();
      await until(
        () => !service.listening.value && service.lastError.value != null,
        'transcriber failure',
      );
      expect(wakes, 0);
      expect(service.listening.value, isFalse);
      expect(service.lastError.value, contains('Wake word stopped'));
      expect(rec.open, 0);
      expect(leftover(), 0);
    });

    test('cleanup tolerates a window the spotter already removed', () async {
      final spotter = _FakeSpotter()..deletes = true;
      final service = make(spotter);
      await service.start();
      await until(() => rec.open == 1, 'recording open');
      (await window(0)).complete();
      await until(
        () => spotter.calls == 1 && windows.length == 2,
        'window scored',
      );
      expect(service.listening.value, isTrue);
      expect(service.lastError.value, isNull);
      await service.stop();
      expect(leftover(), 0);
    });

    test('stop-error returned file is still deleted', () async {
      rec.failStop = true;
      final service = make(_FakeSpotter());
      await service.start();
      await until(() => rec.open == 1, 'recording open');
      (await window(0)).complete();
      await until(
        () => !service.listening.value && service.lastError.value != null,
        'stop failure reported',
      );
      expect(service.lastError.value, contains('Wake word stopped'));
      expect(leftover(), 0);
    });

    test('stop while settings load never reaches the transcriber', () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final transcriber = _FakeTranscriber();
      final service = WakeWordService(
        spotter: _FakeSpotter(),
        transcription: transcriber,
        capture: AudioCapture(driver: rec, tempDirProvider: () async => tmp),
        windowDelay: (_) {
          final c = Completer<void>();
          windows.add(c);
          return c.future;
        },
      );
      service.debugAfterSettingsLoad = () async {
        entered.complete();
        await release.future;
      };
      var wakes = 0;
      service.onWake = () => wakes++;
      await service.start();
      await until(() => rec.open == 1, 'recording open');
      (await window(0)).complete();
      await entered.future;
      final stopping = service.stop();
      release.complete();
      await stopping;
      expect(transcriber.calls, 0);
      expect(wakes, 0);
      expect(leftover(), 0);
    });
  });
}

class _FakeRecorder implements RecorderDriver {
  bool permission = true;
  bool failStart = false;
  Completer<void>? startGate;
  Completer<bool>? permissionGate;
  Object? permissionError;
  int starts = 0;
  int startCalls = 0;
  int permissionCalls = 0;
  bool failStop = false;
  int open = 0;
  int maxOpen = 0;
  String? _path;

  @override
  Future<bool> hasPermission() async {
    permissionCalls++;
    final gate = permissionGate;
    if (gate != null) await gate.future;
    if (permissionError != null) throw permissionError!;
    return permission;
  }

  @override
  Future<void> start(String path) async {
    startCalls++;
    final gate = startGate;
    if (gate != null) await gate.future;
    if (failStart) throw StateError('recorder busy');
    starts++;
    open++;
    if (open > maxOpen) maxOpen = open;
    _path = path;
    File(path).writeAsBytesSync([1, 2, 3]);
  }

  @override
  Future<String?> stop() async {
    if (_path == null) return null;
    open--;
    final path = _path;
    _path = null;
    if (failStop) throw StateError('stop failed');
    return path;
  }

  @override
  Future<void> dispose() async {}
}

class _FakeTranscriber implements TranscriberLike {
  _FakeTranscriber({this.gate, this.fail = false});
  final Completer<String>? gate;
  final bool fail;
  int calls = 0;
  @override
  Future<String> transcribe(File audio, SttSettings settings) async {
    calls++;
    if (fail) throw StateError('transcriber crashed');
    return gate != null ? gate!.future : 'hey bluey';
  }
}

class _GatedSpotter extends WakeWordSpotter {
  _GatedSpotter(this.gate);
  final Completer<double> gate;
  int calls = 0;
  @override
  Future<double> score(File audioWindow) {
    calls++;
    return gate.future;
  }
}
