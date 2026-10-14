import 'llm_provider.dart';
import '../services/degraded.dart';

/// Selects providers without silently escalating to cloud endpoints.
class OfflineProviderFallbackPolicy {
  const OfflineProviderFallbackPolicy({
    required this.local,
    required this.cloud,
    required this.cloudEnabled,
  });

  final LlmProvider local;
  final LlmProvider cloud;
  final bool cloudEnabled;

  LlmProvider select() {
    if (!cloudEnabled) return local;
    return cloud;
  }

  Future<String> chat(List<LlmMessage> messages) async {
    try {
      return await select().chat(messages);
    } catch (_) {
      if (!identical(select(), local)) {
        try {
          return await local.chat(messages);
        } catch (_) {
          throw const OfflineProviderException(
            DegradedMode.brainUnreachable,
          );
        }
      }
      throw const OfflineProviderException(DegradedMode.brainUnreachable);
    }
  }
}

class OfflineProviderException implements Exception {
  const OfflineProviderException(this.mode);

  final DegradedMode mode;
}
