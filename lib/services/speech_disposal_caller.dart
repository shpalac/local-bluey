import 'dart:async';

import 'speech.dart';

/// Terminal caller completion, not proof of playback stop or file erasure.
/// Invokes the retained owner immediately once, without retry or late UI.
class SpeechDisposalCaller {
  SpeechDisposalCaller({required SpeechService owner})
    : _dispose = owner.dispose;

  /// Invocation seam for synchronous failure and reentrant caller fixtures.
  SpeechDisposalCaller.operation(this._dispose);

  final Future<void> Function() _dispose;
  Future<void>? _completion;

  Future<void> dispose() {
    final completion = _completion;
    if (completion != null) return completion;
    final done = Completer<void>();
    _completion = done.future;
    // Install before invoking: owner terminal invalidation is immediate and
    // reentrant callers join, even if invocation throws synchronously.
    try {
      final ownerWork = _dispose();
      ownerWork.then<void>(
        (_) => done.complete(),
        onError: (Object _, StackTrace _) => done.complete(),
      );
    } catch (_) {
      done.complete();
    }
    return done.future;
  }
}
