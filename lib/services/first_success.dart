import 'endpoint_assistant.dart';
import 'settings_store.dart';
import 'strings.dart';
import 'stt.dart';

/// First-request planning labels (#226), not full provider qualification.
enum ServiceReadiness {
  /// Brain model-list check returned OK, or STT configuration passed its
  /// kind/endpoint-presence check. Neither proves a successful first request.
  ready,

  /// Brain check failed or threw; other callers can also supply this label.
  unreachable,

  /// Brain URL empty, or HTTP STT URL absent/blank or STT settings load failed.
  notConfigured,
}

bool get _hebrewSpeech => Strings.speechLanguage.startsWith('he');

/// Caller-supplied permission and service snapshot for planning, not live probes.
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

  /// Caller brain status, normally the model-list check result.
  final ServiceReadiness brain;

  /// Caller STT status, normally configuration only, not transcription readiness.
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

/// Derives first-request suggestions and tutorial flags from supplied labels
/// and permission booleans (#226). It performs no provider or permission probe;
/// a ready input is not independent evidence of working transcription/inference.
class FirstSuccessPlan {
  const FirstSuccessPlan({
    required this.issues,
    required this.suggestedRequest,
    required this.screenQuestionAvailable,
    required this.pointingAvailable,
  });

  /// Builds the plan from [inputs] and the current speech-language preference.
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

  /// Issues implied by the snapshot; empty is not a successful-request proof.
  final List<ReadinessIssue> issues;

  /// The first thing to say, or null when something blocks it.
  final String? suggestedRequest;

  /// Snapshot permits a screen suggestion, not verified screen-answer quality.
  final bool screenQuestionAvailable;

  /// Snapshot permits pointing, not a live native action verification.
  final bool pointingAvailable;

  /// True when the supplied snapshot yields no issues, not a runtime guarantee.
  bool get voiceReady => issues.isEmpty;
}

/// Reads settings and runs the brain model-list check (#226), not chat/model
/// inference qualification. STT is configuration-only: HTTP requires a
/// nonblank endpoint; native kind is labelled ready even though its provider
/// is currently a not-installed placeholder. No STT reachability, credentials,
/// model, language or native capability is tested and no audio is sent here.
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
