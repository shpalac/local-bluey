/// Shared protocol between the Mac and the iPhone, ported from Shared/GooglyLink.swift.
/// Newline-delimited JSON over a plain TCP socket.
library;

enum Mood { listening, resting, thinking, talking, pointing, happy, sleepy }

class FaceState {
  FaceState({
    this.gazeX = 0,
    this.gazeY = 0,
    this.mood = Mood.listening,
    this.talk = 0,
  });

  /// Where the eyes look. x: -1 left … 1 right. y: -1 up … 1 down.
  double gazeX;
  double gazeY;
  Mood mood;

  /// Voice level 0…1. Drives the talking bounce.
  double talk;

  factory FaceState.fromJson(Map<String, dynamic> json) => FaceState(
    gazeX: _wireNumber(json['gazeX'], -1, 1) ?? 0,
    gazeY: _wireNumber(json['gazeY'], -1, 1) ?? 0,
    mood: Mood.values.asNameMap()[json['mood'] as String?] ?? Mood.listening,
    talk: _wireNumber(json['talk'], 0, 1) ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'gazeX': gazeX,
    'gazeY': gazeY,
    'mood': mood.name,
    'talk': talk,
  };
}

class Packet {
  Packet({
    this.face,
    this.hello,
    this.volume,
    this.command,
    this.audio,
    this.speech,
    this.callID,
    this.tool,
    this.text,
    this.image,
  });

  FaceState? face;

  /// Sent once by each side after connecting, with a device name.
  String? hello;

  /// Voice volume 0…1. The Mac shares it, the phone sets it.
  double? volume;

  /// A request or event: "testVoice" (phone→Mac), "playing"/"done" (phone→Mac), "stopSpeech" (Mac→phone).
  String? command;

  /// Speech audio (mp3, base64) for the phone to play.
  String? audio;

  /// Which speech an audio packet or a playing/done event belongs to.
  int? speech;

  /// Pairs a request with its reply (tool calls, realtime tokens).
  String? callID;

  /// Tool name for a "tool" request.
  String? tool;

  /// Free text: tool arguments or output, a token, a caption.
  String? text;

  /// A JPEG (base64) that goes with a tool result.
  String? image;

  factory Packet.fromJson(Map<String, dynamic> json) => Packet(
    face: json['face'] == null
        ? null
        : FaceState.fromJson(Map<String, dynamic>.from(json['face'] as Map)),
    hello: json['hello'] as String?,
    volume: _wireNumber(json['volume'], 0, 1),
    command: json['command'] as String?,
    audio: json['audio'] as String?,
    speech: json['speech'] as int?,
    callID: json['callID'] as String?,
    tool: json['tool'] as String?,
    text: json['text'] as String?,
    image: json['image'] as String?,
  );

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (face != null) map['face'] = face!.toJson();
    if (hello != null) map['hello'] = hello;
    if (volume != null) map['volume'] = volume;
    if (command != null) map['command'] = command;
    if (audio != null) map['audio'] = audio;
    if (speech != null) map['speech'] = speech;
    if (callID != null) map['callID'] = callID;
    if (tool != null) map['tool'] = tool;
    if (text != null) map['text'] = text;
    if (image != null) map['image'] = image;
    return map;
  }
}

// Wire-only validation; local mutable constructors and serialization unchanged.
double? _wireNumber(Object? value, double lower, double upper) {
  if (value == null) return null;
  if (value is! num) throw const FormatException('Invalid numeric state.');
  final number = value.toDouble();
  if (!number.isFinite || number < lower || number > upper) {
    throw const FormatException('Invalid numeric state.');
  }
  return number;
}
