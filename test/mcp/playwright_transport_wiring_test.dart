import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/mcp/mcp_tool_safety_gate.dart';
import 'package:local_bluey/mcp/playwright_browser_adapter.dart';

void main() {
  final url = Uri.parse('https://example.org/research');
  late int transportCalls;
  late int legacyInvokerCalls;
  late bool permissionGranted;
  late PlaywrightBrowserAdapter adapter;

  setUp(() {
    transportCalls = 0;
    legacyInvokerCalls = 0;
    permissionGranted = true;
    adapter = PlaywrightBrowserAdapter(
      enabled: true,
      allowedDomains: {'example.org'},
      gate: McpToolSafetyGate(
        isServerAllowed: (server) => server == 'playwright-local',
        requestPermission: (_, _) async => permissionGranted,
        invoke: (_, _, _) async {
          legacyInvokerCalls++;
          throw StateError('unrelated gate invoker must never run');
        },
      ),
      transport: _RecordingTransport((request) async {
        transportCalls++;
        return {
          'url': request.url.toString(),
          'text': 'untrusted browser text',
        };
      }),
    );
  });

  Future<BrowserResult> execute(Uri target) => adapter.execute(
    request: BrowserRequest(action: BrowserAction.navigate, url: target),
    session: BrowserSession(),
    timeout: const Duration(seconds: 1),
  );

  test('AC-1 blocked domain cannot reach injected transport', () async {
    await expectLater(
      execute(Uri.parse('https://example.org.attacker.test/')),
      throwsA(isA<BrowserException>().having(
        (error) => error.reason,
        'reason',
        BrowserFailure.blockedDomain,
      )),
    );
    expect(transportCalls, 0);
    expect(legacyInvokerCalls, 0);
  });

  test('AC-2 approved navigation uses injected transport', () async {
    final result = await execute(url);
    expect(result.url, url);
    expect(result.untrustedText, 'untrusted browser text');
    expect(transportCalls, 1);
    expect(legacyInvokerCalls, 0);
  });

  test('AC-2 denied permission never invokes transport', () async {
    permissionGranted = false;
    await expectLater(
      execute(url),
      throwsA(isA<BrowserException>().having(
        (error) => error.reason,
        'reason',
        BrowserFailure.denied,
      )),
    );
    expect(transportCalls, 0);
    expect(legacyInvokerCalls, 0);
  });
}

class _RecordingTransport implements BrowserTransport {
  const _RecordingTransport(this.onExecute);

  final Future<Object?> Function(BrowserRequest request) onExecute;

  @override
  Future<Object?> execute(BrowserRequest request) => onExecute(request);
}
