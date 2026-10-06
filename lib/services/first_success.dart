import 'endpoint_assistant.dart';
import 'settings_store.dart';
import 'strings.dart';
import 'stt.dart';

/// How ready a backing service is for the first request (#226).
enum ServiceReadiness {
  /// Verified reachable (brain) or configured (speech-to-text).
  ready,

  /// Configured but not answering.
  unreachable,

  /// No usable configuration yet.
  notConfigured,
}

bool get _hebrewSpeech => Strings.speechLanguage.startsWith('he');

/// Which permissions and services are actually available right now.
class FirstSuccessInputs {
  const FirstSuccessInputs({
    required this.accessibility,
    required this.screenRecording,
    required this.microphone,
    required this.brain,
    required this.stt,
  });

  /// Accessibility granted (needed to move the cursor).
  final bool accessibility;

  /// Screen Recording granted (needed to see the screen).
  final bool screenRecording;

  /// Microphone granted (needed for any spoken question).
  final bool microphone;

  /// The chat model endpoint.
  final ServiceReadiness brain;

  /// Speech-to-text.
  final ServiceReadiness stt;
}

/// One thing that blocks the first request, with where to fix it.
class ReadinessIssue {
  const ReadinessIssue(this.id, this.message);

  /// 'microphone', 'brain' or 'stt'.
  final String id;

  /// Plain-language explanation with the next step.
  final String message;
}

/// The honest first-success path for what is ready (#226): a first request
/// that does not depend on anything missing, and tutorial steps gated on
/// their real capability. A plan never claims readiness it did not verify.
class FirstSuccessPlan {
  const FirstSuccessPlan({
    required this.issues,
    required this.suggestedRequest,
    required this.screenQuestionAvailable,
    required this.pointingAvailable,
  });

  /// Builds the plan from [inputs].
  factory FirstSuccessPlan.from(FirstSuccessInputs inputs) {
    final issues = <ReadinessIssue>[
      if (!inputs.microphone)
        ReadinessIssue(
          'microphone',
          Strings.t(
            'Microphone access is off, so Bluey cannot hear you. Turn it on '
                'in System Settings > Privacy & Security > Microphone.',
            'הגישה למיקרופון כבויה, ולכן בלואי לא יכול לשמוע אותך. הפעל '
                'אותה בהגדרות המערכת > פרטיות ואבטחה > מיקרופון.',
          ),
        ),
      if (inputs.brain == ServiceReadiness.notConfigured)
        ReadinessIssue(
          'brain',
          Strings.t(
            'No chat model is set up. Open Settings and run the endpoint '
                'assistant.',
            'לא הוגדר מודל צ\'אט. פתח הגדרות והפעל את עוזר החיבור.',
          ),
        ),
      if (inputs.brain == ServiceReadiness.unreachable)
        ReadinessIssue(
          'brain',
          Strings.t(
            'The chat model did not answer. Check that it is running, or '
                'open Settings to change the endpoint.',
            'מודל הצ\'אט לא ענה. בדוק שהוא פועל, או פתח הגדרות כדי לשנות '
                'את הכתובת.',
          ),
        ),
      if (inputs.stt == ServiceReadiness.notConfigured)
        ReadinessIssue(
          'stt',
          Strings.t(
            'Speech-to-text is not set up, so spoken questions would fail. '
                'Open Settings to choose a provider.',
            'זיהוי הדיבור לא הוגדר, ולכן שאלות בקול ייכשלו. פתח הגדרות '
                'ובחר ספק.',
          ),
        ),
      if (inputs.stt == ServiceReadiness.unreachable)
        ReadinessIssue(
          'stt',
          Strings.t(
            'The speech-to-text service did not answer. Open Settings to '
                'check it.',
            'שירות זיהוי הדיבור לא ענה. פתח הגדרות כדי לבדוק אותו.',
          ),
        ),
    ];
    final voiceReady = issues.isEmpty;
    final screen = voiceReady && inputs.screenRecording;
    return FirstSuccessPlan(
      issues: issues,
      suggestedRequest: !voiceReady
          ? null
          : screen
          ? (_hebrewSpeech ? 'מה יש על המסך שלי?' : "what's on my screen?")
          : (_hebrewSpeech
                ? 'שלום, מה אתה יכול לעשות?'
                : 'hello, what can you do?'),
      screenQuestionAvailable: screen,
      pointingAvailable:
          voiceReady && inputs.screenRecording && inputs.accessibility,
    );
  }

  /// What blocks a spoken first request; empty when one can work.
  final List<ReadinessIssue> issues;

  /// The first thing to say, or null when something blocks it.
  final String? suggestedRequest;

  /// A question about the screen can be answered.
  final bool screenQuestionAvailable;

  /// Pointing at something on screen can work.
  final bool pointingAvailable;

  /// True when the first spoken request has what it needs.
  bool get voiceReady => issues.isEmpty;
}

/// Reads live settings and verifies the brain endpoint (#226). Speech-to-
/// text is checked for configuration only: probing it would send audio.
Future<(ServiceReadiness brain, ServiceReadiness stt)> checkServices({
  EndpointAssistant? assistant,
}) async {
  ServiceReadiness brain;
  try {
    final settings = await SettingsStore.load();
    if (settings.baseUrl.trim().isEmpty) {
      brain = ServiceReadiness.notConfigured;
    } else {
      final result = await (assistant ?? EndpointAssistant()).checkEndpoint(
        baseUrl: settings.baseUrl,
        backend: settings.backend,
        apiKey: settings.apiKey,
      );
      brain = result is EndpointCheckOk
          ? ServiceReadiness.ready
          : ServiceReadiness.unreachable;
    }
  } catch (_) {
    brain = ServiceReadiness.unreachable;
  }
  ServiceReadiness speech;
  try {
    final s = await SttSettings.load();
    speech =
        s.kind == SttProviderKind.http && (s.baseUrl?.trim().isEmpty ?? true)
        ? ServiceReadiness.notConfigured
        : ServiceReadiness.ready;
  } catch (_) {
    speech = ServiceReadiness.notConfigured;
  }
  return (brain, speech);
}
