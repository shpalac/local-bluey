import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/observation_policy.dart';

void main() {
  const safe = ObservationContext(
    userConsented: true,
    osPermissionGranted: true,
    window: WindowSensitivity.safe,
    sessionActive: true,
    cancelled: false,
  );

  test('explicit safe active session may proceed', () {
    expect(ObservationPolicy.evaluate(safe), ObservationDecision.allow);
  });

  test('default-off, restart, revoked consent and cancellation deny', () {
    for (final context in [
      const ObservationContext(userConsented: false, osPermissionGranted: true, window: WindowSensitivity.safe, sessionActive: true, cancelled: false),
      const ObservationContext(userConsented: true, osPermissionGranted: true, window: WindowSensitivity.safe, sessionActive: false, cancelled: false),
      const ObservationContext(userConsented: true, osPermissionGranted: true, window: WindowSensitivity.safe, sessionActive: true, cancelled: true),
    ]) {
      expect(ObservationPolicy.evaluate(context), ObservationDecision.denyConsent);
    }
  });

  test('missing permission denies', () {
    expect(ObservationPolicy.evaluate(const ObservationContext(userConsented: true, osPermissionGranted: false, window: WindowSensitivity.safe, sessionActive: true, cancelled: false)), ObservationDecision.denyPermission);
  });

  test('private and sensitive windows deny even with consent', () {
    for (final window in [WindowSensitivity.private, WindowSensitivity.sensitive]) {
      expect(ObservationPolicy.evaluate(ObservationContext(userConsented: true, osPermissionGranted: true, window: window, sessionActive: true, cancelled: false)), ObservationDecision.denySensitive);
    }
  });

  test('unknown classification fails closed', () {
    expect(ObservationPolicy.evaluate(const ObservationContext(userConsented: true, osPermissionGranted: true, window: WindowSensitivity.unknown, sessionActive: true, cancelled: false)), ObservationDecision.denyUnknown);
  });
}
