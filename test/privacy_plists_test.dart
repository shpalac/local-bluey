import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:local_bluey/link/phone_server.dart';

/// The privacy keys both shipped apps must declare, and the only reason a
/// device ever shows a permission prompt.
///
/// #15: `ios/Runner/Info.plist` had all three nested inside the innermost
/// `UIApplicationSceneManifest` scene dict. The file still parsed - `plutil
/// -lint` passed and `flutter build ios` succeeded - so nothing caught it,
/// but iOS never saw the keys: no microphone prompt, and no local-network
/// prompt or Bonjour service type, so the iPhone could never find the Mac.
/// These tests pin the shape so it cannot regress silently.
const privacyKeys = [
  'NSMicrophoneUsageDescription',
  'NSLocalNetworkUsageDescription',
  'NSBonjourServices',
];

/// The Info.plist each shipped app target actually builds from. macOS was
/// always correct; iOS was the defect.
const shippedPlists = ['ios/Runner/Info.plist', 'macos/Runner/Info.plist'];

/// The legacy native app's plists, still tracked and referenced by
/// GooglyEyes.xcodeproj. Held to the same contract.
const legacyPlists = ['iOS/Info.plist', 'Mac/Info.plist'];

void main() {
  group('privacy keys are where the OS can read them (#15)', () {
    for (final path in [...shippedPlists, ...legacyPlists]) {
      final plist = parsePlist(File(path).readAsStringSync(), path);

      test('$path declares every privacy key at the top level', () {
        final missing = privacyKeys.where((k) => !plist.containsKey(k));
        expect(
          missing,
          isEmpty,
          reason:
              '$path is missing top-level ${missing.toList()}. A key that is '
              'not a direct child of the root dict is invisible to the OS: '
              'nest it one level too deep and iOS drops it while the plist '
              'still lints clean.',
        );
      });

      test('$path gives each permission a non-empty description', () {
        for (final key in const [
          'NSMicrophoneUsageDescription',
          'NSLocalNetworkUsageDescription',
        ]) {
          expect(
            plist[key],
            isA<String>(),
            reason: '$path: $key must be a string',
          );
          expect(
            (plist[key]! as String).trim(),
            isNotEmpty,
            reason: '$path: $key is blank, so the prompt would show no text',
          );
        }
      });

      test('$path advertises the service type the app registers', () {
        // The OS only allows local-network traffic for service types listed
        // here. After a rename of kServiceType a stale plist means the phone
        // sees an empty Mac list, with no prompt to explain why.
        final services = plist['NSBonjourServices'];
        expect(
          services,
          isA<List<Object?>>(),
          reason: '$path: NSBonjourServices must be an array',
        );
        expect(
          services! as List<Object?>,
          contains(kServiceType),
          reason:
              '$path must list "$kServiceType" (kServiceType in '
              'lib/link/phone_server.dart) or Bonjour discovery is blocked',
        );
      });

      test('$path has no privacy key buried in a nested dict', () {
        // The original bug, asserted directly: a future paste into the wrong
        // container fails here instead of on someone's iPhone.
        final nested = _nestedPrivacyKeys(plist);
        expect(
          nested,
          isEmpty,
          reason:
              '$path nests ${nested.toList()} inside another dict. These keys '
              'only work as direct children of the root dict.',
        );
      });
    }
  });

  test('the legacy Swift link advertises kServiceType (#15)', () {
    // Shared/GooglyLink.swift hardcodes the type for the pre-Flutter app. If
    // kServiceType ever moves, the plists follow it but this constant would
    // silently keep advertising the old type.
    expect(
      File('Shared/GooglyLink.swift').readAsStringSync(),
      contains('"$kServiceType"'),
    );
  });
}

/// Every [privacyKeys] entry reachable only by descending into a child value.
List<String> _nestedPrivacyKeys(Map<String, Object?> plist) {
  final nested = <String>[];

  void walk(Object? node) {
    if (node is Map) {
      for (final entry in node.entries) {
        if (privacyKeys.contains(entry.key)) nested.add(entry.key);
        walk(entry.value);
      }
    } else if (node is List) {
      node.forEach(walk);
    }
  }

  plist.values.forEach(walk);
  return nested;
}

/// Reads [xml] as a property list.
///
/// Hand-rolled on purpose: the app takes no plist dependency for a test, and
/// reading the file as text is the point - the defect being guarded is *where*
/// a key sits in the file, so the reader has to preserve nesting.
Map<String, Object?> parsePlist(String xml, String source) {
  final parser = _Parser(_scanTags(xml, source), source);
  parser.skipRootWrapper();
  final root = parser.value();
  if (root is! Map<String, Object?>) {
    throw FormatException('$source: root element is not a <dict>');
  }
  return root;
}

/// One XML tag: its name, whether it closes itself, and the character data
/// that precedes it.
class _Tag {
  _Tag(this.name, this.isEmpty, this.text, this.end);

  /// `key`, `string`, `/dict`, `true` ...
  final String name;

  /// `<true/>` or `<dict/>` - a leaf with no closing tag.
  final bool isEmpty;

  /// Character data between the previous tag and this one.
  final String text;

  /// Offset just past this tag, where the next tag's text begins.
  final int end;
}

List<_Tag> _scanTags(String xml, String source) {
  final tags = <_Tag>[];
  for (final match in RegExp(r'<[^>]+>').allMatches(xml)) {
    final inner = match
        .group(0)!
        .substring(1, match.group(0)!.length - 1)
        .trim();
    if (inner.startsWith('?') || inner.startsWith('!')) {
      continue; // XML declaration, DOCTYPE
    }
    final isEmpty = inner.endsWith('/');
    final bare = isEmpty ? inner.substring(0, inner.length - 1).trim() : inner;
    final text = _unescape(
      xml.substring(tags.isEmpty ? 0 : tags.last.end, match.start),
    );
    // Attributes are not part of the name: `<plist version="1.0">` is `plist`.
    tags.add(_Tag(bare.split(RegExp(r'\s')).first, isEmpty, text, match.end));
  }
  if (tags.isEmpty) throw FormatException('$source: no XML tags found');
  return tags;
}

const _entities = {'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'"};

String _unescape(String raw) =>
    raw.replaceAllMapped(RegExp('&(amp|lt|gt|quot|apos|#\\d+);'), (m) {
      final name = m.group(1)!;
      if (name.startsWith('#')) {
        return String.fromCharCode(int.parse(name.substring(1)));
      }
      return _entities[name] ?? m.group(0)!;
    }).trim();

class _Parser {
  _Parser(this._tags, this._source);

  final List<_Tag> _tags;
  final String _source;
  int _at = 0;

  _Tag get _tag {
    if (_at >= _tags.length) {
      throw FormatException('$_source: ran off the end of the property list');
    }
    return _tags[_at];
  }

  Never _fail(String what) =>
      throw FormatException('$_source: expected $what, found <${_tag.name}>');

  /// Steps over the `<plist>` wrapper so parsing starts at the root value.
  void skipRootWrapper() {
    if (_tag.name != 'plist') _fail('<plist>');
    _at++;
  }

  /// Reads one value, consuming every tag that belongs to it.
  Object? value() {
    final tag = _tag;
    switch (tag.name) {
      case 'true':
        _at++;
        return true;
      case 'false':
        _at++;
        return false;
      case 'dict':
        return tag.isEmpty ? _empty(<String, Object?>{}) : _dict();
      case 'array':
        return tag.isEmpty ? _empty(<Object?>[]) : _array();
      case 'integer':
      case 'real':
      case 'string':
      case 'data':
      case 'date':
        return _leaf();
      default:
        _fail('a plist value');
    }
  }

  /// `<true/>` and `<dict/>` are their own closing tag.
  T _empty<T>(T value) {
    _at++;
    return value;
  }

  /// A scalar. For a paired leaf the value is the text before the closing
  /// tag, so `<string>hi</string>` yields `hi`, not the whitespace before
  /// `<string>`.
  Object? _leaf() {
    final name = _tag.name;
    final text = _tag.isEmpty ? _tag.text : _tags[_at + 1].text;
    _at += _tag.isEmpty ? 1 : 2;
    return switch (name) {
      'integer' => int.parse(text),
      'real' => double.parse(text),
      _ => text,
    };
  }

  Map<String, Object?> _dict() {
    _at++; // <dict>
    final out = <String, Object?>{};
    while (_tag.name != '/dict') {
      // `<key>Name</key>` is a pair: the name is the text before `</key>`,
      // whether or not it sits on a line of its own.
      if (_tag.name != 'key') _fail('<key>');
      _at++;
      if (_tag.name != '/key') _fail('</key>');
      final key = _tag.text;
      _at++;
      out[key] = value();
    }
    _at++; // </dict>
    return out;
  }

  List<Object?> _array() {
    _at++; // <array>
    final out = <Object?>[];
    while (_tag.name != '/array') {
      out.add(value());
    }
    _at++; // </array>
    return out;
  }
}
