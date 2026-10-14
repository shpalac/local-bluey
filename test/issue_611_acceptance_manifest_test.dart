import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('BLU-055 acceptance manifest matches canonical issue schema', () {
    final manifest = jsonDecode(
      File('docs/acceptance/temporary/issue-611.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    expect(manifest['version'], 1);
    expect(manifest['issues'], hasLength(1));

    final issue = manifest['issues'][0] as Map<String, dynamic>;
    expect(issue['number'], 611);
    expect(issue['criteria'], hasLength(4));

    for (final criterion in issue['criteria'] as List<dynamic>) {
      final item = criterion as Map<String, dynamic>;
      expect(item.containsKey('id'), isTrue);
      expect(item.containsKey('type'), isTrue);
      expect(item.containsKey('requirement'), isTrue);
      expect(
        item['type'] == 'automated' || item.containsKey('reason'),
        isTrue,
      );
    }
  });
}
