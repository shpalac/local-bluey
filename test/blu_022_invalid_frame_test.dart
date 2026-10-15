import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/screen_watch.dart';
import 'package:local_bluey/services/watch_pipeline.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('invalid pilot frame differences never trigger vision', () async {
    SharedPreferences.setMockInitialValues({
      'privacy.localOnly': true,
      'watch.appAllowlist': ['safari'],
    });
    final watch = ScreenWatch.forTesting();
    await watch.start(
      length: const Duration(minutes: 5),
      consentConfirmed: true,
    );
    var frameIndex = 0;
    var visionCalls = 0;
    final readings = <double>[double.nan, double.infinity, -0.5, 1.5];
    final pipeline = WatchPipeline(
      watch: watch,
      frontmost: () async => (app: 'Safari', title: 'Workspace', locked: false),
      frameDiff: () async => readings[frameIndex++],
      onVision: (_, _) async {
        visionCalls++;
        return 'unexpected';
      },
    );

    try {
      expect((await pipeline.tick())?.kind, WatchEventKind.appSwitch);
      for (final _ in readings) {
        expect(await pipeline.tick(), isNull);
      }
      expect(frameIndex, readings.length);
      expect(visionCalls, 0);
      expect(pipeline.events.map((event) => event.kind), [
        WatchEventKind.appSwitch,
      ]);
    } finally {
      await pipeline.dispose();
      watch.stop();
      watch.dispose();
    }
  });
}
