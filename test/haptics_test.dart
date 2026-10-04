import 'package:local_bluey/services/haptics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _CountingHaptics implements Haptics {
  int nLight = 0, nMedium = 0, nError = 0;
  @override
  Future<void> light() async => nLight++;
  @override
  Future<void> medium() async => nMedium++;
  @override
  Future<void> error() async => nError++;
  int get total => nLight + nMedium + nError;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('#88: exactly one haptic per event', () async {
    final fake = _CountingHaptics();
    RemoteHaptics.instance.debugImpl = fake;
    await RemoteHaptics.instance.setEnabled(true);
    for (final event in RemoteHapticEvent.values) {
      await RemoteHaptics.instance.fire(event);
    }
    expect(fake.total, RemoteHapticEvent.values.length);
    expect(fake.nLight, 3); // ack, answer, connect
    expect(fake.nMedium, 2); // holdStart, disconnect
    expect(fake.nError, 1);
  });

  test('#88: toggle off silences every haptic', () async {
    final fake = _CountingHaptics();
    RemoteHaptics.instance.debugImpl = fake;
    await RemoteHaptics.instance.setEnabled(false);
    for (final event in RemoteHapticEvent.values) {
      await RemoteHaptics.instance.fire(event);
    }
    expect(fake.total, 0);
    await RemoteHaptics.instance.setEnabled(true);
  });

  test('#88: enabled state persists', () async {
    SharedPreferences.setMockInitialValues({'haptics.enabled': false});
    await RemoteHaptics.instance.load();
    expect(RemoteHaptics.instance.enabled, isFalse);
    await RemoteHaptics.instance.setEnabled(true);
  });
}
