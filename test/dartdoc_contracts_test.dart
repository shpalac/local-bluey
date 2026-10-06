import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contract dartdoc coverage (#179): every public member of the public
/// service contracts must carry a doc comment, so new backends do not
/// have to read source to learn the contract.
void main() {
  const contractFiles = [
    'lib/services/host_control.dart',
    'lib/services/native_control.dart',
    'lib/services/tool_executor.dart',
    'lib/services/safety_gate.dart',
    'lib/llm/brain.dart',
  ];

  final declStart = RegExp(
    r'^(?:abstract\s+|base\s+|final\s+|sealed\s+)?'
    r'(?:class|enum|mixin|typedef|extension type)\s+[A-Z]'
    r'|^(?:static\s+)?(?:const\s+|final\s+|late\s+)?'
    r'(?:[A-Za-z_][A-Za-z0-9_<>?, ]+\s+)?[a-z][A-Za-z0-9_]*\s*'
    r'(?:\(|=>|;| =|,|$)',
  );

  String stripStrings(String line) =>
      line.replaceAll(RegExp("'[^']*'|\"[^\"]*\""), "''");

  test('every public contract member is documented (#179)', () {
    final offenders = <String>[];
    for (final path in contractFiles) {
      // Join declarations split after a generic return type (e.g. a
      // record return type on its own line) so the name line is not
      // mistaken for a new undocumented declaration.
      final rawLines = File(path).readAsLinesSync();
      final lines = <String>[];
      for (final l in rawLines) {
        final t = l.trim();
        if (lines.isNotEmpty &&
            lines.last.trim().endsWith('>') &&
            t.startsWith(RegExp(r'[a-z_]'))) {
          lines[lines.length - 1] = '${lines.last} $t';
        } else {
          lines.add(l);
        }
      }
      // Stack of what opened each brace level: true = class-like body
      // (its contents are members), false = function/other body.
      final braceStack = <bool>[];
      var parenDepth = 0;
      var pendingIsClassLike = false;
      var skipRestOfLine = false;

      for (var i = 0; i < lines.length; i++) {
        final raw = lines[i];
        final line = stripStrings(raw);
        final trimmed = line.trim();

        final inCode =
            !trimmed.startsWith('///') &&
            !trimmed.startsWith('//') &&
            trimmed.isNotEmpty;
        final atMemberLevel = braceStack.isEmpty || braceStack.last == true;

        if (inCode &&
            atMemberLevel &&
            parenDepth == 0 &&
            !skipRestOfLine &&
            declStart.hasMatch(trimmed) &&
            !trimmed.startsWith('import ') &&
            !trimmed.startsWith('library ') &&
            !trimmed.startsWith('part ') &&
            !_isPrivate(trimmed)) {
          // Docs may sit above annotations; walk back over them.
          var j = i - 1;
          var sawOverride = false;
          while (j >= 0) {
            final prev = lines[j].trim();
            if (prev.isEmpty) {
              j--;
              continue;
            }
            if (prev.startsWith('@')) {
              if (prev == '@override') sawOverride = true;
              j--;
              continue;
            }
            break;
          }
          if (!sawOverride && !(j >= 0 && lines[j].trim().startsWith('///'))) {
            offenders.add('$path:${i + 1}: $trimmed');
          }
        }

        // Advance the state machine across this line.
        if (inCode) {
          final opensClass = RegExp(
            r'(?:class|enum|mixin|extension type)\s+[A-Z]',
          ).hasMatch(trimmed);
          if (opensClass) pendingIsClassLike = true;
          for (final ch in line.split('')) {
            if (ch == '(' || ch == '[') parenDepth++;
            if (ch == ')' || ch == ']') parenDepth--;
            if (ch == '{') {
              braceStack.add(pendingIsClassLike);
              pendingIsClassLike = false;
            }
            if (ch == '}' && braceStack.isNotEmpty) braceStack.removeLast();
          }
          // A `=> ...;` member ends at its semicolon; a declaration that
          // opened parens continues on the next line.
          skipRestOfLine = parenDepth != 0;
          if (trimmed.endsWith(';')) skipRestOfLine = false;
        }
        if (trimmed.isEmpty) skipRestOfLine = parenDepth != 0;
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'public contract members need dartdoc (#179)',
    );
  });
}

bool _isPrivate(String trimmed) {
  final m = RegExp(r'([A-Za-z_][A-Za-z0-9_]*)[\s(<]*').firstMatch(trimmed);
  if (m == null) return false;
  // The first identifier is a keyword or type; check the declared name too.
  final nameMatch = RegExp(
    r'(?:class|enum|mixin|typedef|extension type)\s+([A-Za-z_][A-Za-z0-9_]*)',
  ).firstMatch(trimmed);
  if (nameMatch != null) return nameMatch.group(1)!.startsWith('_');
  final memberMatch = RegExp(r'([A-Za-z_][A-Za-z0-9_]*)\s*(?:\(|=>|;| =|$)')
      .allMatches(trimmed);
  for (final mm in memberMatch) {
    final n = mm.group(1)!;
    if (const {'static', 'const', 'final', 'late', 'abstract'}.contains(n)) {
      continue;
    }
    return n.startsWith('_');
  }
  return false;
}
