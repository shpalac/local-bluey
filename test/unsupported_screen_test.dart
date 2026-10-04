import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/main.dart';
import 'package:local_bluey/services/support_matrix.dart';
import 'package:local_bluey/ui/unsupported_screen.dart';

void main() {
  group('routing by role (#84)', () {
    test('host platforms get the Mac home', () {
      final w = homeForProfile(SupportMatrix.profile(operatingSystem: 'macos'));
      expect(w, isNot(isA<UnsupportedScreen>()));
    });

    test('client platforms get the client UI, never unsupported', () {
      for (final os in ['ios', 'android']) {
        final w = homeForProfile(SupportMatrix.profile(operatingSystem: os));
        expect(w, isNot(isA<UnsupportedScreen>()));
      }
    });

    test('unsupported and unknown platforms get the unsupported screen', () {
      for (final os in ['linux', 'windows', 'fuchsia']) {
        final w = homeForProfile(SupportMatrix.profile(operatingSystem: os));
        expect(w, isA<UnsupportedScreen>());
      }
    });
  });

  group('unsupported reasons', () {
    test('unknown OS names are reported as unrecognized', () {
      final reason = SupportMatrix.unsupportedReason(
        SupportMatrix.profile(operatingSystem: 'fuchsia'),
      );
      expect(reason, contains('fuchsia'));
    });

    test('known-but-unsupported platforms get a role explanation', () {
      final reason = SupportMatrix.unsupportedReason(
        SupportMatrix.profile(operatingSystem: 'windows'),
      );
      expect(reason, isNotEmpty);
    });
  });

  testWidgets('unsupported screen explains and starts no work', (tester) async {
    final profile = SupportMatrix.profile(operatingSystem: 'linux');
    await tester.pumpWidget(
      MaterialApp(home: UnsupportedScreen(profile: profile)),
    );
    expect(
      find.text('Local Bluey does not support this platform yet'),
      findsOneWidget,
    );
    expect(find.text(UnsupportedScreen.readmeMatrixUrl), findsOneWidget);
  });
}
