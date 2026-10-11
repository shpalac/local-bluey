import 'dart:convert';

/// A parsed canonical localbluey:// action identifier (#91).
/// Parsing does not deliver a URL, dispatch work or enforce tool safety.
/// Current app sources have no incoming URL registration or consumer.
class DeepLink {
  const DeepLink(this.action, [this.text]);

  /// One of [DeepLinks.allowedActions].
  final String action;

  /// Optional payload (e.g. the question for 'ask').
  final String? text;
}

/// Validation only for canonical localbluey:// links.
class DeepLinks {
  DeepLinks._();

  /// The scheme accepted by this parser, not registered by the current app.
  static const scheme = 'localbluey';

  /// Accepted action identifiers, not authorization to run them.
  /// Future dispatch needs explicit request, safety and lifetime contracts.
  static const allowedActions = {
    'ask',
    'wake',
    'sleep',
    'stop',
    'mute',
    'status',
  };

  /// Maximum encoded link length, in ASCII code units.
  static const maxInputLength = 8192;

  /// Maximum decoded ask payload, measured in UTF-8 bytes.
  static const maxAskBytes = 2048;

  /// Parses only canonical localbluey://action links. Ask requires exactly
  /// one literal text query key. Invalid encoding or extra syntax rejects
  /// the entire link; parsing never dispatches actions or changes text.
  static DeepLink? parse(String url) {
    if (url.length > maxInputLength) return null;
    final match = RegExp(
      r'^localbluey://(ask|wake|sleep|stop|mute|status)(?:\?text=([^#]*))?$',
    ).firstMatch(url);
    // RegExp's dollar anchor may precede a final newline; require full input.
    if (match == null || match.end != url.length) return null;
    final action = match[1]!;
    final encoded = match[2];
    if (action != 'ask') {
      return encoded == null ? DeepLink(action) : null;
    }
    if (encoded == null || encoded.contains('&') || encoded.contains('=')) {
      return null;
    }
    // No literal whitespace/non-ASCII: callers must percent-encode text.
    if (encoded.codeUnits.any((c) => c <= 32 || c >= 127)) return null;
    try {
      // Reject invalid percent triplets before decoding. decodeQueryComponent
      // also rejects malformed UTF-8 and preserves intended + space semantics.
      for (var i = 0; i < encoded.length; i++) {
        if (encoded[i] != '%') continue;
        if (i + 2 >= encoded.length ||
            !RegExp(r'^[0-9A-Fa-f]{2}$')
                .hasMatch(encoded.substring(i + 1, i + 3))) {
          return null;
        }
        i += 2;
      }
      final text = Uri.decodeQueryComponent(encoded, encoding: utf8);
      if (text.trim().isEmpty || utf8.encode(text).length > maxAskBytes) {
        return null;
      }
      return DeepLink(action, text);
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }
}
