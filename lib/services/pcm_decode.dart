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

  /// Raw little-endian Int16 samples, mono, at [sampleRate]. Decoder returns
  /// are detached read-only snapshots; this public constructor accepts fixtures.
  final Uint8List bytes;

  /// Samples per second (always 16000 from the native decoder).
  final int sampleRate;

  /// Source audio duration, not an exact decoded byte/sample-count guarantee.
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
    try {
      final raw = await _channel.invokeMethod<dynamic>('decodeM4aToPcm', {
        'path': path,
      });
      if (raw is! Map) throw _decodeFailure();
      final pcm = raw['pcm'];
      final rate = raw['sampleRate'];
      final durationMs = raw['durationMs'];
      if (pcm is! Uint8List ||
          rate is! int ||
          durationMs is! int ||
          durationMs <= 0 ||
          durationMs > PcmDecoder.maxDuration.inMilliseconds) {
        throw _decodeFailure();
      }
      return _validateOutput(
        PcmAudio(
          bytes: pcm,
          sampleRate: rate,
          duration: Duration(milliseconds: durationMs),
        ),
      );
    } on SttException {
      rethrow;
    } catch (_) {
      throw _decodeFailure();
    }
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

  /// Native-backed output cap, also enforced on injected drivers.
  static const maxOutputBytes = 40 * 1024 * 1024;

  /// Maximum supported source duration, matching the native decoder bound.
  static const maxDuration = Duration(seconds: 600);

  /// Decodes [audio] (an m4a capture) to mono 16 kHz PCM. Throws
  /// [SttException] with [SttErrorKind.decoderError] when the file is
  /// missing, empty, oversized, corrupt, or undecodable.
  Future<PcmAudio> decode(File audio) async {
    try {
      if (!await audio.exists()) throw _decodeFailure();
      final size = await audio.length();
      if (size <= 0 || size > maxInputBytes) throw _decodeFailure();
      return _validateOutput(await _driver.decode(audio.path));
    } on SttException {
      rethrow;
    } catch (_) {
      throw _decodeFailure();
    }
  }
}

SttException _decodeFailure() =>
    SttException(SttErrorKind.decoderError, 'Audio decode failed.');

PcmAudio _validateOutput(PcmAudio pcm) {
  if (pcm.sampleRate != 16000 ||
      pcm.bytes.isEmpty ||
      pcm.bytes.length.isOdd ||
      pcm.bytes.length > PcmDecoder.maxOutputBytes ||
      pcm.duration <= Duration.zero ||
      pcm.duration > PcmDecoder.maxDuration) {
    throw _decodeFailure();
  }
  // Validate before copying. The owned read-only copy detaches later driver
  // mutations without changing the public PcmAudio constructor contract.
  return PcmAudio(
    bytes: Uint8List.fromList(pcm.bytes).asUnmodifiableView(),
    sampleRate: pcm.sampleRate,
    duration: pcm.duration,
  );
}
