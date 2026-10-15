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
      final response = await select().chat(messages);
      if (response.trim().isEmpty) throw StateError('Empty provider response');
      return response;
    } catch (_) {
      if (!identical(select(), local)) {
        try {
          final response = await local.chat(messages);
          if (response.trim().isEmpty) throw StateError('Empty local response');
          return response;
        } catch (_) {
          throw const OfflineProviderException(DegradedMode.brainUnreachable);
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
