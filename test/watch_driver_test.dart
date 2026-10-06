import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/frame_differ.dart';
import 'package:local_bluey/services/screen_watch.dart';
import 'package:local_bluey/services/watch_driver.dart';
import 'package:local_bluey/services/watch_pipeline.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(
    () => SharedPreferences.setMockInitialValues({
      'privacy.localOnly': true,
      'watch.appAllowlist': ['safari'],
    }),
  );

  test('driver ticks adaptively, stops with the session, clears events', () {
    fakeAsync((async) {
      () async {
        final watch = ScreenWatch.forTesting();
        await watch.start(
          length: const Duration(minutes: 5),
          consentConfirmed: true,
        );
        var reads = 0;
        final pipeline = WatchPipeline(
          watch: watch,
          frontmost: () async {
            reads++;
            return (app: 'Safari', title: '', locked: false);
          },
          frameDiff: () async => 0.0,
        );
        final driver = WatchDriver(pipeline: pipeline, differ: FrameDiffer());
        driver.start();
        async.elapse(const Duration(milliseconds: 100));
        final afterFirst = reads;
        expect(afterFirst, greaterThan(0));

        // Quiet screen: interval backs off, so fewer ticks over time.
        async.elapse(const Duration(seconds: 20));
        final quietReads = reads - afterFirst;
        expect(
          quietReads,
          lessThan(12),
          reason: 'back-off keeps idle polling well under 1Hz average',
        );

        // One-tap stop kills the driver within the same second (#212).
        final readsAtStop = reads;
        watch.stop();
        async.elapse(const Duration(seconds: 10));
        expect(reads, readsAtStop, reason: 'no ticks after stop');
        expect(driver.running, isFalse);
        expect(pipeline.events, isEmpty);
      }();
    });
  });
}
