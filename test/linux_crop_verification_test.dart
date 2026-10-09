import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/llm/tools.dart';
import 'package:local_bluey/services/linux_x11_host_control.dart';
import 'package:local_bluey/services/tool_executor.dart';

const header =
    'level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext\n';
String word(String text, {String conf = '95'}) =>
    '5\t1\t1\t1\t1\t1\t100\t200\t40\t20\t$conf\t$text\n';

void main() {
  for (final scenario in [
    'blank',
    'clean',
    'sensitive',
    'missing',
    'nonzero',
    'malformed',
    'truncated',
    'bad-number',
    'weak',
    'ocr-throw',
    'capture-fail',
  ]) {
    test('exact X11 crop verification and cleanup: $scenario (#285)', () async {
      final dirs = <Directory>[];
      final paths = <String>[];
      var output = '$header${word('Hello')}';
      var failure = '';
      final host = LinuxX11HostControl(
        env: (key) => key == 'DISPLAY' ? ':0' : null,
        hasBinary: (exe) async => !(exe == 'tesseract' && failure == 'missing'),
        makeTempDir: () async {
          final dir = await Directory.systemTemp.createTemp('crop-fixture-');
          dirs.add(dir);
          return dir;
        },
        readBytes: (_) async => Uint8List.fromList([1, 2, 3]),
        run: (exe, args) async {
          if (exe == 'xdotool') return ProcessResult(0, 0, '1920 1080', '');
          if (exe == 'import' && failure == 'capture-fail') {
            return ProcessResult(0, 1, '', 'fixture failure');
          }
          if (exe == 'tesseract') {
            paths.add(args.first);
            if (failure == 'ocr-throw') throw StateError('fixture OCR failed');
            return ProcessResult(0, failure == 'nonzero' ? 1 : 0, output, '');
          }
          return ProcessResult(0, 0, '', '');
        },
      );
      final executor = ToolExecutor(control: host);
      await executor.execute(ToolCall('look_at_screen', {}));
      expect((await host.resolveTarget('W1')).text, 'Hello');
      failure = scenario;
      output = switch (scenario) {
        'blank' => header,
        'sensitive' => '$header${word('user@example.com')}',
        'malformed' => 'not a TSV header\n',
        'truncated' => '${header}5\t1\tbroken\n',
        'bad-number' => '$header${word('Hello').replaceFirst('100', 'NaN')}',
        'weak' => '$header${word('possibly-secret', conf: '10')}',
        _ => '$header${word('Clean')}',
      };
      final zoom = await executor.execute(ToolCall('zoom_screen', {}));
      expect(
        zoom.imageBase64,
        scenario == 'blank' || scenario == 'clean' ? isNotEmpty : isNull,
      );
      if (!['clean', 'sensitive'].contains(scenario)) {
        expect(() => host.resolveTarget('W1'), throwsStateError);
      }
      for (final dir in dirs) {
        expect(await dir.exists(), isFalse);
      }
      if (paths.length > 1) expect(paths.first, isNot(paths.last));
    });
  }
}
