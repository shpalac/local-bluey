import 'request_interfaces.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;

import 'egress_monitor.dart';
import 'endpoint.dart';
import 'privacy_guard.dart';

import 'package:path_provider/path_provider.dart';

import 'settings_store.dart';

/// Turns the brain's spoken reply into audio: POST {baseUrl}/audio/speech
/// (OpenAI-compatible TTS) and plays the result on the Mac.
class SpeechService implements SpeechLike {
  SpeechService({
    http.Client? client,
    AudioPlayer? player,
    SpeechPlayback? playback,
    SpeechClipStorage? storage,
  }) : _client = client ?? http.Client(),
       _playback = playback ?? _AudioPlayback(player),
       _storage = storage ?? FileSpeechClipStorage();

  final http.Client _client;

  final SpeechPlayback _playback;
  final SpeechClipStorage _storage;
  int _generation = 0;
  bool _disposed = false;
  Future<void>? _disposal;
  Future<void> _playerTail = Future<void>.value();
  StreamSubscription<void>? _completion;
  String? _ownedPath;
  String? _cleanupProblem;

  /// Most recent cleanup failure; cleanup is best-effort, not guaranteed.
  String? get cleanupProblem => _cleanupProblem;

  Future<void> _playerOp(Future<void> Function() op) {
    final next = _playerTail.then((_) => op());
    _playerTail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<void> _delete(String path) async {
    try {
      await _storage.delete(path);
    } catch (_) {
      _cleanupProblem = 'Speech clip cleanup failed.';
    }
  }

  Future<void> _release() async {
    final subscription = _completion;
    _completion = null;
    final path = _ownedPath;
    _ownedPath = null;
    try {
      await subscription?.cancel();
    } finally {
      if (path != null) await _delete(path);
    }
  }

  /// Network cap so a stalled TTS server cannot hang a reply (#118).
  static const requestTimeout = Duration(seconds: 60);

  /// Requests speech audio for [text]. Returns the raw audio bytes (mp3).
  @override
  Future<List<int>> synthesize(String text, BrainSettings settings) async {
    final base = settings.ttsBaseUrl?.isNotEmpty == true
        ? settings.ttsBaseUrl!
        : settings.baseUrl;
    // Local-only mode gates TTS exactly like the brain (#120).
    final refusal = await PrivacyGuard.refusalForUrl(base);
    if (refusal != null) throw SpeechException(refusal);
    final headers = {'Content-Type': 'application/json'};
    if (settings.apiKey?.isNotEmpty == true) {
      headers['Authorization'] = 'Bearer ${settings.apiKey}';
    }
    unawaited(EgressMonitor.instance.record(base, 'tts', text.length));
    final response = await _client
        .post(
          Uri.parse(endpoint(base, '/audio/speech')),
          headers: headers,
          body: jsonEncode({
            'model': settings.ttsModel,
            'voice': settings.ttsVoice,
            'input': text,
            'response_format': 'mp3',
          }),
        )
        .timeout(requestTimeout);
    if (response.statusCode != 200) {
      throw SpeechException('Speech ${response.statusCode}: ${response.body}');
    }
    // Checked parsing: some servers return a JSON error with a 200 (#118).
    final bytes = response.bodyBytes;
    if (bytes.isEmpty) {
      throw SpeechException('Speech returned empty audio');
    }
    if (bytes[0] == 0x7B) {
      // '{' - looks like JSON, not mp3 frames.
      try {
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is Map) {
          throw SpeechException('Speech returned an error: $decoded');
        }
      } on FormatException {
        // Not valid JSON; treat as audio and let the player judge.
      }
    }
    return bytes;
  }

  /// Latest request wins. Stop/dispose invalidate pending file work; player
  /// start/stop are ordered so completed stop cannot be followed by old play.
  @override
  Future<void> playBytes(List<int> bytes) async {
    if (_disposed) throw StateError('SpeechService is disposed');
    final generation = ++_generation;
    bool current() => !_disposed && generation == _generation;
    final snapshot = List<int>.of(bytes);
    String? path;
    try {
      path = await _storage.resolve();
      if (!current()) {
        await _delete(path);
        return;
      }
      await _storage.write(path, snapshot);
      if (!current()) {
        await _delete(path);
        return;
      }
      final clip = path;
      await _playerOp(() async {
        if (!current()) {
          await _delete(clip);
          return;
        }
        try {
          await _playback.stop();
        } finally {
          await _release();
        }
        if (!current()) {
          await _delete(clip);
          return;
        }
        _ownedPath = clip;
        // Listen before play: some clients complete during the play await.
        try {
          _completion = _playback.completed.listen(
            (_) {
              if (_ownedPath != clip) return;
              unawaited(
                _playerOp(() async {
                  if (_ownedPath == clip) await _release();
                }).catchError((Object _) {
                  _cleanupProblem = 'Speech completion cleanup failed.';
                }),
              );
            },
            onError: (Object _) {
              unawaited(
                _playerOp(() async {
                  if (_ownedPath == clip) await _release();
                }).catchError((Object _) {
                  _cleanupProblem = 'Speech completion cleanup failed.';
                }),
              );
            },
          );
          await _playback.play(clip);
          if (!current()) {
            await _playback.stop();
            await _release();
          }
        } catch (_) {
          try {
            await _playback.stop();
          } finally {
            await _release();
          }
          rethrow;
        }
      });
    } catch (_) {
      if (path != null) await _delete(path);
      rethrow;
    }
  }

  /// Invalidates pending startup immediately and drains older player startup.
  Future<void> stop() {
    if (_disposed) return _disposal ?? _playerTail;
    ++_generation;
    return _playerOp(() async {
      try {
        await _playback.stop();
      } finally {
        await _release();
      }
    });
  }

  /// Terminal disposal; pending file work can only clean its own stale clip.
  Future<void> dispose() {
    if (_disposed) return _disposal!;
    _disposed = true;
    ++_generation;
    _client.close();
    return _disposal = _playerOp(() async {
      try {
        await _playback.stop();
      } finally {
        try {
          await _release();
        } finally {
          await _playback.dispose();
        }
      }
    });
  }
}

/// A speech-pipeline failure (transcription or TTS).
class SpeechException implements Exception {
  SpeechException(this.message);

  /// Human-readable failure detail.
  final String message;
  @override
  String toString() => message;
}

/// Playback boundary; fixtures never open a platform audio channel.
abstract interface class SpeechPlayback {
  /// Completion events for the currently started clip.
  Stream<void> get completed;

  /// Starts one file; completion may occur before this future settles.
  Future<void> play(String path);

  /// Stops current playback.
  Future<void> stop();

  /// Releases resources permanently.
  Future<void> dispose();
}

class _AudioPlayback implements SpeechPlayback {
  _AudioPlayback(this._player);
  AudioPlayer? _player;
  AudioPlayer get player => _player ??= AudioPlayer();
  @override
  Stream<void> get completed => player.onPlayerComplete;
  @override
  Future<void> play(String path) => player.play(DeviceFileSource(path));
  @override
  Future<void> stop() async {
    await _player?.stop();
  }

  @override
  Future<void> dispose() async {
    await _player?.dispose();
  }
}

/// Each request resolves a unique owned path before writing.
abstract interface class SpeechClipStorage {
  /// Reserves a unique path; no clock-based collision is allowed.
  Future<String> resolve();

  /// Writes one reserved clip.
  Future<void> write(String path, List<int> bytes);

  /// Removes a clip, throwing when cleanup fails.
  Future<void> delete(String path);
}

/// Production temp-file storage, using unique directories rather than clocks.
class FileSpeechClipStorage implements SpeechClipStorage {
  @override
  Future<String> resolve() async {
    final dir = await (await getTemporaryDirectory()).createTemp(
      'bluey_speech_',
    );
    return '${dir.path}/clip.mp3';
  }

  @override
  Future<void> write(String path, List<int> bytes) async {
    await File(path).writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> delete(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
    final dir = file.parent;
    if (await dir.exists()) await dir.delete();
  }
}
