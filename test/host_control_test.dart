import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/host_control.dart';

void main() {
  test('macOS gets the live host control', () {
    expect(HostControl.forPlatform(operatingSystem: 'macos'), isA<MacHostControl>());
  });

  test('other platforms get a loud placeholder', () {
    final host = HostControl.forPlatform(operatingSystem: 'linux');
    expect(host, isA<UnsupportedHostControl>());
    expect(
      () => host.isTrusted(),
      throwsA(
        isA<UnsupportedError>().having(
          (e) => e.message,
          'message',
          contains('linux'),
        ),
      ),
    );
  });
}
