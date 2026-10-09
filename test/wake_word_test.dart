import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/audio_capture.dart';
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

    Future<void> pump() async {
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
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
      await pump();
      windows.first.complete();
      await pump();
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
      await pump();
      expect(rec.open, 1);
      await service.stop();
      expect(rec.open, 0);
      expect(wakes, 0);
      expect(service.listening.value, isFalse);
      expect(leftover(), 0);
    });

    test('stop during scoring suppresses the late wake', () async {
      final gate = Completer<double>();
      final service = make(_GatedSpotter(gate));
      var wakes = 0;
      service.onWake = () => wakes++;
      await service.start();
      await pump();
      windows.first.complete();
      await pump();
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
        await pump();
        windows.first.complete();
        await pump();
        final stopping = service.stop();
        final restarting = service.start();
        gate.complete(0.95);
        await stopping;
        await restarting;
        await pump();
        expect(wakes, 0);
        expect(service.listening.value, isTrue);
        expect(rec.maxOpen, 1);
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
      await pump();
      windows.first.complete();
      await pump();
      expect(service.listening.value, isFalse);
      expect(service.lastError.value, contains('Wake word stopped'));
      expect(rec.open, 0);
      expect(leftover(), 0);
      spotter.fail = false;
      await service.start();
      await pump();
      expect(service.listening.value, isTrue);
      expect(service.lastError.value, isNull);
      await service.stop();
    });

    test('recorder start failure is reported, not thrown', () async {
      rec.failStart = true;
      final service = make(_FakeSpotter());
      await service.start();
      await pump();
      expect(service.listening.value, isFalse);
      expect(service.lastError.value, isNotNull);
      expect(rec.open, 0);
    });

    test('cleanup tolerates a window the spotter already removed', () async {
      final service = make(_FakeSpotter()..deletes = true);
      await service.start();
      await pump();
      windows.first.complete();
      await pump();
      expect(service.listening.value, isTrue);
      expect(service.lastError.value, isNull);
      await service.stop();
      expect(leftover(), 0);
    });
  });
}

class _FakeRecorder implements RecorderDriver {
  bool permission = true;
  bool failStart = false;
  int starts = 0;
  int open = 0;
  int maxOpen = 0;
  String? _path;

  @override
  Future<bool> hasPermission() async => permission;
  @override
  Future<void> start(String path) async {
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
    return path;
  }

  @override
  Future<void> dispose() async {}
}

class _GatedSpotter extends WakeWordSpotter {
  _GatedSpotter(this.gate);
  final Completer<double> gate;
  @override
  Future<double> score(File audioWindow) => gate.future;
}
