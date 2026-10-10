import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'audio_capture.dart';

/// Why a phone hold-to-talk payload was refused (#366).
enum PhoneAudioProblem { malformed, tooLarge, notAudio, storage }

/// A refused phone audio payload. The message is fixed and user-safe: it
/// never carries decoder, path or disk error text.
class PhoneAudioException implements Exception {
  /// Creates the refusal for [problem].
  const PhoneAudioException(this.problem);

  /// The refusal reason.
  final PhoneAudioProblem problem;

  /// Short bubble text for the user.
  String get message => switch (problem) {
    PhoneAudioProblem.malformed => 'Phone audio was not valid and was ignored.',
    PhoneAudioProblem.tooLarge => 'Phone audio was too long and was ignored.',
    PhoneAudioProblem.notAudio =>
      'Phone audio was not a recording and was ignored.',
    PhoneAudioProblem.storage =>
      'Could not save the phone audio. Check free disk space.',
  };

  @override
  String toString() => message;
}

/// Validates and stages untrusted phone hold-to-talk audio (#366).
class PhoneAudioIntake {
  PhoneAudioIntake._();

  /// Largest accepted recording. The Mac recorder caps a hold at two minutes
  /// of 16 kHz AAC (well under this); the link frame cap alone is 16 MiB.
  static const maxBytes = 8 * 1024 * 1024;

  /// Decodes, bounds and checks [encoded], then writes it to a temp .m4a.
  /// Throws [PhoneAudioException] and leaves no file behind on any failure.
  static Future<File> stage(
    String encoded, {
    Future<Directory> Function()? tempDir,
    DateTime Function()? now,
  }) async {
    // base64 inflates by 4/3; reject before allocating the decoded bytes.
    if (encoded.length > (maxBytes * 4 ~/ 3) + 8) {
      throw const PhoneAudioException(PhoneAudioProblem.tooLarge);
    }
    final List<int> bytes;
    try {
      bytes = base64Decode(encoded);
    } on FormatException {
      throw const PhoneAudioException(PhoneAudioProblem.malformed);
    }
    if (bytes.length > maxBytes) {
      throw const PhoneAudioException(PhoneAudioProblem.tooLarge);
    }
    // MP4/M4A container: 'ftyp' box type at offset 4.
    if (bytes.length < 12 ||
        String.fromCharCodes(bytes.sublist(4, 8)) != 'ftyp') {
      throw const PhoneAudioException(PhoneAudioProblem.notAudio);
    }
    File? file;
    try {
      final dir = await (tempDir ?? getTemporaryDirectory)();
      // getTemporaryDirectory() only names the directory (#254).
      await dir.create(recursive: true);
      file = File(
        '${dir.path}/bluey_phone_'
        '${(now ?? DateTime.now)().microsecondsSinceEpoch}.m4a',
      );
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } catch (_) {
      await AudioCapture.deleteQuietly(file);
      throw const PhoneAudioException(PhoneAudioProblem.storage);
    }
  }
}
