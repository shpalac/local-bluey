import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/egress_monitor.dart';

class _MemoryStorage implements EgressStorage {
  String? contents;
  int writes = 0;
  int deletes = 0;

  @override
  Future<String?> read() async => contents;

  @override
  Future<void> write(String value) async {
    writes++;
    contents = value;
  }

  @override
  Future<void> delete() async {
    deletes++;
    contents = null;
  }
}

void main() {
  final now = DateTime.utc(2026, 10, 11, 11);
  Map<String, dynamic> valid() => {
    'host': 'localhost',
    'kind': 'brain',
    'bytes': 7,
    'at': now.toIso8601String(),
  };
  final rejected = <String, Map<String, dynamic>>{
    'missing host': {'host': null},
    'wrong host type': {'host': 7},
    'empty host': {'host': ''},
    'slash host': {'host': 'synthetic.example/path'},
    'at-sign host': {'host': 'synthetic@host'},
    'missing kind': {'kind': null},
    'wrong kind type': {'kind': 7},
    'empty kind': {'kind': ''},
    'missing bytes': {'bytes': null},
    'string bytes': {'bytes': '7'},
    'fractional bytes': {'bytes': 7.5},
    'negative bytes': {'bytes': -1},
    'missing time': {'at': null},
    'invalid time': {'at': 'not-a-time'},
  };

  for (final field in rejected.entries) {
    test('actual parser rejects ${field.key}', () {
      final row = valid()..addAll(field.value);
      // Null represents absence here, not a different accepted serialization.
      row.removeWhere((_, value) => value == null);
      expect(() => EgressEntry.fromJson(row), throwsFormatException);
    });

    test('load preserves mixed rows for ${field.key} until clear', () async {
      final invalid = valid()..addAll(field.value);
      invalid.removeWhere((_, value) => value == null);
      final storage = _MemoryStorage()
        ..contents = '${jsonEncode(valid())}\n${jsonEncode(invalid)}\n';
      final original = storage.contents;
      final monitor = EgressMonitor(storage: storage, now: () => now);
      await monitor.load();
      expect(monitor.entries.single.toJson(), valid());
      expect(monitor.historyAvailable, isFalse);
      expect(monitor.report(), contains('not fully available'));
      await monitor.record('https://later.synthetic.example/path', 'caller', 3);
      await monitor.load(); // Explicit ordered barrier, no timer or file IO.
      expect(monitor.entries, hasLength(2));
      expect(storage.writes, 0);
      expect(storage.contents, original);
      expect(monitor.report(), contains('localhost: 1 calls (brain), 7 bytes'));
      await monitor.clear();
      expect(storage.deletes, 1);
      expect(storage.contents, isNull);
      await monitor.record('http://localhost/fresh', 'fresh-label', 0);
      expect(monitor.historyAvailable, isTrue);
      expect(storage.writes, 1);
      final saved =
          jsonDecode(storage.contents!.trim()) as Map<String, dynamic>;
      expect(saved, {...valid(), 'kind': 'fresh-label', 'bytes': 0});
    });
  }

  for (final shape in <Object?>[
    null,
    7,
    'synthetic-string',
    <Object?>[],
    <Object?>[valid()],
  ]) {
    test(
      'load rejects top-level ${jsonEncode(shape)} without overwrite',
      () async {
        final storage = _MemoryStorage()
          ..contents = '${jsonEncode(valid())}\n${jsonEncode(shape)}\n';
        final original = storage.contents;
        final monitor = EgressMonitor(storage: storage, now: () => now);
        await monitor.load();
        expect(monitor.entries.single.toJson(), valid());
        expect(monitor.historyAvailable, isFalse);
        await monitor.record('http://localhost/new', 'caller', 1);
        expect(storage.contents, original);
        expect(storage.writes, 0);
        await monitor.clear();
        expect(monitor.entries, isEmpty);
        expect(monitor.historyAvailable, isTrue);
      },
    );
  }

  for (final row in <Map<String, dynamic>>[
    {...valid(), 'extra': 'ignored-synthetic'},
    {...valid(), 'host': 'unknown-host'},
    {...valid(), 'host': 'localhost:80'},
    {...valid(), 'host': ' localhost'},
    {...valid(), 'kind': 'unlisted synthetic label'},
    {...valid(), 'kind': ' '},
  ]) {
    test(
      'parser accepts metadata ${jsonEncode(row)} without safe-export claim',
      () async {
        final expected = Map<String, dynamic>.from(row)..remove('extra');
        expect(EgressEntry.fromJson(row).toJson(), expected);
        final storage = _MemoryStorage()..contents = '${jsonEncode(row)}\n';
        final monitor = EgressMonitor(storage: storage, now: () => now);
        await monitor.load();
        expect(monitor.historyAvailable, isTrue);
        expect(monitor.entries.single.toJson(), expected);
        expect(
          monitor.report(),
          contains('${row['host']}: 1 calls (${row['kind']}), 7 bytes'),
        );
      },
    );
  }

  test(
    'record serializes parsed host only and preserves arbitrary caller label',
    () async {
      final storage = _MemoryStorage();
      final monitor = EgressMonitor(storage: storage, now: () => now);
      await monitor.record(
        'https://synthetic-user:synthetic-password@synthetic.example:8443/path?token=synthetic-token#fragment',
        'custom synthetic purpose',
        -17,
      );
      final expected = {
        ...valid(),
        'host': 'synthetic.example',
        'kind': 'custom synthetic purpose',
        'bytes': 0,
      };
      expect(monitor.entries.single.toJson(), expected);
      expect(jsonDecode(storage.contents!.trim()), expected);
      for (final excluded in [
        'synthetic-user',
        'synthetic-password',
        '8443',
        '/path',
        'synthetic-token',
        'fragment',
      ]) {
        expect(storage.contents, isNot(contains(excluded)));
      }
      expect(
        monitor.report(),
        contains('1 calls (custom synthetic purpose), 0 bytes'),
      );
    },
  );

  for (final url in ['not a URL?synthetic-token', 'http://[broken']) {
    test(
      'record uses unknown-host rather than raw fallback for $url',
      () async {
        final storage = _MemoryStorage();
        final monitor = EgressMonitor(storage: storage, now: () => now);
        await monitor.record(url, 'synthetic-label', 2);
        expect(monitor.entries.single.host, 'unknown-host');
        expect(jsonDecode(storage.contents!.trim()), {
          ...valid(),
          'host': 'unknown-host',
          'kind': 'synthetic-label',
          'bytes': 2,
        });
        expect(storage.contents, isNot(contains(url)));
      },
    );
  }

  test(
    'record accepts empty caller label but actual reload rejects its row',
    () async {
      final storage = _MemoryStorage();
      final monitor = EgressMonitor(storage: storage, now: () => now);
      await monitor.record('http://localhost', '', 4);
      expect(monitor.historyAvailable, isTrue);
      expect(monitor.entries.single.kind, '');
      final original = storage.contents;
      final restarted = EgressMonitor(storage: storage, now: () => now);
      await restarted.load();
      expect(restarted.entries, isEmpty);
      expect(restarted.historyAvailable, isFalse);
      await restarted.record('http://localhost', 'new-label', 1);
      expect(storage.contents, original);
      expect(
        storage.writes,
        1,
      ); // Original record, not rejected-history overwrite.
    },
  );
}
