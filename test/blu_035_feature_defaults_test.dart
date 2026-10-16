import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/mcp/home_assistant_adapter.dart';
import 'package:local_bluey/mcp/mcp_tool_safety_gate.dart';
import 'package:local_bluey/mcp/playwright_browser_adapter.dart';
import 'package:local_bluey/services/file_index.dart';
import 'package:local_bluey/services/voice_verification.dart';

void main() {
  test('ac1 fresh opt-in integrations remain disabled by default', () {
    final gate = McpToolSafetyGate(
      isServerAllowed: (_) => true,
      requestPermission: (_, _) async => false,
      invoke: (_, _, _) async => throw StateError('No invocation allowed'),
    );
    final fileIndex = FileIndex();
    final voice = VoiceVerifier(provider: _NoVoiceProvider());
    final home = HomeAssistantAdapter(
      serverId: 'local',
      allowedEntities: {'light.desk'},
      gate: gate,
      approve: (_, _) async => false,
      transport: (_, _) async => throw StateError('No dispatch allowed'),
      isLocalEndpoint: () => true,
      isOnline: () => true,
    );
    final browser = PlaywrightBrowserAdapter(
      gate: gate,
      transport: _NoBrowserTransport(),
      allowedDomains: {'example.org'},
    );

    expect(fileIndex.isEnabled, isFalse);
    expect(voice.enabled, isFalse);
    expect(home.enabled, isFalse);
    expect(browser.enabled, isFalse);
  });
}

final class _NoVoiceProvider implements VoiceEvidenceProvider {
  @override
  Future<bool> hasMicrophonePermission() async => false;

  @override
  Future<bool> isOfflineReady() async => false;

  @override
  Future<VoiceEvidence> assess(String enrollmentId) async {
    throw StateError('Consent not granted');
  }
}

final class _NoBrowserTransport implements BrowserTransport {
  @override
  Future<Object?> execute(BrowserRequest request) async {
    throw StateError('Feature disabled');
  }
}
