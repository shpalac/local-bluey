import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/host_control.dart';

void main() {
  test('Windows host control explicitly fails closed without native dispatch', () {
    final host = HostControl.forPlatform(
      operatingSystem: 'windows',
      environment: const {'DISPLAY': ':0', 'XDG_SESSION_TYPE': 'wayland'},
    );

    expect(host, isA<UnsupportedHostControl>());
    expect((host as UnsupportedHostControl).operatingSystem, 'windows');
    expect(() => host.isTrusted(), throwsUnsupportedError);
    expect(() => host.snapshot(), throwsUnsupportedError);
    expect(() => host.click(10, 20), throwsUnsupportedError);
    expect(() => host.askPermission(), throwsUnsupportedError);
  });

  test('Windows unsupported host errors never disclose caller payloads', () {
    final host = HostControl.forPlatform(operatingSystem: 'windows');
    const privateText = 'private-user-input-597';
    const privateUrl = 'https://example.invalid/?token=secret-597';

    String failureMessage(Future<dynamic> Function() action) {
      try {
        action();
      } on UnsupportedError catch (error) {
        return error.toString();
      }
      throw StateError('Unsupported host action unexpectedly succeeded');
    }

    for (final message in [
      failureMessage(() => host.type(privateText)),
      failureMessage(() => host.openURL(privateUrl)),
    ]) {
      expect(message, contains('windows'));
      expect(message, contains('native bridge'));
      expect(message, isNot(contains(privateText)));
      expect(message, isNot(contains(privateUrl)));
    }
  });
}
