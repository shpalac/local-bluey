import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/degraded.dart';

void main() {
  test('#90: every mode has a user message and a fallback', () {
    for (final mode in DegradedMode.values) {
      expect(Degraded.message(mode), isNotEmpty);
      expect(Degraded.fallback(mode), isNotEmpty);
    }
  });

  test('#90: brain-unreachable keeps local control working', () {
    expect(
      Degraded.message(DegradedMode.brainUnreachable),
      contains('Settings'),
    );
    expect(Degraded.fallback(DegradedMode.brainUnreachable), 'switchProvider');
  });

  test('#90: TTS failure degrades to text-only', () {
    expect(Degraded.fallback(DegradedMode.ttsUnavailable), 'textOnly');
  });

  test('#90: offline Mac auto-reconnects', () {
    expect(Degraded.fallback(DegradedMode.macOffline), 'autoReconnect');
  });

  test('#90: transcription failure offers typed input', () {
    expect(
      Degraded.fallback(DegradedMode.transcriptionUnavailable),
      'typedInput',
    );
  });
}
