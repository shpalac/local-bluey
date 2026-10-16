import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/data_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('ac3 registry provenance stays non-transport and non-artifact', () {
    final source = File('lib/services/data_registry.dart').readAsStringSync();
    expect(
      source.contains(RegExp("import '(package:http)")),
      isFalse,
      reason: 'the registry must not gain transport access',
    );
    expect(
      RegExp(r'writeAsBytesSync|writeAsStringSync').hasMatch(source),
      isFalse,
      reason: 'the registry must not serialize artifacts',
    );
    // The one debug print is a fixed, message-free, non-interpolated line.
    expect(
      source,
      contains("debugPrint('DataRegistry: local store deletion failed.');"),
    );
  });

  test('ac3 failures never echo exception text for the corpus', () async {
    final existing = DataRegistry.stores.toList();
    DataRegistry.stores
      ..clear()
      ..addAll([
        DataStoreInfo(
          id: 'alpha',
          sourceFile: 'lib/services/data_registry.dart',
          whatEn: 'probe',
          whatHe: 'probe',
          where: 'test',
          retentionEn: 'test',
          retentionHe: 'test',
          clear: () async =>
              throw StateError('user secret blowfish22@fixture.invalid'),
        ),
        DataStoreInfo(
          id: 'beta',
          sourceFile: 'lib/services/data_registry.dart',
          whatEn: 'probe',
          whatHe: 'probe',
          where: 'test',
          retentionEn: 'test',
          retentionHe: 'test',
          clear: () async =>
              throw Exception('session token 4111-1111-1111-1111'),
        ),
      ]);
    addTearDown(() {
      DataRegistry.stores
        ..clear()
        ..addAll(existing);
    });

    final messages = <String>[];
    final previousPrinter = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) messages.add(message);
    };
    Object? caught;
    try {
      await DataRegistry.deleteAll();
    } catch (error) {
      caught = error;
    } finally {
      debugPrint = previousPrinter;
    }

    final output = messages.join('\n');
    for (final secret in [
      'blowfish22@fixture.invalid',
      '4111-1111-1111-1111',
      'session token',
    ]) {
      expect(output, isNot(contains(secret)));
    }

    // The aggregated failure message carries stable ids only.
    final message = caught is StateError ? caught.message : '';
    expect(message, 'Could not clear stores: alpha, beta');
    for (final secret in ['blowfish22', '4111']) {
      expect(message, isNot(contains(secret)));
    }
  });

  test(
    'ac3 the deletion itself is the leak-prevention: secrets erased',
    () async {
      SharedPreferences.setMockInitialValues({
        'brain.apiKey': 'sample@fixture.invalid',
        'haptics.enabled': true,
      });
      final existing = DataRegistry.stores.toList();
      DataRegistry.stores
        ..clear()
        ..addAll([]);
      addTearDown(() {
        DataRegistry.stores
          ..clear()
          ..addAll(existing);
      });
      await DataRegistry.deleteAll();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('brain.apiKey'), isNull);
      expect(prefs.getStringList('brain.apiKey'), isNull);
    },
  );
}
