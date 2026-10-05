import 'dart:convert';
import 'dart:io';

/// Renders a markdown summary (slowest tests, failures) from flutter's
/// JSON test reporter output, and can list failed test files for the
/// flaky-retry pass (#159).
void main(List<String> args) {
  final path = args.isEmpty ? 'test-report.jsonl' : args.first;
  final failedFilesOnly = args.contains('--failed-files');
  final suites = <int, String>{};
  final names = <int, String>{};
  final suiteOf = <int, int>{};
  final durations = <int, int>{};
  final failed = <int>{};
  var count = 0;

  for (final line in File(path).readAsLinesSync()) {
    if (line.trim().isEmpty || !line.startsWith('{')) continue;
    final Map<String, dynamic> e = jsonDecode(line);
    switch (e['type']) {
      case 'suite':
        suites[e['suite']['id'] as int] = (e['suite']['path'] as String)
            .replaceFirst(RegExp(r'^.*[\\/](test[\\/])'), '');
      case 'testStart':
        final t = e['test'];
        names[t['id'] as int] = t['name'] as String;
        suiteOf[t['id'] as int] = t['suiteID'] as int;
      case 'testDone':
        if ((e['hidden'] as bool?) ?? false) break;
        final id = e['testID'] as int;
        count++;
        durations[id] = e['time'] as int;
        if (e['result'] == 'failure' || e['result'] == 'error') {
          failed.add(id);
        }
      case 'allSuites':
    }
  }

  if (failedFilesOnly) {
    final files = failed.map((id) => suites[suiteOf[id]] ?? '').toSet()
      ..remove('');
    stdout.writeln(files.map((f) => 'test/$f').join(' '));
    return;
  }

  final sorted = durations.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final totalMs = durations.values.fold<int>(0, (a, b) => a + b);
  final b = StringBuffer('## Test report\n\n')
    ..writeln(
      '$count tests, ${failed.length} failed, '
      '${(totalMs / 1000).toStringAsFixed(1)} s total.\n',
    )
    ..writeln('| Slowest 10 | ms |')
    ..writeln('|---|---:|');
  for (final e in sorted.take(10)) {
    b.writeln('| ${names[e.key]} | ${e.value} |');
  }
  if (failed.isNotEmpty) {
    b.writeln('\n**Failed:**');
    for (final id in failed) {
      b.writeln('- ${names[id]} (test/${suites[suiteOf[id]]})');
    }
  }
  stdout.write(b);
}
