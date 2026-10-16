import 'dart:convert';
import 'dart:io';

/// Partitions impacted tests without dropping or repeating a test file.
List<List<String>> partitionImpactedTests(
  List<String> files, {
  int shardCount = 2,
}) {
  if (shardCount < 1) {
    throw ArgumentError.value(shardCount, 'shardCount', 'must be positive');
  }
  if (files.isEmpty ||
      files.any(
        (file) =>
            !file.startsWith('test/') ||
            !file.endsWith('_test.dart') ||
            file.contains('..') ||
            file.contains('\\') ||
            file.contains('\n'),
      )) {
    throw const FormatException('expected nonempty test/*_test.dart paths');
  }
  if (files.toSet().length != files.length) {
    throw const FormatException('duplicate test file in impact plan');
  }

  final ordered = files.toList()..sort();
  final shards = List.generate(shardCount, (_) => <String>[]);
  for (var index = 0; index < ordered.length; index++) {
    shards[index % shardCount].add(ordered[index]);
  }
  return shards;
}

void main(List<String> args) {
  try {
    if (args.length != 1) {
      throw const FormatException('expected one JSON array argument');
    }
    final decoded = jsonDecode(args.single);
    if (decoded is! List || decoded.any((value) => value is! String)) {
      throw const FormatException('expected JSON array of test filenames');
    }
    stdout.writeln(jsonEncode(partitionImpactedTests(decoded.cast<String>())));
  } on FormatException catch (error) {
    stderr.writeln('::error::CI test sharding failed: ${error.message}');
    exitCode = 1;
  } on ArgumentError catch (error) {
    stderr.writeln('::error::CI test sharding failed: $error');
    exitCode = 1;
  }
}
