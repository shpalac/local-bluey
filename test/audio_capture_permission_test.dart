import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/audio_capture.dart';
import 'package:record/record.dart';
// Actual default implementation is not exported by the public barrel.
// ignore: implementation_imports, depend_on_referenced_packages
import 'package:record_platform_interface/src/record_platform.dart';

/// Real AudioRecorder + locked RecordPlatformImpl to an injected channel.
/// No native prompt, grant, recorder readiness or settings effect is proved.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.llfbandit.record/messages');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late RecordPlatform previous;
  setUp(() {
    previous = RecordPlatform.instance;
    RecordPlatform.instance = RecordPlatformImpl();
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    RecordPlatform.instance = previous;
  });

  for (final direct in [true, false]) {
    for (final result in [true, false]) {
      test(
        'actual permission requesting default direct=$direct result=$result waits create and permission',
        () async {
          final calls = <MethodCall>[];
          final createEntered = Completer<void>(),
              releaseCreate = Completer<void>();
          final permissionEntered = Completer<void>(),
              releasePermission = Completer<void>();
          final disposeEntered = Completer<void>(),
              releaseDispose = Completer<void>();
          messenger.setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            switch (call.method) {
              case 'create':
                createEntered.complete();
                await releaseCreate.future;
                return null;
              case 'hasPermission':
                permissionEntered.complete();
                await releasePermission.future;
                return result;
              case 'dispose':
                disposeEntered.complete();
                await releaseDispose.future;
                return null;
              default:
                fail('Unexpected recorder effect: ${call.method}');
            }
          });
          final recorder = AudioRecorder();
          final driver = AudioRecorderDriver(recorder);
          final capture = AudioCapture(driver: driver);
          final permission = direct
              ? driver.hasPermission()
              : capture.hasPermission();
          var settled = false;
          permission.then((_) => settled = true);
          await createEntered.future;
          expect(calls.map((c) => c.method), ['create']);
          expect(settled, isFalse);
          releaseCreate.complete();
          await permissionEntered.future;
          expect(calls.map((c) => c.method), ['create', 'hasPermission']);
          expect(settled, isFalse);
          final id = calls.first.arguments['recorderId'];
          expect(id, isA<String>());
          expect(id, isNotEmpty);
          expect(calls[1].arguments, {'recorderId': id, 'request': true});
          expect(capture.isRecording, isFalse);
          expect(capture.cleanupPending, isFalse);
          releasePermission.complete();
          expect(await permission, result);
          expect(calls.map((c) => c.method), ['create', 'hasPermission']);
          final close = direct ? driver.dispose() : capture.dispose();
          var closed = false;
          close.then((_) => closed = true);
          await disposeEntered.future;
          expect(closed, isFalse);
          expect(calls.last.arguments, {'recorderId': id});
          releaseDispose.complete();
          await close;
          expect(calls.map((c) => c.method), [
            'create',
            'hasPermission',
            'dispose',
          ]);
          expect(closed, isTrue);
        },
      );
    }
    test(
      'actual permission error propagates direct=$direct without capture effects and cleanup is observed',
      () async {
        final calls = <MethodCall>[];
        final entered = Completer<void>(), release = Completer<void>();
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'hasPermission') {
            entered.complete();
            await release.future;
            throw PlatformException(code: 'injected-permission-failure');
          }
          expect(call.method, isIn(['create', 'dispose']));
          return null;
        });
        final recorder = AudioRecorder();
        final driver = AudioRecorderDriver(recorder);
        final capture = AudioCapture(driver: driver);
        final permission = direct
            ? driver.hasPermission()
            : capture.hasPermission();
        final observed = expectLater(
          permission,
          throwsA(isA<PlatformException>()),
        );
        await entered.future;
        expect(calls.map((c) => c.method), ['create', 'hasPermission']);
        final id = calls.first.arguments['recorderId'];
        expect(calls.last.arguments, {'recorderId': id, 'request': true});
        release.complete();
        await observed;
        expect(capture.isRecording, isFalse);
        expect(capture.cleanupPending, isFalse);
        expect(calls.map((c) => c.method), ['create', 'hasPermission']);
        await (direct ? driver.dispose() : capture.dispose());
        expect(calls.map((c) => c.method), [
          'create',
          'hasPermission',
          'dispose',
        ]);
        expect(calls.last.arguments, {'recorderId': id});
      },
    );
  }
}
