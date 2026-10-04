/// Undo offers for actions the host can actually reverse (#89). Actions not
/// listed here are never offered an undo, and the UI labels them as final.
class UndoSpec {
  const UndoSpec({
    required this.labelEn,
    required this.labelHe,
    required this.keys,
  });

  final String labelEn;
  final String labelHe;

  /// Shortcut passed to press_keys to reverse the action.
  final String keys;
}

/// What the host can reverse, per tool (#89).
UndoSpec? undoFor(String tool, Map<String, dynamic> arguments) =>
    switch (tool) {
      // Typed text is reversed with the platform undo shortcut.
      'type_text' => const UndoSpec(
        labelEn: 'Undo typing',
        labelHe: 'ביטול הקלדה',
        keys: 'cmd+z',
      ),
      // Everything else (click, scroll, drag, open_app, ...) has no reliable
      // host-side reversal, so no undo is offered for it.
      _ => null,
    };
