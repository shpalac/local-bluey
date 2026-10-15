import 'dart:convert';
import 'dart:io';

/// Summarizes PerfMonitor samples (#617): per-stage count, p50 and p95 of the
/// latency in milliseconds, using nearest-rank percentiles.
///
/// Usage: dart tool/perf_summary.dart `<perf.jsonl>`
///
/// Exit codes: 0 summary printed, 2 missing file, empty input or an invalid
/// line. Errors name only the line number, never the line content. This reads
/// latency only; it does not measure CPU, RAM, disk or cold start.
int nearestRank(List<int> sorted, double percentile) {
  final rank = (percentile / 100 * sorted.length).ceil();
  return sorted[(rank < 1 ? 1 : rank) - 1];
}

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: dart tool/perf_summary.dart <perf.jsonl>');
    exit(2);
  }
  final file = File(args.first);
  if (!file.existsSync()) {
    stderr.writeln('${args.first} not found');
    exit(2);
  }
  final stages = <String, List<int>>{};
  var lineNumber = 0;
  for (final line in file.readAsLinesSync()) {
    lineNumber++;
    if (line.trim().isEmpty) continue;
    Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      decoded = null;
    }
    final stage = decoded is Map ? decoded['stage'] : null;
    final ms = decoded is Map ? decoded['ms'] : null;
    if (stage is! String ||
        !RegExp(r'^[A-Za-z0-9_.-]+
      stderr.writeln('Invalid sample at line $lineNumber');
      exit(2);
    }
    stages.putIfAbsent(stage, () => []).add(ms);
  }
  if (stages.isEmpty) {
    stderr.writeln('No samples');
    exit(2);
  }
  final names = stages.keys.toList()..sort();
  stdout.writeln('stage,count,p50_ms,p95_ms');
  for (final name in names) {
    final sorted = [...stages[name]!]..sort();
    stdout.writeln(
      '$name,${sorted.length},${nearestRank(sorted, 50)},'
      '${nearestRank(sorted, 95)}',
    );
  }
}
).hasMatch(stage) ||
        ms is! int ||
        ms < 0) {
      stderr.writeln('Invalid sample at line $lineNumber');
      exit(2);
    }
    stages.putIfAbsent(stage, () => []).add(ms);
  }
  if (stages.isEmpty) {
    stderr.writeln('No samples');
    exit(2);
  }
  final names = stages.keys.toList()..sort();
  stdout.writeln('stage,count,p50_ms,p95_ms');
  for (final name in names) {
    final sorted = [...stages[name]!]..sort();
    stdout.writeln(
      '$name,${sorted.length},${nearestRank(sorted, 50)},'
      '${nearestRank(sorted, 95)}',
    );
  }
}
