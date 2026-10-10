import 'dart:async';
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

  static int _sequence = 0;

  /// Decodes, bounds and checks [encoded], then writes it to a temp .m4a.
  /// Throws [PhoneAudioException] and leaves no file behind on any failure.
  /// The 'ftyp' check only says the bytes look like an MP4 container; it does
  /// not validate the audio. Each call owns a unique file name even under
  /// equal clock readings.
  static Future<File> stage(
    String encoded, {
    Future<Directory> Function()? tempDir,
    DateTime Function()? now,
    Future<void> Function(File file, List<int> bytes)? write,
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
        '${(now ?? DateTime.now)().microsecondsSinceEpoch}_${_sequence++}.m4a',
      );
      await (write ?? (f, b) => f.writeAsBytes(b, flush: true))(file, bytes);
      return file;
    } catch (_) {
      await AudioCapture.deleteQuietly(file);
      throw const PhoneAudioException(PhoneAudioProblem.storage);
    }
  }
}

/// Receives phone hold-to-talk audio: stages it, hands it to [process] and
/// reports refusals once (#366). Everything is guarded so the packet listener
/// never sees a synchronous or unobserved asynchronous error.
class PhoneAudioReceiver {
  /// Creates a receiver. [stage] and [isActive] are test seams.
  PhoneAudioReceiver({
    required this.process,
    required this.onRejected,
    this.stage = PhoneAudioIntake.stage,
    this.isActive = _always,
  });

  /// Runs one staged recording (the request runner); it deletes the file.
  final Future<void> Function(File file) process;

  /// Shows one short, safe message.
  final void Function(String message) onRejected;

  /// Stages the payload.
  final Future<File> Function(String encoded) stage;

  /// False once the owner is disposed: nothing may run or be shown.
  final bool Function() isActive;

  static bool _always() => true;

  /// Handles one `holdAudio` payload without throwing.
  void handle(String encoded) {
    unawaited(_handle(encoded));
  }

  Future<void> _handle(String encoded) async {
    final File file;
    try {
      file = await stage(encoded);
    } on PhoneAudioException catch (e) {
      if (isActive()) onRejected(e.message);
      return;
    } catch (_) {
      if (isActive()) {
        onRejected(
          const PhoneAudioException(PhoneAudioProblem.storage).message,
        );
      }
      return;
    }
    if (!isActive()) {
      await AudioCapture.deleteQuietly(file);
      return;
    }
    try {
      await process(file);
    } catch (_) {
      await AudioCapture.deleteQuietly(file);
    }
  }
}
