import 'dart:io';

/// Per-directory line-coverage thresholds (#136). Fails the CI test lane
/// when lib/services or lib/link drop below their floor; raise the floors
/// deliberately as coverage improves.
const thresholds = {'lib/services': 60.0, 'lib/link': 65.0};

void main(List<String> args) {
  final file = File(args.isEmpty ? 'coverage/lcov.info' : args.first);
  if (!file.existsSync()) {
    stderr.writeln('${file.path} not found - run flutter test --coverage');
    exit(2);
  }
  final found = <String, int>{};
  final hit = <String, int>{};
  var current = '';
  int? recordFound;
  int? recordHit;
  void finishRecord() {
    if (current.isEmpty) return;
    if (recordFound == null || recordHit == null || recordHit > recordFound) {
      stderr.writeln('Invalid coverage counts for $current');
      exit(2);
    }
    found[current] = (found[current] ?? 0) + recordFound;
    hit[current] = (hit[current] ?? 0) + recordHit;
  }

  int count(String value) {
    final parsed = int.tryParse(value);
    if (parsed == null || parsed < 0) {
      stderr.writeln('Invalid coverage count');
      exit(2);
    }
    return parsed;
  }

  for (final line in file.readAsLinesSync()) {
    if (line.startsWith('SF:')) {
      finishRecord();
      recordFound = null;
      recordHit = null;
      final path = line.substring(3);
      current = thresholds.keys.firstWhere(
        (dir) => path.startsWith('$dir/'),
        orElse: () => '',
      );
    } else if (current.isNotEmpty && line.startsWith('LF:')) {
      if (recordFound != null) {
        stderr.writeln('Duplicate coverage count');
        exit(2);
      }
      recordFound = count(line.substring(3));
    } else if (current.isNotEmpty && line.startsWith('LH:')) {
      if (recordHit != null) {
        stderr.writeln('Duplicate coverage count');
        exit(2);
      }
      recordHit = count(line.substring(3));
    }
  }
  finishRecord();
  var failed = false;
  for (final entry in thresholds.entries) {
    final lf = found[entry.key] ?? 0;
    final lh = hit[entry.key] ?? 0;
    final pct = lf == 0 ? 0.0 : 100.0 * lh / lf;
    final ok = pct >= entry.value;
    if (!ok) failed = true;
    stdout.writeln(
      '${entry.key}: ${pct.toStringAsFixed(1)}% ($lh/$lf) '
      '${ok ? '>=' : '<'} floor ${entry.value}%${ok ? '' : '  FAIL'}',
    );
  }
  exit(failed ? 1 : 0);
}
