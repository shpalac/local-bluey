import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/native_control.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('local_bluey/control');
  late Map<String, Object?> payload;

  setUp(() {
    payload = {
      'jpeg': Uint8List.fromList([1, 2, 3]),
      'width': 100,
      'height': 100,
      'app': 'Safari',
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'snapshotRegion');
          return payload;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('snapshot verification defaults to unknown (#245)', () {
    final crop = ScreenSnapshot(
      jpeg: Uint8List.fromList([1, 2, 3]),
      targets: '',
      width: 100,
      height: 100,
    );
    expect(crop.cropTextVerified, isFalse);
  });

  test('missing crop evidence is unknown, not verified blank (#245)', () async {
    final crop = await NativeControl.snapshotRegion(0, 0, 100, 100);
    expect(crop.targets, isEmpty);
    expect(crop.cropTextVerified, isFalse);
  });

  test('explicit verification requires a text field (#245)', () async {
    payload['cropTextVerified'] = true;
    final crop = await NativeControl.snapshotRegion(0, 0, 100, 100);
    expect(crop.cropTextVerified, isFalse);
  });

  test('verified blank text is valid evidence (#245)', () async {
    payload['targets'] = '';
    payload['cropTextVerified'] = true;
    final crop = await NativeControl.snapshotRegion(0, 0, 100, 100);
    expect(crop.targets, isEmpty);
    expect(crop.cropTextVerified, isTrue);
  });

  test('verified nonempty text is preserved (#245)', () async {
    payload['targets'] = 'Hello world';
    payload['cropTextVerified'] = true;
    final crop = await NativeControl.snapshotRegion(0, 0, 100, 100);
    expect(crop.targets, 'Hello world');
    expect(crop.cropTextVerified, isTrue);
  });

  for (final status in [null, false, 'true', 1]) {
    test('unverified status $status fails closed (#245)', () async {
      payload['targets'] = 'Hello world';
      payload['cropTextVerified'] = status;
      final crop = await NativeControl.snapshotRegion(0, 0, 100, 100);
      expect(crop.cropTextVerified, isFalse);
    });
  }

  test('malformed crop text cannot be verified (#245)', () async {
    payload['targets'] = 123;
    payload['cropTextVerified'] = true;
    final crop = await NativeControl.snapshotRegion(0, 0, 100, 100);
    expect(crop.targets, isEmpty);
    expect(crop.cropTextVerified, isFalse);
  });
}
