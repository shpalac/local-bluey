import 'dart:async';

/// What went wrong when the settings "Test connection" call failed (#239).
enum ConnectionFailureKind {
  refused,
  timeout,
  unreachableHost,
  tls,
  unauthorized,
  wrongPath,
  modelMissing,
  other,
}

/// A plain-language result for a failed connection test. [summary] is what
/// the user reads; [details] keeps the raw error for a "Details" expander.
class ConnectionFailure {
  const ConnectionFailure({
    required this.kind,
    required this.summary,
    required this.details,
    required this.target,
  });

  final ConnectionFailureKind kind;
  final String summary;
  final String details;

  /// host:port the test aimed at, taken from the configured Base URL.
  final String target;

  /// True when starting or detecting a local server could fix it.
  bool get suggestsLocalServer =>
      kind == ConnectionFailureKind.refused ||
      kind == ConnectionFailureKind.timeout;
}

/// The host:port of [baseUrl], with the scheme's default port when none is
/// set. Never the client's ephemeral port. Falls back to the raw text.
String connectionTarget(String baseUrl) {
  final uri = Uri.tryParse(baseUrl.trim());
  if (uri == null || uri.host.isEmpty) return baseUrl.trim();
  final port = uri.hasPort
      ? uri.port
      : (uri.scheme == 'https' ? 443 : (uri.scheme == 'http' ? 80 : null));
  return port == null ? uri.host : '${uri.host}:$port';
}

bool _isLocalTarget(String baseUrl) {
  final host = Uri.tryParse(baseUrl.trim())?.host.toLowerCase() ?? '';
  return host == 'localhost' || host == '127.0.0.1' || host == '::1';
}

final _statusPattern = RegExp(r'^(?:Ollama|OpenAI-compatible)\s+(\d{3})\b');

/// Maps [error] from a connection test against [baseUrl] to a message that
/// names the real target and the next step, without exception internals.
ConnectionFailure describeConnectionFailure(Object error, String baseUrl) {
  final raw = error.toString();
  final lower = raw.toLowerCase();
  final target = connectionTarget(baseUrl);
  final local = _isLocalTarget(baseUrl);

  ConnectionFailure result(ConnectionFailureKind kind, String summary) =>
      ConnectionFailure(
        kind: kind,
        summary: summary,
        details: raw,
        target: target,
      );

  if (error is TimeoutException || lower.contains('timed out')) {
    return result(
      ConnectionFailureKind.timeout,
      'No answer from $target in time. Check that the server is running and '
      'the address is right.',
    );
  }
  if (lower.contains('connection refused') ||
      lower.contains('errno = 61') ||
      lower.contains('errno = 111') ||
      lower.contains('errno = 1225')) {
    return result(
      ConnectionFailureKind.refused,
      local
          ? 'Nothing is listening at $target. Start your local model server '
                '(for example "ollama serve"), or pick another endpoint.'
          : 'The server at $target refused the connection. Check the address '
                'and that the server is running.',
    );
  }
  if (lower.contains('failed host lookup') ||
      lower.contains('nodename nor servname') ||
      lower.contains('name or service not known')) {
    return result(
      ConnectionFailureKind.unreachableHost,
      'Could not find the host in $target. Check the spelling of the Base URL '
      'and your network.',
    );
  }
  if (lower.contains('handshakeexception') ||
      lower.contains('certificate_verify_failed') ||
      lower.contains('tlsexception')) {
    return result(
      ConnectionFailureKind.tls,
      'A secure connection to $target could not be set up. Check that the '
      'address should use https and that the certificate is valid.',
    );
  }

  final status = int.tryParse(_statusPattern.firstMatch(raw)?.group(1) ?? '');
  if (status == 401 || status == 403) {
    return result(
      ConnectionFailureKind.unauthorized,
      '$target rejected the API key (HTTP $status). Check the key in Brain '
      'settings.',
    );
  }
  if (status == 404) {
    if (lower.contains('model')) {
      return result(
        ConnectionFailureKind.modelMissing,
        '$target is running but does not have that model. Check the Model '
        'name, or pull the model first.',
      );
    }
    return result(
      ConnectionFailureKind.wrongPath,
      '$target answered, but not at that path (HTTP 404). Check the Base URL, '
      'it often needs to end in /v1.',
    );
  }
  if (status != null) {
    return result(
      ConnectionFailureKind.other,
      '$target answered with an error (HTTP $status). Open Details for the '
      'server message.',
    );
  }
  return result(
    ConnectionFailureKind.other,
    'The connection test to $target failed. Open Details for the raw error.',
  );
}
