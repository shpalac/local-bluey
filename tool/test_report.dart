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
  final starts = <int, int>{};
  final failed = <int>{};
  final hidden = <int>{};

  for (final line in File(path).readAsLinesSync()) {
    if (line.trim().isEmpty || !line.startsWith('{')) continue;
    final Map<String, dynamic> e = jsonDecode(line);
    switch (e['type']) {
      case 'suite':
        suites[e['suite']['id'] as int] = (e['suite']['path'] as String)
            .replaceFirst(RegExp(r'^.*[\\/](test[\\/])'), '');
      case 'testStart':
        final t = e['test'];
        final id = t['id'] as int;
        final started = e['time'] as int;
        if (started < 0 || starts.containsKey(id)) {
          stderr.writeln('Invalid test start timing');
          exit(2);
        }
        starts[id] = started;
        names[id] = t['name'] as String;
        suiteOf[t['id'] as int] = t['suiteID'] as int;
      case 'testDone':
        final id = e['testID'] as int;
        final started = starts[id];
        // Preserve exclusion of hidden loader completions without a start.
        // An error naming that unknown identity is still invalid below.
        if (started == null && ((e['hidden'] as bool?) ?? false)) break;
        final ended = e['time'] as int;
        if (started == null || ended < started || durations.containsKey(id)) {
          stderr.writeln('Invalid test completion timing');
          exit(2);
        }
        durations[id] = ended - started;
        if ((e['hidden'] as bool?) ?? false) hidden.add(id);
        if (e['result'] == 'failure' || e['result'] == 'error') {
          failed.add(id);
        }
      case 'error':
        final id = e['testID'];
        if (id is! int || !starts.containsKey(id)) {
          stderr.writeln('Invalid test error identity');
          exit(2);
        }
        // Error text/stack is deliberately not copied into the report.
        failed.add(id);
      case 'allSuites':
    }
  }

  if (failed.any((id) => !durations.containsKey(id))) {
    stderr.writeln('Invalid test error completion');
    exit(2);
  }
  // A late error makes a previously hidden completion visible (Dart protocol).
  hidden.removeAll(failed);
  durations.removeWhere((id, _) => hidden.contains(id));
  final count = durations.length;

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
      '${(totalMs / 1000).toStringAsFixed(1)} s summed test time.\n',
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
