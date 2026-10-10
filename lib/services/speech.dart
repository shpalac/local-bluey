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
    Duration timeout = requestTimeout,
  }) : _client = client ?? http.Client(),
       _playback = playback ?? _AudioPlayback(player),
       _storage = storage ?? FileSpeechClipStorage(),
       _timeout = timeout {
    if (timeout <= Duration.zero) throw ArgumentError.value(timeout, 'timeout');
  }

  final http.Client _client;
  final Duration _timeout;

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

  /// Requests speech audio for [text]. Returns opaque nonempty audio bytes.
  /// JSON/error envelopes rejected; this is not MP3 codec validation.
  /// Transport/deadline failures use safe typed messages without retries.
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
    final http.Response response;
    try {
      response = await _client
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
          .timeout(_timeout);
    } on TimeoutException {
      throw SpeechException('Speech request timed out.');
    } catch (_) {
      throw SpeechException('Speech request failed.');
    }
    if (response.statusCode != 200) {
      throw SpeechException('Speech HTTP ${response.statusCode}.');
    }
    final bytes = response.bodyBytes;
    if (bytes.isEmpty) throw SpeechException('Speech returned empty audio.');
    final mediaType = response.headers['content-type']
        ?.split(';')
        .first
        .trim()
        .toLowerCase();
    if (mediaType == 'application/json' ||
        mediaType?.endsWith('+json') == true ||
        _isJsonEnvelope(bytes)) {
      throw SpeechException('Speech returned a JSON response, not audio.');
    }
    return bytes;
  }

  bool _isJsonEnvelope(List<int> bytes) {
    var i = 0;
    while (i < bytes.length &&
        (bytes[i] == 32 || bytes[i] == 9 || bytes[i] == 10 || bytes[i] == 13)) {
      i++;
    }
    if (i == bytes.length) return false;
    final first = bytes[i];
    // Only potential JSON starts warrant decoding. Binary remains opaque.
    if (!(first == 123 ||
        first == 91 ||
        first == 34 ||
        first == 45 ||
        (first >= 48 && first <= 57) ||
        first == 116 ||
        first == 102 ||
        first == 110)) {
      return false;
    }
    try {
      jsonDecode(utf8.decode(bytes));
      return true;
    } on FormatException {
      return false;
    }
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
          _completion = _playback
              .completed(clip)
              .listen(
                (_) {
                  if (_ownedPath != clip) return;
                  unawaited(
                    _playerOp(() async {
                      if (_ownedPath == clip) {
                        try {
                          await _playback.stop();
                        } finally {
                          await _release();
                        }
                      }
                    }).catchError((Object _) {
                      _cleanupProblem = 'Speech completion cleanup failed.';
                    }),
                  );
                },
                onError: (Object _) {
                  unawaited(
                    _playerOp(() async {
                      if (_ownedPath == clip) {
                        try {
                          await _playback.stop();
                        } finally {
                          await _release();
                        }
                      }
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
  Stream<void> completed(String path);

  /// Starts one file; completion may occur before this future settles.
  Future<void> play(String path);

  /// Stops current playback.
  Future<void> stop();

  /// Releases resources permanently.
  Future<void> dispose();
}

class _AudioPlayback implements SpeechPlayback {
  _AudioPlayback(this._injected);
  AudioPlayer? _injected;
  AudioPlayer? _player;
  String? _path;
  @override
  Stream<void> completed(String path) {
    // A player identity is never reused for a replacement clip. Native late
    // events from the old player cannot enter the new clip's stream.
    _path = path;
    _player = _injected ?? AudioPlayer();
    _injected = null;
    return _player!.onPlayerComplete;
  }

  @override
  Future<void> play(String path) {
    if (path != _path) throw StateError('Unowned speech clip');
    return _player!.play(DeviceFileSource(path));
  }

  @override
  Future<void> stop() async {
    final player = _player;
    _player = null;
    _path = null;
    if (player == null) return;
    try {
      await player.stop();
    } finally {
      await player.dispose();
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await stop();
    } finally {
      await _injected?.dispose();
      _injected = null;
    }
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
