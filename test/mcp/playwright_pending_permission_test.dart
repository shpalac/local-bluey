import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/mcp/mcp_tool_safety_gate.dart';
import 'package:local_bluey/mcp/playwright_browser_adapter.dart';

void main() {
  test(
    'ac2 cancellation while permission pending blocks late transport',
    () async {
      final entered = Completer<void>();
      final permission = Completer<bool>();
      var transportCalls = 0;
      final session = BrowserSession();
      final url = Uri.parse('https://example.org/page');
      final adapter = PlaywrightBrowserAdapter(
        enabled: true,
        allowedDomains: {'example.org'},
        gate: McpToolSafetyGate(
          isServerAllowed: (_) => true,
          requestPermission: (_, _) {
            entered.complete();
            return permission.future;
          },
          invoke: (_, _, _) async => throw StateError('Unsafe invoker'),
        ),
        transport: _Transport((_) async {
          transportCalls++;
          return {'url': url.toString(), 'text': 'content'};
        }),
      );

      final pending = adapter.execute(
        request: BrowserRequest(action: BrowserAction.navigate, url: url),
        session: session,
        timeout: const Duration(seconds: 1),
      );
      await entered.future;
      session.cancel();

      await expectLater(
        pending,
        throwsA(
          isA<BrowserException>().having(
            (error) => error.reason,
            'reason',
            BrowserFailure.cancelled,
          ),
        ),
      );
      permission.complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(transportCalls, 0);
    },
  );

  test('ac2 restart invalidates an older outstanding approval', () async {
    final entered = Completer<void>();
    final permission = Completer<bool>();
    var transportCalls = 0;
    final session = BrowserSession();
    final url = Uri.parse('https://example.org/');
    final adapter = PlaywrightBrowserAdapter(
      enabled: true,
      allowedDomains: {'example.org'},
      gate: McpToolSafetyGate(
        isServerAllowed: (_) => true,
        requestPermission: (_, _) {
          entered.complete();
          return permission.future;
        },
        invoke: (_, _, _) async => null,
      ),
      transport: _Transport((_) async {
        transportCalls++;
        return {'url': url.toString(), 'text': 'content'};
      }),
    );
    final pending = adapter.execute(
      request: BrowserRequest(action: BrowserAction.snapshot, url: url),
      session: session,
      timeout: const Duration(seconds: 1),
    );
    await entered.future;
    session.restart();
    await expectLater(
      pending,
      throwsA(
        isA<BrowserException>().having(
          (error) => error.reason,
          'reason',
          BrowserFailure.cancelled,
        ),
      ),
    );
    permission.complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(transportCalls, 0);
  });
}

final class _Transport implements BrowserTransport {
  const _Transport(this.callback);
  final Future<Object?> Function(BrowserRequest request) callback;

  @override
  Future<Object?> execute(BrowserRequest request) => callback(request);
}
