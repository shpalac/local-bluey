import 'dart:async';

import 'workflow_dsl.dart';
import 'workflow_execution.dart';

/// Only [confirmed] permits a workflow to advance.
enum VerificationOutcome { confirmed, rejected, inconclusive, cancelled }

enum PostconditionKind { accessibility, artifact, toolResponse }

/// Describes an expected observable value without storing observed secrets.
final class Postcondition {
  const Postcondition({
    required this.kind,
    required this.key,
    required this.expected,
  });

  final PostconditionKind kind;
  final String key;
  final String expected;

  factory Postcondition.parse(String source) {
    final first = source.indexOf(':');
    final second = source.indexOf('=', first + 1);
    if (first <= 0 || second <= first + 1 || second == source.length - 1) {
      throw const FormatException('Expected kind:key=value');
    }
    final kind = switch (source.substring(0, first)) {
      'ax' => PostconditionKind.accessibility,
      'file' => PostconditionKind.artifact,
      'tool' => PostconditionKind.toolResponse,
      _ => throw const FormatException('Unsupported postcondition kind'),
    };
    final key = source.substring(first + 1, second).trim();
    final expected = source.substring(second + 1).trim();
    if (key.isEmpty ||
        expected.isEmpty ||
        key.contains('..') ||
        key.contains('/') ||
        key.contains('\\')) {
      throw const FormatException('Invalid postcondition key or value');
    }
    return Postcondition(kind: kind, key: key, expected: expected);
  }
}

/// An adapter supplies already-authorized, local observations only.
/// Returning null means unavailable evidence (including offline/permission errors).
abstract interface class PostconditionReader {
  Future<String?> read(Postcondition condition);
}

/// Cancellation is cooperative. Late observations never confirm a cancelled run.
final class VerificationCancellation {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// Memory-only verifier: never performs actions, network requests or persistence.
final class PostconditionVerifier {
  const PostconditionVerifier(this.reader);

  final PostconditionReader reader;

  Future<VerificationOutcome> verify(
    List<Postcondition> conditions, {
    required Duration timeout,
    VerificationCancellation? cancellation,
  }) async {
    if (cancellation?.isCancelled ?? false) {
      return VerificationOutcome.cancelled;
    }
    if (conditions.isEmpty || timeout <= Duration.zero) {
      return VerificationOutcome.inconclusive;
    }
    // A timeout is terminal for this verification even when a reader's
    // outstanding Future cannot be interrupted. Never issue the next read.
    final timedOut = VerificationCancellation();
    VerificationOutcome onTimeout() {
      timedOut.cancel();
      return VerificationOutcome.inconclusive;
    }

    try {
      final result = await _check(
        conditions,
        cancellation,
        timedOut,
      ).timeout(timeout, onTimeout: onTimeout);
      if (cancellation?.isCancelled ?? false) {
        return VerificationOutcome.cancelled;
      }
      return result;
    } catch (_) {
      return (cancellation?.isCancelled ?? false)
          ? VerificationOutcome.cancelled
          : VerificationOutcome.inconclusive;
    }
  }

  Future<VerificationOutcome> _check(
    List<Postcondition> conditions,
    VerificationCancellation? cancellation,
    VerificationCancellation timedOut,
  ) async {
    for (final condition in conditions) {
      if (timedOut.isCancelled) return VerificationOutcome.inconclusive;
      if (cancellation?.isCancelled ?? false) {
        return VerificationOutcome.cancelled;
      }
      final observed = await reader.read(condition);
      if (timedOut.isCancelled) return VerificationOutcome.inconclusive;
      if (cancellation?.isCancelled ?? false) {
        return VerificationOutcome.cancelled;
      }
      // Empty observations are missing evidence, never proof of failure or success.
      if (observed == null || observed.trim().isEmpty) {
        return VerificationOutcome.inconclusive;
      }
      if (observed != condition.expected) {
        return VerificationOutcome.rejected;
      }
    }
    return VerificationOutcome.confirmed;
  }
}

/// Opt-in bridge for the existing WorkflowHost API. No action is issued here.
final class VerifyingWorkflowHost implements WorkflowHost {
  VerifyingWorkflowHost({
    required this.delegate,
    required this.verifier,
    required this.postconditions,
    required this.timeout,
    this.cancellation,
  });

  final WorkflowHost delegate;
  final PostconditionVerifier verifier;
  final List<Postcondition> postconditions;
  final Duration timeout;
  final VerificationCancellation? cancellation;

  @override
  Future<bool> approve(WorkflowStep step) => delegate.approve(step);

  @override
  Future<void> execute(WorkflowStep step) => delegate.execute(step);

  @override
  Future<bool> verify(WorkflowStep step) async {
    // Preserve legacy host verification; never replace its safety checks.
    if (!await delegate.verify(step)) return false;
    return await verifier.verify(
          postconditions,
          timeout: timeout,
          cancellation: cancellation,
        ) ==
        VerificationOutcome.confirmed;
  }
}
