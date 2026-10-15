import 'package:flutter_test/flutter_test.dart';

import '../tool/ci_test_shards.dart' as ci;

void main() {
  test(
    'issue 600 AC-1 shard parity covers every impacted test exactly once',
    () {
      final input = [
        'test/z_test.dart',
        'test/a_test.dart',
        'test/b_test.dart',
      ];
      final shards = ci.partitionImpactedTests(input);
      final flattened = shards.expand((shard) => shard).toList();

      expect(shards, hasLength(2));
      expect(flattened, hasLength(input.length));
      expect(flattened.toSet(), input.toSet());
    },
  );

  test('issue 600 AC-2 shard results are order independent', () {
    final first = ci.partitionImpactedTests([
      'test/z_test.dart',
      'test/a_test.dart',
      'test/b_test.dart',
    ]);
    final second = ci.partitionImpactedTests([
      'test/b_test.dart',
      'test/z_test.dart',
      'test/a_test.dart',
    ]);

    expect(first, second);
  });

  test('issue 600 AC-2 malformed shard inputs fail explicitly', () {
    expect(
      () => ci.partitionImpactedTests(['test/a_test.dart', 'test/a_test.dart']),
      throwsFormatException,
    );
    expect(
      () => ci.partitionImpactedTests(['../secret_test.dart']),
      throwsFormatException,
    );
    expect(() => ci.partitionImpactedTests([]), throwsFormatException);
    expect(
      () => ci.partitionImpactedTests(['test/a_test.dart'], shardCount: 0),
      throwsArgumentError,
    );
  });
}
