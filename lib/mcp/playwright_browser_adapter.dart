import 'dart:async';

import 'mcp_tool_safety_gate.dart';

/// Deliberately no browser process, network client, or persistent storage.
/// Callers inject a trusted MCP transport after explicit feature opt-in.
enum BrowserFailure {
  disabled,
  invalidInput,
  blockedDomain,
  denied,
  offline,
  timeout,
  cancelled,
  untrustedResponse,
}

class BrowserException implements Exception {
  const BrowserException(this.reason);
  final BrowserFailure reason;
  @override
  String toString() => 'Browser operation unavailable: ${reason.name}';
}

enum BrowserAction { navigate, snapshot }

class BrowserRequest {
  const BrowserRequest({required this.action, required this.url});
  final BrowserAction action;
  final Uri url;
}

class BrowserResult {
  const BrowserResult({required this.url, required this.untrustedText});
  final Uri url;

  /// Never pass this value into an instruction, tool call, or approval policy.
  final String untrustedText;
}

abstract interface class BrowserTransport {
  Future<Object?> execute(BrowserRequest request);
}

/// Revoking a session also invalidates any pending earlier response.
class BrowserSession {
  int _generation = 0;
  bool _cancelled = false;

  int get generation => _generation;
  bool get cancelled => _cancelled;

  void cancel() {
    _cancelled = true;
    _generation++;
  }

  void restart() {
    _cancelled = false;
    _generation++;
  }
}

/// Local, opt-in boundary for read-only Playwright MCP browser capabilities.
class PlaywrightBrowserAdapter {
  PlaywrightBrowserAdapter({
    required this.gate,
    required this.transport,
    required Set<String> allowedDomains,
    this.enabled = false,
    this.online = true,
    this.maxTextLength = 16384,
  }) : _allowedDomains = Set.unmodifiable(
         allowedDomains.map((domain) => domain.toLowerCase()),
       );

  final McpToolSafetyGate gate;
  final BrowserTransport transport;
  final Set<String> _allowedDomains;
  final bool enabled;
  final bool online;
  final int maxTextLength;

  static final _hostPattern = RegExp(r'^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?$');
  static final _ipv4Pattern = RegExp(r'^\d+\.\d+\.\d+\.\d+$');

  static final _navigateSpec = McpToolSpec(
    name: 'browser_navigate',
    description: 'Navigate to a permitted HTTPS webpage (read-only).',
    inputSchema: {
      'type': 'object',
      'properties': {
        'url': {'type': 'string'},
      },
      'required': ['url'],
    },
  );

  static final _snapshotSpec = McpToolSpec(
    name: 'browser_snapshot',
    description: 'Read untrusted page text from an approved HTTPS origin.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'url': {'type': 'string'},
      },
      'required': ['url'],
    },
  );

  bool _isAllowed(Uri url) {
    final host = url.host.toLowerCase();
    if (url.scheme != 'https' ||
        url.userInfo.isNotEmpty ||
        url.hasFragment ||
        url.port != 443 ||
        host.isEmpty ||
        !_hostPattern.hasMatch(host) ||
        host.contains('..') ||
        host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local') ||
        host.endsWith('.internal') ||
        _ipv4Pattern.hasMatch(host) ||
        host.contains(':')) {
      return false;
    }
    return _allowedDomains.any(
      (domain) =>
          domain.contains('.') &&
          !_ipv4Pattern.hasMatch(domain) &&
          !domain.contains('..') &&
          _hostPattern.hasMatch(domain) &&
          (host == domain || host.endsWith('.$domain')),
    );
  }

  Future<BrowserResult> execute({
    required BrowserRequest request,
    required BrowserSession session,
    required Duration timeout,
  }) async {
    if (!enabled) throw const BrowserException(BrowserFailure.disabled);
    if (session.cancelled) {
      throw const BrowserException(BrowserFailure.cancelled);
    }
    if (timeout <= Duration.zero || maxTextLength <= 0) {
      throw const BrowserException(BrowserFailure.invalidInput);
    }
    if (!online) throw const BrowserException(BrowserFailure.offline);
    final url = request.url;
    if (!_isAllowed(url)) {
      throw const BrowserException(BrowserFailure.blockedDomain);
    }

    final initialGeneration = session.generation;
    try {
      final spec = request.action == BrowserAction.navigate
          ? _navigateSpec
          : _snapshotSpec;
      final value = await gate.execute(
        serverId: 'playwright-local',
        spec: spec,
        arguments: {'url': url.toString()},
        timeout: timeout,
      );
      // The gate's invoker must be wired by the host to the injected
      // transport; returned page content is never executable instructions.
      if (session.cancelled || session.generation != initialGeneration) {
        throw const BrowserException(BrowserFailure.cancelled);
      }
      if (value is! Map ||
          value['url'] is! String ||
          value['text'] is! String) {
        throw const BrowserException(BrowserFailure.untrustedResponse);
      }
      final returnedUrl = Uri.tryParse(value['url'] as String);
      if (returnedUrl == null ||
          !_isAllowed(returnedUrl) ||
          returnedUrl.host != url.host) {
        throw const BrowserException(BrowserFailure.blockedDomain);
      }
      final text = value['text'] as String;
      if (text.length > maxTextLength) {
        throw const BrowserException(BrowserFailure.untrustedResponse);
      }
      return BrowserResult(url: returnedUrl, untrustedText: text);
    } on McpToolException catch (error) {
      throw BrowserException(switch (error.reason) {
        McpToolFailure.timeout => BrowserFailure.timeout,
        McpToolFailure.offline => BrowserFailure.offline,
        McpToolFailure.cancelled => BrowserFailure.cancelled,
        McpToolFailure.denied => BrowserFailure.denied,
        _ => BrowserFailure.invalidInput,
      });
    }
  }
}
