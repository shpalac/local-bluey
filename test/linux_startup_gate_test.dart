import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/main.dart';
import 'package:local_bluey/services/support_matrix.dart';
import 'package:local_bluey/ui/unsupported_screen.dart';

void main() {
  test('Linux capability lookup fails closed for unknown host powers', () {
    final profile = SupportMatrix.profile(operatingSystem: 'linux');
    expect(profile.supports(SupportMatrix.hostControl), isFalse);
    expect(profile.supports(SupportMatrix.phoneServer), isFalse);
    expect(profile.supports(SupportMatrix.macLink), isFalse);
    expect(profile.supports('linux-desktop-face'), isFalse);
  });

  test('Linux initial routing rejects experimental backend promotion', () {
    final profile = SupportMatrix.profile(operatingSystem: 'linux');
    final home = homeForProfile(profile);
    expect(home, isA<UnsupportedScreen>());
    expect((home as UnsupportedScreen).profile, same(profile));
  });

  testWidgets('Linux unsupported startup describes the blocked role', (
    tester,
  ) async {
    final home = homeForProfile(
      SupportMatrix.profile(operatingSystem: 'linux'),
    );
    await tester.pumpWidget(MaterialApp(home: home));
    expect(find.byType(UnsupportedScreen), findsOneWidget);
    expect(
      find.text('Local Bluey does not support this platform yet'),
      findsOneWidget,
    );
    expect(
      find.text('This platform can be neither a host nor a remote client.'),
      findsOneWidget,
    );
  });

  test('unknown operating system routes to unsupported initial screen', () {
    final profile = SupportMatrix.profile(
      operatingSystem: 'unknown-linux-variant',
    );
    expect(profile.capabilities, isEmpty);
    expect(homeForProfile(profile), isA<UnsupportedScreen>());
  });
}
