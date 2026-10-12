import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../llm/llm_provider.dart';
import '../link/models.dart';
import '../services/characters.dart';
import '../services/conversation.dart';
import '../services/strings.dart';
import 'bluey_character.dart';
import 'motion.dart';

/// Bluey's responsive character with gaze, mood and speech animation.
/// Gestures (ported from the iOS SwiftUI face):
/// - double-tap: wake / put to sleep
/// - long-press hold: hold to talk (release ends the ask)
class FaceScreen extends StatefulWidget {
  const FaceScreen({
    super.key,
    required this.face,
    this.awake = false,
    this.bubble,
    this.status = BlueyStatus.listening,
    this.onWakeChanged,
    this.onHoldStart,
    this.onHoldEnd,
    this.perfOverlay,
  });

  final FaceState face;
  final bool awake;

  /// Current speech-bubble text, null when hidden.
  final String? bubble;

  /// Working state for the status chip.
  final BlueyStatus status;
  final ValueChanged<bool>? onWakeChanged;
  final VoidCallback? onHoldStart;
  final VoidCallback? onHoldEnd;

  /// Optional perf overlay shown under the status chip (#61).
  final Widget? perfOverlay;

  @override
  State<FaceScreen> createState() => _FaceScreenState();
}

class _FaceScreenState extends State<FaceScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breathing;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _breathing = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.of(context).disableAnimations;
    if (_reduceMotion) {
      _breathing.stop();
      _breathing.value = 0;
    } else if (widget.awake && _breathing.value == 0) {
      // A finite transition preserves pumpAndSettle and avoids idle CPU work.
      _breathing.forward();
    }
  }

  @override
  void didUpdateWidget(FaceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_reduceMotion &&
        widget.awake &&
        (oldWidget.awake != widget.awake ||
            !identical(oldWidget.face, widget.face))) {
      _breathing.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _breathing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final face = widget.face;
    final color =
        CharacterStore.instance.current.value.moodColors[face.mood] ??
        const Color(0xFF5BC8E5);

    // #131: real semantic actions so VoiceOver/TalkBack users can wake
    // and hold-to-talk without the gestures or a hardware keyboard.
    return Semantics(
      label: Strings.t(
        'Bluey. Activate to wake or sleep. '
            'Use "start listening" to talk.',
        'בלוי. הפעל כדי להעיר או להרדים. '
            'השתמש ב"התחל האזנה" כדי לדבר.',
      ),
      button: true,
      onTap: () => widget.onWakeChanged?.call(!widget.awake),
      customSemanticsActions: {
        CustomSemanticsAction(
          label: Strings.t('Start listening', 'התחל האזנה'),
        ): () {
          widget.onHoldStart?.call();
        },
        CustomSemanticsAction(
          label: Strings.t('Stop and send', 'עצור ושלח'),
        ): () {
          widget.onHoldEnd?.call();
        },
      },
      child: GestureDetector(
        onDoubleTap: () => widget.onWakeChanged?.call(!widget.awake),
        onLongPressStart: (_) => widget.onHoldStart?.call(),
        onLongPressEnd: (_) => widget.onHoldEnd?.call(),
        child: Container(
          color: Colors.black,
          child: Stack(
            children: [
              Center(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final extent = math.min(
                      500.0,
                      math.min(constraints.maxWidth, constraints.maxHeight) *
                          0.82,
                    );
                    return SizedBox.square(
                      dimension: math.max(0.0, extent),
                      child: AnimatedBuilder(
                        animation: _breathing,
                        builder: (context, _) => BlueyCharacter(
                          key: const ValueKey('bluey-character'),
                          face: face,
                          awake: widget.awake,
                          tint: color,
                          phase: _breathing.value,
                        ),
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                top: 12,
                left: 0,
                right: 0,
                child: Center(child: _StatusChip(status: widget.status)),
              ),
              if (widget.perfOverlay != null)
                Positioned(
                  top: 40,
                  left: 0,
                  right: 0,
                  child: Center(child: widget.perfOverlay!),
                ),
              const Positioned(
                top: 44,
                left: 24,
                right: 24,
                height: 140,
                child: _AnswerLog(),
              ),
              // #130: ONE bubble widget with a stable key - only show/hide
              // animates; streamed tokens just update its text. Constrained
              // so a long answer scrolls instead of covering the face.
              Positioned(
                left: 24,
                right: 24,
                bottom: 60,
                child: AnimatedSwitcher(
                  duration: motionDuration(context),
                  child: widget.bubble == null
                      ? const SizedBox.shrink()
                      : ConstrainedBox(
                          key: const ValueKey('speech-bubble'),
                          constraints: BoxConstraints(
                            maxHeight:
                                MediaQuery.of(context).size.height * 0.35,
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: SingleChildScrollView(
                              child: SelectableText(
                                widget.bubble!,
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final BlueyStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      BlueyStatus.listening => (
        Strings.t('Listening', 'מאזין'),
        const Color(0xFF5BC8E5),
      ),
      BlueyStatus.thinking => (
        Strings.t('Thinking', 'חושב'),
        const Color(0xFF9B8CE5),
      ),
      BlueyStatus.acting => (
        Strings.t('Acting', 'פועל'),
        const Color(0xFFE5A75B),
      ),
      BlueyStatus.error => (Strings.t('Error', 'שגיאה'), Colors.redAccent),
      BlueyStatus.offline => (Strings.t('Offline', 'לא מחובר'), Colors.grey),
    };
    // #131: live region so screen readers announce status changes.
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color),
        ),
        child: Text(label, style: TextStyle(color: color, fontSize: 12)),
      ),
    );
  }
}

/// Scrollable history of everything asked and answered; survives restarts.
class _AnswerLog extends StatelessWidget {
  const _AnswerLog();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ConversationStore.instance,
      builder: (context, _) {
        final entries = ConversationStore.instance.entries;
        if (entries.isEmpty) return const SizedBox.shrink();
        // #131: announce new answers to screen readers.
        return Semantics(
          liveRegion: true,
          label: Strings.t('Answers', 'תשובות'),
          child: ListView.builder(
            reverse: true,
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[entries.length - 1 - index];
              final isUser = entry.role == 'user';
              return Align(
                alignment: isUser
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isUser
                        ? Colors.white.withValues(alpha: 0.14)
                        : Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    entry.text,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
