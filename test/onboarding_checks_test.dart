import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/onboarding_checks.dart';

class _FakeChecker implements PermissionChecker {
  _FakeChecker({this.mic = false});
  bool mic;
  int micCalls = 0;
  @override
  Future<bool> accessibility() async => true;
  @override
  Future<bool> screenRecording() async => false;
  @override
  Future<bool> microphone() async {
    micCalls++;
    return mic;
  }

  @override
  Future<bool> localNetwork() async => false;
}

void main() {
  test('#86: minimal path needs only the first-feature permission', () async {
    // Accessibility/screen-recording/local-network are not required to
    // finish onboarding - only the microphone is.
    final requiredIds = onboardingPermissions
        .where((p) => p.requiredForFirstAnswer)
        .map((p) => p.id);
    expect(requiredIds, ['microphone']);
  });

  test('#86: requiredGranted gates on the required permission only', () async {
    final checker = _FakeChecker(mic: false);
    expect(await requiredGranted(checker), isFalse);
    checker.mic = true;
    expect(await requiredGranted(checker), isTrue);
  });
}
