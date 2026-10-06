/// localbluey:// deep links (#91): a small validated action set. Every
/// action goes through the same request path as the face gesture; risky,
/// confirm-required actions are never triggered silently (#19, #57).
/// A parsed localbluey:// link (#91).
class DeepLink {
  const DeepLink(this.action, [this.text]);

  /// One of [DeepLinks.allowedActions].
  final String action;

  /// Optional payload (e.g. the question for 'ask').
  final String? text;
}

/// Validation + dispatch for localbluey:// links.
class DeepLinks {
  DeepLinks._();

  /// The URL scheme the app registers.
  static const scheme = 'localbluey';

  /// Safe, silent actions only. Anything that could control the computer
  /// or spend resources stays behind the in-app confirmation flow (#19).
  static const allowedActions = {
    'ask',
    'wake',
    'sleep',
    'stop',
    'mute',
    'status',
  };

  /// Parses and validates a deep link; null when invalid (#91).
  static DeepLink? parse(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != scheme) return null;
    final action = uri.host.isNotEmpty
        ? uri.host
        : uri.pathSegments.isNotEmpty
        ? uri.pathSegments.first
        : null;
    if (action == null || !allowedActions.contains(action)) return null;
    final text = uri.queryParameters['text'];
    // 'ask' without text cannot do anything - reject instead of guessing.
    if (action == 'ask' && (text == null || text.trim().isEmpty)) return null;
    return DeepLink(action, text);
  }
}
