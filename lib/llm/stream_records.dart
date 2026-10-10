import 'dart:convert';

/// Maximum pending wire line or SSE data-event bytes. Over-limit/malformed
/// records fail with generic errors, never payloads, keys or transcript text.
const maxStreamRecordBytes = 64 * 1024;

/// Complete UTF-8 lines across arbitrary transport chunks, LF/CRLF and EOF.
/// EOF accepts a final unterminated line; malformed UTF-8 is an honest failure.
/// Cancellation/error closes only this owned consumption, not the HTTP client.
Stream<String> streamLines(Stream<List<int>> bytes) async* {
  var pending = <int>[];
  await for (final chunk in bytes) {
    for (final byte in chunk) {
      if (byte == 10) {
        if (pending.isNotEmpty && pending.last == 13) pending.removeLast();
        final line = _decode(pending);
        pending = <int>[];
        yield line;
      } else {
        if (pending.length >= maxStreamRecordBytes) {
          throw const FormatException('Stream record exceeds limit');
        }
        pending.add(byte);
      }
    }
  }
  if (pending.isNotEmpty) {
    if (pending.last == 13) pending.removeLast();
    yield _decode(pending);
  }
}

String _decode(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } catch (_) {
    throw const FormatException('Invalid stream encoding');
  }
}

/// NDJSON has one nonempty JSON record per line, including final EOF record.
Stream<String> ndjsonRecords(Stream<List<int>> bytes) async* {
  await for (final line in streamLines(bytes)) {
    if (line.trim().isNotEmpty) yield line;
  }
}

/// SSE combines data fields within blank-line-delimited events with newlines.
/// Comments and non-data metadata are ignored. EOF dispatches final data event.
/// Both wire line and accumulated event are capped; [DONE] is handled by caller.
Stream<String> sseRecords(Stream<List<int>> bytes) async* {
  var data = <String>[];
  var size = 0;
  await for (final line in streamLines(bytes)) {
    if (line.isEmpty) {
      if (data.isNotEmpty) yield data.join('\n');
      data = [];
      size = 0;
      continue;
    }
    if (line.startsWith(':')) continue;
    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    if (field != 'data') continue;
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    size += utf8.encode(value).length + (data.isEmpty ? 0 : 1);
    if (size > maxStreamRecordBytes) {
      throw const FormatException('Stream event exceeds limit');
    }
    data.add(value);
  }
  if (data.isNotEmpty) yield data.join('\n');
}

/// JSON object only, with generic malformed failure that never echoes input.
Map<String, dynamic> streamObject(String payload) {
  try {
    final decoded = jsonDecode(payload);
    if (decoded is! Map<String, dynamic>) throw const FormatException();
    return decoded;
  } catch (_) {
    throw const FormatException('Malformed stream record');
  }
}
