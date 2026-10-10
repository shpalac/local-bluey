import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../link/models.dart';

/// One clip's playback session (#372). A session plays exactly one clip and
/// owns its completion stream, so a late event from a replaced clip can never
/// be mistaken for the current one. Injectable so fixtures drive start,
/// completion and failure without a device.
abstract class ReplySession {
  /// Fires when this session's clip finishes.
  Stream<void> get completions;

  /// Starts playing the file at [path].
  Future<void> play(String path);

  /// Stops playback; throws when stopping could not be confirmed.
  Future<void> stop();

  /// Releases the session.
  Future<void> dispose();
}

/// [ReplySession] over its own audioplayers player.
class AudioplayersReplySession implements ReplySession {
  /// Creates a session with a fresh player.
  AudioplayersReplySession({AudioPlayer? player})
    : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  @override
  Stream<void> get completions => _player.onPlayerComplete;

  @override
  Future<void> play(String path) => _player.play(DeviceFileSource(path));

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

class _Clip {
  _Clip(this.file, this.session, this.ticket, this.speech);
  final File file;
  final ReplySession session;
  final int ticket;
  final int? speech;

  /// Completes true on natural completion, false when the clip is retired
  /// (cancelled) so the waiter never outlives its resources.
  final finished = Completer<bool>();

  /// Completes true once play succeeded and the playing receipt was handled,
  /// false when the start failed or was superseded.
  final started = Completer<bool>();
  StreamSubscription<void>? subscription;

  /// Audio may be playing: set before play starts, cleared by natural
  /// completion or by stop/dispose evidence.
  bool live = false;
  bool playingSent = false;
  bool subscriptionCancelled = false;
  bool sessionDisposed = false;
  bool fileRemoved = false;
}

/// Phone-side owner of Mac reply audio (#372): guarded intake, unique clip
/// files, latest-wins ordered playback, receipts tied to real playback, and
/// cleanup on completion, replacement, failure, stopSpeech and dispose. The
/// audio stays opaque (the host sends MP3); nothing here validates it as a
/// codec stream. Every entry point contains its own errors.
///
/// A clip's resources (live audio, subscription, session, file) are released
/// only on evidence: natural completion, or a confirmed stop/dispose.
/// Anything unconfirmed stays tracked in [cleanupPending] and is retried on
/// the next release, and no replacement audio starts over it.
class PhoneReplyReceiver {
  /// Creates the receiver. The remaining parameters are test seams.
  PhoneReplyReceiver({
    required this.createSession,
    required this.send,
    required this.showText,
    this.isActive = _always,
    this.tempDir,
    this.write,
    this.delete,
  });

  /// Short user-safe note shown while reply audio is still being released.
  static const cleanupNote = 'Reply audio cleanup is still pending.';

  /// Largest accepted decoded reply; the link frame cap is 16 MiB.
  static const maxBytes = 12 * 1024 * 1024;

  /// Creates one playback session per clip.
  final ReplySession Function() createSession;

  /// Sends a receipt packet to the Mac.
  final void Function(Packet packet) send;

  /// Shows the reply text, or the text with a short safe note on failure.
  final void Function(String text) showText;

  /// False once the owner is disposed: no UI callback or receipt may follow.
  final bool Function() isActive;

  /// Temp directory (null = the platform temp directory).
  final Future<Directory> Function()? tempDir;

  /// Writes a clip (null = write and flush).
  final Future<void> Function(File file, List<int> bytes)? write;

  /// Deletes a clip (null = File.delete).
  final Future<void> Function(File file)? delete;

  static bool _always() => true;
  static int _sequence = 0;

  int _generation = 0;
  Future<void> _ops = Future<void>.value();
  _Clip? _current;
  bool _disposed = false;
  bool _notifierClosed = false;
  final _stuck = <_Clip>[];

  /// Number of clips with unreleased resources (unconfirmed stop, failed
  /// dispose/cancel or failed delete), retried on the next release. Not an
  /// erasure guarantee. After dispose it reaches 0 only once they resolve.
  final ValueNotifier<int> cleanupPending = ValueNotifier<int>(0);

  void _publishPending() {
    if (_notifierClosed) return;
    final count = _stuck.length;
    if (cleanupPending.value != count) cleanupPending.value = count;
    if (_disposed && count == 0) {
      _notifierClosed = true;
      cleanupPending.dispose();
    }
  }

  /// Completes when no queued operation is pending (test seam). Follow-up
  /// work scheduled by a finished operation is awaited too.
  @visibleForTesting
  Future<void> get idle async {
    Future<void> last;
    do {
      last = _ops;
      await last;
      await Future<void>.delayed(Duration.zero);
    } while (!identical(last, _ops));
  }

  /// Handles one packet from the Mac without throwing.
  void handle(Packet packet) {
    try {
      if (_disposed) return;
      if (packet.command == 'stopSpeech') {
        _generation++;
        _enqueue(_release);
        return;
      }
      if (packet.command == 'say' && packet.text != null) {
        final ticket = ++_generation;
        final text = packet.text!;
        if (isActive()) showText(text);
        final audio = packet.audio;
        if (audio == null) {
          // Text-only reply: display is the receipt (#87).
          _enqueue(() async {
            await _release();
            if (_isCurrent(ticket) && isActive()) {
              send(Packet(command: 'done', speech: packet.speech));
            }
          });
          return;
        }
        _enqueue(() => _start(packet, text, audio, ticket));
      }
    } catch (e) {
      debugPrint('PhoneReplyReceiver: $e');
    }
  }

  void _enqueue(Future<void> Function() op) {
    _ops = _ops.then((_) => op()).catchError((Object e) {
      debugPrint('PhoneReplyReceiver: $e');
    });
  }

  bool _isCurrent(int ticket) => ticket == _generation && !_disposed;

  Future<void> _start(
    Packet packet,
    String text,
    String encoded,
    int ticket,
  ) async {
    if (!await _release()) {
      _fail(ticket, text, 'The previous reply audio could not be stopped.');
      return;
    }
    if (!_isCurrent(ticket)) return;
    _Clip? clip;
    try {
      final bytes = _decode(encoded);
      if (bytes == null) {
        _fail(ticket, text, 'Reply audio was not valid and was not played.');
        return;
      }
      final file = await _newFile();
      clip = _Clip(file, createSession(), ticket, packet.speech);
      _current = clip;
      try {
        await (write ?? (f, b) => f.writeAsBytes(b, flush: true))(file, bytes);
      } catch (_) {
        await _settle(clip);
        _fail(ticket, text, 'Could not save the reply audio.');
        return;
      }
      if (!_isCurrent(ticket)) {
        await _settle(clip);
        return;
      }
      // Subscribe before starting so an immediate completion is not lost, and
      // observe completion for every entered session, whatever happens next.
      final owned = clip;
      clip.subscription = clip.session.completions.listen((_) {
        if (!owned.finished.isCompleted) owned.finished.complete(true);
      });
      unawaited(_awaitCompletion(owned));
      clip.live = true;
      try {
        await clip.session.play(file.path);
      } catch (_) {
        // Play may have started natively before it threw: stop evidence is
        // required before anything is released.
        await _settle(clip);
        _fail(ticket, text, 'Could not play the reply audio.');
        return;
      }
      if (!_isCurrent(ticket)) {
        // Superseded while starting: no receipt; the release queued behind
        // this turn (or dispose) retires the clip.
        return;
      }
      clip.playingSent = true;
      try {
        if (isActive()) send(Packet(command: 'playing', speech: packet.speech));
      } catch (e) {
        debugPrint('PhoneReplyReceiver: $e');
      }
      if (!clip.started.isCompleted) clip.started.complete(true);
    } catch (e) {
      debugPrint('PhoneReplyReceiver: $e');
      if (clip != null) await _settle(clip);
      _fail(ticket, text, 'Could not play the reply audio.');
    } finally {
      if (clip != null && !clip.started.isCompleted) {
        clip.started.complete(false);
      }
    }
  }

  /// Natural completion of [clip]: receipt only for the current, started
  /// reply, then evidence-based cleanup whatever the receipt send does.
  Future<void> _awaitCompletion(_Clip clip) async {
    try {
      final natural = await clip.finished.future;
      // Cancelled: the clip was already retired; no receipt, nothing queued.
      if (!natural) return;
      clip.live = false; // natural end is evidence the audio stopped
      // Completion evidence is kept apart from start readiness: a completion
      // that lands while play is still held waits for the start outcome.
      final ready = await clip.started.future;
      if (ready && clip.playingSent && _isCurrent(clip.ticket) && isActive()) {
        send(Packet(command: 'done', speech: clip.speech));
      }
      _enqueue(() => _settle(clip));
    } catch (e) {
      debugPrint('PhoneReplyReceiver: $e');
      _enqueue(() => _settle(clip));
    }
  }

  /// Retires [clip] now, parking it for retry when something is unconfirmed.
  Future<bool> _settle(_Clip clip) async {
    final done = await _retire(clip);
    if (done) {
      // Retired: release the waiter without a completion outcome.
      if (!clip.finished.isCompleted) clip.finished.complete(false);
      _stuck.remove(clip);
      if (identical(_current, clip)) _current = null;
    } else {
      if (!_stuck.contains(clip)) _stuck.add(clip);
      if (identical(_current, clip)) _current = null;
    }
    _publishPending();
    return done;
  }

  void _fail(int ticket, String text, String note) {
    // Only the admitted, still-current reply may publish; a held old failure
    // must not overwrite a newer reply's text.
    if (!_isCurrent(ticket) || !isActive()) return;
    showText('$text\n($note)');
  }

  List<int>? _decode(String encoded) {
    if (encoded.isEmpty || encoded.length > (maxBytes * 4 ~/ 3) + 8) {
      return null;
    }
    try {
      final bytes = base64Decode(encoded);
      return bytes.isEmpty || bytes.length > maxBytes ? null : bytes;
    } on FormatException {
      return null;
    }
  }

  Future<File> _newFile() async {
    final dir = await (tempDir ?? getTemporaryDirectory)();
    await dir.create(recursive: true);
    return File(
      '${dir.path}/bluey_say_${DateTime.now().microsecondsSinceEpoch}'
      '_${_sequence++}.mp3',
    );
  }

  /// Stops and removes the current and any parked clips. Returns false when
  /// some resource could not be released on evidence; those clips stay
  /// tracked and retried, and no replacement starts.
  Future<bool> _release() async {
    var confirmed = true;
    for (final clip in <_Clip>[..._stuck, ?_current]) {
      if (!await _settle(clip)) confirmed = false;
    }
    return confirmed;
  }

  /// Releases every resource of [clip] it has evidence for; true when all
  /// are released. Safe to call repeatedly: finished steps are not repeated.
  Future<bool> _retire(_Clip clip) async {
    if (clip.live) {
      if (!await _confirmStopped(clip)) return false;
    }
    if (!clip.subscriptionCancelled) {
      try {
        await clip.subscription?.cancel();
        clip.subscriptionCancelled = true;
      } catch (_) {}
    }
    if (!clip.sessionDisposed) {
      try {
        await clip.session.dispose();
        clip.sessionDisposed = true;
      } catch (_) {}
    }
    if (!clip.fileRemoved) {
      try {
        if (delete != null) {
          await delete!(clip.file);
        } else if (await clip.file.exists()) {
          await clip.file.delete();
        }
        clip.fileRemoved = true;
      } catch (_) {}
    }
    return clip.subscriptionCancelled &&
        clip.sessionDisposed &&
        clip.fileRemoved;
  }

  /// Stop evidence: stop() succeeded, or failing that, dispose() did.
  Future<bool> _confirmStopped(_Clip clip) async {
    try {
      await clip.session.stop();
      clip.live = false;
      return true;
    } catch (_) {}
    try {
      await clip.session.dispose();
      clip.sessionDisposed = true;
      clip.live = false;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Stops playback, removes clips and releases the sessions. Late
  /// completions after this call send no receipt and touch no UI. Clips that
  /// could not be released stay tracked until a natural completion resolves
  /// them; [cleanupPending] is closed only when none remain.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    await _ops;
    await _release();
    _publishPending();
  }
}

/// Pure rules for the phone bubble so the latest answer survives a cleanup
/// note and only the note is removed on recovery.
class ReplyBubble {
  const ReplyBubble._();

  /// The answer with the safe cleanup note appended when [pending].
  static String compose(String? text, bool pending) {
    if (!pending) return text ?? '';
    return text == null
        ? PhoneReplyReceiver.cleanupNote
        : '$text\n(${PhoneReplyReceiver.cleanupNote})';
  }

  /// New bubble after the pending flag changed from [was] to [now]. Only a
  /// bubble this class composed is touched; anything else is left alone.
  static String? next(String? current, String? text, bool was, bool now) {
    if (was == now) return current;
    final mine = compose(text, was);
    if (current != mine) return current;
    final out = compose(text, now);
    return out.isEmpty ? null : out;
  }
}
