import 'dart:io';

import 'package:local_bluey/services/nightly_test_summary.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln('Expected one machine-events input path.');
    exitCode = 2;
    return;
  }

  try {
    final input = File(arguments.single).readAsStringSync();
    final summary = NightlyTestSummary.parse(input);
    final destination = Platform.environment['GITHUB_STEP_SUMMARY'];
    if (destination == null || destination.isEmpty) {
      throw const FormatException('GitHub job summary destination missing');
    }
    File(destination).writeAsStringSync(
      summary.toMarkdown(),
      mode: FileMode.append,
    );
    if (summary.failed > 0) exitCode = 1;
  } on FileSystemException {
    stderr.writeln('Nightly summary input or output is unavailable.');
    exitCode = 2;
  } on FormatException {
    stderr.writeln('Nightly test report is invalid or incomplete.');
    exitCode = 2;
  }
}
