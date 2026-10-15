import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/data_registry.dart';

DataStoreInfo failingStore(String message) => DataStoreInfo(
  id: 'failure_probe',
  sourceFile: 'lib/services/data_registry.dart',
  whatEn: 'probe',
  whatHe: 'probe',
  where: 'test',
  retentionEn: 'test',
  retentionHe: 'test',
  clear: () async => throw StateError(message),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('deletion errors never print secret exception contents', () async {
    final existing = DataRegistry.stores.toList();
    final messages = <String>[];
    final previousPrinter = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) messages.add(message);
    };
    DataRegistry.stores
      ..clear()
      ..add(failingStore('private@example.com API_KEY_SECRET'));
    addTearDown(() {
      debugPrint = previousPrinter;
      DataRegistry.stores
        ..clear()
        ..addAll(existing);
    });

    await expectLater(DataRegistry.deleteAll(), throwsStateError);

    final output = messages.join('\n');
    expect(output, isNot(contains('private@example.com')));
    expect(output, isNot(contains('API_KEY_SECRET')));
  });

  test('deletion failure reports the failed registered store id', () async {
    final existing = DataRegistry.stores.toList();
    DataRegistry.stores
      ..clear()
      ..add(failingStore('backend unavailable'));
    addTearDown(() {
      DataRegistry.stores
        ..clear()
        ..addAll(existing);
    });

    await expectLater(
      DataRegistry.deleteAll(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Could not clear stores: failure_probe',
        ),
      ),
    );
  });
}
