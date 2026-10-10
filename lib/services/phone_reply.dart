import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../link/models.dart';

/// The playback seam of [PhoneReplyReceiver] (#372): injectable so fixtures
/// drive start, completion and failure without a device.
abstract class ReplyPlayer {
  /// Fires once per finished clip.
  Stream<void> get completions;

  /// Starts playing the file at [path].
  Future<void> play(String path);

  /// Stops playback (also safe when nothing plays).
  Future<void> stop();

  /// Releases the player.
  Future<void> dispose();
}

/// [ReplyPlayer] over audioplayers.
class AudioplayersReplyPlayer implements ReplyPlayer {
  /// Creates a player; pass [player] in tests of the adapter only.
  AudioplayersReplyPlayer({AudioPlayer? player})
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
  _Clip(this.file);
  final File file;
  final finished = Completer<bool>();
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
    required this.player,
    required this.send,
    required this.showText,
    this.isActive = _always,
    this.tempDir,
    this.write,
    this.delete,
  });

  /// Largest accepted decoded reply; the link frame cap is 16 MiB.
  static const maxBytes = 12 * 1024 * 1024;

  /// Playback backend.
  final ReplyPlayer player;

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

  /// Clips whose deletion failed and will be retried on the next release.
  int get undeletedCount => _leftovers.length;

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
    await _release();
    if (!_isCurrent(ticket)) return;
    _Clip? clip;
    try {
      final bytes = _decode(encoded);
      if (bytes == null) {
        _fail(text, 'Reply audio was not valid and was not played.');
        return;
      }
      final file = await _newFile();
      clip = _Clip(file);
      _current = clip;
      try {
        await (write ?? (f, b) => f.writeAsBytes(b, flush: true))(file, bytes);
      } catch (_) {
        await _discard(clip);
        _fail(text, 'Could not save the reply audio.');
        return;
      }
      if (!_isCurrent(ticket)) {
        await _discard(clip);
        return;
      }
      // Subscribe before starting so an immediate completion is not lost.
      final owned = clip;
      clip.subscription = player.completions.listen((_) {
        if (!owned.finished.isCompleted) owned.finished.complete(true);
      });
      try {
        await player.play(file.path);
      } catch (_) {
        await _discard(clip);
        _fail(text, 'Could not play the reply audio.');
        return;
      }
      if (!_isCurrent(ticket) || clip.released) {
        // Superseded while starting: no receipt; the newer turn (queued
        // behind this one) or dispose releases the clip.
        return;
      }
      if (isActive()) send(Packet(command: 'playing', speech: packet.speech));
      unawaited(
        clip.finished.future.then((completed) async {
          if (completed && _isCurrent(ticket) && isActive()) {
            send(Packet(command: 'done', speech: packet.speech));
          }
          await _enqueueDiscard(owned);
        }),
      );
    } catch (e) {
      debugPrint('PhoneReplyReceiver: $e');
      if (clip != null) await _discard(clip);
      _fail(text, 'Could not play the reply audio.');
    }
  }

  Future<void> _enqueueDiscard(_Clip clip) {
    final done = Completer<void>();
    _enqueue(() async {
      await _discard(clip);
      done.complete();
    });
    return done.future;
  }

  void _fail(String text, String note) {
    if (_disposed || !isActive()) return;
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

  /// Stops and removes the current clip (completing its wait as not done).
  Future<void> _release() async {
    final clip = _current;
    if (clip != null) {
      if (!clip.finished.isCompleted) clip.finished.complete(false);
      try {
        await player.stop();
      } catch (_) {}
      await _discard(clip);
    }
    await _retryLeftovers();
  }

  Future<void> _discard(_Clip clip) async {
    if (clip.released) return;
    clip.released = true;
    if (!clip.finished.isCompleted) clip.finished.complete(false);
    await clip.subscription?.cancel();
    if (identical(_current, clip)) _current = null;
    await _remove(clip.file);
  }

  Future<void> _remove(File file) async {
    try {
      if (delete != null) {
        await delete!(file);
      } else if (await file.exists()) {
        await file.delete();
      }
      _leftovers.remove(file);
    } catch (_) {
      if (!_leftovers.any((f) => f.path == file.path)) _leftovers.add(file);
    }
  }

  Future<void> _retryLeftovers() async {
    for (final file in List<File>.of(_leftovers)) {
      await _remove(file);
    }
  }

  /// Stops playback, removes clips and releases the player. Late completions
  /// after this call send no receipt and touch no UI.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    await _ops;
    await _release();
    try {
      await player.dispose();
    } catch (_) {}
  }
}
