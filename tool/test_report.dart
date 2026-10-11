import 'dart:io';

/// Compatibility entry point for the structured JSON/JUnit reporting tool.
void main(List<String> args) {
  final result = Process.runSync('python3', ['tool/test_report.py', ...args]);
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  exit(result.exitCode);
}
