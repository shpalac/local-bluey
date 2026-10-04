import 'package:flutter/material.dart';

import '../llm/llm_provider.dart';
import '../link/models.dart';
import '../services/characters.dart';
import '../services/conversation.dart';

/// Bluey's face: two eyes that follow the gaze, colored by mood.
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

class _FaceScreenState extends State<FaceScreen> {
  @override
  Widget build(BuildContext context) {
    final face = widget.face;
    final color = CharacterStore.instance.current.value.moodColors[face.mood] ??
        const Color(0xFF5BC8E5);

    return Semantics(
      label: 'Bluey. Double-tap to wake or sleep. '
          'Long-press and hold to talk. '
          'Keyboard: W toggles wake, hold Space to talk.',
      button: true,
      child: GestureDetector(
      onDoubleTap: () => widget.onWakeChanged?.call(!widget.awake),
      onLongPressStart: (_) => widget.onHoldStart?.call(),
      onLongPressEnd: (_) => widget.onHoldEnd?.call(),
      child: Container(
        color: Colors.black,
        child: Stack(
          children: [
            Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                width: 220,
                height: 160,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: widget.awake ? 0.25 : 0.08),
                  borderRadius: BorderRadius.circular(80),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _Eye(
                      gazeX: face.gazeX,
                      gazeY: face.gazeY,
                      color: color,
                      dim: !widget.awake,
                    ),
                    _Eye(
                      gazeX: face.gazeX,
                      gazeY: face.gazeY,
                      color: color,
                      dim: !widget.awake,
                    ),
                  ],
                ),
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
            if (widget.bubble != null)
              Positioned(
                left: 24,
                right: 24,
                bottom: 60,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    widget.bubble!,
                    style: const TextStyle(color: Colors.black87, fontSize: 16),
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
      BlueyStatus.listening => ('Listening', const Color(0xFF5BC8E5)),
      BlueyStatus.thinking => ('Thinking', const Color(0xFF9B8CE5)),
      BlueyStatus.acting => ('Acting', const Color(0xFFE5A75B)),
      BlueyStatus.error => ('Error', Colors.redAccent),
      BlueyStatus.offline => ('Offline', Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 12)),
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
        return ListView.builder(
          reverse: true,
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final entry = entries[entries.length - 1 - index];
            final isUser = entry.role == 'user';
            return Align(
              alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
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
        );
      },
    );
  }
}

class _Eye extends StatelessWidget {
  const _Eye({
    required this.gazeX,
    required this.gazeY,
    required this.color,
    required this.dim,
  });

  final double gazeX;
  final double gazeY;
  final Color color;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: dim ? 0.3 : 0.95),
      ),
      child: Center(
        child: Transform.translate(
          offset: Offset(gazeX * 14, gazeY * 14),
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
        ),
      ),
    );
  }
}
