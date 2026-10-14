import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/providers/offline_provider_fallback.dart';

void main() {
  test('offline fallback reports unavailable provider without egress', () {
    const fallback = OfflineProviderFallback(localProviderAvailable: false);

    final result = fallback.execute('hello');

    expect(result, isA<ProviderFailure>());
    expect((result as ProviderFailure).code, 'local_provider_unavailable');
  });

  test('offline fallback returns deterministic local response', () {
    const fallback = OfflineProviderFallback(localProviderAvailable: true);

    final result = fallback.execute('hello');

    expect(result, const TypeMatcher<ProviderResponse>());
    expect((result as ProviderResponse).value, 'local:hello');
  });

  test('offline fallback rejects malformed input explicitly', () {
    const fallback = OfflineProviderFallback(localProviderAvailable: true);

    final result = fallback.execute(' ');

    expect(result, isA<ProviderFailure>());
    expect((result as ProviderFailure).code, 'empty_input');
  });
}
