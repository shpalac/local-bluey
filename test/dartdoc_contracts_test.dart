import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contract dartdoc coverage (#179): every public member of lib/services
/// (and the public brain contract) must carry a doc comment, so nobody
/// has to read source to learn a contract.
void main() {
  const contractFiles = [
    'lib/services/host_control.dart',
    'lib/services/native_control.dart',
    'lib/services/tool_executor.dart',
    'lib/services/safety_gate.dart',
    'lib/llm/brain.dart',
    'lib/services/stt.dart',
    'lib/services/linux_host_base.dart',
    'lib/services/endpoint_assistant.dart',
    'lib/services/user_feedback.dart',
    'lib/services/action_log.dart',
    'lib/services/audio_capture.dart',
    'lib/services/biometric_lock.dart',
    'lib/services/brain_host.dart',
    'lib/services/characters.dart',
    'lib/services/conversation.dart',
    'lib/services/data_registry.dart',
    'lib/services/deep_links.dart',
    'lib/services/degraded.dart',
    'lib/services/diagnostics.dart',
    'lib/services/discover.dart',
    'lib/services/egress_monitor.dart',
    'lib/services/endpoint.dart',
    'lib/services/frame_differ.dart',
    'lib/services/haptics.dart',
    'lib/services/linux_portal_host_control.dart',
    'lib/services/linux_x11_host_control.dart',
    'lib/services/onboarding_checks.dart',
    'lib/services/perf_monitor.dart',
    'lib/services/permission_watchdog.dart',
    'lib/services/privacy_guard.dart',
    'lib/services/request_interfaces.dart',
    'lib/services/request_runner.dart',
    'lib/services/routines.dart',
    'lib/services/screen_watch.dart',
    'lib/services/settings_store.dart',
    'lib/services/speak_receipts.dart',
    'lib/services/speech.dart',
    'lib/services/strings.dart',
    'lib/services/support_matrix.dart',
    'lib/services/tutorial.dart',
    'lib/services/undo.dart',
    'lib/services/wake_word.dart',
    'lib/services/watch_context.dart',
    'lib/services/watch_driver.dart',
    'lib/services/watch_pipeline.dart',
    'lib/services/watch_policy.dart',
    'lib/services/watch_suggestions.dart',
  ];

  final declStart = RegExp(
    r'^(?:abstract\s+|base\s+|final\s+|sealed\s+)?'
    r'(?:class|enum|mixin|typedef|extension type)\s+[A-Z]'
    // methods / getters (a type or modifier must precede the name)
    r'|^(?:static\s+)?(?:[A-Za-z_][A-Za-z0-9_<>?, ]+\s+)'
    r'[a-z][A-Za-z0-9_]*\s*(?:\(|=>)'
    // fields: const/final/late, or static + type
    r'|^(?:(?:static\s+)?(?:const|final|late)\s+'
    r'(?:[A-Za-z_][A-Za-z0-9_<>?, ]+\s+)?|static\s+)'
    r'[a-z][A-Za-z0-9_]*\s*(?:;| =)'
    // enum values (whole line is an identifier + comma/semicolon)
    r'|^[a-z][A-Za-z0-9_]*\s*[,;]\$',
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
