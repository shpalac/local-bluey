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
  _Clip(this.file, this.session);
  final File file;
  final ReplySession session;
  final finished = Completer<void>();
  StreamSubscription<void>? subscription;
  bool released = false;
}

/// Phone-side owner of Mac reply audio (#372): guarded intake, unique clip
/// files, latest-reply-wins ordered playback, receipts tied to real playback,
/// and cleanup on completion, replacement, failure, stopSpeech and dispose.
/// The audio stays opaque (the host sends MP3); nothing here validates it as
/// a codec stream. Every entry point contains its own errors.
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
  final _leftovers = <File>[];

  final _stuck = <_Clip>[];

  /// Clips whose deletion or stop could not be completed; retried on the next
  /// release. Observable by the caller; this is not an erasure guarantee.
  final ValueNotifier<int> cleanupPending = ValueNotifier<int>(0);

  void _publishPending() {
    final count = _leftovers.length + _stuck.length;
    if (cleanupPending.value != count) cleanupPending.value = count;
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
            if (ticket == _generation && isActive()) {
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
      final session = createSession();
      clip = _Clip(file, session);
      _current = clip;
      try {
        await (write ?? (f, b) => f.writeAsBytes(b, flush: true))(file, bytes);
      } catch (_) {
        await _discard(clip);
        _fail(ticket, text, 'Could not save the reply audio.');
        return;
      }
      if (!_isCurrent(ticket)) {
        await _discard(clip);
        return;
      }
      // Subscribe before starting so an immediate completion is not lost.
      final owned = clip;
      clip.subscription = session.completions.listen((_) {
        if (!owned.finished.isCompleted) owned.finished.complete();
      });
      try {
        await session.play(file.path);
      } catch (_) {
        await _discard(clip);
        _fail(ticket, text, 'Could not play the reply audio.');
        return;
      }
      if (!_isCurrent(ticket) || clip.released) {
        // Superseded while starting: no receipt; the newer turn (queued
        // behind this one) or dispose releases the clip.
        return;
      }
      if (isActive()) send(Packet(command: 'playing', speech: packet.speech));
      unawaited(_awaitCompletion(owned, packet, ticket));
    } catch (e) {
      debugPrint('PhoneReplyReceiver: $e');
      if (clip != null) await _discard(clip);
      _fail(ticket, text, 'Could not play the reply audio.');
    }
  }

  /// Natural completion of [clip]: receipt for the current reply, then cleanup
  /// no matter what the receipt send does.
  Future<void> _awaitCompletion(_Clip clip, Packet packet, int ticket) async {
    try {
      await clip.finished.future;
      if (_isCurrent(ticket) && !clip.released && isActive()) {
        send(Packet(command: 'done', speech: packet.speech));
      }
    } catch (e) {
      debugPrint('PhoneReplyReceiver: $e');
    } finally {
      _enqueue(() => _discard(clip));
    }
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

  /// Stops and removes the current and any previously stuck clips. Returns
  /// false when a stop could not be confirmed: such a clip keeps its file and
  /// session and is retried on the next release, and no replacement starts.
  Future<bool> _release() async {
    var confirmed = true;
    final clips = <_Clip>[..._stuck, ?_current];
    for (final clip in clips) {
      if (await _stopClip(clip)) {
        _stuck.remove(clip);
        await _discard(clip);
      } else {
        if (!_stuck.contains(clip)) _stuck.add(clip);
        if (identical(_current, clip)) _current = null;
        confirmed = false;
      }
    }
    await _retryLeftovers();
    _publishPending();
    return confirmed;
  }

  /// Stop evidence for [clip]: stop() succeeded, or failing that, dispose().
  Future<bool> _stopClip(_Clip clip) async {
    try {
      await clip.session.stop();
      return true;
    } catch (_) {}
    try {
      await clip.session.dispose();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _discard(_Clip clip) async {
    if (clip.released) return;
    clip.released = true;
    _stuck.remove(clip);
    try {
      await clip.subscription?.cancel();
    } catch (_) {}
    try {
      await clip.session.dispose();
    } catch (_) {}
    if (identical(_current, clip)) _current = null;
    await _remove(clip.file);
    _publishPending();
  }

  Future<void> _remove(File file) async {
    try {
      if (delete != null) {
        await delete!(file);
      } else if (await file.exists()) {
        await file.delete();
      }
      _leftovers.removeWhere((f) => f.path == file.path);
    } catch (_) {
      if (!_leftovers.any((f) => f.path == file.path)) _leftovers.add(file);
    }
  }

  Future<void> _retryLeftovers() async {
    for (final file in List<File>.of(_leftovers)) {
      await _remove(file);
    }
  }

  /// Stops playback, removes clips and releases the sessions. Late
  /// completions after this call send no receipt and touch no UI.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    await _ops;
    await _release();
    cleanupPending.dispose();
  }
}
