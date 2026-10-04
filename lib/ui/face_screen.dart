import 'package:flutter/material.dart';

import '../link/models.dart';

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
    this.onWakeChanged,
    this.onHoldStart,
    this.onHoldEnd,
  });

  final FaceState face;
  final bool awake;

  /// Current speech-bubble text, null when hidden.
  final String? bubble;
  final ValueChanged<bool>? onWakeChanged;
  final VoidCallback? onHoldStart;
  final VoidCallback? onHoldEnd;

  @override
  State<FaceScreen> createState() => _FaceScreenState();
}

class _FaceScreenState extends State<FaceScreen> {
  @override
  Widget build(BuildContext context) {
    final face = widget.face;
    final color = switch (face.mood) {
      Mood.listening => const Color(0xFF5BC8E5),
      Mood.thinking => const Color(0xFF9B8CE5),
      Mood.talking => const Color(0xFF5BE49B),
      Mood.pointing => const Color(0xFFE5A75B),
      Mood.happy => const Color(0xFF5BE49B),
      Mood.sleepy => const Color(0xFF6B7280),
      Mood.resting => const Color(0xFF8B95A5),
    };

    return GestureDetector(
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
