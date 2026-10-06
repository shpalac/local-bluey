import 'dart:io';

import 'package:flutter/services.dart';

import 'stt.dart';

/// Decoded mono 16 kHz Int16 PCM, ready for a local STT backend (#197
/// prework).
class PcmAudio {
  const PcmAudio({
    required this.bytes,
    required this.sampleRate,
    required this.duration,
  });

  /// Raw little-endian Int16 samples, mono, at [sampleRate].
  final Uint8List bytes;

  /// Samples per second (always 16000 from the native decoder).
  final int sampleRate;

  /// Source audio duration.
  final Duration duration;
}

/// Platform seam so the decode path is testable without AVFoundation.
abstract class PcmDecoderDriver {
  /// Decodes the m4a at [path]. Throws [SttException] with
  /// [SttErrorKind.decoderError] on any decode failure.
  Future<PcmAudio> decode(String path);
}

/// Production driver: the `local_bluey/audio` MethodChannel backed by
/// AVFoundation on macOS.
class NativePcmDecoderDriver implements PcmDecoderDriver {
  /// Test seam: an injected channel wins over the default.
  NativePcmDecoderDriver([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel('local_bluey/audio');

  final MethodChannel _channel;

  @override
  Future<PcmAudio> decode(String path) async {
    final Map<dynamic, dynamic> res;
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'decodeM4aToPcm',
        {'path': path},
      );
      if (raw == null) {
        throw SttException(SttErrorKind.decoderError, 'Decoder returned null.');
      }
      res = raw;
    } on PlatformException catch (e) {
      throw SttException(
        SttErrorKind.decoderError,
        'Audio decode failed: ${e.message ?? e.code}',
      );
    }
    final pcm = res['pcm'];
    final rate = res['sampleRate'];
    final durationMs = res['durationMs'];
    if (pcm is! Uint8List || rate is! int || durationMs is! int) {
      throw SttException(SttErrorKind.decoderError, 'Malformed decoder reply.');
    }
    return PcmAudio(
      bytes: pcm,
      sampleRate: rate,
      duration: Duration(milliseconds: durationMs),
    );
  }
}

/// Validates capture files and decodes them to PCM (#197 prework): every
/// local STT backend consumes PCM, not the recorded AAC-LC m4a. Decoding
/// happens fully in memory - no intermediate files are written, so the
/// capture cleanup behavior (#116/#128) is unchanged.
class PcmDecoder {
  PcmDecoder({PcmDecoderDriver? driver})
    : _driver = driver ?? NativePcmDecoderDriver();

  final PcmDecoderDriver _driver;

  /// Input sanity cap. Two minutes of AAC-LC at 16 kHz is well under 2MB;
  /// 8MB leaves generous headroom while still bounding what reaches the
  /// native decoder.
  static const maxInputBytes = 8 * 1024 * 1024;

  /// Decodes [audio] (an m4a capture) to mono 16 kHz PCM. Throws
  /// [SttException] with [SttErrorKind.decoderError] when the file is
  /// missing, empty, oversized, corrupt, or undecodable.
  Future<PcmAudio> decode(File audio) async {
    if (!await audio.exists()) {
      throw SttException(
        SttErrorKind.decoderError,
        'Audio file missing: ${audio.path}',
      );
    }
    final size = await audio.length();
    if (size == 0) {
      throw SttException(SttErrorKind.decoderError, 'Audio file is empty.');
    }
    if (size > maxInputBytes) {
      throw SttException(
        SttErrorKind.decoderError,
        'Audio file too large ($size bytes).',
      );
    }
    return _driver.decode(audio.path);
  }
}
