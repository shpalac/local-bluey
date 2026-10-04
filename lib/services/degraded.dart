/// Offline-first degraded modes (#90): what still works, and what the user
/// sees, for each unavailable dependency.
enum DegradedMode {
  /// LLM endpoint unreachable: face and local controls keep working.
  brainUnreachable,

  /// Transcription down: offer typed input instead of voice.
  transcriptionUnavailable,

  /// TTS down: the reply is shown as text only.
  ttsUnavailable,

  /// Phone side: the Mac is unreachable; auto-reconnect keeps trying.
  macOffline,
}

class Degraded {
  Degraded._();

  /// The message the user sees for each mode (#90).
  static String message(DegradedMode mode) => switch (mode) {
    DegradedMode.brainUnreachable =>
      "Bluey's brain is unreachable. Face and local controls still work - "
          'check the provider in Settings.',
    DegradedMode.transcriptionUnavailable =>
      'Voice input is unavailable right now - type your request instead.',
    DegradedMode.ttsUnavailable =>
      'Voice replies are unavailable - answers will appear as text.',
    DegradedMode.macOffline =>
      'Looking for your Mac on the local network - will reconnect '
          'automatically.',
  };

  /// The concrete fallback each mode offers (#90).
  static String fallback(DegradedMode mode) => switch (mode) {
    DegradedMode.brainUnreachable => 'switchProvider',
    DegradedMode.transcriptionUnavailable => 'typedInput',
    DegradedMode.ttsUnavailable => 'textOnly',
    DegradedMode.macOffline => 'autoReconnect',
  };
}
