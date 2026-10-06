import 'watch_pipeline.dart';

/// What the user seems to be doing, derived from the watch event stream
/// (#214). A guess with a confidence - and uncertain means silent.
/// The layer's best guess at what the user is currently doing (#214).
class TaskContext {
  const TaskContext({
    required this.app,
    required this.category,
    required this.confidence,
    this.detail = '',
  });

  /// The frontmost app this context belongs to.
  final String app;

  /// Coarse activity bucket: coding, browsing, writing, terminal, media,
  /// communication, other.
  final String category;

  /// 0..1. Below [WatchContext.confidentEnough] the layer stays silent.
  final double confidence;

  /// Optional human-readable detail for the UI.
  final String detail;
}

/// Turns the rolling event buffer into the current task context (#214).
/// Rule-based on purpose: no model call for this, and every rule is
/// explainable from the events it read.
class WatchContext {
  WatchContext._();

  /// Suggestions require at least this confidence (#214).
  static const confidentEnough = 0.6;

  static const _categories = {
    'coding': {
      'xcode',
      'visual studio code',
      'vscode',
      'android studio',
      'intellij idea',
      'cursor',
      'zed',
    },
    'terminal': {'terminal', 'iterm', 'iterm2', 'warp', 'alacritty'},
    'browsing': {
      'safari',
      'google chrome',
      'firefox',
      'arc',
      'microsoft edge',
      'orion',
      'brave browser',
    },
    'writing': {
      'pages',
      'microsoft word',
      'google docs',
      'notion',
      'obsidian',
      'bear',
    },
    'communication': {
      'messages',
      'whatsapp',
      'slack',
      'telegram',
      'microsoft teams',
      'zoom',
    },
    'media': {'music', 'spotify', 'quicktime player', 'vlc', 'tv', 'photos'},
  };

  /// Infers context from recent events. Returns null when there is not
  /// enough signal - the caller must treat that as "stay quiet" (#214).
  static TaskContext? infer(List<WatchEvent> recent) {
    if (recent.isEmpty) return null;
    final last = recent.last;
    final app = last.app.toLowerCase();

    String category = 'other';
    for (final entry in _categories.entries) {
      if (entry.value.contains(app)) {
        category = entry.key;
        break;
      }
    }

    // Confidence: categorized app with a stable title = high; known app
    // with a flickering title = medium; unknown app = too low to act on.
    final titles = recent
        .where((e) => e.kind == WatchEventKind.appSwitch)
        .map((e) => e.detail)
        .toList();
    final stableTitle =
        titles.isEmpty || titles.every((t) => t == titles.first);
    if (category == 'other') return null;
    final confidence = stableTitle ? 0.8 : 0.65;
    return TaskContext(
      app: last.app,
      category: category,
      confidence: confidence,
      detail: titles.isEmpty ? '' : titles.first,
    );
  }
}
