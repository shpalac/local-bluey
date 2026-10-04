import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Hold-to-talk audio capture. Transcription is pluggable: send the file to
/// any OpenAI-compatible /audio/transcriptions endpoint, or swap in a local
/// whisper.cpp binding later.
class AudioCapture {
  final AudioRecorder _recorder = AudioRecorder();
  String? _path;

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<void> start() async {
    final dir = await getTemporaryDirectory();
    _path =
        '${dir.path}/bluey_hold_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 16000),
      path: _path!,
    );
  }

  /// Stops and returns the recorded file, or null if nothing was captured.
  Future<File?> stop() async {
    final path = await _recorder.stop();
    if (path == null) return null;
    return File(path);
  }

  Future<void> dispose() => _recorder.dispose();
}
