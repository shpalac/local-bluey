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
  for (final line in file.readAsLinesSync()) {
    if (line.startsWith('SF:')) {
      final path = line.substring(3);
      current = thresholds.keys.firstWhere(
        (dir) => path.startsWith('$dir/'),
        orElse: () => '',
      );
    } else if (current.isNotEmpty && line.startsWith('LF:')) {
      found[current] = (found[current] ?? 0) + int.parse(line.substring(3));
    } else if (current.isNotEmpty && line.startsWith('LH:')) {
      hit[current] = (hit[current] ?? 0) + int.parse(line.substring(3));
    }
  }
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
