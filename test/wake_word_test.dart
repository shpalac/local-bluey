import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/wake_word.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSpotter extends WakeWordSpotter {
  double value = 0.9;
  int calls = 0;
  @override
  Future<double> score(File audioWindow) async {
    calls++;
    return value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('dormant without a spotter engine', () async {
    final service = WakeWordService(spotter: null);
    final file = await File(
      '${Directory.systemTemp.path}/ww_test.m4a',
    ).create();
    expect(await service.scoreAndMaybeWake(file), isFalse);
  });

  test('below threshold never confirms', () async {
    final spotter = _FakeSpotter()..value = 0.2;
    final service = WakeWordService(spotter: spotter);
    final file = await File(
      '${Directory.systemTemp.path}/ww_test2.m4a',
    ).create();
    expect(await service.scoreAndMaybeWake(file), isFalse);
    expect(spotter.calls, 1);
  });

  test('default is off and persisted', () async {
    expect(await WakeWordService.isEnabled(), isFalse);
    await WakeWordService.setEnabled(true);
    expect(await WakeWordService.isEnabled(), isTrue);
  });


}
