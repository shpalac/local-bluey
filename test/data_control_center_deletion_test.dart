import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/data_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingStore extends DataStoreInfo {
  _RecordingStore(String id, this.calls, {this.fails = false})
    : super(
        id: id,
        sourceFile: 'lib/services/data_registry.dart',
        whatEn: 'probe',
        whatHe: 'probe',
        where: 'test',
        retentionEn: 'test',
        retentionHe: 'test',
        clear: () async {
          if (fails) throw StateError('simulated deletion failure');
          calls.add(id);
        },
      );

  final List<String> calls;
  final bool fails;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  List<DataStoreInfo> restore = const [];
  tearDown(() {
    DataRegistry.stores
      ..clear()
      ..addAll(restore);
  });

  test(
    'ac1 deleteAll clears every registered store, verifiably and once',
    () async {
      restore = DataRegistry.stores.toList();
      final calls = <String>[];
      DataRegistry.stores
        ..clear()
        ..addAll([
          _RecordingStore('alpha', calls),
          _RecordingStore('beta', calls),
          _RecordingStore('gamma', calls),
        ]);

      await DataRegistry.deleteAll();
      // Every store cleared exactly once, in registry order.
      expect(calls, ['alpha', 'beta', 'gamma']);

      // Idempotent: a second sweep runs the same clear closures again
      // without failure, keeping the successful deletion state.
      calls.clear();
      await DataRegistry.deleteAll();
      expect(calls, ['alpha', 'beta', 'gamma']);
    },
  );

  test('ac1 the inventory stays describable for the UX surface', () {
    restore = DataRegistry.stores.toList();
    for (final store in DataRegistry.stores) {
      expect(store.id, isNotEmpty, reason: 'inventory id present');
      expect(store.sourceFile, startsWith('lib/'));
      expect(store.whatEn, isNotEmpty, reason: 'English inventory copy');
      expect(store.whatHe, isNotEmpty, reason: 'Hebrew inventory copy');
      expect(store.where, isNotEmpty, reason: 'storage location copy');
      expect(store.retentionEn, isNotEmpty, reason: 'retention copy');
      expect(store.retentionHe, isNotEmpty, reason: 'retention copy He');
    }
  });

  test(
    'ac1 preferences are wiped on deleteAll, and the result is verifiable',
    () async {
      SharedPreferences.setMockInitialValues({
        'brain.apiKey': 'legacy-secret',
        'haptics.enabled': true,
      });
      restore = DataRegistry.stores.toList();
      DataRegistry.stores
        ..clear()
        ..addAll([]);
      await DataRegistry.deleteAll();
      final prefs = await SharedPreferences.getInstance();
      // Deletion is the requested act and stays verifiable afterwards: no
      // pref key, secret or otherwise, survives the wipe.
      expect(prefs.getKeys(), isEmpty);
    },
  );
}
