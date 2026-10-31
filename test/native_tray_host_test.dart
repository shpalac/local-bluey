import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/native_tray_host.dart';
import 'package:local_bluey/services/tray_publication_caller.dart';

void main() {
  test('native tray menu accepts all real inactive and active actions', () {
    for (final active in [false, true]) {
      final entries = TrayPublicationCaller.menuFor(active);
      expect(() => validateTrayMenuEntries(entries), returnsNormally);
      expect(
        entries
            .where((entry) => !entry.isSeparator)
            .map((entry) => entry.key)
            .toSet()
            .length,
        entries.where((entry) => !entry.isSeparator).length,
      );
    }
  });

  test(
    'native tray menu rejects duplicate actions before native allocation',
    () {
      expect(
        () => validateTrayMenuEntries([
          const TrayMenuEntry('quit', 'Quit'),
          const TrayMenuEntry('quit', 'Quit again'),
        ]),
        throwsArgumentError,
      );
    },
  );

  test('native tray menu rejects missing action keys and labels', () {
    expect(
      () => validateTrayMenuEntries([const TrayMenuEntry('', 'Missing key')]),
      throwsArgumentError,
    );
    expect(
      () => validateTrayMenuEntries([const TrayMenuEntry('quit', '')]),
      throwsArgumentError,
    );
  });

  test('native tray separators cannot dispatch a menu action', () {
    final entries = TrayPublicationCaller.menuFor(true);
    expect(
      entries
          .where((entry) => entry.isSeparator)
          .every((entry) => entry.key == null && entry.label.isEmpty),
      isTrue,
    );
    expect(() => validateTrayMenuEntries(entries), returnsNormally);
  });
}
