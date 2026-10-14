import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('BLU-055 acceptance manifest does not claim unsupported automation', () {
    final manifest = jsonDecode(
      File('docs/acceptance/temporary/issue-611.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    final criteria = manifest['criteria'] as List<dynamic>;

    expect(criteria, hasLength(4));
    expect(
      criteria.every(
        (criterion) =>
            (criterion as Map<String, dynamic>)['status'] == 'manual',
      ),
      isTrue,
    );
  });
}
