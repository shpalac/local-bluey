/// Result of a provider attempt without hiding failures.
sealed class OfflineProviderResult {
  const OfflineProviderResult();
}

class ProviderResponse extends OfflineProviderResult {
  const ProviderResponse(this.value);

  final String value;
}

class ProviderFailure extends OfflineProviderResult {
  const ProviderFailure(this.code);

  final String code;
}

/// Deterministic fallback boundary for local providers.
class OfflineProviderFallback {
  const OfflineProviderFallback({required this.localProviderAvailable});

  final bool localProviderAvailable;

  OfflineProviderResult execute(String prompt) {
    if (prompt.trim().isEmpty) {
      return const ProviderFailure('empty_input');
    }

    if (!localProviderAvailable) {
      return const ProviderFailure('local_provider_unavailable');
    }

    return ProviderResponse('local:$prompt');
  }
}
