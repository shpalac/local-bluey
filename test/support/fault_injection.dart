import 'dart:async';
import 'dart:io';

/// The faults BLU-054 simulates. Every fault is deterministic and
/// in-process: no real disk is filled, no process is killed, no OS
/// permission is touched.
enum Fault {
  /// ENOSPC from a write.
  diskFull,

  /// An unexpected error type, as from a crashed or corrupted dependency.
  crash,

  /// A TimeoutException from an operation that gave up.
  timeout,

  /// EACCES, as after the OS permission was revoked mid-run.
  permissionRevoked,

  /// The operation never completes (a hung dependency).
  hang,
}

/// A scripted sequence of outcomes for one operation. Call [next] once per
/// attempt: `null` means success, a [Fault] means that fault. After the
/// script runs out every further attempt succeeds, so a retry after the
/// fault clears is modelled by simply calling again.
///
/// The thrown objects carry a fake secret path in their message on purpose,
/// so tests can prove callers never copy exception text into results.
class FaultPlan {
  FaultPlan(Iterable<Fault?> script) : _script = List.of(script);

  /// Always succeeds.
  FaultPlan.none() : _script = const [];

  /// The same fault on the first [times] attempts, then success.
  FaultPlan.first(Fault fault, {int times = 1})
    : _script = List.filled(times, fault);

  static const secretPath = '/home/fake-user/FAKE-SECRET-PATH/notes.db';

  final List<Fault?> _script;
  int attempts = 0;

  /// Runs one attempt: throws the scripted fault, hangs, or returns.
  Future<void> attempt() async {
    final step = attempts < _script.length ? _script[attempts] : null;
    attempts++;
    switch (step) {
      case null:
        return;
      case Fault.diskFull:
        throw const FileSystemException(
          'No space left on device: $secretPath',
          secretPath,
          OSError('No space left on device', 28),
        );
      case Fault.crash:
        throw StateError('crashed near $secretPath');
      case Fault.timeout:
        throw TimeoutException('timed out near $secretPath');
      case Fault.permissionRevoked:
        throw const FileSystemException(
          'Permission denied: $secretPath',
          secretPath,
          OSError('Permission denied', 13),
        );
      case Fault.hang:
        await Completer<void>().future;
    }
  }
}
